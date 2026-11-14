/// Audit action codes → French labels (admin audit log). The map also drives the
/// action-filter dropdown. Design: docs/design/admin-console-ui.md §3.
///
/// **Every code the backend appends to the ADMIN log has a label here** —
/// `auditActionLabel` falls back to the raw code, which is how
/// `subscription.paid`, `user.erase`, `demo.snapshot` and
/// `admin.password_changed` reached the screen in English until B0.18
/// (salon-go-live-approval.md §4.4). Pinned by
/// test/unit/validation_labels_test.dart against the backend's writers.
const Map<String, String> kAuditActions = {
  'kyc.approve': 'KYC approuvé',
  'kyc.reject': 'KYC rejeté',
  'review.hide': 'Avis masqué',
  'review.restore': 'Avis restauré',
  'review.dismiss_reports': 'Signalements ignorés',
  'provider.suspend': 'Salon suspendu',
  // B0.18: a lift no longer always puts the salon back online (§3.4).
  'provider.restore': 'Suspension levée',
  'provider.feature': 'Mise en avant',
  'subscription.paid': 'Abonnement marqué payé',
  // B0.18 — salon-go-live-approval.md §4.4. « Validé », never « vérifié »:
  // that word is KYC's.
  'salon.approve': 'Salon validé',
  'salon.refuse': 'Mise en ligne refusée',
  'user.ban': 'Client banni',
  'user.unban': 'Client réactivé',
  'user.erase': 'Compte client effacé',
  // B0.25's server half — admin-pro-account-erase.md §4.1.
  'provider_account.erase': 'Compte Pro effacé',
  'dispute.open': 'Litige ouvert',
  'dispute.resolve': 'Litige résolu',
  'client_floor.set': 'Version minimale modifiée',
  'demo.snapshot': 'Instantané de la démo',
  'admin.password_changed': 'Mot de passe admin modifié',
};

/// French label for an audit action code (falls back to the raw code).
String auditActionLabel(String? code) => kAuditActions[code] ?? (code ?? '—');
