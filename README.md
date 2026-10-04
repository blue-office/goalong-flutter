# GoAlong Flutter SDK

紹介コード・紹介リンクの検証、適用、特典の取得を Flutter アプリに追加します。
Flutter 3.22 以上 / Dart 3.4 以上（Dart 3、null safety）に対応します。
iOS・Android で紹介の適用と状態取得を利用できます。報酬の対象となる課金は App Store のみです。

## 導入

アプリの `pubspec.yaml` に追加します。

```yaml
dependencies:
  goalong:
    git: { url: https://github.com/blue-office/goalong-flutter.git, ref: 0.1.0 }
```

```sh
flutter pub get
```

SDK の実行時依存は Flutter、`http`、`shared_preferences` です。
RevenueCat を利用するアプリでは `purchases_flutter` も追加してください。
Android アプリはメインの AndroidManifest.xml にインターネット通信の権限を設定します。

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

## 初期化

起動時に一度、画面を表示する前に呼びます。

```dart
import 'package:flutter/material.dart';
import 'package:goalong/goalong.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GoAlong.configure(
    appId: 'YOUR_APP_ID',
    appSlug: 'your-app',
    appVersion: '1.0.0',
  );
  runApp(const MaterialApp(
    home: Scaffold(body: Padding(
      padding: EdgeInsets.all(24),
      child: CreatorCodeInput(),
    )),
  ));
}
```

`appId` は GoAlong のアプリ ID、`appSlug` は紹介リンクの最初のパス要素です。
`appSlug` の指定を推奨します。指定すると別アプリのリンクを受け付けません。
`baseUrl` の既定値は `https://goalong.me` です。
`configure` は端末 ID の保存まで待ち、初回の installation 報告はバックグラウンドで行います。
報告に失敗した場合は次の起動で再試行します。

`appVersion` はアプリから渡してください。省略時は `--dart-define=APP_VERSION=1.0.0`
の値、未指定なら `unknown` になります。`osVersion` と `locale` は自動取得し、引数でも指定できます。

## RevenueCat との連携

`Purchases.configure` の後に、RevenueCat の App User ID を渡します。
既存購読者の判定は、アプリの `CustomerInfo` を使うコールバックを設定します。

```dart
import 'package:goalong/goalong.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

Future<void> configureServices(String revenueCatApiKey) async {
  // プラットフォームに対応する RevenueCat の公開 SDK キーを渡します。
  await Purchases.configure(PurchasesConfiguration(revenueCatApiKey));
  await GoAlong.configure(
    appId: 'YOUR_APP_ID',
    appSlug: 'your-app',
    appVersion: '1.0.0',
    isActiveSubscriber: () async {
      final info = await Purchases.getCustomerInfo();
      // GoAlong の特典などで付与された無料期間(rc_promo_ で始まる)は購読に数えない
      return info.activeSubscriptions.any((id) => !id.startsWith('rc_promo'));
    },
  );
  await GoAlong.setRevenueCatUserID(await Purchases.appUserID);
  await syncReferralAttributes();
}

Future<void> syncReferralAttributes() async {
  final attributes = await GoAlong.attributionAttributes();
  await Purchases.setAttributes({
    ...attributes,
    // 紹介取消や特典変更で不要になった属性も削除します。
    'goalong_referred': attributes['goalong_referred'] ?? '',
    'goalong_offering': attributes['goalong_offering'] ?? '',
  });
}

Future<void> onLogin(String userId) async {
  await Purchases.logIn(userId);
  final perk = await GoAlong.setRevenueCatUserID(await Purchases.appUserID);
  await syncReferralAttributes();
  if (perk != null) {
    // perk.label と perk.expiresAt をアプリの完了画面で表示できます。
  }
}

Future<Offerings> offeringsForPaywall() async {
  await syncReferralAttributes();
  return Purchases.syncAttributesAndOfferingsIfNeeded();
}
```

ログイン・ログアウトなどで RevenueCat の ID が変わった後も `setRevenueCatUserID` を呼びます。
紹介が適用済みなら保留中の特典を取得し、付与された `Perk` を返します。
特典がない場合や既存購読者の場合は `null` を返します。通信に失敗した場合は例外になるため、
アプリ側で扱い、次回ログイン時などに再試行してください。ID 自体は通信より先に保存します。

