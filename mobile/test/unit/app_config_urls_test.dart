import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/config/app_config.dart';

/// The five site URLs the binary carries.
///
/// ## Why this file exists
///
/// `AppConfig` builds these by interpolating `siteBaseUrl`, and **an escaped
/// dollar compiles**. `'\$siteBaseUrl/support'` is valid Dart, passes
/// `dart analyze` without a murmur, and produces the literal string
/// `$siteBaseUrl/support` — a URL that opens nothing. It happened here while
/// adding the support page, caught only because a Python escape warning
/// happened to be visible.
///
/// No mobile test can reach the web, so this cannot prove the pages exist. It
/// proves the far cheaper thing: that these are URLs at all.
void main() {
  // Getters, so not a const map — they interpolate at call time, which is
  // precisely the thing under test.
  final urls = {
    'privacyUrl': AppConfig.privacyUrl,
    'termsUrl': AppConfig.termsUrl,
    'legalNoticeUrl': AppConfig.legalNoticeUrl,
    'accountDeletionUrl': AppConfig.accountDeletionUrl,
    'supportUrl': AppConfig.supportUrl,
  };

  group('every site URL is interpolated, not literal', () {
    urls.forEach((name, url) {
      test(name, () {
        expect(
          url,
          startsWith('https://'),
          reason:
              '$name is "$url" — an escaped \$ leaves the variable name in the '
              'string, and the result opens nothing',
        );
        expect(
          url,
          isNot(contains(r'$')),
          reason: '$name still contains a literal dollar sign: "$url"',
        );
        expect(Uri.tryParse(url)?.host, isNotEmpty);
      });
    });

    test('they are five distinct paths on one host', () {
      final hosts = urls.values.map((u) => Uri.parse(u).host).toSet();
      expect(hosts, hasLength(1), reason: 'the base must be shared: $hosts');
      expect(
        urls.values.toSet(),
        hasLength(urls.length),
        reason: 'two of these resolve to the same page',
      );
    });
  });

  test('support points at the page, not a wa.me link', () {
    // The whole reason this URL exists: `supportWhatsApp` had no default and was
    // passed by no build, so « Aide & Support » showed « Contact bientôt
    // disponible. » in every artifact ever shipped — while the mentions légales
    // told the public it was the contact channel of record.
    expect(AppConfig.supportUrl, endsWith('/support'));
    expect(AppConfig.supportUrl, isNot(contains('wa.me')));
  });
}
