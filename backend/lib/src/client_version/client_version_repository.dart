/// One app × platform's version policy.
typedef ClientVersionFloor = ({
  String appId,
  String platform,
  int minimumBuild,
  int recommendedBuild,
  String? updateUrl,
});

/// Reads and writes the per-app, per-platform version floors.
///
/// Design: docs/design/client-version-gate.md §5.
abstract class ClientVersionRepository {
  /// The floor for one app × platform, or null when the pair is unknown.
  ///
  /// **Unknown is not an error here.** A build of a flavour this backend has
  /// never heard of must be allowed through, not refused — see
  /// `ClientVersionService`.
  Future<ClientVersionFloor?> floor(String appId, String platform);

  /// Every floor, for the admin console.
  Future<List<ClientVersionFloor>> all();

  /// Set one floor. Returns the updated row, or null when the pair is unknown.
  ///
  /// **Deliberately cannot create rows.** The four (app, platform) pairs are
  /// created by migration 0032 and are a property of what we ship, not
  /// something an admin should be able to invent — a typo'd `app_id` would
  /// otherwise create a row that silently governs nothing.
  Future<ClientVersionFloor?> setFloor(
    String appId,
    String platform, {
    required int minimumBuild,
    required int recommendedBuild,
    String? updateUrl,
  });
}

/// In-memory implementation — seeded with the same four rows migration 0032
/// inserts, so dev and test behave like production.
class InMemoryClientVersionRepository implements ClientVersionRepository {
  InMemoryClientVersionRepository() {
    for (final app in const ['com.myweli.app', 'com.myweli.pro']) {
      _rows['$app|android'] = (
        appId: app,
        platform: 'android',
        minimumBuild: 0,
        recommendedBuild: 0,
        updateUrl: 'https://play.google.com/store/apps/details?id=$app',
      );
      // NULL on purpose: iOS has no bundle-id-based store URL.
      _rows['$app|ios'] = (
        appId: app,
        platform: 'ios',
        minimumBuild: 0,
        recommendedBuild: 0,
        updateUrl: null,
      );
    }
  }

  final Map<String, ClientVersionFloor> _rows = {};

  @override
  Future<ClientVersionFloor?> floor(String appId, String platform) async =>
      _rows['$appId|$platform'];

  @override
  Future<List<ClientVersionFloor>> all() async =>
      _rows.values.toList()..sort((a, b) {
        final byApp = a.appId.compareTo(b.appId);
        return byApp != 0 ? byApp : a.platform.compareTo(b.platform);
      });

  @override
  Future<ClientVersionFloor?> setFloor(
    String appId,
    String platform, {
    required int minimumBuild,
    required int recommendedBuild,
    String? updateUrl,
  }) async {
    final key = '$appId|$platform';
    if (!_rows.containsKey(key)) return null;
    return _rows[key] = (
      appId: appId,
      platform: platform,
      minimumBuild: minimumBuild,
      recommendedBuild: recommendedBuild,
      updateUrl: updateUrl,
    );
  }
}
