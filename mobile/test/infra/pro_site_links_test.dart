import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/config/app_config.dart';

import '../support/dart_source.dart';
import '../support/pro_closure.dart';

/// The Pro app's links to our own website, and nothing else.
/// docs/design/app-review-round-2.md §4, §10.
///
/// ## Why this file exists
///
/// Apple refused MyWeli Pro 0.0.1 twice under 3.1.1. The second time, build 698
/// on 2026-11-03, the words were broader than the login's link: « remove
/// features, account registration links, and any other links to your site that
/// could indirectly provide access to external purchase mechanisms. »
///
/// So the question for every future change is not « is the sign-up link gone »
/// (`pro_login_only_test.dart` says that) but « did a NEW link to the site
/// appear ». A pin on the removed words cannot see the next one, whatever it
/// says. This pins the other side: the set of pages the Pro app opens on our
/// site is **exactly** the five Apple or the law requires it to have, and a
/// change to that set has to come through here.
///
/// Going red on a removal is deliberate too: privacy (5.1.1(i)) and support
/// (1.5) are required, and the other three are the owner's call.
///
/// ## What it reads
///
/// The import closure of `lib/main_pro.dart`: what can ship in the Pro binary.
/// The consumer app's own links are in `lib/` and not in scope.
///
/// ## What it cannot see, said plainly
///
/// - A URL or a sentence the **server** sends (`update_url`, a push). It is data.
///   Round 2's §10 lists who holds those.
/// - What the five pages themselves link to. No test here reaches the web:
///   `web/tests/` and the post-merge read of the live pages hold that.
/// - A call that is not one of the five (`tel:`, `wa.me`, a map, the store)
///   re-pointed at somewhere else, and a sentence reworded past the word list.
///   The inventory below counts those calls and does not read their URLs. Our
///   domain written whole is seen wherever it is; built from pieces in such a
///   call, it is left to the IPA check (`app-store-forms.md` §11.3).
/// - A new package that opens a page by itself. The `url_launcher` importers and
///   the `webview` check see those two; the next one has another name.
void main() {
  final closure = proClosure();
  const config = 'lib/core/config/app_config.dart';
  const login = 'lib/screens/provider/auth/pro_login_screen.dart';

  /// `AppConfig.x`, however `dart format` wrapped it.
  final appConfigRead = RegExp(r'\bAppConfig\s*\.\s*(\w+)');

  /// The only pages of ours the Pro app may open: getter, value, page.
  final required = <String, ({String url, String page})>{
    'privacyUrl': (
      url: AppConfig.privacyUrl,
      page: '/politique-confidentialite',
    ),
    'termsUrl': (url: AppConfig.termsUrl, page: '/cgu'),
    'legalNoticeUrl': (
      url: AppConfig.legalNoticeUrl,
      page: '/mentions-legales',
    ),
    'accountDeletionUrl': (
      url: AppConfig.accountDeletionUrl,
      page: '/suppression-compte',
    ),
    'supportUrl': (url: AppConfig.supportUrl, page: '/support'),
  };

  group('the closure is the Pro binary', () {
    test(
      'it reaches the screens that hold links, and it is not all of lib/',
      () {
        // Without this, a closure that stopped at main_pro.dart would pass every
        // « nothing found » below.
        for (final path in [
          config,
          login,
          'lib/screens/profile/about_screen.dart',
          'lib/screens/provider/profile/pro_profile_screen.dart',
          'lib/core/router/pro_router.dart',
        ]) {
          expect(closure.keys, contains(path), reason: 'does not reach $path');
        }
        expect(
          closure.keys,
          isNot(contains('lib/main.dart')),
          reason: 'the closure is reading the consumer app',
        );
        final all = Directory('lib')
            .listSync(recursive: true)
            .where((f) => f is File && f.path.endsWith('.dart'))
            .length;
        expect(closure.length, lessThan(all));
      },
    );
  });

  group('links to the site', () {
    test('the getters built on the site are exactly the five required pages', () {
      // A `static` member of AppConfig that mentions `siteBaseUrl`, or a member
      // already found, before its first `;`, so `'$supportUrl/../tarifs'` is on
      // the site too. Nothing else: a block body's `return` comes after a `;`,
      // and a getter outside the class is not `static`. The two tests below
      // hold those, whatever shape they take.
      final onSite = <String>{};
      for (var known = 0; ; known = onSite.length) {
        final names = ['siteBaseUrl', ...onSite].join('|');
        final builtOnSite = RegExp(
          r'static[^;{]*?\b(\w+)\s*(?:\([^)]*\))?\s*(?:=>|=|\{)[^;]*\b'
          '(?:$names)'
          r'\b',
        );
        onSite.addAll({
          for (final m in builtOnSite.allMatches(closure[config]!)) m.group(1)!,
        });
        if (onSite.length == known) break;
      }
      final used = {
        for (final code in closure.values)
          for (final m in appConfigRead.allMatches(code))
            if (onSite.contains(m.group(1))) m.group(1)!,
      };
      expect(
        used,
        unorderedEquals(required.keys),
        reason:
            'the Pro app links to these pages of our site. A new one is what '
            'Apple refused on 2026-11-03 (« any other links to your site »); a '
            'missing one is a required page lost. Either way: '
            'docs/design/app-review-round-2.md first.',
      );
    });

    test('the config names the base six times: itself and the five', () {
      // The regex above reads a shape; this reads the word. A block body, a
      // top-level getter or a second helper in this file all have to say
      // `siteBaseUrl`, and that is one too many, used or not:
      // `web/tests/store-linked-pages.test.tsx` refuses an unclassified sixth too.
      expect(
        RegExp(r'\bsiteBaseUrl\b').allMatches(closure[config]!).length,
        1 + required.length,
        reason:
            'a new way to the site in app_config.dart, however it is written. '
            'docs/design/app-review-round-2.md §4 first.',
      );
    });

    test('each is read once, as the whole of the link it opens', () {
      // A getter that stays right but stops being what is opened is the way past
      // everything else here: `Uri.parse(AppConfig.supportUrl).resolve('/x')`,
      // `cond ? 'https://myweli.$tld/x' : AppConfig.supportUrl`, a local copy.
      // Each of those reads the getter in another shape, or a second time.
      final open = RegExp(
        r'\bopenExternalUrl\(\s*\w+\s*,\s*AppConfig\s*\.\s*(\w+)\s*,?\s*\)',
      );
      Map<String, List<String>> found(RegExp pattern) {
        final files = <String, List<String>>{};
        for (final e in closure.entries) {
          for (final m in pattern.allMatches(e.value)) {
            if (required.containsKey(m.group(1))) {
              (files[m.group(1)!] ??= []).add(e.key);
            }
          }
        }
        return files;
      }

      const about = 'lib/screens/profile/about_screen.dart';
      const expected = {
        'privacyUrl': [about],
        'termsUrl': [about],
        'legalNoticeUrl': [about],
        'accountDeletionUrl': [about],
        'supportUrl': ['lib/screens/provider/profile/pro_profile_screen.dart'],
      };
      expect(found(appConfigRead), expected, reason: 'where each one is read');
      expect(found(open), expected, reason: 'what is done with it');
    });

    test('each points to its page, and the page exists', () {
      for (final entry in required.entries) {
        expect(
          entry.value.url,
          '${AppConfig.siteBaseUrl}${entry.value.page}',
          reason: '${entry.key} was re-pointed',
        );
        expect(
          File('../web/app${entry.value.page}/page.tsx').existsSync(),
          isTrue,
          reason: '${entry.key} opens a page the web does not have',
        );
      }
    });

    test('nothing reaches the site except through those getters', () {
      final hits = [
        for (final e in closure.entries)
          if (e.key != config &&
              (e.value.contains('siteBaseUrl') ||
                  e.value.contains('SITE_BASE_URL')))
            e.key,
      ];
      expect(hits, isEmpty, reason: 'builds its own link to the site: $hits');
    });

    test('no web page of ours is written out as a path', () {
      // The pages that sign up, sign in or sell, and the page that creates a
      // salon: `web/app/pro/(dash)/salons/nouveau`, one of the two things Apple's
      // first refusal was about. A path needs no domain. asCopy, because
      // '/pro/' 'connexion' is the same path to whoever opens it.
      //
      // A list: a page it does not name passes here. What opens such a path goes
      // through a call, and the getters' test and the inventory read those.
      const pages = [
        '/pro/inscription',
        '/pro/connexion',
        '/pro/abonnement',
        '/pro/salons/nouveau',
        '/professionnels',
        '/connexion',
        '/mon-compte',
      ];
      final hits = [
        for (final e in closure.entries)
          for (final page in pages)
            if (asCopy(e.value).contains(page)) '${e.key}: $page',
      ];
      expect(hits, isEmpty);
    });
  });

  group('what the app says about the site', () {
    test('no string names the domain — only the base the getters read', () {
      final domain = RegExp(
        r'''[^\s'"]*myweli\.com[^\s'"]*''',
        caseSensitive: false,
      );
      final hits = [
        for (final e in closure.entries)
          // asCopy: 'myweli' '.com' is one word on screen, so one word here.
          for (final m in domain.allMatches(asCopy(e.value)))
            '${e.key}: ${m.group(0)}',
      ];
      // Exact, not « empty », because this line is the proof that the scan
      // reads strings at all. A list, because a second base spelled the same
      // would disappear into a Set. The domain changing turns it red; say so here.
      expect(hits, ['$config: https://myweli.com']);
    });

    test(
      'no sentence sends anyone to the website, with or without a domain',
      () {
        // An instruction needs no URL to be a call to action: « Inscrivez-vous
        // sur notre site » has no myweli.com in it. `\binscri` is the start of
        // a word, so a mock's « désinscrit » is not it.
        final pointing = RegExp(
          r'\binscri|\bnotre site\b|\ble site\b|\bsite web\b|\bsur le web\b|'
          r'\bnavigateur\b',
          caseSensitive: false,
        );
        final hits = [
          for (final e in closure.entries)
            for (final m in pointing.allMatches(asCopy(e.value)))
              '${e.key}: « ${m.group(0)} »',
        ];
        expect(hits, isEmpty);
      },
    );

    test('no native resource names the site', () {
      const text = {
        '.plist',
        '.strings',
        '.xml',
        '.storyboard',
        '.entitlements',
        '.xcprivacy',
        '.swift',
        '.kt',
      };
      final read = <String>[];
      final hits = <String>[];
      for (final root in ['ios/Runner', 'android/app/src']) {
        for (final f in Directory(root).listSync(recursive: true)) {
          if (f is! File) continue;
          if (!text.any(f.path.endsWith)) continue;
          read.add(f.path);
          if (f.readAsStringSync().toLowerCase().contains('myweli.com')) {
            hits.add(f.path);
          }
        }
      }
      // A scan that read nothing would pass: it must have seen these two.
      expect(read, contains('ios/Runner/Info.plist'));
      expect(read, contains('android/app/src/main/AndroidManifest.xml'));
      expect(hits, isEmpty);
    });
  });

  group('every way out of the app is known', () {
    test('the calls that leave the app, file by file', () {
      // Not a list of URLs: most of these are `tel:`, `wa.me` or a map. It is
      // the class the checks above cannot see — a link that names neither our
      // domain nor a getter. A new line here means someone reads what it opens.
      final out = RegExp(r'\b(?:openExternalUrl|launchUrlString|launchUrl)\b');
      final calls = {
        for (final e in closure.entries)
          if (out.hasMatch(e.value)) e.key: out.allMatches(e.value).length,
      };
      expect(calls, {
        'lib/core/utils/external_link.dart': 4, // the helpers themselves
        'lib/core/utils/helpers.dart': 2, // map apps
        'lib/screens/profile/about_screen.dart': 4, // the four legal pages
        'lib/screens/provider/clients/client_detail_screen.dart': 1, // wa.me
        'lib/screens/provider/profile/pro_profile_screen.dart': 1, // support
        'lib/screens/providers/provider_detail_screen.dart': 1, // wa.me
        'lib/screens/update/update_required_app.dart': 1, // the store
        'lib/widgets/common/update_available_banner.dart': 1, // the store
      });
    });

    test('url_launcher is imported by exactly these', () {
      // Its `Link` widget leaves the app with none of the three names above, and
      // an import is the one thing it cannot do without. A new line here means
      // someone reads what the new file opens.
      final launcher = RegExp(
        r'''^\s*(?:import|export)\s+['"]package:url_launcher/''',
        multiLine: true,
      );
      final importers = [
        for (final e in closure.entries)
          if (launcher.hasMatch(e.value)) e.key,
      ]..sort();
      expect(importers, [
        'lib/core/utils/external_link.dart',
        'lib/core/utils/helpers.dart',
        'lib/screens/provider/clients/client_detail_screen.dart',
        'lib/screens/providers/provider_detail_screen.dart',
      ]);
    });

    test('there is no web view to stay inside', () {
      // The other way to open a page: no `launchUrl`, no external browser.
      expect(
        File('pubspec.yaml').readAsStringSync().toLowerCase(),
        isNot(contains('webview')),
      );
    });
  });
}
