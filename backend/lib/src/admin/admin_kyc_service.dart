import '../auth/provider_auth_repository.dart';
import '../providers_repository.dart';
import '../storage/storage_service.dart';
import 'audit_log_repository.dart';

/// Outcome of an admin operation; [data] is the response body on success.
typedef AdminResult = ({bool ok, String? error, Object? data});

/// Admin KYC review (design: docs/design/admin-console.md). Lists pending
/// provider accounts, issues short-lived **signed-GET** URLs to view their
/// private ID documents, and approves/rejects verification — every decision
/// written to the audit log.
class AdminKycService {
  AdminKycService(this._providers, this._storage, this._audit, this._listings);

  final ProviderAuthRepository _providers;
  final StorageService _storage;
  final AuditLogRepository _audit;

  /// The public salon listing — approve/reject denormalizes `verified` onto
  /// it so consumer surfaces can render the « Vérifié » badge (audit 15.1).
  final ProvidersRepository _listings;

  static const _docTtl = Duration(minutes: 5);

  Future<AdminResult> queue({int page = 1, int pageSize = 20}) async {
    final r = await _providers.listByVerificationStatus(
      'pending',
      page: page,
      pageSize: pageSize,
    );
    return (
      ok: true,
      error: null,
      data: {
        'items': [
          for (final a in r.items)
            {
              'accountId': a.id,
              'businessName': a.businessName,
              'businessType': a.businessType,
              'submittedAt': a.createdAt.toIso8601String(),
              'docCount': a.kycDocs.length,
            },
        ],
        'page': page,
        'pageSize': pageSize,
        'total': r.total,
      },
    );
  }

  Future<AdminResult> detail(String accountId) async {
    final a = await _providers.accountById(accountId);
    if (a == null) return (ok: false, error: 'not_found', data: null);
    final docs = [
      for (final d in a.kycDocs)
        {
          'type': d['type'],
          'key': d['key'],
          if (d['key'] is String)
            'viewUrl': _storage.presignGet(
              key: d['key'] as String,
              bucket: StorageBucket.kyc,
              ttl: _docTtl,
            ),
        },
    ];
    return (ok: true, error: null, data: {...a.toJson(), 'docs': docs});
  }

  Future<AdminResult> approve(String adminId, String accountId) async {
    final updated = await _providers.setVerification(
      accountId,
      status: 'verified',
    );
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    final providerId = updated.providerId;
    if (providerId != null) {
      await _listings.updateProfile(providerId, {'verified': true});
    }
    await _audit.append((
      actorAdminId: adminId,
      action: 'kyc.approve',
      targetType: 'provider_account',
      targetId: accountId,
      reason: null,
      metadata: const {},
    ));
    return (ok: true, error: null, data: updated.toJson());
  }

  Future<AdminResult> reject(
    String adminId,
    String accountId,
    Object? reason,
  ) async {
    if (reason is! String || reason.trim().isEmpty) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final updated = await _providers.setVerification(
      accountId,
      status: 'rejected',
      rejectionReason: reason.trim(),
    );
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    final providerId = updated.providerId;
    if (providerId != null) {
      await _listings.updateProfile(providerId, {'verified': false});
    }
    await _audit.append((
      actorAdminId: adminId,
      action: 'kyc.reject',
      targetType: 'provider_account',
      targetId: accountId,
      reason: reason.trim(),
      metadata: const {},
    ));
    return (ok: true, error: null, data: updated.toJson());
  }
}
