/// Audit action codes → French labels (admin audit log). The map also drives the
/// action-filter dropdown. Design: docs/design/admin-console-ui.md §3.
const Map<String, String> kAuditActions = {
  'kyc.approve': 'KYC approuvé',
  'kyc.reject': 'KYC rejeté',
  'review.hide': 'Avis masqué',
  'review.restore': 'Avis restauré',
  'review.dismiss_reports': 'Signalements ignorés',
  'provider.suspend': 'Salon suspendu',
  'provider.restore': 'Salon réactivé',
  'provider.feature': 'Mise en avant',
  'user.ban': 'Client banni',
  'user.unban': 'Client réactivé',
  'dispute.open': 'Litige ouvert',
  'dispute.resolve': 'Litige résolu',
};

/// French label for an audit action code (falls back to the raw code).
String auditActionLabel(String? code) => kAuditActions[code] ?? (code ?? '—');
