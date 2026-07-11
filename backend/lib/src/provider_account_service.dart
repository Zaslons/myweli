import 'package:http/http.dart' as http;

import 'appointments/appointment_repository.dart';
import 'auth/provider_auth_repository.dart';
import 'providers_repository.dart';
import 'storage/storage_service.dart';

/// Provider ACCOUNT lifecycle (audit 11.5 — threat T53): the deletion flow
/// that the `/me/provider` route delegates to. Orchestrates the
/// future-bookings gate, the salon unpublish, the KYC storage erasure and
/// the identity delete. Design: docs/design/pro-account-deletion-export.md.
class ProviderAccountService {
  ProviderAccountService(
    this._auth,
    this._providers,
    this._appointments,
    this._storage, {
    http.Client? client,
  }) : _client = client ?? http.Client();

  final ProviderAuthRepository _auth;
  final ProvidersRepository _providers;
  final AppointmentRepository _appointments;
  final StorageService _storage;
  final http.Client _client;

  /// Delete the account behind [accountId]. Error codes: `forbidden`
  /// (unknown account), `future_bookings` (settle the agenda first).
  Future<({bool ok, String? error})> deleteAccount(String accountId) async {
    final account = await _auth.accountById(accountId);
    if (account == null) return (ok: false, error: 'forbidden');

    final providerId = account.providerId;
    if (providerId != null) {
      // The salon settles its agenda first — no surprise mass-cancellations.
      final open = await _appointments.listForProvider(providerId);
      final now = DateTime.now().toUtc();
      final hasFuture = open.any((a) {
        final status = a['status'] as String?;
        if (status != 'pending' && status != 'confirmed') return false;
        final date = DateTime.tryParse(a['appointmentDate'] as String? ?? '');
        return date != null && date.isAfter(now);
      });
      if (hasFuture) return (ok: false, error: 'future_bookings');

      // Unpublish, don't destroy: T51 hides drafts everywhere while bookings,
      // reviews and the CRM keep resolving (business history ≠ identity).
      await _providers.setStatus(providerId, 'draft');
    }

    // Erase the KYC objects from the private bucket (T53 — « définitive »
    // means the documents too). Own-prefix keys only (defense in depth); a
    // storage hiccup never blocks the account erasure — the rows go next,
    // making any survivor unreachable.
    for (final doc in account.kycDocs) {
      final key = doc['key'] as String?;
      if (key == null || !key.startsWith('kyc/$accountId/')) continue;
      try {
        final url = _storage.presignDelete(key: key, bucket: StorageBucket.kyc);
        await _client.delete(Uri.parse(url));
      } catch (_) {
        // Tolerated: uuid-named + private + rows deleted ⇒ unreachable.
      }
    }

    final ok = await _auth.deleteAccount(accountId);
    return ok ? (ok: true, error: null) : (ok: false, error: 'forbidden');
  }
}
