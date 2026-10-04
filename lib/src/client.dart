import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'device_meta.dart';
import 'link.dart';
import 'models.dart';
import 'storage.dart';

/// 起動時に configure を await してから利用する。
abstract final class GoAlong {
  static const sdkVersion = '0.1.0';
  static _Client? _client;

  /// 通信完了は待たず、installation ID の永続化まで待つ。
  /// 注入した httpClient の寿命は呼び出し元が管理する。
  static Future<void> configure({
    required String appId,
    String? appSlug,
    String baseUrl = 'https://goalong.me',
    ActiveSubscriberCheck? isActiveSubscriber,
    String appVersion = const String.fromEnvironment(
      'APP_VERSION',
      defaultValue: 'unknown',
    ),
    String? osVersion,
    String? locale,
    http.Client? httpClient,
    GoAlongStorage? storage,
  }) async {
    if (_client != null) {
      throw StateError('GoAlong.configure must be called once per app launch.');
    }
    final base = Uri.parse(baseUrl);
    if (appId.trim().isEmpty ||
        !base.hasAuthority ||
        (base.scheme != 'https' && base.scheme != 'http') ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw ArgumentError(
        'A non-empty appId and an HTTP(S) baseUrl are required.',
      );
    }
    WidgetsFlutterBinding.ensureInitialized();
    final client = _Client(
      appId: appId,
      appSlug: appSlug,
      baseUrl: base,
      subscriberCheck: isActiveSubscriber,
      metadata: {
        'sdkVersion': sdkVersion,
        'osVersion': osVersion ?? defaultOsVersion,
        'appVersion': appVersion,
        'locale': locale ??
            WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
      },
      httpClient: httpClient ?? http.Client(),
      ownsHttpClient: httpClient == null,
      storage: storage ?? SharedPreferencesGoAlongStorage(),
    );
    _client = client;
    try {
      await client.installationId();
    } catch (_) {
      _client = null;
      client.close();
      rethrow;
    }
    client.installationReport = client.reportInstallation();
    unawaited(client.installationReport);
  }

  static _Client get _configured =>
      _client ?? (throw const GoAlongException.notConfigured());

  static Future<String> installationId() async => _configured.installationId();

  static Future<Map<String, String>> attributionAttributes() async =>
      _configured.attributes();

  static Future<Perk?> setRevenueCatUserID(String id) async =>
      _configured.setRevenueCatUserID(id);

  static Future<CodeValidation> validateCode(String code) async =>
      _configured.validateCode(code);

  static Future<ApplyResult> applyCode(
    String code, {
    ApplyMethod method = ApplyMethod.code,
    String? rcAppUserId,
    bool confirmReplace = false,
    ActiveSubscriberCheck? isActiveSubscriber,
  }) async =>
      _configured.applyCode(
        code,
        method: method,
        rcAppUserId: rcAppUserId,
        confirmReplace: confirmReplace,
        subscriberCheck: isActiveSubscriber,
      );

  static Future<ReferralSnapshot> currentReferral() async =>
      _configured.currentReferral();

  static Future<bool> removeReferral() async => _configured.removeReferral();

  /// 抽出のみ。適用はユーザーの確認後に行う。
  /// 生文字列がある場合は extractCode を使うと明示ポートも検査できる。
  static String? handleDeepLink(Uri uri) => extractCode(uri.toString());

  /// 未設定時は goalong.me、slug 制限なしで検査する。
  static String? extractCode(String text) => extractReferralCode(
        text,
        expectedHost: _client?.baseUrl.host ?? 'goalong.me',
        appSlug: _client?.appSlug,
      );

  static Future<bool> referralEntryEnabled() async =>
      _configured.referralEntryEnabled();

  /// 紹介者情報が不要な画面向けのローカル判定。
  static Future<bool> hasAppliedReferralLocally() async =>
      _configured.hasAppliedReferral();

  /// 保存済みの RevenueCat ID があるか(特典の後追い付与の表示用)。
  static Future<bool> hasRevenueCatUserID() async =>
      _configured.hasRevenueCatUserID();

