import 'unicode_data.dart';

/// Full Unicode uppercase mapping, including expansions such as ß → SS.
/// Dart's native String.toUpperCase only performs simple mappings on the VM.
String uppercaseUnicode(String input) => String.fromCharCodes(
      input.runes.expand((rune) => uppercaseMappings[rune] ?? [rune]),
    );

/// Compatibility decomposition, canonical ordering, canonical composition.
/// Hangul is handled algorithmically, without an additional dependency.
String normalizeNfkc(String input) {
  final ordered = <int>[];
  for (final rune in input.runes) {
    final syllable = rune - 0xac00;
    final List<int> decomposition;
    if (syllable >= 0 && syllable < 11172) {
      decomposition = [
        0x1100 + syllable ~/ 588,
        0x1161 + (syllable % 588) ~/ 28,
        if (syllable % 28 != 0) 0x11a7 + syllable % 28,
      ];
    } else {
      decomposition = nfkdMappings[rune] ?? [rune];
    }
    for (final scalar in decomposition) {
      ordered.add(scalar);
      final combining = combiningClasses[scalar] ?? 0;
      if (combining == 0) continue;
      var index = ordered.length - 1;
      while (index > 0 &&
          (combiningClasses[ordered[index - 1]] ?? 0) > combining) {
        ordered[index] = ordered[index - 1];
        index--;
      }
      ordered[index] = scalar;
    }
  }
  final composed = <int>[];
  var starterIndex = -1;
  var previousClass = 0;
  for (final scalar in ordered) {
    final combining = combiningClasses[scalar] ?? 0;
    final replacement =
        starterIndex < 0 ? null : _compose(composed[starterIndex], scalar);
    if (replacement != null &&
        (previousClass == 0 || previousClass < combining)) {
      composed[starterIndex] = replacement;
    } else {
      if (combining == 0) starterIndex = composed.length;
      composed.add(scalar);
      previousClass = combining;
    }
  }
  return String.fromCharCodes(composed);
}

int? _compose(int first, int second) {
  final lead = first - 0x1100;
  final vowel = second - 0x1161;
  if (lead >= 0 && lead < 19 && vowel >= 0 && vowel < 21) {
    return 0xac00 + (lead * 21 + vowel) * 28;
  }
  final syllable = first - 0xac00;
  final tail = second - 0x11a7;
  if (syllable >= 0 &&
      syllable < 11172 &&
      syllable % 28 == 0 &&
      tail > 0 &&
      tail < 28) {
    return first + tail;
  }
  return canonicalCompositions[first * 0x110000 + second];
}
