/// Global 403 seam (module `access` §5.3 — team access R4b).
///
/// Pro ChangeNotifier providers report forbidden ApiResponses here; the
/// wired handler (ProAuthProvider.checkMembershipAlive) probes
/// GET /me/provider ONCE. A REVOKED member is held on « Invitations » when
/// re-invited, else signed out with « Votre accès à {salon} a été retiré. »
/// (docs/design/pro-rejoin-gate.md). A capability-403 from a still-
/// active member probes, gets a 200, and nothing happens — no dead-end
/// screens either way. Static so providers need no coupling to auth.
class ProAccessGuard {
  ProAccessGuard._();

  /// Wired by ProAuthProvider at construction.
  static Future<void> Function()? onForbidden;

  /// Report a failed ApiResponse's machine [code]; only forbidden-shaped
  /// codes trigger the (single-flight) membership probe.
  static void report(String? code) {
    if (code == 'forbidden' || code == 'not_a_member') {
      onForbidden?.call();
    }
  }
}
