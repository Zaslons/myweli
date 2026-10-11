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

    test(
      'the probe tile is the template filled the way flutter_map fills it',
      () {
        expect(
          cartoProbeTileUrl('k', retina: true),
          'https://basemaps.cartocdn.com/rastertiles/light_all/11/1001/993@2x.png'
          '?key=k',
        );
        expect(
          cartoProbeTileUrl('k', retina: false),
          'https://basemaps.cartocdn.com/rastertiles/light_all/11/1001/993.png'
          '?key=k',
        );
      },
    );
  });

  group('the restriction headers', () {
    test('every app request carries the iOS AND the Android identity', () {
      // CARTO ANDs restriction types and does not say whether iOS and Android
      // are one type or two — both sets pass under either reading (§3.3).
      expect(cartoRestrictionHeaders(appId: 'com.myweli.pro'), {
        'X-Ios-Bundle-Identifier': 'com.myweli.pro',
        'X-Android-Package': 'com.myweli.pro',
        'X-Android-Cert': '94BE494A905B2C2ADC66AD5720EDDE124089C985',
      });
      expect(cartoRestrictionHeaders(appId: 'com.myweli.app'), {
        'X-Ios-Bundle-Identifier': 'com.myweli.app',
        'X-Android-Package': 'com.myweli.app',
        'X-Android-Cert': 'B73647C6B06001AF04D38EE2D0A5AA4722CA156F',
      });
    });

    test('an id with no known certificate gets no cert header', () {
      expect(cartoRestrictionHeaders(appId: 'com.example.other'), {
        'X-Ios-Bundle-Identifier': 'com.example.other',
        'X-Android-Package': 'com.example.other',
      });
    });

    test('no id → no headers, and the map is mutable for the User-Agent', () {
      for (final id in [null, '', '  ']) {
        final h = cartoRestrictionHeaders(appId: id);
        expect(h, isEmpty);
        h['User-Agent'] = 'x'; // throws on a const map
      }
      cartoRestrictionHeaders(appId: 'com.myweli.app')['User-Agent'] = 'x';
    });

    test(
      'the cert travels upper-case without colons — ONE place to change',
      () {
        expect(
          cartoAndroidCertHeaderValue('ab:cd:0f'),
          'ABCD0F',
          reason: 'UNVERIFIED for CARTO; spec §10 A says how to adjust',
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

  group('the probe verdict', () {
    List<int> png(int width) => [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
      0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, // IHDR
      (width >> 24) & 0xFF, (width >> 16) & 0xFF, (width >> 8) & 0xFF,
      width & 0xFF, 0, 0, 1, 0, // width, height
    ];

    String? verdict({
      int status = 200,
      String? type = 'image/png',
      String? etag = '"real"',
      List<int>? body,
      bool retina = false,
    }) => cartoTileVerdict(
      status: status,
      contentType: type,
      etag: etag,
      body: body ?? png(retina ? 512 : 256),
      retina: retina,
    );

    test('a real tile at the right size passes, 1x and @2x', () {
      expect(verdict(), isNull);
      expect(verdict(retina: true), isNull);
    });

    test('403 names the restriction headers', () {
      expect(verdict(status: 403), contains('restriction headers'));
    });

    test('the watermark names the key', () {
      expect(verdict(etag: '"wm-da89c20e77c1-light"'), contains('watermark'));
    });

    test('anything else that is not a PNG tile fails', () {
      expect(verdict(status: 500), contains('HTTP 500'));
      expect(verdict(type: 'text/html'), contains('not a PNG'));
      expect(verdict(type: null), contains('not a PNG'));
      expect(verdict(body: [1, 2, 3]), contains('unreadable'));
    });

    test('@2x answered at 256 px means CARTO ignores retina here', () {
      expect(
        verdict(retina: true, body: png(256)),
        contains('retinaMode: false'),
      );
      expect(verdict(body: png(512)), contains('expected 256'));
    });
  });
}
