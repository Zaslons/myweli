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
  KycService(
    this._providerAuth, {
    UploadVerificationService? verifier,
    StorageService? storage,
    Duration deleteBudget = const Duration(seconds: 5),
  }) : _verifier = verifier,
       _storage = storage,
       _deleteBudget = deleteBudget;

  final ProviderAuthRepository _providerAuth;

  /// Claim-time size check (T61). Optional so existing construction sites keep
  /// working; when absent no size check runs, which is why the composition root
  /// always supplies it in production.
  final UploadVerificationService? _verifier;

  /// Deletes the documents a re-submit replaced (B0.22 — design:
  /// docs/design/pro-deletion-erase-gaps.md §3.2). Optional for the same
  /// reason; without it nothing is deleted, which is why `dependencies.dart`
  /// wires it (`kyc_wiring_test.dart` pins it).
  final StorageService? _storage;

  /// How long one submit's post-write deletes may hold its response, all of
  /// them together. They run after the transaction has committed, so a
  /// storage call that HANGS rather than erroring must not turn a stored
  /// submit into a client timeout: past the budget, a delete is treated like
  /// a thrown one (the object survives, as any best-effort survivor does).
  /// The R2 client sets no timeout of its own.
  final Duration _deleteBudget;

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

    // B0.22 §3.2 — compared AFTER the promotion, so a re-sent pending key
    // already maps to its stored form. A final key in `stored` was passed
    // through on the strength of the read above; any other one this request
    // just promoted. The write re-checks the pass-through keys under the row
    // lock: a concurrent re-submit may have replaced — and deleted — one
    // since. docs/design/pro-deletion-erase-gaps.md
    final keys = [for (final d in docs) d['key'] as String];
    final passThrough = {
      for (final k in keys)
        if (stored.contains(k)) k,
    };
    final write = await _providerAuth.submitKyc(
      accountId,
      docs,
      passThrough: passThrough,
    );
    final updated = write.account;
    if (write.refused || updated == null) {
      // Lost the race (or the account went meanwhile). This request's fresh
      // copies would sit unreferenced in a retained bucket — but NOT one the
      // locked list holds: a promoted key is a pure function of its pending
      // key, so a winner that carried the same upload committed that very
      // object. Nothing old is deleted. A refusal is the contract's existing
      // 400 (« one this account no longer holds »).
      //
      // The lock is gone by the time these deletes run, so a THIRD submit
      // carrying that same upload can commit the same key in between (its
      // pass-through set is empty, so nothing refuses it). Hence the re-read
      // before each delete. It narrows that window to one storage call; it
      // does not close it, and nothing here claims it does: the row would
      // then point at a deleted object, which re-uploading that document
      // recovers.
      final locked = write.lockedKeys.toSet();
      await _deleteOwn(accountId, {
        for (final k in keys)
          if (!passThrough.contains(k) && !locked.contains(k)) k,
      }, recheck: true);
      return (
        ok: false,
        error: write.refused ? 'invalid_input' : 'forbidden',
        data: null,
      );
    }

    // Written: the documents the new list leaves out are referenced by
    // nothing now, and the account's deletion would no longer list them —
    // so they go here, after the transaction, never inside the lock. No
    // re-read: a later submit can only list one of them again by promoting
    // its `pending/` source anew, and that source exists only if an earlier
    // promotion's best-effort delete of it failed — the residual BACKEND.md
    // T15 declares.
    final kept = keys.toSet();
    await _deleteOwn(accountId, {
      for (final k in write.lockedKeys)
        if (!kept.contains(k)) k,
    });
    return (ok: true, error: null, data: _statusDto(updated));
  }

  /// Delete [keys] from the KYC bucket — only this account's own
  /// `kyc/{accountId}/…` objects (never a `pending/` key, never another
  /// prefix: the filter of the account deletion), sequentially (the lists
  /// are capped at [_maxDocuments]) and **best effort**, as the deletion is.
  /// A survivor is private, uuid-named and referenced by nothing; a storage
  /// failure — a thrown call, or one still unanswered when [_deleteBudget]
  /// runs out — never turns a stored submit into an error. With [recheck],
  /// the row is re-read before each delete and a key it lists again is kept
  /// (a failed re-read keeps it too: a leftover object over a row pointing
  /// at a deleted one). Nothing is logged.
  Future<void> _deleteOwn(
    String accountId,
    Iterable<String> keys, {
    bool recheck = false,
  }) async {
    final storage = _storage;
    if (storage == null) return;
    final own = 'kyc/$accountId/';
    final deadline = DateTime.now().add(_deleteBudget);
    for (final key in keys) {
      if (!key.startsWith(own)) continue;
      try {
        if (recheck) {
          final now = await _providerAuth.accountById(accountId);
          if (now != null && kycKeysOf(now.kycDocs).contains(key)) continue;
        }
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) return;
        await storage
            .deleteObject(key: key, bucket: StorageBucket.kyc)
            .timeout(left);
      } catch (_) {
        // Tolerated: see above.
      }
    }
  }

  Map<String, dynamic> _statusDto(ProviderAccount a) => {
    'status': a.verificationStatus,
    'documents': a.kycDocs,
    'rejectionReason': a.rejectionReason,
  };
}
