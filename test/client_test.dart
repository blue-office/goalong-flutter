import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goalong/goalong.dart';
import 'package:http/http.dart' as http;

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(GoAlong.resetForTesting);
  tearDown(GoAlong.resetForTesting);

  Matcher errorKind(GoAlongErrorKind kind) =>
      isA<GoAlongException>().having((error) => error.kind, 'kind', kind);

  test('未設定の API は notConfigured', () async {
    for (final action in <Future<Object?> Function()>[
      GoAlong.installationId,
      GoAlong.attributionAttributes,
      () => GoAlong.setRevenueCatUserID('user'),
      () => GoAlong.validateCode('MIKA'),
      () => GoAlong.applyCode('MIKA'),
      GoAlong.currentReferral,
      GoAlong.removeReferral,
      GoAlong.referralEntryEnabled,
    ]) {
      await expectLater(
        action(),
        throwsA(errorKind(GoAlongErrorKind.notConfigured)),
      );
    }
  });

  test('UUID v4 を一度だけ生成し、起動をまたいで保持する', () async {
    final h = Harness();
    await h.configure();
    final ids = await Future.wait(
      List.generate(20, (_) => GoAlong.installationId()),
    );
    expect(ids.toSet(), hasLength(1));
    expect(
      ids.first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    await GoAlong.resetForTesting();
    await h.configure();
    expect(await GoAlong.installationId(), ids.first);
    expect(h.storage.values['goalong.installation_id'], ids.first);
  });

  test('installation はバックグラウンド報告し、成功を保存して再送しない', () async {
    final response = Completer<http.Response>();
    final h = Harness(reported: false);
    h.responder = (_) => response.future;
    await h.configure(); // ネットワークの完了を待たない。
    response.complete(jsonResponse({'ok': true}));
    await GoAlong.debugWaitForInstallationReport();
    final body = h.body('installations');
    expect(body['installationId'], await GoAlong.installationId());
    expect(body, containsPair('sdkVersion', '0.1.0'));
    expect(body, containsPair('osVersion', 'testOS'));
    expect(body, containsPair('appVersion', '1.2.3'));
    expect(body, containsPair('locale', 'ja-JP'));
    expect(h.storage.values['goalong.installation_reported'], true);
    await GoAlong.resetForTesting();
    await h.configure();
    await GoAlong.debugWaitForInstallationReport();
    expect(h.calls('installations'), hasLength(1));
  });

  test('installation の失敗は次の起動で再試行', () async {
    final h = Harness(reported: false);
    h.responder = (_) => jsonResponse({'error': 'offline'}, status: 503);
    await h.configure();
    await GoAlong.debugWaitForInstallationReport();
    expect(h.storage.values['goalong.installation_reported'], isNull);
    await GoAlong.resetForTesting();
    h.responder = (_) => jsonResponse({'ok': true});
    await h.configure();
    await GoAlong.debugWaitForInstallationReport();
    expect(h.calls('installations'), hasLength(2));
    expect(h.storage.values['goalong.installation_reported'], true);
  });

  test('検証時の正規化、特典、invalid_format / not_found / expired', () async {
    final h = Harness();
    await h.configure();
    h.responder = (_) => jsonResponse({
          'valid': true,
          'code': 'MIKA',
          'creator': {
            'displayName': 'みか',
            'avatarUrl': 'https://example.com/a.png',
          },
          'perk': {'label': '1週間無料', 'entitlement': null, 'duration': 'weekly'},
        });
    final validation = await GoAlong.validateCode('　ｍｉｋａ　');
    expect(validation.valid, true);
    expect(validation.creator?.displayName, 'みか');
    expect(validation.perk?.duration, 'weekly');
    expect(h.body('codes/validate')['code'], 'MIKA');
    for (final kind in CodeErrorKind.values) {
      h.responder = (_) => jsonResponse({'valid': false, 'error': kind.value});
      expect((await GoAlong.validateCode('ABC')).error, kind);
    }
  });

  test('apply の全 status と nullable creator を変換', () async {
    final h = Harness();
    await h.configure();
    final cases = <String, Matcher>{
      'applied': isA<Applied>(),
      'already_applied': isA<AlreadyApplied>(),
      'conflict': isA<Conflict>(),
      'existing_subscriber': isA<ExistingSubscriber>(),
      'not_found': isA<NotFound>(),
      'expired': isA<NotFound>().having(
        (r) => r.error,
        'error',
        CodeErrorKind.expired,
      ),
    };
    for (final entry in cases.entries) {
      h.responder = (_) => jsonResponse({'status': entry.key, 'creator': null});
      expect(await GoAlong.applyCode('MIKA'), entry.value);
    }
    h.responder =
        (_) => jsonResponse({'status': 'not_found', 'error': 'invalid_format'});
    expect(
      await GoAlong.applyCode('MIKA'),
      isA<NotFound>().having(
        (r) => r.error,
        'error',
        CodeErrorKind.invalidFormat,
      ),
    );
    h.responder = (_) => jsonResponse({
          'status': 'conflict',
          'currentCreator': {'displayName': 'SHO'},
        });
    expect(
      await GoAlong.applyCode('MIKA'),
      isA<Conflict>().having(
        (r) => r.currentCreator?.displayName,
        'currentCreator',
        'SHO',
      ),
    );
  });

  test('confirmReplace、method、保存済み RevenueCat ID、明示 ID を送信', () async {
    final h = Harness();
    await h.configure();
    await GoAlong.setRevenueCatUserID('saved-user');
    expect(h.calls('perks/claim'), isEmpty);
    await GoAlong.applyCode(
      'ｍｉｋａ',
      method: ApplyMethod.deepLink,
      confirmReplace: true,
    );
    expect(h.body('codes/apply'), containsPair('confirmReplace', true));
    expect(h.body('codes/apply'), containsPair('rcAppUserId', 'saved-user'));
    expect(h.body('codes/apply'), containsPair('method', 'DEEP_LINK'));
    expect(h.body('codes/apply'), containsPair('code', 'MIKA'));
    await GoAlong.applyCode(
      'MIKA',
      rcAppUserId: 'explicit',
      method: ApplyMethod.clipboard,
    );
    expect(h.body('codes/apply'), containsPair('rcAppUserId', 'explicit'));
    expect(h.body('codes/apply'), containsPair('method', 'CLIPBOARD'));
    expect(h.body('codes/apply'), containsPair('confirmReplace', false));
    expect(h.storage.values['goalong.rc_app_user_id'], 'saved-user');
  });

  test('既存購読者は送信しない。呼び出し単位の callback が優先', () async {
    final h = Harness();
    await h.configure(isActiveSubscriber: () async => true);
    expect(await GoAlong.applyCode('MIKA'), isA<ExistingSubscriber>());
    expect(h.calls('codes/apply'), isEmpty);
    expect(
      await GoAlong.applyCode('MIKA', isActiveSubscriber: () async => false),
      isA<Applied>(),
    );
    expect(h.calls('codes/apply'), hasLength(1));
  });

  test('購読判定に失敗しても適用を続ける(サーバーでも再判定する)', () async {
    final h = Harness();
    await h.configure(
      isActiveSubscriber: () async => throw StateError('unavailable'),
    );
    await GoAlong.applyCode('MIKA');
    expect(h.calls('codes/apply'), hasLength(1));
  });

  test('無関係な URL や不正形式をサーバーに送らない', () async {
    final h = Harness();
    await h.configure();
    for (final value in [
      'https://private.example/account/SECRET',
      'AB',
      'A-B-C',
    ]) {
      expect(
        (await GoAlong.validateCode(value)).error,
        CodeErrorKind.invalidFormat,
      );
      expect(await GoAlong.applyCode(value), isA<NotFound>());
    }
    expect(h.calls('codes/validate'), isEmpty);
    expect(h.calls('codes/apply'), isEmpty);
    await GoAlong.applyCode('https://goalong.me/booknotion/mika');
    expect(h.body('codes/apply')['code'], 'MIKA');
  });

  test('attributionAttributes の未適用・適用済み・offering の 3 パターン', () async {
    final h = Harness();
    await h.configure();
    final id = await GoAlong.installationId();
    expect(await GoAlong.attributionAttributes(), {
      'goalong_installation_id': id,
    });
    await GoAlong.applyCode('MIKA');
    expect(await GoAlong.attributionAttributes(), {
      'goalong_installation_id': id,
      'goalong_referred': 'true',
    });
    h.responder =
        (_) => jsonResponse({'status': 'applied', 'offeringKey': 'intro'});
    await GoAlong.applyCode('SHO', confirmReplace: true);
    expect(await GoAlong.attributionAttributes(), {
      'goalong_installation_id': id,
      'goalong_referred': 'true',
      'goalong_offering': 'intro',
    });
    h.responder = (_) => jsonResponse({'status': 'applied'});
    await GoAlong.applyCode('ABC', confirmReplace: true);
    expect(
      (await GoAlong.attributionAttributes()).containsKey('goalong_offering'),
      false,
    );
  });

  test('already_applied でも適用済みを保存し、offering は応答に合わせる', () async {
    final h = Harness();
    h.storage.values['goalong.referral_offering_key'] = 'intro';
    h.responder = (_) => jsonResponse({'status': 'already_applied'});
    await h.configure();
    await GoAlong.applyCode('MIKA');
    expect(await GoAlong.hasAppliedReferralLocally(), true);
    expect(
      (await GoAlong.attributionAttributes()).containsKey('goalong_offering'),
      isFalse,
    );
  });

  test('特典の後追い取得で perk を返し offeringKey を保存', () async {
    final h = Harness();
    await h.configure();
    await GoAlong.applyCode('MIKA');
    h.responder = (_) => jsonResponse({
          'status': 'granted',
          'offeringKey': 'intro',
          'perk': {
            'label': '1週間無料',
            'entitlement': 'pro',
            'expiresAtMs': 2000000000000,
          },
        });
    final perk = await GoAlong.setRevenueCatUserID('login-user');
    expect(perk?.entitlement, 'pro');
    expect(perk?.expiresAt?.millisecondsSinceEpoch, 2000000000000);
    expect(h.body('perks/claim')['rcAppUserId'], 'login-user');
    expect(
      (await GoAlong.attributionAttributes())['goalong_offering'],
      'intro',
    );
    for (final status in ['no_perk', 'no_attribution', 'existing_subscriber']) {
      h.responder = (_) => jsonResponse({'status': status});
      expect(await GoAlong.setRevenueCatUserID('login-user'), isNull);
    }
  });

  test('claim の結果に offering が無ければ古い値を消す', () async {
    final h = Harness();
    await h.configure();
    h.responder =
        (_) => jsonResponse({'status': 'applied', 'offeringKey': 'intro'});
    await GoAlong.applyCode('MIKA');
    h.responder = (_) => jsonResponse({'status': 'no_perk'});
    await GoAlong.setRevenueCatUserID('login-user');
    expect(
      (await GoAlong.attributionAttributes()).containsKey('goalong_offering'),
      isFalse,
    );
  });

  test('取消成功時は referred と offering を消す。失敗時は保持', () async {
    final h = Harness();
    await h.configure();
    h.responder =
        (_) => jsonResponse({'status': 'applied', 'offeringKey': 'intro'});
    await GoAlong.applyCode('MIKA');
    h.responder = (_) => jsonResponse({}, status: 500);
    await expectLater(
      GoAlong.removeReferral(),
      throwsA(errorKind(GoAlongErrorKind.server)),
    );
    expect(await GoAlong.hasAppliedReferralLocally(), true);
    h.responder = (_) => jsonResponse({'status': 'removed'});
    expect(await GoAlong.removeReferral(), true);
    expect(await GoAlong.hasAppliedReferralLocally(), false);
    expect((await GoAlong.attributionAttributes()).keys, [
      'goalong_installation_id',
    ]);
    h.storage.values['goalong.referral_applied'] = true;
    h.responder = (_) => jsonResponse({'status': 'no_attribution'});
    expect(await GoAlong.removeReferral(), false);
    expect(await GoAlong.hasAppliedReferralLocally(), false);
  });

  test('currentReferral の日時・特典・none・removed', () async {
    final h = Harness();
    await h.configure();
    h.responder = (_) => jsonResponse({
          'status': 'applied',
          'creator': {'displayName': 'MIKA'},
          'appliedAt': '2026-01-01T00:00:00.000Z',
          'perk': {'label': '無料', 'expiresAtMs': 2000000000000},
        });
    final result = await GoAlong.currentReferral() as ReferralApplied;
    expect(result.appliedAt, DateTime.utc(2026));
    expect(result.perk?.label, '無料');
    expect(result.perk?.entitlement, isNull);
    expect(h.calls('codes/current').last.url.queryParameters, {
      'appId': 'test-app',
      'installationId': await GoAlong.installationId(),
    });
    h.responder = (_) => jsonResponse({
          'status': 'removed',
          'removedAt': '2026-01-02T00:00:00Z',
        });
    expect(await GoAlong.currentReferral(), isA<ReferralRemoved>());
    h.responder = (_) => jsonResponse({'status': 'none'});
    expect(await GoAlong.currentReferral(), isA<ReferralNone>());
    expect(await GoAlong.hasAppliedReferralLocally(), false);
  });

  test('config はサーバー TTL の期間だけメモリに保持し同時取得をまとめる', () async {
    final h = Harness();
    await h.configure();
    var now = DateTime.utc(2026);
    GoAlong.debugNow = () => now;
    expect(
      await Future.wait(
        List.generate(8, (_) => GoAlong.referralEntryEnabled()),
      ),
      everyElement(true),
    );
    expect(h.calls('config'), hasLength(1));
    now = now.add(const Duration(seconds: 59));
    expect(await GoAlong.referralEntryEnabled(), true);
    expect(h.calls('config'), hasLength(1));
    now = now.add(const Duration(seconds: 1));
    h.responder =
        (_) => jsonResponse({'entryEnabled': false, 'cacheMaxAgeSeconds': 0});
    expect(await GoAlong.referralEntryEnabled(), false);
    expect(await GoAlong.referralEntryEnabled(), false);
    expect(h.calls('config'), hasLength(3));
    expect(h.calls('config').first.url.queryParameters, {'appId': 'test-app'});
    expect(h.storage.values.keys.where((k) => k.contains('entry')), isEmpty);
  });

  test('config 失敗は前回値、なければ false、失敗をキャッシュしない', () async {
    final h = Harness();
    await h.configure();
    h.responder = (_) => throw http.ClientException('offline');
    expect(await GoAlong.referralEntryEnabled(), false);
    h.responder =
        (_) => jsonResponse({'entryEnabled': true, 'cacheMaxAgeSeconds': 0});
    expect(await GoAlong.referralEntryEnabled(), true);
    h.responder = (_) => jsonResponse({}, status: 503);
    expect(await GoAlong.referralEntryEnabled(), true);
    expect(h.calls('config'), hasLength(3));
  });

  test('network、JSON 不正、2xx 以外を区別', () async {
    final h = Harness();
    await h.configure();
    h.responder = (_) => throw http.ClientException('offline');
    await expectLater(
      GoAlong.applyCode('MIKA'),
      throwsA(errorKind(GoAlongErrorKind.network)),
    );
    h.responder = (_) => http.Response('not json', 200);
    await expectLater(
      GoAlong.applyCode('MIKA'),
      throwsA(errorKind(GoAlongErrorKind.network)),
    );
    h.responder = (_) => jsonResponse({'status': 'unknown'});
    await expectLater(
      GoAlong.applyCode('MIKA'),
      throwsA(errorKind(GoAlongErrorKind.network)),
    );
    h.responder = (_) => http.Response('not json', 429);
    await expectLater(
      GoAlong.applyCode('MIKA'),
      throwsA(
        isA<GoAlongException>()
            .having((e) => e.kind, 'kind', GoAlongErrorKind.server)
            .having((e) => e.statusCode, 'statusCode', 429),
      ),
    );
    h.responder = (_) => jsonResponse({'status': 'applied'}, status: 201);
    expect(await GoAlong.applyCode('MIKA'), isA<Applied>());
  });

  testWidgets('未完了の installation を待たず reset し、遅い応答を保存しない', (tester) async {
    final response = Completer<http.Response>();
    final h = Harness(reported: false);
    h.responder = (_) => response.future;
    await h.configure();
    await tester.pump();
    expect(h.calls('installations'), hasLength(1));
    await GoAlong.resetForTesting();
    await tester.pump();
    // タイムアウトを進めずにリセットが完了し、新しいクライアントを使える。
    final next = Harness();
    await next.configure();
    response.complete(jsonResponse({'ok': true}));
    await tester.pump();
    expect(h.storage.values['goalong.installation_reported'], isNull);
    expect(await GoAlong.installationId(),
        next.storage.values['goalong.installation_id']);
    // 注入したクライアントは SDK が close しない。
    expect(
        (await h.client.get(Uri.https('example.test', '/'))).statusCode, 200);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('完了した installation の Future をテスト外の tearDown で待たない',
      (tester) async {
    final h = Harness(reported: false);
    await h.configure();
    await GoAlong.debugWaitForInstallationReport();
    expect(h.storage.values['goalong.installation_reported'], true);
    // resetForTesting はこの FakeAsync zone の外の tearDown で呼ばれる。
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('保存済み RevenueCat ID の有無を返す', () async {
    final h = Harness();
    await h.configure();
    expect(await GoAlong.hasRevenueCatUserID(), false);
    await GoAlong.setRevenueCatUserID('saved-user');
    expect(await GoAlong.hasRevenueCatUserID(), true);
  });

  testWidgets('通信は 15 秒でタイムアウトする', (tester) async {
    final h = Harness();
    await h.configure();
    h.responder = (_) => Completer<http.Response>().future;
    final assertion = expectLater(
      GoAlong.validateCode('MIKA'),
      throwsA(errorKind(GoAlongErrorKind.network)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    await assertion;
  }, timeout: const Timeout(Duration(seconds: 30)));
}
