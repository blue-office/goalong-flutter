import 'creator_code_controller.dart';

/// {perk} / {date} を表示時に置換する。すべての表示文言を変更可能。
class CreatorCodeLabels {
  const CreatorCodeLabels({
    this.title = '紹介コードをお持ちですか?',
    this.placeholder = 'コードを入力（例: MIKA）',
    this.useThisCode = 'このコードを使う',
    this.skip = 'あとで',
    this.checking = '確認中',
    this.applying = '適用中',
    this.appliedNoCreator = 'コードを適用しました',
    this.perkPreview = 'このコードで {perk}',
    this.perkGranted = '{perk} が適用されました',
    this.perkValidUntil = '{date} まで利用できます',
    this.perkPending = '特典はログイン後に受け取れます',
    this.errorFormat = '半角英数字 3〜20 文字で入力してください',
    this.errorNotFound = 'コードが見つかりません。入力内容を確認してください',
    this.errorExpired = 'このコードは有効期限が切れています',
    this.errorConflict = '別の紹介コードが適用済みです',
    this.errorExistingSubscriber = '有料プランをご契約中のため、この紹介コードはご利用いただけません',
    this.errorNetwork = '通信に失敗しました。時間をおいてお試しください',
    this.replace = 'このコードに変更する',
    this.currentReferralNoCreator = '紹介コードは適用済みです',
    this.removedNotice = '紹介を取り消しました。別のコードを入力して再適用できます',
    this.retry = 'もう一度試す',
    this.dateFormatter,
  });

  final String title;
  final String placeholder;
  final String useThisCode;
  final String skip;
  final String checking;
  final String applying;
  final String appliedNoCreator;
  final String perkPreview;
  final String perkGranted;
  final String perkValidUntil;
  final String perkPending;
  final String errorFormat;
  final String errorNotFound;
  final String errorExpired;
  final String errorConflict;
  final String errorExistingSubscriber;
  final String errorNetwork;
  final String replace;
  final String currentReferralNoCreator;
  final String removedNotice;
  final String retry;
  final String Function(DateTime date)? dateFormatter;

  String formatDate(DateTime date) {
    final local = date.toLocal();
    return dateFormatter?.call(local) ??
        '${local.year}年${local.month}月${local.day}日';
  }

  String error(CreatorCodeIssue issue) => switch (issue) {
        CreatorCodeIssue.invalidFormat => errorFormat,
        CreatorCodeIssue.notFound => errorNotFound,
        CreatorCodeIssue.expired => errorExpired,
        CreatorCodeIssue.conflict => errorConflict,
        CreatorCodeIssue.existingSubscriber => errorExistingSubscriber,
        CreatorCodeIssue.network => errorNetwork,
      };
}

class ReferralEntryLabels {
  const ReferralEntryLabels({
    this.collapsed = '紹介コードを入力する',
    this.title = '紹介コード',
    this.close = '閉じる',
  });
  final String collapsed;
  final String title;
  final String close;
}
