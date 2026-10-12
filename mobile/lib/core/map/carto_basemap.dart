/// The CARTO basemap every app map draws on — its keyed URL, the restriction
/// headers CARTO checks per platform, and how to recognise the « API KEY
/// REQUIRED » watermark. Design: docs/design/map-basemap-key.md.
///
/// **Pure Dart, deliberately — no Flutter import, no define read here.** Both
/// branches (key / no key) and both platforms must be testable, and a
/// `flutter test` run can vary neither a `String.fromEnvironment` nor the
/// platform it reports (always Android). So the key, the platform and the app
/// id all arrive as parameters: `CartoBasemapLayer` passes
/// `AppConfig.cartoBasemapsKey`, `defaultTargetPlatform` and the OS-reported
/// package name.
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
/// plausible-looking fallback would hide it. A store build cannot get here:
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

/// The platform a request comes from, as far as CARTO's restrictions care.
enum CartoPlatform { ios, android, other }

/// The header names CARTO's mobile-app restriction reads (CARTO FAQ,
/// 2026-10-11): the bundle id on iOS, the package + signing cert on Android.
const String cartoIosBundleHeader = 'X-Ios-Bundle-Identifier';
const String cartoAndroidPackageHeader = 'X-Android-Package';
const String cartoAndroidCertHeader = 'X-Android-Cert';

/// The release signing certificate SHA-1 of each Android app (Play App
/// Signing), lower-case hex without colons — the form `google-services.json`
/// and `infra/mobile/signing-manifest.json` store it in. A test pins this
/// table to both files.
///
/// A constant, not something the app measures: a debug build signed with the
/// development keystore sends the same value, so a key restricted to the
/// release certificates also serves `flutter run`. The header is a claim, not
/// a proof — anyone can read these from an APK.
const Map<String, String> cartoAndroidReleaseCertSha1 = {
  'com.myweli.app': 'b73647c6b06001af04d38ee2d0a5aa4722ca156f',
  'com.myweli.pro': '94be494a905b2c2adc66ad5720edde124089c985',
};

/// How the certificate travels in [cartoAndroidCertHeader]: upper-case hex,
/// no colons — Google's convention for its own `X-Android-Cert` header, whose
/// name CARTO's copies.
///
/// Verified against CARTO with the real app key on 2026-10-11 (spec §10):
/// accepted — as are colon-separated and lower case; a wrong cert → 403.
String cartoAndroidCertHeaderValue(String sha1) =>
    sha1.replaceAll(':', '').toUpperCase();

/// The restriction headers for the app [appId] (its bundle id on iOS, its
/// package on Android — the same string in this project) on [platform].
///
/// - iOS → the bundle id.
/// - Android → the package, plus its release certificate when it is one of
///   ours (an unknown package gets no cert header).
/// - anything else, or no [appId] → none (a restricted key then refuses,
///   visibly).
///
/// Returns a fresh, mutable map: flutter_map writes its User-Agent into it.
Map<String, String> cartoRestrictionHeaders({
  required CartoPlatform platform,
  required String? appId,
}) {
  final id = appId?.trim() ?? '';
  if (id.isEmpty) return <String, String>{};
  switch (platform) {
    case CartoPlatform.ios:
      return <String, String>{cartoIosBundleHeader: id};
    case CartoPlatform.android:
      final sha1 = cartoAndroidReleaseCertSha1[id];
      return <String, String>{
        cartoAndroidPackageHeader: id,
        if (sha1 != null)
          cartoAndroidCertHeader: cartoAndroidCertHeaderValue(sha1),
      };
    case CartoPlatform.other:
      return <String, String>{};
  }
}

/// Everything one flutter_map `TileLayer` needs to fetch the keyed basemap.
class CartoBasemapRequest {
  /// For `TileLayer.urlTemplate` ([cartoTileUrlTemplate]).
  final String urlTemplate;

  /// For `NetworkTileProvider.headers` ([cartoRestrictionHeaders]).
  final Map<String, String> headers;

  /// For `TileLayer.userAgentPackageName` — the running app's id. It was the
  /// stale `com.sadreddine.myweli` on both maps before this existed.
  final String userAgentPackageName;

  const CartoBasemapRequest({
    required this.urlTemplate,
    required this.headers,
    required this.userAgentPackageName,
  });
}

/// The one function both app maps build their basemap from: [key] (empty →
/// keyless, the visible watermark), the [platform] the request comes from,
/// and the running app's [appId] (null when the OS could not say).
CartoBasemapRequest cartoBasemapRequest({
  required String key,
  required CartoPlatform platform,
  required String? appId,
}) {
  final id = appId?.trim() ?? '';
  return CartoBasemapRequest(
    urlTemplate: cartoTileUrlTemplate(key),
    headers: cartoRestrictionHeaders(platform: platform, appId: id),
    userAgentPackageName: id.isEmpty ? 'myweli' : id,
  );
}

/// Whether an `etag` is CARTO's watermark tile (`"wm-da89c20e77c1-light"`,
/// measured 2026-10-11 on every keyless and bogus-key request), strong or
/// weak.
///
/// The watermark is served `200` with `max-age=2592000, immutable`, so a tile
/// cache that stores it shows it for 30 days after whatever made the key
/// unusable has been fixed. The app's cache refuses these
/// (`CartoWatermarkRefusingCache`).
bool isCartoWatermarkEtag(String? etag) {
  if (etag == null) return false;
  var e = etag.trim();
  if (e.startsWith('W/')) e = e.substring(2);
  if (e.startsWith('"')) e = e.substring(1);
  return e.startsWith('wm-');
}
