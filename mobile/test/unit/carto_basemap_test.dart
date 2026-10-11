import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/map/carto_basemap.dart';

/// The pure half of the keyed CARTO basemap (docs/design/map-basemap-key.md).
///
/// Both branches of the key live here, because a `flutter test` run cannot
/// set `CARTO_BASEMAPS_KEY` — the define is always empty under test, so a
/// test that read it would only ever see the keyless world.
void main() {
  group('the tile URL', () {
    test('with a key: the documented rastertiles path, keyed', () {
      expect(
        cartoTileUrlTemplate('k-123'),
        'https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}{r}.png'
        '?key=k-123',
      );
    });

    test('without one: the same URL, keyless — the visible watermark', () {
      expect(
        cartoTileUrlTemplate(''),
        'https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}{r}.png',
      );
      expect(cartoTileUrlTemplate('   '), cartoTileUrlTemplate(''));
    });

    test('a key is trimmed and encoded — never read as a {placeholder}', () {
      expect(cartoTileUrlTemplate(' k-1 \n'), endsWith('?key=k-1'));
      final odd = cartoTileUrlTemplate('a{b}&c=d');
      expect(odd, endsWith('?key=a%7Bb%7D%26c%3Dd'));
      // flutter_map substitutes every {…}: exactly its own four may remain.
      expect(RegExp(r'\{(\w+)\}').allMatches(odd).map((m) => m[1]).toList(), [
        'z',
        'x',
        'y',
        'r',
      ]);
    });
  });

  group('the restriction headers', () {
    test('iOS sends the bundle id, and only that', () {
      expect(
        cartoRestrictionHeaders(
          platform: CartoPlatform.ios,
          appId: 'com.myweli.pro',
        ),
        {'X-Ios-Bundle-Identifier': 'com.myweli.pro'},
      );
      expect(
        cartoRestrictionHeaders(
          platform: CartoPlatform.ios,
          appId: 'com.myweli.app',
        ),
        {'X-Ios-Bundle-Identifier': 'com.myweli.app'},
      );
    });

    test('Android sends the package and THAT package\'s release cert', () {
      expect(
        cartoRestrictionHeaders(
          platform: CartoPlatform.android,
          appId: 'com.myweli.app',
        ),
        {
          'X-Android-Package': 'com.myweli.app',
          'X-Android-Cert': 'B73647C6B06001AF04D38EE2D0A5AA4722CA156F',
        },
      );
      expect(
        cartoRestrictionHeaders(
          platform: CartoPlatform.android,
          appId: 'com.myweli.pro',
        ),
        {
          'X-Android-Package': 'com.myweli.pro',
          'X-Android-Cert': '94BE494A905B2C2ADC66AD5720EDDE124089C985',
        },
      );
    });

    test('an unknown Android package gets no cert header', () {
      expect(
        cartoRestrictionHeaders(
          platform: CartoPlatform.android,
          appId: 'com.example.other',
        ),
        {'X-Android-Package': 'com.example.other'},
      );
    });

    test('no id, or no mobile platform → no headers; always mutable', () {
      for (final platform in CartoPlatform.values) {
        for (final id in [null, '', '  ']) {
          final h = cartoRestrictionHeaders(platform: platform, appId: id);
          expect(h, isEmpty);
          h['User-Agent'] = 'x'; // throws on a const map
        }
      }
      expect(
        cartoRestrictionHeaders(
          platform: CartoPlatform.other,
          appId: 'com.myweli.app',
        ),
        isEmpty,
      );
      for (final platform in [CartoPlatform.ios, CartoPlatform.android]) {
        cartoRestrictionHeaders(
          platform: platform,
          appId: 'com.myweli.app',
        )['User-Agent'] = 'x';
      }
    });

    test(
      'the cert travels upper-case without colons — ONE place to change',
      () {
        expect(
          cartoAndroidCertHeaderValue('ab:cd:0f'),
          'ABCD0F',
          reason: 'UNVERIFIED for CARTO; spec §10 says how to adjust',
        );
      },
    );

    test('the certificates ARE the Play App Signing ones of the manifest', () {
      // The manifest's values were read off the Play-DELIVERED artifacts; the
      // console page produced two wrong ones (2026-08-26). A drift here sends
      // a certificate CARTO's dashboard does not hold → 403 → no tiles.
      final manifest =
          jsonDecode(
                File(
                  '../infra/mobile/signing-manifest.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final packages = manifest['packages'] as Map<String, dynamic>;
      final fromManifest = {
        for (final e in packages.entries)
          e.key: (e.value as Map<String, dynamic>)['playSha1'] as String,
      };
      expect(fromManifest, hasLength(2));
      expect(cartoAndroidReleaseCertSha1, fromManifest);
    });

    test('and each is registered for its package in google-services.json', () {
      // The brief's source of truth for « the release cert »: the flavour's
      // own Firebase config lists every fingerprint Google accepts for it.
      for (final (flavour, package) in [
        ('consumer', 'com.myweli.app'),
        ('pro', 'com.myweli.pro'),
      ]) {
        final config =
            jsonDecode(
                  File(
                    'android/app/src/$flavour/google-services.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final hashes = <String>[];
        for (final c
            in (config['client'] as List).cast<Map<String, dynamic>>()) {
          final info = c['client_info'] as Map<String, dynamic>;
          final android = info['android_client_info'] as Map<String, dynamic>;
          if (android['package_name'] != package) continue;
          for (final o
              in (c['oauth_client'] as List? ?? const [])
                  .cast<Map<String, dynamic>>()) {
            final cert = o['android_info'] as Map<String, dynamic>?;
            if (cert != null) hashes.add(cert['certificate_hash'] as String);
          }
        }
        expect(
          hashes,
          contains(cartoAndroidReleaseCertSha1[package]),
          reason: '$package in $flavour/google-services.json',
        );
      }
    });
  });

  group('the one request both maps build from', () {
    test('keyed, per platform, with the real app as User-Agent', () {
      final ios = cartoBasemapRequest(
        key: 'k-1',
        platform: CartoPlatform.ios,
        appId: 'com.myweli.pro',
      );
      expect(ios.urlTemplate, cartoTileUrlTemplate('k-1'));
      expect(ios.urlTemplate, endsWith('?key=k-1'));
      expect(ios.headers, {'X-Ios-Bundle-Identifier': 'com.myweli.pro'});
      expect(ios.userAgentPackageName, 'com.myweli.pro');

      final android = cartoBasemapRequest(
        key: 'k-1',
        platform: CartoPlatform.android,
        appId: ' com.myweli.app ',
      );
      expect(
        android.headers,
        cartoRestrictionHeaders(
          platform: CartoPlatform.android,
          appId: 'com.myweli.app',
        ),
      );
      expect(android.userAgentPackageName, 'com.myweli.app');
    });

    test('no key → keyless URL; no id → no headers, a neutral agent', () {
      final r = cartoBasemapRequest(
        key: '',
        platform: CartoPlatform.android,
        appId: null,
      );
      expect(r.urlTemplate, isNot(contains('key=')));
      expect(r.headers, isEmpty);
      expect(r.userAgentPackageName, 'myweli');
      expect(r.userAgentPackageName, isNot(contains('sadreddine')));
    });
  });

  group('the watermark', () {
    test('is recognised by its etag, strong or weak', () {
      // Measured 2026-10-11 on every keyless or bad-key raster request.
      expect(isCartoWatermarkEtag('"wm-da89c20e77c1-light"'), isTrue);
      expect(isCartoWatermarkEtag('W/"wm-da89c20e77c1-light"'), isTrue);
      expect(isCartoWatermarkEtag('wm-x'), isTrue);
    });

    test('and nothing else is', () {
      expect(isCartoWatermarkEtag(null), isFalse);
      expect(isCartoWatermarkEtag(''), isFalse);
      expect(isCartoWatermarkEtag('"a1b2c3"'), isFalse);
      expect(
        isCartoWatermarkEtag('W/"1a17e-Dtpwy38ZL8ILlNnH7GapWgFBEcg"'),
        isFalse,
      );
      expect(isCartoWatermarkEtag('"swm-1"'), isFalse);
    });
  });
}
