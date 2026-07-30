import '../appointments/appointment_repository.dart';
import '../providers_repository.dart';
import '../subscription/salon_subscription_service.dart';
import 'admin_kyc_service.dart' show AdminResult;
import 'audit_log_repository.dart';

/// Admin provider management (design: docs/design/admin-console.md §12). List /
/// view providers, suspend/restore (hide from discovery + block new bookings),
/// and toggle featured placement — every mutation audited.
class AdminProviderService {
  AdminProviderService(
    this._providers,
    this._appointments,
    this._audit,
    this._subscriptions,
  );

  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;
  final AuditLogRepository _audit;
  final SalonSubscriptionService _subscriptions;

  Future<AdminResult> list({
    String? status,
    String? q,
    int page = 1,
    int pageSize = 20,
  }) async {
    final r = await _providers.listForAdmin(
      status: status,
      q: q,
      page: page,
      pageSize: pageSize,
    );
    return (
      ok: true,
      error: null,
      data: {
        'items': r.items,
        'page': page,
        'pageSize': pageSize,
        'total': r.total,
      },
    );
  }

  /// Read-only support view: the provider + its recent bookings (no act-as).
  Future<AdminResult> detail(String id) async {
    final p = await _providers.byId(id);
    if (p == null) return (ok: false, error: 'not_found', data: null);
    final appts = await _appointments.listForProvider(id);
    return (
      ok: true,
      error: null,
      data: {...p, 'recentAppointments': appts.take(20).toList()},
    );
  }

  Future<AdminResult> suspend(String adminId, String id, Object? reason) =>
      _setStatus(adminId, id, 'suspended', 'provider.suspend', reason);

  Future<AdminResult> restore(String adminId, String id) =>
      _setStatus(adminId, id, 'active', 'provider.restore', null);

  Future<AdminResult> _setStatus(
    String adminId,
    String id,
    String status,
    String action,
    Object? reason,
  ) async {
    final updated = await _providers.setStatus(id, status);
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    await _audit.append((
      actorAdminId: adminId,
      action: action,
      targetType: 'provider',
      targetId: id,
      reason: reason is String && reason.trim().isNotEmpty
          ? reason.trim()
          : null,
      metadata: const {},
    ));
    return (ok: true, error: null, data: updated);
  }

  Future<AdminResult> feature(
    String adminId,
    String id,
    Object? featured,
  ) async {
    if (featured is! bool) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final updated = await _providers.setFeatured(id, featured);
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    await _audit.append((
      actorAdminId: adminId,
      action: 'provider.feature',
      targetType: 'provider',
      targetId: id,
      reason: null,
      metadata: {'featured': featured},
    ));
    return (ok: true, error: null, data: updated);
  }

  /// Manual billing (« Nous contacter », T54): record [months] months of
  /// payment for the salon; republishes a billing-unpublished salon when the
  /// publish gate passes. Audited.
  Future<AdminResult> markSubscriptionPaid(
    String adminId,
    String id,
    Object? months, {
    Object? reason,
  }) async {
    if (months is! int || months < 1 || months > 24) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final r = await _subscriptions.markPaid(id, months: months);
    if (!r.ok) return (ok: false, error: r.error, data: null);
    await _audit.append((
      actorAdminId: adminId,
      action: 'subscription.paid',
      targetType: 'provider',
      targetId: id,
      reason: reason is String ? reason : null,
      metadata: {'months': months},
    ));
    return (ok: true, error: null, data: r.data);
  }
}
