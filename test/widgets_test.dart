import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goalong/goalong.dart';
import 'package:http/http.dart' as http;

import 'support.dart';

Widget screen(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

Future<void> enterAndValidate(WidgetTester tester,
    [String code = 'MIKA']) async {
  await tester.enterText(find.byType(TextField), code);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void expectNoCreatorOrRemoval() {
  expect(find.text('MIKA'), findsNothing);
  expect(find.textContaining('MIKA さん'), findsNothing);
  expect(find.textContaining('SHO'), findsNothing);
  expect(find.text('紹介を取り消す'), findsNothing);
  expect(find.text('取り消す'), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
}

void main() {
  setUp(GoAlong.resetForTesting);
  tearDown(GoAlong.resetForTesting);

  testWidgets('手入力は 400ms 待って検証し、valid の確定ボタンでだけ適用', (tester) async {
    final h = Harness();
    final validation = Completer<http.Response>();
    final applying = Completer<http.Response>();
    h.responder = (r) {
      if (r.url.path.endsWith('/validate')) return validation.future;
      if (r.url.path.endsWith('/apply')) return applying.future;
      return Harness.defaultResponse(r);
    };
    await h.configure();
    var callbacks = 0;
    await tester
        .pumpWidget(screen(CreatorCodeInput(onApplied: (_) => callbacks++)));
    await tester.pumpAndSettle();
    expect(find.text('紹介コードをお持ちですか?'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await tester.enterText(find.byType(TextField), 'ｍｉｋａ');
    await tester.pump(const Duration(milliseconds: 399));
    expect(h.calls('codes/validate'), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(h.body('codes/validate')['code'], 'MIKA');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(h.calls('codes/apply'), isEmpty);
    validation.complete(jsonResponse({
      'valid': true,
      'creator': {'displayName': 'MIKA'},
      'perk': {'label': '1週間無料'},
    }));
    await tester.pumpAndSettle();
    expect(find.text('このコードで 1週間無料'), findsOneWidget);
    expect(find.text('このコードを使う'), findsOneWidget);
    expectNoCreatorOrRemoval();
    await tester.tap(find.text('このコードを使う'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    applying.complete(jsonResponse({
      'status': 'applied',
      'creator': {'displayName': 'MIKA'},
      'perk': {
        'label': '1週間無料',
        'expiresAtMs': DateTime(2026, 10, 11).millisecondsSinceEpoch
      },
    }));
    await tester.pumpAndSettle();
    expect(find.text('1週間無料 が適用されました'), findsOneWidget);
    expect(find.text('2026年10月11日 まで利用できます'), findsOneWidget);
    expect(callbacks, 1);
    expect(find.byType(TextField), findsNothing);
    expectNoCreatorOrRemoval();
  });

  testWidgets('紹介リンクを貼るとコードを抽出して CLIPBOARD で自動適用', (tester) async {
    final h = Harness();
    await h.configure();
    var callbacks = 0;
    await tester
        .pumpWidget(screen(CreatorCodeInput(onApplied: (_) => callbacks++)));
    await tester.pumpAndSettle();
    await enterAndValidate(tester, 'https://goalong.me/booknotion/mika');
    expect(h.calls('codes/validate'), hasLength(1));
    expect(h.body('codes/apply')['code'], 'MIKA');
    expect(h.body('codes/apply')['method'], 'CLIPBOARD');
    expect(find.text('コードを適用しました'), findsOneWidget);
    expect(find.text('特典はログイン後に受け取れます'), findsNothing);
    expect(callbacks, 1);
    expectNoCreatorOrRemoval();
  });

  testWidgets('conflict は名前なしで表示し、変更ボタンで confirmReplace を送る', (tester) async {
    final h = Harness();
    h.responder = (r) {
      if (!r.url.path.endsWith('/apply')) return Harness.defaultResponse(r);
      return jsonResponse(h.calls('codes/apply').length == 1
          ? {
              'status': 'conflict',
              'currentCreator': {'displayName': 'SHO'}
            }
          : {'status': 'applied'});
    };
    await h.configure();
    await tester.pumpWidget(screen(const CreatorCodeInput()));
    await tester.pumpAndSettle();
    await enterAndValidate(tester);
    await tester.tap(find.text('このコードを使う'));
    await tester.pumpAndSettle();
    expect(find.text('別の紹介コードが適用済みです'), findsOneWidget);
    expect(find.text('このコードに変更する'), findsOneWidget);
    expect(find.textContaining('SHO'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.calls('codes/apply'), hasLength(1));
    expect(h.body('codes/apply')['confirmReplace'], false);
    await tester.pump(const Duration(seconds: 2));
    expect(h.calls('codes/apply'), hasLength(1));
    await tester.tap(find.text('このコードに変更する'));
    await tester.pumpAndSettle();
    expect(h.calls('codes/apply'), hasLength(2));
    expect(h.body('codes/apply')['confirmReplace'], true);
  });

  for (final withPerk in [false, true]) {
    testWidgets('表示時点で適用済み: perk=$withPerk、入力や取消は表示しない', (tester) async {
      final h = Harness();
      h.responder = (_) => jsonResponse({
            'status': 'applied',
            'creator': {'displayName': 'MIKA'},
            if (withPerk)
              'perk': {
                'label': '無料',
                'expiresAtMs': DateTime(2026, 10, 11).millisecondsSinceEpoch
              },
          });
      await h.configure();
      await tester.pumpWidget(screen(const CreatorCodeInput()));
      await tester.pumpAndSettle();
      expect(
          find.text(withPerk ? '無料 が適用されました' : '紹介コードは適用済みです'), findsOneWidget);
      if (withPerk) expect(find.text('2026年10月11日 まで利用できます'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('紹介コードをお持ちですか?'), findsNothing);
      expectNoCreatorOrRemoval();
    });
  }

  testWidgets('取り消し済みは案内と入力欄を出し、再適用できる', (tester) async {
    final h = Harness();
    h.responder = (r) => r.url.path.endsWith('/current')
        ? jsonResponse({'status': 'removed'})
        : Harness.defaultResponse(r);
    await h.configure();
    await tester.pumpWidget(screen(const CreatorCodeInput()));
    await tester.pumpAndSettle();
    expect(find.text('紹介を取り消しました。別のコードを入力して再適用できます'), findsOneWidget);
    await enterAndValidate(tester);
    await tester.tap(find.text('このコードを使う'));
    await tester.pumpAndSettle();
    expect(find.text('コードを適用しました'), findsOneWidget);
    expect(h.calls('codes/remove'), isEmpty);
  });

  testWidgets('未ログインで特典の付与待ちなら専用の完了文言', (tester) async {
    final h = Harness();
    h.responder = (r) => r.url.path.endsWith('/validate')
        ? jsonResponse({
            'valid': true,
            'perk': {'label': '1週間無料'}
          })
        : Harness.defaultResponse(r);
    await h.configure();
    await tester.pumpWidget(screen(const CreatorCodeInput()));
    await tester.pumpAndSettle();
    await enterAndValidate(tester);
    await tester.tap(find.text('このコードを使う'));
    await tester.pumpAndSettle();
    expect(find.text('特典はログイン後に受け取れます'), findsOneWidget);
    expect(find.text('1週間無料 が適用されました'), findsNothing);
    expect(find.text('コードを適用しました'), findsNothing);
  });

  testWidgets('形式エラーは送信せず、確定時に表示する', (tester) async {
    final h = Harness();
    await h.configure();
    await tester.pumpWidget(screen(const CreatorCodeInput()));
    await tester.pumpAndSettle();
    for (final code in [
      'AB',
      'A-B-C',
      'ABCDEFGHIJKLMNOPQRSTU',
      'https://private.example/foo/ABC'
    ]) {
      await enterAndValidate(tester, code);
      expect(h.calls('codes/validate'), isEmpty);
      expect(find.byType(FilledButton), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('半角英数字 3〜20 文字で入力してください'), findsOneWidget);
    }
    expect(h.calls('codes/apply'), isEmpty);
  });

  for (final entry in {
    'not_found': 'コードが見つかりません。入力内容を確認してください',
    'expired': 'このコードは有効期限が切れています',
  }.entries) {
    testWidgets('検証失敗の文言: ${entry.key}', (tester) async {
      final h = Harness();
      h.responder = (r) => r.url.path.endsWith('/validate')
          ? jsonResponse({'valid': false, 'error': entry.key})
          : Harness.defaultResponse(r);
      await h.configure();
      await tester.pumpWidget(screen(const CreatorCodeInput()));
      await tester.pumpAndSettle();
      await enterAndValidate(tester);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(h.calls('codes/apply'), isEmpty);
    });
  }

  testWidgets('既存購読者メッセージと文言・色・スキップの差し替え', (tester) async {
    final h = Harness();
    await h.configure(isActiveSubscriber: () async => true);
    var skips = 0;
    await tester.pumpWidget(screen(CreatorCodeInput(
      labels: const CreatorCodeLabels(title: '招待', useThisCode: '利用する'),
      theme: const GoAlongTheme(accent: Colors.purple, onAccent: Colors.white),
      onSkip: () => skips++,
    )));
    await tester.pumpAndSettle();
    expect(find.text('招待'), findsOneWidget);
    await tester.tap(find.text('あとで'));
    expect(skips, 1);
    await enterAndValidate(tester);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.style!.backgroundColor!.resolve({}), Colors.purple);
    await tester.tap(find.text('利用する'));
    await tester.pumpAndSettle();
    expect(find.text('有料プランをご契約中のため、この紹介コードはご利用いただけません'), findsOneWidget);
    expect(h.calls('codes/apply'), isEmpty);
  });

  for (final endpoint in ['current', 'validate', 'apply']) {
    testWidgets('通信失敗を表示し、もう一度試すで $endpoint を再試行', (tester) async {
      final h = Harness();
      var offline = true;
      h.responder = (r) {
        if (r.url.path.endsWith('/$endpoint') && offline) {
          throw http.ClientException('offline');
        }
        return Harness.defaultResponse(r);
      };
      await h.configure();
      await tester.pumpWidget(screen(const CreatorCodeInput()));
      await tester.pumpAndSettle();
      if (endpoint != 'current') await enterAndValidate(tester);
      if (endpoint == 'apply') {
        await tester.tap(find.text('このコードを使う'));
        await tester.pumpAndSettle();
      }
      expect(find.text('通信に失敗しました。時間をおいてお試しください'), findsOneWidget);
      expect(find.text('もう一度試す'), findsOneWidget);
      offline = false;
      await tester.tap(find.text('もう一度試す'));
      await tester.pumpAndSettle();
      expect(find.text('通信に失敗しました。時間をおいてお試しください'), findsNothing);
      expect(h.calls('codes/$endpoint'), hasLength(2));
      if (endpoint == 'validate') expect(h.calls('codes/apply'), isEmpty);
      if (endpoint == 'apply') expect(find.text('コードを適用しました'), findsOneWidget);
    });
  }

  testWidgets('入力直後の破棄で debounce を解除する', (tester) async {
    final h = Harness();
    await h.configure();
    await tester.pumpWidget(screen(const CreatorCodeInput()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'MIKA');
    await tester.pumpWidget(screen(const SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 1));
    expect(h.calls('codes/validate'), isEmpty);
    expect(h.calls('codes/apply'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('適用済みなら clipboard も config も読まず入口を隠す', (tester) async {
    final h = Harness();
    h.storage.values['goalong.referral_applied'] = true;
    await h.configure();
    var reads = 0;
    await tester.pumpWidget(
      screen(
        ReferralEntry(
          clipboardReader: () async {
            reads++;
            return 'https://goalong.me/booknotion/MIKA';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('紹介コードを入力する'), findsNothing);
    expect(reads, 0);
    expect(h.calls('config'), isEmpty);
  });

  testWidgets('既存購読者の入口を隠す', (tester) async {
    final h = Harness();
    await h.configure(isActiveSubscriber: () async => true);
    await tester.pumpWidget(screen(const ReferralEntry()));
    await tester.pumpAndSettle();
    expect(find.text('紹介コードを入力する'), findsNothing);
    expect(h.calls('config'), isEmpty);
  });

  testWidgets('正規 clipboard リンクなら config を待たず開き、自動適用する', (tester) async {
    final h = Harness();
    await h.configure();
    var callbacks = 0;
    await tester.pumpWidget(screen(ReferralEntry(
      clipboardReader: () async => 'https://goalong.me/booknotion/mika',
      onApplied: (_) => callbacks++,
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'MIKA');
    expect(h.calls('config'), isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.body('codes/apply')['method'], 'CLIPBOARD');
    expect(find.byType(TextField), findsNothing);
    expect(callbacks, 1);
  });

  testWidgets('無関係な clipboard は無視し、受付中のときだけ入口を出す', (tester) async {
    final h = Harness();
    await h.configure();
    await tester.pumpWidget(
      screen(
        ReferralEntry(
          clipboardReader: () async => 'https://private.example/account/SECRET',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('紹介コードを入力する'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(h.calls('codes/validate'), isEmpty);
    expect(h.calls('codes/apply'), isEmpty);
    await tester.tap(find.text('紹介コードを入力する'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
  });

  testWidgets('clipboardReader 未指定・拒否、受付停止時は入力欄を出さない', (tester) async {
    final h = Harness();
    await h.configure();
    h.responder =
        (_) => jsonResponse({'entryEnabled': false, 'cacheMaxAgeSeconds': 0});
    await tester.pumpWidget(screen(const ReferralEntry()));
    await tester.pumpAndSettle();
    expect(find.text('紹介コードを入力する'), findsNothing);
    await tester.pumpWidget(
      screen(
        ReferralEntry(
          key: const ValueKey('denied'),
          clipboardReader: () async => throw StateError('permission denied'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('紹介コードを入力する'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('破棄後の clipboard 応答は UI を更新しない', (tester) async {
    final h = Harness();
    await h.configure();
    final clipboard = Completer<String?>();
    await tester.pumpWidget(
      screen(ReferralEntry(clipboardReader: () => clipboard.future)),
    );
    await tester.pump();
    await tester.pumpWidget(screen(const SizedBox.shrink()));
    clipboard.complete('https://goalong.me/booknotion/MIKA');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(h.calls('config'), isEmpty);
  });
}
