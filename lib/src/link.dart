import 'unicode_normalization.dart';

final _codePattern = RegExp(r'^[A-Z0-9]{3,20}$');

String normalizeCode(String text) =>
    uppercaseUnicode(normalizeNfkc(text).trim());

bool isValidCode(String code) => _codePattern.hasMatch(code);

/// Uri.parse は明示された :443 やドットセグメントを失うため、先に生文字列を検査。
String? extractReferralCode(
  String text, {
  String expectedHost = 'goalong.me',
  String? appSlug,
}) {
  final raw = text.trim();
  final match = RegExp(
    r'^https://([^/?#]+)(/[^?#]*)?(?:\?[^#]*)?(?:#.*)?$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) return null;
  final authority = match.group(1)!;
  if (authority.contains(RegExp(r'[:@%\\\s]'))) return null;
  final host = authority.toLowerCase();
  final expected = expectedHost.toLowerCase();
  if (host != expected && !host.endsWith('.$expected')) return null;
  if (!RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)*$').hasMatch(host)) {
    return null;
  }
  final parts = (match.group(2) ?? '').split('/');
  if (parts.length != 3 || parts[0].isNotEmpty || parts[1].isEmpty) {
    return null;
  }
  try {
    final slug = _decodeSegment(parts[1]);
    final rawCode = _decodeSegment(parts[2]);
    if (slug == '.' || slug == '..' || slug.contains(RegExp(r'[/\\]'))) {
      return null;
    }
    if (appSlug != null && slug.toLowerCase() != appSlug.toLowerCase()) {
      return null;
    }
    final code = normalizeCode(rawCode);
    return isValidCode(code) ? code : null;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

String _decodeSegment(String segment) {
  // decodeComponent expects ASCII / percent-encoded UTF-8. Preserve existing
  // escapes while encoding literal Unicode in pasted links first.
  final encoded = StringBuffer();
  for (final rune in segment.runes) {
    if (rune <= 0x7f) {
      encoded.writeCharCode(rune);
    } else {
      encoded.write(Uri.encodeComponent(String.fromCharCode(rune)));
    }
  }
  return Uri.decodeComponent(encoded.toString());
}
