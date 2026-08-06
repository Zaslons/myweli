import 'auth/provider_auth_repository.dart';
import 'storage/storage_service.dart';
import 'upload_verification_service.dart';

/// Outcome of a KYC operation; [data] is the `KycStatus` body on success.
typedef KycResult = ({bool ok, String? error, Map<String, dynamic>? data});

/// Provider KYC — submit identity documents + read verification status (design:
/// docs/design/pro-kyc.md). Self-scoped to the calling provider account (the
/// route passes the token's `sub`). Documents are uploaded to **private**
/// storage out of band; this records their metadata + keys and sets the status
/// to `pending`. The server is the authority on `verificationStatus` /
/// `rejectionReason` (only the future admin flips them).
class KycService {
  KycService(this._providerAuth, {UploadVerificationService? verifier})
    : _verifier = verifier;

  final ProviderAuthRepository _providerAuth;

  /// Claim-time size check (T61). Optional so existing construction sites keep
  /// working; when absent no size check runs, which is why the composition root
  /// always supplies it in production.
  final UploadVerificationService? _verifier;

  static const _docTypes = {
    'idCard',
    'selfie',
    'businessRegistration',
    'addressProof',
  };

  Future<KycResult> status(String accountId) async {
    final account = await _providerAuth.accountById(accountId);
    if (account == null) return (ok: false, error: 'forbidden', data: null);
    return (ok: true, error: null, data: _statusDto(account));
  }

  Future<KycResult> submit(String accountId, Object? documents) async {
    final account = await _providerAuth.accountById(accountId);
    if (account == null) return (ok: false, error: 'forbidden', data: null);
    if (documents is! List || documents.isEmpty) {
      return (ok: false, error: 'invalid_input', data: null);
    }

    final prefix = 'kyc/$accountId/';
    final docs = <Map<String, dynamic>>[];
    for (final d in documents) {
      if (d is! Map) return (ok: false, error: 'invalid_input', data: null);
      final type = d['type'];
      final key = d['key'];
      // The key must be one this account just uploaded (own KYC prefix) — no
      // attaching a foreign/arbitrary object.
      if (type is! String || !_docTypes.contains(type)) {
        return (ok: false, error: 'invalid_input', data: null);
      }
      if (key is! String || !key.startsWith(prefix)) {
        return (ok: false, error: 'invalid_input', data: null);
      }
      docs.add({
        'type': type,
        'fileName': d['fileName'] is String ? d['fileName'] : '',
        'key': key,
        'submittedAt': DateTime.now().toUtc().toIso8601String(),
      });
    }

    // Every key is proven to belong to this account above; none is proven to
    // be a sane size. KYC lands in a RETAINED bucket, so an oversized document
    // is paid for far longer than a deposit screenshot.
    final v = await _verifier?.verify(
      docs.map((d) => d['key'] as String).toList(),
      bucket: StorageBucket.kyc,
    );
    if (v != null && !v.ok) {
      return (ok: false, error: v.error, data: null);
    }

    final updated = await _providerAuth.submitKyc(accountId, docs);
    if (updated == null) return (ok: false, error: 'forbidden', data: null);
    return (ok: true, error: null, data: _statusDto(updated));
  }

  Map<String, dynamic> _statusDto(ProviderAccount a) => {
    'status': a.verificationStatus,
    'documents': a.kycDocs,
    'rejectionReason': a.rejectionReason,
  };
}