  /// 入口でも configure と同じ既存購読者判定を使う。
  static Future<bool> hasActiveSubscription({
    ActiveSubscriberCheck? isActiveSubscriber,
  }) async {
    final client = _configured;
    return client.checkSubscriber(isActiveSubscriber);
  }

  @visibleForTesting
  static Future<void> debugWaitForInstallationReport() async {
    await _configured.installationReport;
  }

  @visibleForTesting
  static set debugNow(DateTime Function() now) {
    _configured.now = now;
  }

  @visibleForTesting
  static Future<void> resetForTesting() async {
    final client = _client;
    _client = null;
    // Widget テストの FakeAsync 内で作られた Future は、テスト外の
    // tearDown から await すると、完了済みでも継続が実行されず停止する。
    // 報告の確認はテスト本体で debugWaitForInstallationReport を使う。
    client?.close();
  }
}

class _Client {
  _Client({
    required this.appId,
    required this.appSlug,
    required this.baseUrl,
    required this.subscriberCheck,
    required this.metadata,
    required this.httpClient,
    required this.ownsHttpClient,
    required this.storage,
  });

  final String appId;
  final String? appSlug;
  final Uri baseUrl;
  final ActiveSubscriberCheck? subscriberCheck;
  final Map<String, String> metadata;
  final http.Client httpClient;
  final bool ownsHttpClient;
  final GoAlongStorage storage;
  Future<String>? _installationId;
  Future<void> installationReport = Future<void>.value();
  Future<void> _mutationTail = Future<void>.value();
  DateTime Function() now = DateTime.now;
  bool? _entryEnabled;
  DateTime? _entryExpiresAt;
  Future<bool>? _entryRequest;
  bool _closed = false;
  final _pendingRequests = <void Function()>{};

  void close() {
    if (_closed) return;
    _closed = true;
    for (final cancel in _pendingRequests.toList()) {
      cancel();
    }
    _pendingRequests.clear();
    if (ownsHttpClient) httpClient.close();
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on GoAlongException {
      rethrow;
    } catch (error) {
      throw GoAlongException.network(error);
    }
  }

  // apply / claim / remove とローカル状態の書き込み順を一致させる。
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _mutationTail.then((_) => _guard(action));
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<String> installationId() => _installationId ??= _guard(() async {
        final saved = await storage.getString(StorageKeys.installationId);
        if (saved != null) return saved;
        final random = Random.secure();
        final bytes = List<int>.generate(16, (_) => random.nextInt(256));
        bytes[6] = (bytes[6] & 0x0f) | 0x40;
        bytes[8] = (bytes[8] & 0x3f) | 0x80;
        final hex =
            bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        final id = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
            '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
            '${hex.substring(20)}';
        await storage.setString(StorageKeys.installationId, id);
        return id;
      });

  Future<bool> hasAppliedReferral() => _guard(
        () async => await storage.getBool(StorageKeys.referralApplied) ?? false,
      );

  Future<bool> hasRevenueCatUserID() => _guard(() async {
        final id = await storage.getString(StorageKeys.rcAppUserId);
        return id != null && id.isNotEmpty;
      });

  Future<http.Response> _send(Future<http.Response> Function() send) async {
    if (_closed) throw const GoAlongException.network();
    final response = Completer<http.Response>();
    final timer = Timer(const Duration(seconds: 15), () {
      response.completeError(TimeoutException('GoAlong request timed out'));
    });
    void cancel() {
      timer.cancel();
      if (!response.isCompleted) {
        response.completeError(const GoAlongException.network());
      }
    }

    _pendingRequests.add(cancel);
    unawaited(Future.sync(send).then((value) {
      if (!response.isCompleted) response.complete(value);
    }, onError: (Object error, StackTrace stack) {
      if (!response.isCompleted) response.completeError(error, stack);
    }));
    try {
      return await response.future;
    } finally {
      timer.cancel();
      _pendingRequests.remove(cancel);
    }
  }

