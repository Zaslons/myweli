import '../client_version/client_version_repository.dart';
import 'admin_kyc_service.dart' show AdminResult;
import 'audit_log_repository.dart';

/// Admin control over the client version floors — the lever that retires an old
/// app build (docs/design/client-version-gate.md §6).
///
/// **Every write is audited.** Raising a floor is a denial of service to every
/// user below it — deliberate and necessary, but it is the one action here whose
/// blast radius is "everyone on that build", so it should never be anonymous.
/// Threat model: BACKEND.md §7 T63.
class AdminClientVersionService {
  const AdminClientVersionService(this._repo, this._audit);

  final ClientVersionRepository _repo;
  final AuditLogRepository _audit;

  Future<AdminResult> list() async {
    final rows = await _repo.all();
    return (
      ok: true,
      error: null,
      data: {
        'items': [for (final r in rows) _json(r)],
      },
    );
  }

  Future<AdminResult> set(
    String adminId, {
    required Object? appId,
    required Object? platform,
    required Object? minimumBuild,
    required Object? recommendedBuild,
    required Object? updateUrl,
  }) async {
    if (appId is! String || appId.isEmpty) {
      return (ok: false, error: 'invalid_app', data: null);
    }
    if (platform is! String || platform.isEmpty) {
      return (ok: false, error: 'invalid_platform', data: null);
    }
    // Boundary validation, not a trusted client: a negative floor is
    // meaningless and a huge one is almost certainly a typo that would lock out
    // every build that will ever exist. 0 means "no floor" and stays legal.
    if (minimumBuild is! int || minimumBuild < 0 || minimumBuild > 1000000) {
      return (ok: false, error: 'invalid_minimum_build', data: null);
    }
    if (recommendedBuild is! int ||
        recommendedBuild < 0 ||
        recommendedBuild > 1000000) {
      return (ok: false, error: 'invalid_recommended_build', data: null);
    }
    // A recommendation below the floor is incoherent — everyone below the floor
    // is already blocked, so the nudge could never be shown. Refuse rather than
    // silently store a setting that can have no effect.
    if (recommendedBuild != 0 && recommendedBuild < minimumBuild) {
      return (ok: false, error: 'recommended_below_minimum', data: null);
    }
    if (updateUrl != null && updateUrl is! String) {
      return (ok: false, error: 'invalid_update_url', data: null);
    }

    final updated = await _repo.setFloor(
      appId,
      platform.toLowerCase(),
      minimumBuild: minimumBuild,
      recommendedBuild: recommendedBuild,
      updateUrl: (updateUrl as String?)?.trim().isEmpty ?? true
          ? null
          : (updateUrl as String).trim(),
    );
    if (updated == null) return (ok: false, error: 'not_found', data: null);

    await _audit.append((
      actorAdminId: adminId,
      action: 'client_floor.set',
      targetType: 'client_version_floor',
      targetId: '$appId:${platform.toLowerCase()}',
      reason: null,
      // The values ARE the record here — unlike a user erasure, where the
      // metadata would be PII. Without them the log says a floor moved but not
      // to what, which is the one thing an incident review needs.
      metadata: {
        'minimumBuild': minimumBuild,
        'recommendedBuild': recommendedBuild,
        'hasUpdateUrl': updated.updateUrl != null,
      },
    ));
    return (ok: true, error: null, data: _json(updated));
  }

  Map<String, dynamic> _json(ClientVersionFloor f) => {
    'appId': f.appId,
    'platform': f.platform,
    'minimumBuild': f.minimumBuild,
    'recommendedBuild': f.recommendedBuild,
    'updateUrl': f.updateUrl,
  };
}
