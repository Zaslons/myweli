import 'client_version_repository.dart';

/// What the client is told to do. The client renders this; it never decides.
enum ClientVersionStatus {
  ok,
  updateAvailable,
  updateRequired;

  String get wire => switch (this) {
    ClientVersionStatus.ok => 'ok',
    ClientVersionStatus.updateAvailable => 'update_available',
    ClientVersionStatus.updateRequired => 'update_required',
  };
}

typedef ClientVersionVerdict = ({
  ClientVersionStatus status,
  String? updateUrl,
});

/// Decides whether a client build may keep running.
///
/// **The server decides; the client only renders.** The alternative — serve the
/// floor and let the client compare — puts the comparison logic and the update
/// URL inside the artifact we are trying to retire, which are exactly the two
/// things we cannot patch there. Keeping both here means the whole policy is
/// changeable in one place, and the oldest client in the field never becomes
/// the bug.
///
/// Design: docs/design/client-version-gate.md §4.
class ClientVersionService {
  const ClientVersionService(this._repo);

  final ClientVersionRepository _repo;

  static const ClientVersionVerdict _allow = (
    status: ClientVersionStatus.ok,
    updateUrl: null,
  );

  /// [build] is the monotonic build number (`pubspec`'s `+N`), never semver:
  /// it feeds `versionCode`, `CFBundleVersion` and `FLUTTER_BUILD_NUMBER`
  /// alike, so it has a total order and no parsing traps.
  Future<ClientVersionVerdict> check({
    String? appId,
    String? platform,
    int? build,
  }) async {
    // Fail OPEN on anything malformed, and deliberately not with a 400. A
    // future flavour, a typo, or a client we have not shipped yet must never be
    // indistinguishable from an outage — the caller cannot tell the difference,
    // and the safe reading of "I don't know you" is "carry on".
    if (appId == null || platform == null || build == null) return _allow;

    final floor = await _repo.floor(appId, platform);
    if (floor == null) return _allow;

    // **You cannot block users you have nowhere to send.** A platform with no
    // store URL is never blocked and never nudged, whatever the floor says.
    //
    // This is not defensive coding: iOS genuinely has no URL until App Store
    // Connect mints the adamId, and this rule is what makes it safe to ship the
    // whole mechanism before that record exists. A test holds it.
    if (floor.updateUrl == null) return _allow;

    if (build < floor.minimumBuild) {
      return (
        status: ClientVersionStatus.updateRequired,
        updateUrl: floor.updateUrl,
      );
    }
    if (build < floor.recommendedBuild) {
      return (
        status: ClientVersionStatus.updateAvailable,
        updateUrl: floor.updateUrl,
      );
    }
    return _allow;
  }
}