  Future<Map<String, String>> attributes() => _serial(() async {
        final attributes = {'goalong_installation_id': await installationId()};
        if (await hasAppliedReferral()) {
          attributes['goalong_referred'] = 'true';
          final key = await storage.getString(StorageKeys.referralOfferingKey);
          if (key != null) attributes['goalong_offering'] = key;
        }
        return attributes;
      });

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) =>
      _guard(() async {
        final uri = baseUrl
            .resolve('/api/sdk/v1/$path')
            .replace(queryParameters: query);
        final response = await _send(() => body == null
            ? httpClient.get(uri, headers: {'Accept': 'application/json'})
            : httpClient.post(
                uri,
                headers: {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(body),
              ));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw GoAlongException.server(response.statusCode);
        }
        return jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      });

  Future<void> reportInstallation() async {
    try {
      if (await storage.getBool(StorageKeys.installationReported) == true ||
          _closed) {
        return;
      }
      final json = await _request(
        'installations',
        body: {
          'appId': appId,
          'installationId': await installationId(),
          ...metadata,
        },
      );
      if (!_closed && json['ok'] == true) {
        await storage.setBool(StorageKeys.installationReported, true);
      }
    } catch (_) {
      // 未報告のまま残し、次回起動の configure で再試行する。
    }
  }

  String? _code(String text) => text.contains('://')
      ? extractReferralCode(text, expectedHost: baseUrl.host, appSlug: appSlug)
      : normalizeCode(text);

  Creator? _creator(Object? value) =>
      value == null ? null : Creator.fromJson(value as Map<String, dynamic>);
  Perk? _perk(Object? value) =>
      value == null ? null : Perk.fromJson(value as Map<String, dynamic>);

  Future<CodeValidation> validateCode(String raw) => _guard(() async {
        final code = _code(raw);
        if (code == null || !isValidCode(code)) {
          return const CodeValidation(
            valid: false,
            error: CodeErrorKind.invalidFormat,
          );
        }
        final json = await _request(
          'codes/validate',
          body: {'appId': appId, 'code': code},
        );
        return CodeValidation(
          valid: json['valid'] as bool,
          error: CodeErrorKind.fromValue(json['error']),
          code: json['code'] as String?,
          creator: _creator(json['creator']),
          perk: _perk(json['perk']),
        );
      });

  /// 判定に失敗したときは続行する(rcAppUserId があればサーバーでも再判定する。React Native 版と同じ)
  Future<bool> checkSubscriber(ActiveSubscriberCheck? override) async {
    final check = override ?? subscriberCheck;
    if (check == null) return false;
    try {
      return await check();
    } catch (_) {
      return false;
    }
  }

  Future<ApplyResult> applyCode(
    String raw, {
    required ApplyMethod method,
    required String? rcAppUserId,
    required bool confirmReplace,
    required ActiveSubscriberCheck? subscriberCheck,
  }) =>
      _serial(() async {
        if (await checkSubscriber(subscriberCheck)) {
          return const ExistingSubscriber();
        }
        final code = _code(raw);
        if (code == null || !isValidCode(code)) {
          return const NotFound(error: CodeErrorKind.invalidFormat);
        }
        final userId =
            rcAppUserId ?? await storage.getString(StorageKeys.rcAppUserId);
        final json = await _request(
          'codes/apply',
          body: {
            'appId': appId,
            'installationId': await installationId(),
            'code': code,
            'method': method.value,
            'confirmReplace': confirmReplace,
            if (userId != null) 'rcAppUserId': userId,
            ...metadata,
          },
        );
        switch (json['status']) {
          case 'applied':
          case 'already_applied':
            final creator = _creator(json['creator']);
            final perk = _perk(json['perk']);
            final label = json['perkLabel'] as String?;
            final offering = json['offeringKey'] as String?;
            await storage.setBool(StorageKeys.referralApplied, true);
            // サーバーの応答を正として置き換える(already_applied でも。コード変更の再試行で古い値を残さない)
            if (offering != null) {
              await storage.setString(
                  StorageKeys.referralOfferingKey, offering);
            } else {
              await storage.remove(StorageKeys.referralOfferingKey);
            }
            return json['status'] == 'applied'
                ? Applied(
                    creator: creator,
                    perk: perk,
                    perkLabel: label,
                    offeringKey: offering,
                  )
                : AlreadyApplied(
                    creator: creator,
                    perk: perk,
                    perkLabel: label,
                    offeringKey: offering,
                  );
          case 'conflict':
            return Conflict(currentCreator: _creator(json['currentCreator']));
          case 'existing_subscriber':
            return const ExistingSubscriber();
          case 'expired':
            return const NotFound(error: CodeErrorKind.expired);
          case 'not_found':
            return NotFound(error: CodeErrorKind.fromValue(json['error']));
          default:
            throw const FormatException('Unknown apply status');
        }
      });

  Future<Perk?> setRevenueCatUserID(String id) => _serial(() async {
        await storage.setString(StorageKeys.rcAppUserId, id);
        if (!await hasAppliedReferral()) return null;
        final json = await _request(
          'perks/claim',
          body: {
            'appId': appId,
            'installationId': await installationId(),
            'rcAppUserId': id,
          },
        );
        switch (json['status']) {
          case 'granted':
          case 'no_perk':
            // offering はサーバーの最新の内容に置き換える(特典が変わった場合に古い値を残さない)
            final key = json['offeringKey'] as String?;
            if (key != null) {
              await storage.setString(StorageKeys.referralOfferingKey, key);
            } else {
              await storage.remove(StorageKeys.referralOfferingKey);
            }
            return json['status'] == 'granted' ? _perk(json['perk']) : null;
          case 'no_attribution':
            await storage.remove(StorageKeys.referralApplied);
            await storage.remove(StorageKeys.referralOfferingKey);
            return null;
          case 'existing_subscriber':
            return null;
          default:
            throw const FormatException('Unknown claim status');
        }
      });

  Future<ReferralSnapshot> currentReferral() => _serial(() async {
        final json = await _request(
          'codes/current',
          query: {'appId': appId, 'installationId': await installationId()},
        );
        switch (json['status']) {
          case 'applied':
            final snapshot = ReferralApplied(
              creator: _creator(json['creator']),
              appliedAt: DateTime.tryParse(json['appliedAt'] as String? ?? ''),
              perk: _perk(json['perk']),
            );
            await storage.setBool(StorageKeys.referralApplied, true);
            return snapshot;
          case 'none':
          case 'removed':
            await _clearReferral();
            return json['status'] == 'none'
                ? const ReferralNone()
                : ReferralRemoved(
                    removedAt: DateTime.tryParse(
                      json['removedAt'] as String? ?? '',
                    ),
                  );
          default:
            throw const FormatException('Unknown referral status');
        }
      });

  Future<void> _clearReferral() async {
    await storage.setBool(StorageKeys.referralApplied, false);
    await storage.remove(StorageKeys.referralOfferingKey);
  }

  Future<bool> removeReferral() => _serial(() async {
        final json = await _request(
          'codes/remove',
          body: {'appId': appId, 'installationId': await installationId()},
        );
        if (json['status'] != 'removed' && json['status'] != 'no_attribution') {
          throw const FormatException('Unknown removal status');
        }
        await _clearReferral();
        return json['status'] == 'removed';
      });

  Future<bool> referralEntryEnabled() async {
    if (_entryExpiresAt != null && now().isBefore(_entryExpiresAt!)) {
      return _entryEnabled!;
    }
    final pending = _entryRequest;
    if (pending != null) return pending;
    final request = _fetchEntry();
    _entryRequest = request;
    try {
      return await request;
    } finally {
      _entryRequest = null;
    }
  }

  Future<bool> _fetchEntry() async {
    try {
      final json = await _request('config', query: {'appId': appId});
      final enabled = json['entryEnabled'] as bool;
      final seconds = json['cacheMaxAgeSeconds'] as int;
      _entryEnabled = enabled;
      _entryExpiresAt = now().add(Duration(seconds: max(0, seconds)));
      return enabled;
    } catch (_) {
      // 失敗をキャッシュしない。次の呼び出しで再試行する。
      return _entryEnabled ?? false;
    }
  }
}
