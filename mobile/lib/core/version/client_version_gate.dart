import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';

/// What the server told us to do. **The client never decides** — it renders a
/// verdict the backend computed (docs/design/client-version-gate.md §4).
enum ClientVersionVerdict {
  /// Carry on. Also the answer to every ambiguity — see [ClientVersionGate].
  ok,

  /// A newer build exists and is recommended. Dismissible.
  updateAvailable,

  /// This build is below the floor. Blocking.
  updateRequired,
}

typedef ClientVersionResult = ({
  ClientVersionVerdict verdict,
  String? updateUrl,
  int build,
});

/// Asks the backend whether this build may keep running.
///
/// ## Why this exists at all
///
/// **You cannot roll back an app release** (docs/LAUNCH.md §1.4). A bad version
/// sits on people's phones until they choose to update, and some never will.
/// This is the only lever that reaches such a phone.
///
/// ## Fail open, on everything
///
/// Timeout, DNS failure, socket error, 4xx, 5xx, unparseable JSON, a missing
/// field, **or a `status` string this build has never heard of** — all of them
/// return [ClientVersionVerdict.ok]. Only a well-formed 200 carrying
/// `update_required` blocks.
///
/// This is the house rule copied from `refreshing_http_client.dart:102`:
/// distinguish *"the server said no"* from *"I could not reach the server."*
/// The cost, stated rather than hidden: **a device that is offline at every
/// launch is never blocked.** That is the correct trade — the backend must stay
/// backward-compatible with old clients anyway, so serving one is survivable;
/// bricking a working app on a flaky Abidjan network is not.
///
/// The unknown-`status` rule is the other half. A v1.0 that treats an
/// unrecognised verdict as "block" would be undeployable-around: a later server
/// could never introduce a new verdict without bricking the oldest clients it
/// is trying to manage.
/// The verdict for "we did not, or could not, ask".
const ClientVersionResult kClientVersionAllowed = (
  verdict: ClientVersionVerdict.ok,
  updateUrl: null,
  build: 0,
);

/// The verdict from this launch's check, for surfaces that render the NUDGE.
///
/// **A top-level holder, and the reasons are specific.** The blocking verdict is
/// consumed in `main()` before anything exists to inject into. The nudge is the
/// opposite: it is rendered deep inside the running app, on a surface reached
/// through a router that `main()` does not build. Threading one nullable record
/// from `main()` through both app widgets, both routers and two home screens —
/// to be read in exactly one place each — would be more machinery than the fact
/// it carries.
///
/// Written once, before `runApp`, and only read afterwards. It is not a
/// mutable-global pattern the app should grow more of; if a second consumer
/// appears, that is the signal to give it a provider.
ClientVersionResult clientVersionResult = kClientVersionAllowed;

class ClientVersionGate {
  const ClientVersionGate({this._client, this._packageInfo, this._platform});

  final http.Client? _client;
  final PackageInfo? _packageInfo;

  /// Test seam. Production passes nothing and the platform is read from
  /// `dart:io`; a test VM is neither Android nor iOS, and a gate that silently
  /// returns `ok` on the only machine that can run its tests is a gate nobody
  /// can prove works.
  final String? _platform;

  /// Whether this build should ask at all.
  ///
  /// **Deliberately not checked inside [check].** It was, and it made the whole
  /// class untestable: `AppConfig.useApiBackend` is a `bool.fromEnvironment`
  /// that is false under `flutter test`, so every test exercised the early
  /// return instead of the gate. The caller decides whether to ask; the gate
  /// only knows how to ask.
  static bool get enabledForThisBuild => AppConfig.useApiBackend && !kIsWeb;

  /// How long the whole check may take before we give up and let the app run.
  ///
  /// **Its own constant, deliberately.** `AppConstants.apiTimeout` is 30s and is
  /// referenced by nothing — 20× too long for something the first frame waits
  /// on. A gate with no deadline hangs the splash forever behind a captive
  /// portal, which is the failure mode most likely to be blamed on the app.
  static const Duration deadline = Duration(milliseconds: 1500);

  static const ClientVersionResult _allow = kClientVersionAllowed;

  Future<ClientVersionResult> check() async {
    try {
      final info = _packageInfo ?? await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber);
      if (build == null) return _allow;

      final platform =
          _platform ??
          (Platform.isIOS
              ? 'ios'
              : Platform.isAndroid
              ? 'android'
              : null);
      if (platform == null) return _allow;

      final uri = Uri.parse('${AppConfig.apiBaseUrl}/client-version').replace(
        queryParameters: {
          'app': info.packageName,
          'platform': platform,
          'build': '$build',
          'version': info.version,
        },
      );

      final client = _client ?? http.Client();
      final res = await client.get(uri).timeout(deadline);
      if (res.statusCode != 200) return _allow;

      final body = jsonDecode(res.body);
      if (body is! Map) return _allow;
      final url = body['updateUrl'];

      return switch (body['status']) {
        'update_required' => (
          verdict: ClientVersionVerdict.updateRequired,
          updateUrl: url is String ? url : null,
          build: build,
        ),
        'update_available' => (
          verdict: ClientVersionVerdict.updateAvailable,
          updateUrl: url is String ? url : null,
          build: build,
        ),
        // 'ok' AND anything unrecognised. See the class doc.
        _ => (verdict: ClientVersionVerdict.ok, updateUrl: null, build: build),
      };
    } catch (_) {
      // Every failure is the same failure here: we could not get an answer, so
      // the app runs. Deliberately swallowed without reporting — a captive
      // portal is not an error worth an event on every launch.
      return _allow;
    }
  }
}
