import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goalong/goalong.dart';
import 'package:http/http.dart' as http;

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(GoAlong.resetForTesting);
  tearDown(GoAlong.resetForTesting);

  test('入力中に返ってきた古い検証結果を捨てる', () async {
    final h = Harness();
    await h.configure();
    final response = Completer<http.Response>();
    h.responder = (_) => response.future;
    final model = CreatorCodeController(code: 'MIKA');
    addTearDown(model.dispose);
    final checking = model.validatePreview();
    expect(model.phase, CreatorCodePhase.checking);
    model.code = 'SHO';
    response.complete(
      jsonResponse({
        'valid': true,
        'creator': {'displayName': 'MIKA'},
      }),
    );
    await checking;
    expect(model.phase, CreatorCodePhase.idle);
    expect(model.creator, isNull);
    expect(model.code, 'SHO');
  });

  test('apply 中に完了した preview で done を上書きしない', () async {
    final h = Harness();
    await h.configure();
    final response = Completer<http.Response>();
    h.responder = (r) => r.url.path.endsWith('/validate')
        ? response.future
        : jsonResponse({
            'status': 'applied',
            'creator': {'displayName': 'MIKA'},
          });
    final model = CreatorCodeController(code: 'MIKA');
    addTearDown(model.dispose);
    final preview = model.validatePreview();
    await model.apply();
    response.complete(jsonResponse({'valid': false, 'error': 'expired'}));
    await preview;
    expect(model.phase, CreatorCodePhase.done);
    expect(model.creator?.displayName, 'MIKA');
  });

  test('リンク貼付はコードだけを表示し、検証後に CLIPBOARD で自動適用', () async {
    final h = Harness();
    await h.configure();
    final model = CreatorCodeController();
    addTearDown(model.dispose);
    model.code = 'https://goalong.me/booknotion/mika';
    expect(model.code, 'MIKA');
    expect(h.calls('codes/apply'), isEmpty);
    await model.validatePreview();
    expect(model.phase, CreatorCodePhase.done);
    expect(h.body('codes/apply')['method'], 'CLIPBOARD');
  });

  test('headless の conflict、置換、done、API で取消、再入力', () async {
    final h = Harness();
    await h.configure();
    final model = CreatorCodeController(code: 'MIKA');
    addTearDown(model.dispose);
    h.responder = (_) => jsonResponse({
          'status': 'conflict',
          'currentCreator': {'displayName': 'SHO'},
        });
    await model.apply();
    expect(model.phase, CreatorCodePhase.failed);
    expect(model.issue, CreatorCodeIssue.conflict);
    expect(model.conflictCreator?.displayName, 'SHO');
    h.responder = (_) => jsonResponse({'status': 'applied'});
    await model.apply(confirmReplace: true);
    expect(h.body('codes/apply')['confirmReplace'], true);
    expect(model.phase, CreatorCodePhase.done);
    h.responder = (_) => jsonResponse({'status': 'removed'});
    expect(await GoAlong.removeReferral(), true);
    model.reset();
    await model.loadCurrentReferral();
    expect(model.current, isA<ReferralRemoved>());
    expect(model.removed, true);
    model.code = 'SHO';
    expect(model.phase, CreatorCodePhase.idle);
    expect(model.removed, false);
  });

  test('二重送信を防ぎ、dispose 後に通知しない', () async {
    final h = Harness();
    await h.configure();
    final response = Completer<http.Response>();
    h.responder = (_) => response.future;
    final model = CreatorCodeController(code: 'MIKA');
    var notifications = 0;
    model.addListener(() => notifications++);
    final applying = model.apply();
    expect(await model.apply(), isNull);
    model.code = 'SHO';
    expect(model.code, 'MIKA');
    model.dispose();
    final before = notifications;
    response.complete(jsonResponse({'status': 'applied'}));
    await applying;
    expect(notifications, before);
    expect(h.calls('codes/apply'), hasLength(1));
  });

  test('network 失敗は入力を保持して再試行可能', () async {
    final h = Harness();
    await h.configure();
    final model = CreatorCodeController(code: 'MIKA');
    addTearDown(model.dispose);
    h.responder = (_) => throw http.ClientException('offline');
    await model.apply();
    expect(model.phase, CreatorCodePhase.failed);
    expect(model.issue, CreatorCodeIssue.network);
    expect(model.code, 'MIKA');
    h.responder = (_) => jsonResponse({'status': 'applied'});
    await model.apply();
    expect(model.phase, CreatorCodePhase.done);
  });

  testWidgets('headless の入力も debounce し、古い検証結果や消した特典を表示しない', (tester) async {
    final h = Harness();
    await h.configure();
    final old = Completer<http.Response>();
    h.responder = (_) => old.future;
    final model = CreatorCodeController();
    addTearDown(model.dispose);
    model.code = 'MIKA';
    await tester.pump(const Duration(milliseconds: 399));
    expect(model.phase, CreatorCodePhase.idle);
    await tester.pump(const Duration(milliseconds: 1));
    expect(model.phase, CreatorCodePhase.checking);
    model.code = 'SHO';
    old.complete(jsonResponse({
      'valid': true,
      'perk': {'label': '古い特典'}
    }));
    await tester.pump();
    expect(model.phase, CreatorCodePhase.idle);
    expect(model.perk, isNull);
    h.responder = (_) => jsonResponse({
          'valid': true,
          'perk': {'label': '新しい特典'}
        });
    await tester.pump(const Duration(milliseconds: 400));
    expect(model.phase, CreatorCodePhase.valid);
    expect(model.perk?.label, '新しい特典');
    expect(h.calls('codes/apply'), isEmpty);
    model.code = 'AB';
    expect(model.perk, isNull);
    expect(model.previewPerk, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(h.calls('codes/validate'), hasLength(2));
  });

  testWidgets('初期状態取得中のリンク貼付は取得後に検証・自動適用する', (tester) async {
    final h = Harness();
    final current = Completer<http.Response>();
    h.responder = (r) => r.url.path.endsWith('/current')
        ? current.future
        : Harness.defaultResponse(r);
    await h.configure();
    final model = CreatorCodeController();
    addTearDown(model.dispose);
    final loading = model.loadCurrentReferral();
    model.code = 'https://goalong.me/booknotion/MIKA';
    await tester.pump(const Duration(seconds: 1));
    expect(h.calls('codes/validate'), isEmpty);
    current.complete(jsonResponse({'status': 'none'}));
    await loading;
    await tester.pump(const Duration(milliseconds: 400));
    expect(model.phase, CreatorCodePhase.done);
    expect(h.body('codes/apply')['method'], 'CLIPBOARD');
  });

  test('同じコードのプレビューにリンクを貼っても CLIPBOARD になる', () async {
    final h = Harness();
    await h.configure();
    final model = CreatorCodeController(code: 'MIKA');
    addTearDown(model.dispose);
    await model.validatePreview();
    expect(model.phase, CreatorCodePhase.valid);
    model.code = 'https://goalong.me/booknotion/MIKA';
    await model.validatePreview();
    expect(model.phase, CreatorCodePhase.done);
    expect(h.calls('codes/apply'), hasLength(1));
    expect(h.body('codes/apply')['method'], 'CLIPBOARD');
  });

  for (final idSource in ['none', 'stored', 'explicit']) {
    test('perkPending は特典あり・未付与・RC ID 未設定のときだけ: $idSource', () async {
      final h = Harness();
      await h.configure();
      if (idSource == 'stored') await GoAlong.setRevenueCatUserID('saved');
      h.responder = (r) => r.url.path.endsWith('/validate')
          ? jsonResponse({
              'valid': true,
              'perk': {'label': '無料'}
            })
          : jsonResponse({'status': 'applied', 'perkLabel': '無料'});
      final model = CreatorCodeController(
          code: 'MIKA',
          rcAppUserId: idSource == 'explicit' ? 'explicit' : null);
      addTearDown(model.dispose);
      await model.validatePreview();
      expect(model.perk?.label, '無料');
      await model.apply();
      expect(model.phase, CreatorCodePhase.done);
      expect(model.perk, isNull);
      expect(model.perkPending, idSource == 'none');
    });
  }

  test('未ログインで適用後の再試行(already_applied + perkLabel)は付与待ちにする', () async {
    final h = Harness();
    await h.configure();
    h.responder =
        (_) => jsonResponse({'status': 'already_applied', 'perkLabel': '無料'});
    final model = CreatorCodeController(code: 'MIKA');
    addTearDown(model.dispose);
    await model.apply();
    expect(model.phase, CreatorCodePhase.done);
    expect(model.perkPending, true);
  });

  test('特典のない already_applied と apply では付与待ちにしない', () async {
    final h = Harness();
    await h.configure();
    for (final status in ['already_applied', 'applied']) {
      h.responder = (_) => jsonResponse({'status': status});
      final model = CreatorCodeController(code: 'MIKA');
      await model.apply();
      expect(model.phase, CreatorCodePhase.done);
      expect(model.perkPending, false);
      model.dispose();
    }
  });

  test('付与済み perk は done から読めて、付与待ちにしない', () async {
    final h = Harness();
    await h.configure();
    h.responder = (_) => jsonResponse({
          'status': 'applied',
          'perk': {'label': '無料', 'expiresAtMs': 2000000000000}
        });
    final model = CreatorCodeController(code: 'MIKA');
    addTearDown(model.dispose);
    await model.apply();
    expect(model.phase, CreatorCodePhase.done);
    expect(model.perk?.label, '無料');
    expect(model.perk?.expiresAtMs, 2000000000000);
    expect(model.perkPending, false);
  });

  test('置換の通信再試行は confirmReplace と CLIPBOARD を保持する', () async {
    final h = Harness();
    await h.configure();
    final model = CreatorCodeController();
    addTearDown(model.dispose);
    h.responder = (r) => r.url.path.endsWith('/apply')
        ? jsonResponse({'status': 'conflict'})
        : Harness.defaultResponse(r);
    model.code = 'https://goalong.me/booknotion/MIKA';
    await model.validatePreview();
    expect(model.issue, CreatorCodeIssue.conflict);
    h.responder = (_) => throw http.ClientException('offline');
    await model.apply(confirmReplace: true);
    expect(model.issue, CreatorCodeIssue.network);
    h.responder = Harness.defaultResponse;
    await model.retry();
    expect(model.phase, CreatorCodePhase.done);
    expect(h.body('codes/apply')['confirmReplace'], true);
    expect(h.body('codes/apply')['method'], 'CLIPBOARD');
  });

  test('破棄後のリンク検証結果は自動適用を始めない', () async {
    final h = Harness();
    await h.configure();
    final response = Completer<http.Response>();
    h.responder = (_) => response.future;
    final model = CreatorCodeController();
    model.code = 'https://goalong.me/booknotion/MIKA';
    final preview = model.validatePreview();
    model.dispose();
    response.complete(jsonResponse({'valid': true}));
    await preview;
    expect(h.calls('codes/apply'), isEmpty);
  });
}
