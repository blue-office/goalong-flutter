typedef ActiveSubscriberCheck = Future<bool> Function();
typedef ClipboardReader = Future<String?> Function();

enum ApplyMethod {
  code('CODE'),
  deepLink('DEEP_LINK'),
  clipboard('CLIPBOARD');

  const ApplyMethod(this.value);
  final String value;
}

enum CodeErrorKind {
  invalidFormat('invalid_format'),
  notFound('not_found'),
  expired('expired');

  const CodeErrorKind(this.value);
  final String value;

  static CodeErrorKind? fromValue(Object? value) {
    for (final kind in values) {
      if (kind.value == value) return kind;
    }
    return null;
  }
}

class Creator {
  const Creator({required this.displayName, this.avatarUrl});

  factory Creator.fromJson(Map<String, dynamic> json) => Creator(
        displayName: json['displayName'] as String,
        avatarUrl: json['avatarUrl'] as String?,
      );

  final String displayName;
  final String? avatarUrl;
}

class Perk {
  const Perk({
    required this.label,
    this.entitlement,
    this.duration,
    this.expiresAtMs,
  });

  factory Perk.fromJson(Map<String, dynamic> json) => Perk(
        label: json['label'] as String,
        entitlement: json['entitlement'] as String?,
        duration: json['duration'] as String?,
        expiresAtMs: (json['expiresAtMs'] as num?)?.toInt(),
      );

  final String label;
  final String? entitlement;
  final String? duration;
  final int? expiresAtMs;

  DateTime? get expiresAt => expiresAtMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(expiresAtMs!, isUtc: true);
}

class CodeValidation {
  const CodeValidation({
    required this.valid,
    this.error,
    this.code,
    this.creator,
    this.perk,
  });

  final bool valid;
  final CodeErrorKind? error;
  final String? code;
  final Creator? creator;
  final Perk? perk;
}

sealed class ApplyResult {
  const ApplyResult();
}

final class Applied extends ApplyResult {
  const Applied({this.creator, this.perk, this.perkLabel, this.offeringKey});
  final Creator? creator;
  final Perk? perk;
  final String? perkLabel;
  final String? offeringKey;
}

final class AlreadyApplied extends ApplyResult {
  const AlreadyApplied({
    this.creator,
    this.perk,
    this.perkLabel,
    this.offeringKey,
  });
  final Creator? creator;
  final Perk? perk;
  final String? perkLabel;
  final String? offeringKey;
}

final class Conflict extends ApplyResult {
  const Conflict({this.currentCreator});
  final Creator? currentCreator;
}

final class ExistingSubscriber extends ApplyResult {
  const ExistingSubscriber();
}

final class NotFound extends ApplyResult {
  const NotFound({this.error});
  final CodeErrorKind? error;
}

sealed class ReferralSnapshot {
  const ReferralSnapshot();
}

final class ReferralNone extends ReferralSnapshot {
  const ReferralNone();
}

final class ReferralApplied extends ReferralSnapshot {
  const ReferralApplied({this.creator, this.appliedAt, this.perk});
  final Creator? creator;
  final DateTime? appliedAt;
  final Perk? perk;
}

final class ReferralRemoved extends ReferralSnapshot {
  const ReferralRemoved({this.removedAt});
  final DateTime? removedAt;
}

enum GoAlongErrorKind { notConfigured, network, server }

class GoAlongException implements Exception {
  const GoAlongException.notConfigured()
      : kind = GoAlongErrorKind.notConfigured,
        statusCode = null,
        cause = null;

  const GoAlongException.network([this.cause])
      : kind = GoAlongErrorKind.network,
        statusCode = null;

  const GoAlongException.server(int this.statusCode)
      : kind = GoAlongErrorKind.server,
        cause = null;

  final GoAlongErrorKind kind;
  final int? statusCode;
  final Object? cause;

  // 入力コード、RevenueCat ID、レスポンス本文をログに含めない。
  @override
  String toString() => 'GoAlongException(${kind.name}'
      '${statusCode == null ? '' : ', $statusCode'})';
}
