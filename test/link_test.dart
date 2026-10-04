import 'package:flutter_test/flutter_test.dart';
import 'package:goalong/goalong.dart';
import 'package:goalong/src/link.dart';
import 'package:goalong/src/unicode_normalization.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(GoAlong.resetForTesting);
  tearDown(GoAlong.resetForTesting);

  test('未設定でも既定ホストから抽出でき、適用はしない', () {
    expect(GoAlong.extractCode('https://goalong.me/any/mika'), 'MIKA');
    expect(GoAlong.extractCode('MIKA'), isNull);
  });

  test('ホスト、slug、コードの大小文字と全角・互換文字を正規化', () async {
    final h = Harness();
    await h.configure();
    for (final value in [
      'https://goalong.me/booknotion/mika',
      ' HTTPS://GOALONG.ME/BookNotion/ｍｉｋａ ',
      'https://links.goalong.me/booknotion/ＭＩＫＡ?utm_source=video#ref',
      'https://goalong.me/booknotion/%EF%BC%AD%EF%BC%A9%EF%BC%AB%EF%BC%A1',
    ]) {
      expect(GoAlong.extractCode(value), 'MIKA', reason: value);
    }
    expect(
      GoAlong.handleDeepLink(Uri.parse('https://goalong.me/booknotion/mika')),
      'MIKA',
    );
    expect(GoAlong.extractCode('https://goalong.me/booknotion/①ﬃ'), '1FFI');
    expect(h.calls('codes/apply'), isEmpty);
  });

  test('不正な境界のリンクを一切抽出しない', () async {
    await Harness().configure();
    for (final value in [
      'http://goalong.me/booknotion/MIKA',
      'goalong://booknotion/MIKA',
      'https://goalong.me:443/booknotion/MIKA',
      'https://goalong.me:8443/booknotion/MIKA',
      'https://goalong.me:/booknotion/MIKA',
      'https://user@goalong.me/booknotion/MIKA',
      'https://@goalong.me/booknotion/MIKA',
      'https://user:password@goalong.me/booknotion/MIKA',
      'https://example.com/booknotion/MIKA',
      'https://evilgoalong.me/booknotion/MIKA',
      'https://goalong.me.evil.test/booknotion/MIKA',
      'https://goalong.me./booknotion/MIKA',
      'https://goalong%2eme/booknotion/MIKA',
      'https://goalong.me/booknotion/MIKA/extra',
      'https://goalong.me/booknotion/MIKA/',
      'https://goalong.me//booknotion/MIKA',
      'https://goalong.me/booknotion',
      'https://goalong.me/other/MIKA',
      'https://goalong.me/booknotion/AB',
      'https://goalong.me/booknotion/ABCDEFGHIJKLMNOPQRSTU',
      'https://goalong.me/booknotion/AB-CD',
      'https://goalong.me/booknotion/MI%2FKA',
      'https://goalong.me/booknotion/MI%5CKA',
      'https://goalong.me/booknotion/%FF',
      'https://goalong.me/booknotion/%ZZ',
      'https://goalong.me/extra/../booknotion/MIKA',
      'https://goalong.me/booknotion/日本語',
    ]) {
      expect(GoAlong.extractCode(value), isNull, reason: value);
    }
    expect(GoAlong.extractCode('https://goalong.me/booknotion/ABC'), 'ABC');
    expect(
      GoAlong.extractCode('https://goalong.me/booknotion/ABCDEFGHIJKLMNOPQRST'),
      'ABCDEFGHIJKLMNOPQRST',
    );
  });

  test('baseUrl のホストとサブドメインだけを許可', () async {
    await Harness().configure(baseUrl: 'https://ref.example.com');
    expect(
      GoAlong.extractCode('https://ref.example.com/booknotion/ABC'),
      'ABC',
    );
    expect(
      GoAlong.extractCode('https://links.ref.example.com/booknotion/ABC'),
      'ABC',
    );
    expect(GoAlong.extractCode('https://goalong.me/booknotion/ABC'), isNull);
    expect(GoAlong.extractCode('https://example.com/booknotion/ABC'), isNull);
  });

  test('NFKC は全角以外の互換分解・再結合・結合順序も扱う', () {
    expect(normalizeCode('　ｍｉｋａ　'), 'MIKA');
    expect(normalizeCode('①ﬃK'), '1FFIK');
    expect(normalizeCode('ßab'), 'SSAB');
    expect(normalizeCode('𝕄𝕚𝕜𝕒'), 'MIKA');
    expect(normalizeNfkc('A\u030a'), 'Å');
    expect(normalizeNfkc('a\u0315\u0300'), 'à\u0315');
    expect(normalizeNfkc('\u1100\u1161\u11a8'), '각');
    expect(normalizeNfkc('㍍'), 'メートル');
    expect(isValidCode(normalizeCode('A\u030aBC')), isFalse);
    expect(isValidCode(normalizeCode('AB\u200bC')), isFalse);
  });
}
