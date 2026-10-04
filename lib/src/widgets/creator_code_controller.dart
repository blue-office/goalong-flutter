import 'dart:async';

import 'package:flutter/foundation.dart';

import '../client.dart';
import '../link.dart';
import '../models.dart';

enum CreatorCodePhase { idle, checking, valid, applying, done, failed }

enum CreatorCodeIssue {
  invalidFormat,
  notFound,
  expired,
  conflict,
  existingSubscriber,
  network,
}

enum _RetryAction { current, validate, apply }

/// 独自 UI 用の状態管理。入力は 400ms 待って検証し、紹介リンクは検証後に
/// CLIPBOARD として自動適用する。不要になったら dispose する。
class CreatorCodeController extends ChangeNotifier {
  CreatorCodeController({
    String code = '',
    ApplyMethod method = ApplyMethod.code,
    this.rcAppUserId,
    this.isActiveSubscriber,
  }) {
    _setCode(code, method: method);
  }

  final String? rcAppUserId;
  final ActiveSubscriberCheck? isActiveSubscriber;
  String _code = '';
  ApplyMethod _method = ApplyMethod.code;
  CreatorCodePhase _phase = CreatorCodePhase.idle;
  CreatorCodeIssue? _issue;
  Creator? _creator;
  Creator? _conflictCreator;
  Perk? _perk;
  Perk? _previewPerk;
  bool _perkPending = false;
  ReferralSnapshot? _current;
  bool _loadingCurrent = false;
  bool _disposed = false;
  int _revision = 0;
  int _currentRevision = 0;
  Timer? _debounce;
  _RetryAction _retryAction = _RetryAction.validate;
  bool _retryConfirmReplace = false;

  String get code => _code;
  CreatorCodePhase get phase => _phase;
  CreatorCodeIssue? get issue => _issue;

  /// API のメタデータ。既成 UI では紹介者名を表示しない。
  Creator? get creator => _creator;
  Creator? get conflictCreator => _conflictCreator;

  /// valid では検証時の特典、done では実際に付与された特典。
  Perk? get perk => _phase == CreatorCodePhase.valid ? _previewPerk : _perk;
  Perk? get previewPerk => _previewPerk;
  bool get perkPending => _perkPending;
  ReferralSnapshot? get current => _current;
  ApplyMethod get method => _method;
  bool get removed => _current is ReferralRemoved && _code.isEmpty;
  bool get isLoadingCurrent => _loadingCurrent;
  bool get isValidFormat => isValidCode(normalizeCode(_code));
  bool get isBusy =>
      _loadingCurrent ||
      _phase == CreatorCodePhase.checking ||
      _phase == CreatorCodePhase.applying;

  set code(String value) => _setCode(value);

  /// deepLink / clipboard など、コードを受け取った経路を指定する。
  void fill(String value, {ApplyMethod method = ApplyMethod.code}) =>
      _setCode(value, method: method);

  void _setCode(String value, {ApplyMethod method = ApplyMethod.code}) {
    if (_disposed ||
        _phase == CreatorCodePhase.applying ||
        _phase == CreatorCodePhase.done) {
      return;
    }
    final extracted = value.contains('://') ? GoAlong.extractCode(value) : null;
    final next = extracted ?? value;
    final nextMethod = extracted == null ? method : ApplyMethod.clipboard;
    if (next == _code && nextMethod == _method) return;
    _revision++;
    _debounce?.cancel();
    _code = next;
    _method = nextMethod;
    _phase = CreatorCodePhase.idle;
    _issue = null;
    _creator = null;
    _conflictCreator = null;
    _previewPerk = null;
    _perk = null;
    _perkPending = false;
    _notify();
    _scheduleValidation();
  }

