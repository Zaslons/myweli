/// The CARTO basemap every app map draws on — its URL, the restriction
/// headers CARTO checks, and how to tell a real tile from the « API KEY
/// REQUIRED » watermark. Design: docs/design/map-basemap-key.md.
///
/// **Pure Dart, deliberately — no Flutter import.** Two reasons:
///
/// - `tool/carto_probe.dart` runs these exact functions under plain `dart`
///   at release time, so the request it checks is the request the app makes.
///   A probe with its own copy of the URL or the headers would verify a
///   sentence about the app, not the app.
/// - Both branches (key / no key) must be testable, and a `flutter test` run
///   cannot vary a `String.fromEnvironment` — so nothing here reads one. The
///   key arrives as a parameter (`AppConfig.cartoBasemapsKey` in the app).
library;

/// The raster style — the light basemap the app has always used (`light_all`
/// ↔ the web's `positron-gl-style`, its vector twin).
const String cartoRasterStyle = 'light_all';

/// The URL template for flutter_map's `TileLayer.urlTemplate`, `{r}` being its
/// retina slot (`@2x` on dense screens).
///
/// **No key → no `?key=`, on purpose.** Since 2026-09-25 CARTO answers a
/// keyless raster request with a tile reading « API KEY REQUIRED ». That is
/// what a `flutter run` without the define, a test, or a CI build shows — and
/// it is the right thing to show: it names its own cause, where a
/// plausible-looking fallback would hide it. Release builds cannot get here:
/// `tool/release_build.sh` refuses to build without the key.
///
/// The key is query-encoded, so nothing in it can ever be read as a
/// flutter_map `{placeholder}`.
String cartoTileUrlTemplate(String key) {
  const base =
      'https://basemaps.cartocdn.com/rastertiles/$cartoRasterStyle'
      '/{z}/{x}/{y}{r}.png';
  final k = key.trim();
  return k.isEmpty ? base : '$base?key=${Uri.encodeQueryComponent(k)}';
}

/// The header names CARTO's mobile-app restriction reads (CARTO FAQ,
/// 2026-10-11).
const String cartoIosBundleHeader = 'X-Ios-Bundle-Identifier';
const String cartoAndroidPackageHeader = 'X-Android-Package';
const String cartoAndroidCertHeader = 'X-Android-Cert';

/// The Play App Signing certificate SHA-1 of each Android app, lower-case hex
/// without colons — the form `google-services.json` and
/// `infra/mobile/signing-manifest.json` store. A test pins this table to the
/// manifest's `playSha1`, which was read off the Play-DELIVERED artifacts
/// (the console page gave two wrong values on 2026-08-26).
///
/// It is a constant, not something the app measures: a debug build signed
/// with the development keystore sends the same value, so a key restricted
/// to the release certificates works there too. The header is a claim, not a
/// proof — anyone can read these from an APK.
const Map<String, String> cartoAndroidReleaseCertSha1 = {
  'com.myweli.app': 'b73647c6b06001af04d38ee2d0a5aa4722ca156f',
  'com.myweli.pro': '94be494a905b2c2adc66ad5720edde124089c985',
};

/// How the certificate travels in [cartoAndroidCertHeader]: upper-case hex,
/// no colons — Google's convention for the header CARTO's naming copies.
///
/// **UNVERIFIED for CARTO**, which documents the header but not its format.
/// This is the one place to change it; `tool/carto_probe.dart` tells you at
/// the first release build whether it is right (spec §10 A).
String cartoAndroidCertHeaderValue(String sha1) =>
    sha1.replaceAll(':', '').toUpperCase();

/// The restriction headers for the app with [appId] (its bundle id on iOS,
/// its package on Android — the same string in this project).
///
/// **The iOS AND the Android headers, on every platform.** CARTO ANDs
/// restriction types (« a request must pass all of them ») and does not say
/// whether iOS and Android are one type or two. Sending both sets passes
/// under either reading with a single app key; sending only the running
/// platform's would need one key per platform under the second. Spec §3.3.
///
/// No [appId] → no headers (a restricted key then refuses, visibly). An id
/// with no known certificate gets the package without a cert.
///
/// Returns a fresh, mutable map: flutter_map writes its User-Agent into it.
Map<String, String> cartoRestrictionHeaders({required String? appId}) {
  final id = appId?.trim() ?? '';
  if (id.isEmpty) return <String, String>{};
  final sha1 = cartoAndroidReleaseCertSha1[id];
  return <String, String>{
    cartoIosBundleHeader: id,
    cartoAndroidPackageHeader: id,
    if (sha1 != null) cartoAndroidCertHeader: cartoAndroidCertHeaderValue(sha1),
  };
}

/// Whether an `etag` is CARTO's watermark tile (`"wm-da89c20e77c1-light"`,
/// measured 2026-10-11), strong or weak.
///
/// The watermark is served `200` with `max-age=2592000, immutable`, so a tile
/// cache that stores it shows it for 30 days after whatever made the key
/// unusable has been fixed. The app's cache refuses these.
bool isCartoWatermarkEtag(String? etag) {
  if (etag == null) return false;
  var e = etag.trim();
  if (e.startsWith('W/')) e = e.substring(2);
  if (e.startsWith('"')) e = e.substring(1);
  return e.startsWith('wm-');
}

/// The probe's tile: Abidjan (the app's default centre) at zoom 11.
const String cartoProbeTilePath = '11/1001/993';

/// The concrete URL of the probe tile — [cartoTileUrlTemplate] with the
/// placeholders filled the way flutter_map fills them.
String cartoProbeTileUrl(String key, {required bool retina}) {
  final parts = cartoProbeTilePath.split('/');
  return cartoTileUrlTemplate(key)
      .replaceAll('{z}', parts[0])
      .replaceAll('{x}', parts[1])
      .replaceAll('{y}', parts[2])
      .replaceAll('{r}', retina ? '@2x' : '');
}

/// Why a response is NOT a usable basemap tile, or null when it is.
///
/// Used by `tool/carto_probe.dart`. Each refusal names what it means, because
/// the operator reading it at release time has to act on it.
String? cartoTileVerdict({
  required int status,
  required String? contentType,
  required String? etag,
  required List<int> body,
  required bool retina,
}) {
  if (status == 403) {
    return 'HTTP 403 — CARTO refused the restriction headers for this key '
        '(dashboard restrictions vs. what the app sends; see spec §10 A).';
  }
  if (status != 200) return 'HTTP $status — not a tile.';
  if (isCartoWatermarkEtag(etag)) {
    return 'the « API KEY REQUIRED » watermark (etag $etag) — CARTO did not '
        'accept the key at all (revoked, mistyped, or not activated).';
  }
  if (contentType == null || !contentType.startsWith('image/png')) {
    return 'content-type ${contentType ?? 'absent'} — not a PNG tile.';
  }
  final width = _pngWidth(body);
  final expected = retina ? 512 : 256;
  if (width != expected) {
    return 'PNG width ${width ?? 'unreadable'} px, expected $expected'
        '${retina ? ' — CARTO ignores @2x on this path; set retinaMode: false '
                  'in CartoBasemapLayer' : ''}.';
  }
  return null;
}

/// A PNG's width from its IHDR chunk (bytes 16–19, big-endian), or null.
int? _pngWidth(List<int> b) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (b.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (b[i] != signature[i]) return null;
  }
  return (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
}
