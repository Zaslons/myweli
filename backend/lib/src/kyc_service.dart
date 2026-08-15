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

  /// Generous against four document types, and a bound where there was none:
  /// this list is handed straight to the verifier, making it the largest
  /// promotion batch in the system with nothing capping it.
  static const _maxDocuments = 8;

  Future<KycResult> status(String accountId) async {
    final account = await _providerAuth.accountById(accountId);
    if (account == null) return (ok: false, error: 'forbidden', data: null);
    return (ok: true, error: null, data: _statusDto(account));
  }

  Future<KycResult> submit(String accountId, Object? documents) async {
    final account = await _providerAuth.accountById(accountId);
    if (account == null) return (ok: false, error: 'forbidden', data: null);
    if (documents is! List ||
        documents.isEmpty ||
        documents.length > _maxDocuments) {
      return (ok: false, error: 'invalid_input', data: null);
    }

    // **A rejected professional could not fix ONE document.** The gate below
    // used to require every key to be pending — the CLAIM form — while
    // `GET /me/kyc` hands back the PROMOTED keys and both clients repopulate
    // the tile list from exactly that response. So replacing only the document
    // the admin flagged, or simply pressing submit again, failed with a bare
    // `invalid_input` the UI cannot attribute to a field, on the one screen
    // standing between a salon and going live. (Re-uploading EVERY tile did
    // work, so this was never the hard lockout it looked like — it was the
    // natural action failing while an exhausting one succeeded.)
    //
    // Two states, not one. `stored` is this account's OWN current documents,
    // read from the account already in hand — membership, never shape.
    // Accepting `kyc/{accountId}/…` because it *looks* promoted would let the
    // account point a document at an object it deleted or never uploaded; the
    // set is scoped to its own docs for the same reason an artist's set is
    // scoped to that artist rather than to the salon.
    final prefix = '${kPendingPrefix}kyc/$accountId/';
    final stored = <String>{
      for (final d in account.kycDocs)
        if (d['key'] is String) d['key'] as String,
    };
    final docs = <Map<String, dynamic>>[];
    for (final d in documents) {
      if (d is! Map) return (ok: false, error: 'invalid_input', data: null);
      final type = d['type'];
      final key = d['key'];
      if (type is! String || !_docTypes.contains(type)) {
        return (ok: false, error: 'invalid_input', data: null);
      }
      if (key is! String || !(stored.contains(key) || key.startsWith(prefix))) {
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
    // is paid for far longer than a deposit screenshot. Keys, not urls: the KYC
    // bucket has no public base at all, so there is nothing to strip.
    final v = await _verifier?.promoteNewKeys(
      docs.map((d) => d['key'] as String).toList(),
      alreadyStored: stored,
      bucket: StorageBucket.kyc,
    );
    if (v != null && !v.ok) {
      return (ok: false, error: v.error, data: null);
    }
    // Record the PROMOTED keys — a pending key would be expired by the
    // lifecycle rule while the document is still the account's KYC evidence.
    if (v != null) {
      for (var i = 0; i < docs.length; i++) {
        docs[i]['key'] = v.keys[i];
      }
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