`isActiveSubscriber` が `true` を返すと適用リクエストを送らず `ExistingSubscriber` を返します。
`applyCode` の引数で呼び出しごとに上書きできます。コールバックが失敗した場合は判定せずに適用を続けます(RevenueCat ID があればサーバーが再判定します)。
未設定の場合、端末での購読判定は行いません。サーバーは RevenueCat ID があれば再判定します。
SDK は StoreKit を直接呼び出しません。

紹介適用・取消後にも属性を同期してください。RevenueCat の Targeting を使う場合は
`setAttributes` の後に `syncAttributesAndOfferingsIfNeeded` を待ち、返された
`Offerings.current` からペイウォールを表示します。
属性の空文字による削除と同期方法は [RevenueCat の属性ガイド](https://www.revenuecat.com/docs/customers/customer-attributes) も参照してください。

## コード入力欄

オンボーディング、設定画面、ペイウォールなど、`MaterialApp` 配下に配置します。

```dart
CreatorCodeInput(
  onApplied: (_) async {
    await syncReferralAttributes();
    // アプリの完了画面へ進むなど。
  },
  onSkip: () {
    // 「あとで」を表示して、次の画面へ進むなど。
  },
)
```

形式に合うコードを入力して 400ms 待つと検証し、特典があれば「このコードで {特典}」を表示します。
検証に成功したときだけ「このコードを使う」ボタンを表示し、タップで適用します。
正規の紹介 URL を貼り付けた場合はコードを取り出し、検証後に `CLIPBOARD` として自動適用します。
紹介者名はどの状態でも表示しません。別のコードが適用済みの場合は
「別の紹介コードが適用済みです」と「このコードに変更する」ボタンを表示します。
このボタンを押した場合だけ `confirmReplace: true` で再実行します。

完了時は、付与された特典があれば「{特典} が適用されました」と「{日付} まで利用できます」、
特典がなければ「コードを適用しました」と表示します。特典があり、RevenueCat ID が
未設定でまだ付与されていない場合は「特典はログイン後に受け取れます」と表示します。

表示時点で適用済みなら、入力欄の代わりに「紹介コードは適用済みです」、
または付与済み特典とその期限を表示します。取消済みなら
「紹介を取り消しました。別のコードを入力して再適用できます」と入力欄を表示します。
取消 UI は提供しません。必要な場合は `await GoAlong.removeReferral()` を呼び、
RevenueCat の属性を同期してください。受け取り済みの特典は期限まで利用できます。

通信失敗時は「もう一度試す」で失敗した操作を再試行できます。
`onSkip` を渡した場合だけ、入力画面に「あとで」を表示します。

色はアプリの `Theme` に従い、既定のアクセントはモノクロです。文言と色を変更できます。

```dart
CreatorCodeInput(
  labels: const CreatorCodeLabels(
    title: '招待コード',
    useThisCode: 'このコードを使う',
  ),
  theme: GoAlongTheme(
    accent: Theme.of(context).colorScheme.primary,
    onAccent: Theme.of(context).colorScheme.onPrimary,
  ),
)
```

`CreatorCodeLabels` でエラー、変更確認、完了、取消済みの案内、スキップ、日付の文言も変更できます。
文中の `{perk}`、`{date}` は表示時に置換します。紹介者名を含む labels はありません。
`dateFormatter` を渡すと特典の期限の日付形式を変更できます。

### 独自 UI

`CreatorCodeController` は `ChangeNotifier` です。`ListenableBuilder` などで監視できます。

```dart
final controller = CreatorCodeController();
await controller.loadCurrentReferral();
controller.code = 'MIKA';
// setter が 400ms 後の検証を予約します。今すぐ検証する場合:
await controller.validatePreview();
if (controller.phase == CreatorCodePhase.valid) {
  // 独自 UI の「このコードを使う」ボタンで実行する処理:
  await controller.apply();
}
// phase、issue、perk、perkPending、current を表示に利用します。
// conflict は「このコードに変更する」ボタンから
// await controller.apply(confirmReplace: true) で変更します。
// 通信失敗は await controller.retry() で再試行します。
controller.dispose();
```

状態は `idle / checking / valid / applying / done / failed` です。
`valid` の `perk` は検証時の特典、`done` の `perk` は付与済みの特典です。
`done` の `perkPending` はログイン後に特典を受け取れることを表し、`failed` の理由は `issue` で取得します。
紹介リンクを `controller.code` に代入すると、headless でも検証後に自動適用します。
`fill(code, method: ApplyMethod.clipboard)` でも同じ動作になります。
`reset()` と `dispose()` は検証タイマーを解除し、古い応答を無視します。
`creator` / `conflictCreator` と `onApplied` の引数は API のメタデータとして保持しますが、紹介者名の表示には使いません。

以前の Flutter 版から移行する場合、`labels.apply` は `labels.useThisCode` に変更してください。
紹介者名・取消操作の labels、`onRemoved`、`controller.removeReferral()` は削除しました。
取消には `GoAlong.removeReferral()` を使います。

`CreatorCodeInput(controller: controller)` で既成 UI に渡すこともできます。
外から渡したコントローラーの `dispose` はアプリ側で行ってください。

## 初回画面の入口

```dart
const ReferralEntry()
```

適用済み・既存購読者なら非表示になります。
それ以外は受付中のときだけ「紹介コードを入力する」を表示し、タップで開きます。

クリップボードを使う場合はアプリ側で読み取り関数を渡します。
SDK はこの関数が渡されたときだけ、一度呼び出します。
関数内でアプリの同意や OS の許可を扱ってください。

```dart
import 'package:flutter/services.dart';

ReferralEntry(
  clipboardReader: () async {
    // アプリで読み取りへの同意を得た場合に利用してください。
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  },
  onApplied: (_) async {
    await syncReferralAttributes();
  },
)
```

正規の紹介リンクが見つかると、受付設定の取得を待たず、コードを入れた状態で開きます。
検証後に `CLIPBOARD` として自動適用します。無関係なテキストやコード単体では自動展開しません。
読み取りを拒否された場合は、通常の手入力の入口に戻ります。
入口の文言は `ReferralEntryLabels`、入力欄は `inputLabels` で変更できます。

## ディープリンク

iOS の Associated Domains、Android の App Links と受信処理はアプリ側で設定します。
受け取ったリンクを渡すと、適用せずにコードを取り出します。

```dart
void onIncomingLink(Uri uri, BuildContext context) {
  final code = GoAlong.handleDeepLink(uri);
  if (code == null) return;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: CreatorCodeInput(initialCode: code, method: ApplyMethod.deepLink),
      ),
    ),
  );
}
```

受け付ける形式は `https://goalong.me/{appSlug}/{CODE}` です。
HTTPS、ユーザー情報・ポートなし、許可ホストまたはそのサブドメイン、ちょうど 2 要素のパス、
設定済み slug との一致を検査します。コードは NFKC、前後空白除去、大文字化の後、
半角英数字 3〜20 文字に限定します。

元の文字列がある場合は `GoAlong.extractCode(rawLink)` を利用してください。
Dart の `Uri` は標準ポート `:443` やパスの `..` などを正規化して元の表記を失うため、
`handleDeepLink(Uri)` はその表記を遡って拒否できません。文字列版は正規化前に検査します。
詳細は [Dart Uri のポート仕様](https://api.dart.dev/dart-core/Uri/hasPort.html) を参照してください。

## API 一覧

| API | 戻り値・動作 |
|---|---|
| `configure(...)` | `Future<void>`。起動時の初期化 |
| `installationId()` | `Future<String>`。永続化した UUID v4 |
| `setRevenueCatUserID(id)` | `Future<Perk?>`。ID 保存と適用済み特典の後追い取得 |
| `attributionAttributes()` | `Future<Map<String, String>>`。RevenueCat に渡す属性 |
| `validateCode(code)` | `Future<CodeValidation>`。適用せず検証 |
| `applyCode(code, ...)` | `Future<ApplyResult>`。紹介を適用 |
| `currentReferral()` | `Future<ReferralSnapshot>`。サーバー上の現在状態 |
| `removeReferral()` | `Future<bool>`。取消成立なら `true`、適用なしなら `false` |
| `handleDeepLink(Uri)` | `String?`。リンクから抽出のみ |
| `extractCode(String)` | `String?`。生のリンク文字列から抽出のみ |
| `referralEntryEnabled()` | `Future<bool>`。サーバー指定期間のメモリキャッシュ |
| `hasAppliedReferralLocally()` | `Future<bool>`。端末保存の適用済み状態 |
| `hasRevenueCatUserID()` | `Future<bool>`。保存済み RevenueCat ID の有無 |
| `hasActiveSubscription(...)` | `Future<bool>`。設定した購読判定コールバックを実行 |

`applyCode` の任意引数は `method`（`ApplyMethod.code / deepLink / clipboard`）、
`rcAppUserId`、`confirmReplace`、`isActiveSubscriber` です。
RevenueCat ID を省略すると保存済みの値を使います。

`ApplyResult` は sealed 型で、`Applied / AlreadyApplied / Conflict / ExistingSubscriber / NotFound`
のいずれかです。期限切れは `NotFound(error: CodeErrorKind.expired)` になります。
`Applied` と `AlreadyApplied` には nullable な `creator / perk / perkLabel / offeringKey` があります。
`ReferralSnapshot` は `ReferralNone / ReferralApplied / ReferralRemoved` のいずれかです。

通信タイムアウトは 15 秒です。エラーは `GoAlongException` で、`kind` が
`notConfigured / network / server`、サーバーエラーには `statusCode` が入ります。
入口設定の取得失敗は前回の値、前回値がなければ `false` を返します。
リンク抽出は初期化前でも既定ホストで動作します。

## テスト

```sh
flutter analyze
flutter test --timeout 30s test/client_test.dart
flutter test --timeout 30s test/controller_test.dart
flutter test --timeout 30s test/link_test.dart
flutter test --timeout 30s test/widgets_test.dart
```

`configure(httpClient: ..., storage: ...)` で `http.Client` と `GoAlongStorage` を
差し替えられます。テストでは `package:http/testing.dart` の `MockClient` と
メモリ上のストレージを利用しています。注入した HTTP クライアントはアプリ側で管理します。
各テストファイルは一つずつ実行してください。

`resetForTesting()` は未完了の通信の待ち合わせとタイマーを解除し、installation 報告は待ちません。
Widget テストの仮想時間内で作られた Future をテスト外の `tearDown` で待つと、
完了済みでも停止するためです。報告の成功を確認するテストでは、テスト本体内で
`await GoAlong.debugWaitForInstallationReport()` を使ってください。

## iOS 版との違い

- 表示文言・紹介者名の非表示・取消 UI の非表示は共通です。Flutter は Material の部品を使います。
- `onSkip` を渡すと「あとで」を表示します(iOS と同じ)。
- Flutter の headless controller 自体が 400ms の debounce とリンクの自動適用を管理し、
  `method: CLIPBOARD` を送ります(iOS は View 側で同じことを行います)。
- Flutter は付与済み特典を含む現在状態をサーバーから取得してから表示します。
  iOS のローカル特典キャッシュによる先行表示は行いません。
- Flutter の通信再試行は、失敗した取得・検証・適用を再実行し、置換の同意と経路を保持します。
  iOS の「もう一度試す」は再検証します。
- Flutter は `done` の `perkPending` で付与待ちを明示し、保存済み／明示された RevenueCat ID も確認します。
- 既存購読者の端末判定は `isActiveSubscriber` をアプリから渡します。iOS は StoreKit を使います。

## プライバシー

- 端末にランダムな installation ID、報告済みフラグ、紹介の適用状態、Offering の識別子、
  アプリから渡された RevenueCat ID を保存します。ID は端末の永続データを削除すると再生成します。
  OS のバックアップ復元で保存データが戻る場合は同じ ID になります。
- installation ID、アプリ ID、SDK・OS・アプリのバージョン、ロケールを GoAlong に送信します。
  適用時には紹介コード・経路、設定されていれば RevenueCat ID も送ります。
- SDK は広告 ID、デバイスフィンガープリントを取得しません。IP アドレスを収集する処理もありません。
- SDK 自体はクリップボード API を呼びません。読み取り関数を渡す場合は、アプリで同意を扱ってください。
  無関係なクリップボード内容を保存・送信しません。
- 紹介を取り消すと以後の紹介帰属が止まります。受け取り済み特典は取り消しません。