  void _scheduleValidation() {
    _debounce?.cancel();
    if (_disposed ||
        _loadingCurrent ||
        _phase != CreatorCodePhase.idle ||
        !isValidFormat) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(validatePreview());
    });
  }

  Future<void> loadCurrentReferral() async {
    if (_disposed ||
        _loadingCurrent ||
        _phase == CreatorCodePhase.applying ||
        _phase == CreatorCodePhase.done) {
      return;
    }
    _debounce?.cancel();
    final revision = _revision;
    final currentRevision = ++_currentRevision;
    _loadingCurrent = true;
    _notify();
    try {
      final snapshot = await GoAlong.currentReferral();
      if (_disposed || currentRevision != _currentRevision) return;
      _current = snapshot;
      if (_retryAction == _RetryAction.current && revision == _revision) {
        _phase = CreatorCodePhase.idle;
        _issue = null;
      }
    } catch (_) {
      if (!_disposed &&
          currentRevision == _currentRevision &&
          revision == _revision) {
        _retryAction = _RetryAction.current;
        _fail(CreatorCodeIssue.network);
      }
    } finally {
      if (!_disposed && currentRevision == _currentRevision) {
        _loadingCurrent = false;
        _notify();
        _scheduleValidation();
      }
    }
  }

  Future<void> validatePreview() async {
    if (_disposed ||
        _loadingCurrent ||
        _phase == CreatorCodePhase.applying ||
        _phase == CreatorCodePhase.done ||
        _code.trim().isEmpty) {
      return;
    }
    _debounce?.cancel();
    final revision = ++_revision;
    _phase = CreatorCodePhase.checking;
    _issue = null;
    _previewPerk = null;
    _retryAction = _RetryAction.validate;
    _notify();
    try {
      final validation = await GoAlong.validateCode(_code);
      if (_disposed || revision != _revision) return;
      if (validation.valid) {
        _previewPerk = validation.perk;
        _creator = validation.creator;
        _phase = CreatorCodePhase.valid;
      } else {
        _fail(_codeIssue(validation.error));
      }
    } catch (_) {
      if (_disposed || revision != _revision) return;
      _fail(CreatorCodeIssue.network);
    }
    _notify();
    if (!_disposed &&
        revision == _revision &&
        _phase == CreatorCodePhase.valid &&
        _method == ApplyMethod.clipboard) {
      await apply();
    }
  }

  /// 特典があるコードなのに付与されておらず、RevenueCat のユーザー ID がまだ分からない(未ログイン)とき
  Future<bool> _isPerkPending(Perk? perk, String? perkLabel) async =>
      perk == null &&
      (_previewPerk != null || perkLabel != null) &&
      (rcAppUserId == null || rcAppUserId!.isEmpty) &&
      !await GoAlong.hasRevenueCatUserID();

  Future<ApplyResult?> apply({bool confirmReplace = false}) async {
    if (_disposed ||
        _loadingCurrent ||
        _phase == CreatorCodePhase.applying ||
        _phase == CreatorCodePhase.done ||
        _code.trim().isEmpty) {
      return null;
    }
    _debounce?.cancel();
    final revision = ++_revision;
    _phase = CreatorCodePhase.applying;
    _issue = null;
    _retryAction = _RetryAction.apply;
    _retryConfirmReplace = confirmReplace;
    _notify();
    try {
      final result = await GoAlong.applyCode(
        _code,
        method: _method,
        rcAppUserId: rcAppUserId,
        confirmReplace: confirmReplace,
        isActiveSubscriber: isActiveSubscriber,
      );
      if (_disposed || revision != _revision) return null;
      switch (result) {
        case Applied(:final creator, :final perk, :final perkLabel):
          final pending = await _isPerkPending(perk, perkLabel);
          if (_disposed || revision != _revision) return null;
          _complete(creator, perk, pending: pending);
        case AlreadyApplied(:final creator, :final perk, :final perkLabel):
          // 未ログインで適用した後の再試行など。特典が未付与なら「ログイン後に受け取れます」(iOS・RN と同じ)
          final pending = await _isPerkPending(perk, perkLabel);
          if (_disposed || revision != _revision) return null;
          _complete(creator, perk, pending: pending);
        case Conflict(:final currentCreator):
          _conflictCreator = currentCreator;
          _fail(CreatorCodeIssue.conflict);
        case ExistingSubscriber():
          _fail(CreatorCodeIssue.existingSubscriber);
        case NotFound(:final error):
          _fail(_codeIssue(error));
      }
      _notify();
      return result;
    } catch (_) {
      if (_disposed || revision != _revision) return null;
      _fail(CreatorCodeIssue.network);
      _notify();
      return null;
    }
  }

  /// 失敗した操作を再試行する。置換の同意と入力経路は保持する。
  Future<void> retry() async {
    if (_disposed || isBusy || _issue != CreatorCodeIssue.network) return;
    switch (_retryAction) {
      case _RetryAction.current:
        await loadCurrentReferral();
      case _RetryAction.validate:
        await validatePreview();
      case _RetryAction.apply:
        await apply(confirmReplace: _retryConfirmReplace);
    }
  }

  void _complete(Creator? creator, Perk? perk, {bool pending = false}) {
    _creator = creator;
    _perk = perk;
    _perkPending = pending;
    _phase = CreatorCodePhase.done;
    _current = ReferralApplied(creator: creator, perk: perk);
    _code = normalizeCode(_code);
  }

  void reset() {
    if (_disposed || _phase == CreatorCodePhase.applying) return;
    _debounce?.cancel();
    _revision++;
    _currentRevision++;
    _loadingCurrent = false;
    _code = '';
    _method = ApplyMethod.code;
    _phase = CreatorCodePhase.idle;
    _issue = null;
    _creator = null;
    _conflictCreator = null;
    _perk = null;
    _previewPerk = null;
    _perkPending = false;
    _notify();
  }

  CreatorCodeIssue _codeIssue(CodeErrorKind? kind) => switch (kind) {
        CodeErrorKind.invalidFormat => CreatorCodeIssue.invalidFormat,
        CodeErrorKind.expired => CreatorCodeIssue.expired,
        _ => CreatorCodeIssue.notFound,
      };

  void _fail(CreatorCodeIssue issue) {
    _issue = issue;
    _phase = CreatorCodePhase.failed;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _disposed = true;
    _revision++;
    _currentRevision++;
    super.dispose();
  }
}
