// CARTO probe — does CARTO serve THIS app a real basemap with THIS key?
//
//   CARTO_BASEMAPS_KEY=… dart run tool/carto_probe.dart --app-id com.myweli.pro
//
// Run by `tool/release_build.sh` before every store build, and by hand for
// the post-key verification (docs/design/map-basemap-key.md §10). Plain
// `dart`, no Flutter: it imports only `core/map/carto_basemap.dart`, which is
// pure for exactly this reason — the URL and the headers checked here are
// produced by the functions the app calls, not by a copy of them.
//
// **Why the release refuses on a failure.** A key CARTO refuses is the defect
// this exists for, wearing a key: the build compiles, signs, uploads, and
// every map shows « API KEY REQUIRED » (a dead key) or nothing (403, the
// restriction headers refused). Neither is visible to any test — only to a
// request against CARTO with the real key.
//
// The key comes from the environment, never argv, and is never printed.
// Two requests (1× and @2x) of the 1 M free monthly allowance.

import 'dart:io';

import 'package:myweli/core/map/carto_basemap.dart';

Future<void> main(List<String> args) async {
  final i = args.indexOf('--app-id');
  final appId = i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  final key = (Platform.environment['CARTO_BASEMAPS_KEY'] ?? '').trim();
  if (appId == null || appId.isEmpty || key.isEmpty) {
    stderr.writeln(
      'usage: CARTO_BASEMAPS_KEY=… dart run tool/carto_probe.dart '
      '--app-id <com.myweli.app|com.myweli.pro>',
    );
    exit(2);
  }

  final headers = cartoRestrictionHeaders(appId: appId);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  var failures = 0;
  try {
    for (final retina in [false, true]) {
      final url = cartoProbeTileUrl(key, retina: retina);
      final shown = url.replaceFirst(RegExp(r'key=[^&]*'), 'key=…');
      String? verdict;
      try {
        final request = await client.getUrl(Uri.parse(url));
        headers.forEach(request.headers.set);
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'flutter_map ($appId)',
        );
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        final body = <int>[];
        await response.forEach(body.addAll);
        verdict = cartoTileVerdict(
          status: response.statusCode,
          contentType: response.headers.contentType?.mimeType,
          etag: response.headers.value(HttpHeaders.etagHeader),
          body: body,
          retina: retina,
        );
      } on Exception catch (e) {
        verdict = 'request failed: ${e.runtimeType} — no answer from CARTO.';
      }
      if (verdict == null) {
        stdout.writeln('CARTO_PROBE ok   $shown');
      } else {
        failures++;
        stderr.writeln('CARTO_PROBE FAIL $shown\n    $verdict');
      }
    }
  } finally {
    client.close(force: true);
  }

  if (failures > 0) {
    stderr.writeln(
      'CARTO_PROBE sent: ${headers.keys.join(', ')} for $appId. '
      'Fix the key or its restrictions — docs/design/map-basemap-key.md §10.',
    );
    exit(1);
  }
}
