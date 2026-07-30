import 'package:http/http.dart' as http;

import '../appointments/appointment_repository.dart';
import '../auth/auth_repository.dart';
import '../clients/clients_service.dart';
import '../favorites_repository.dart';
import '../notifications/notification_prefs_repository.dart';
import '../notifications/notifications_repository.dart';
import '../push/device_token_repository.dart';
import '../reviews_repository.dart';
import '../storage/storage_service.dart';

/// Consumer ACCOUNT erasure (L1 — threat T59): what `DELETE /me` delegates to.
///
/// The consumer twin of [ProviderAccountService], which has orchestrated the
/// same shape for the pro side since audit 11.5. Design:
/// docs/design/account-deletion-erasure.md.
///
/// **Why this class exists at all.** `DELETE /me` returned 204 and deleted two
/// things: the `users` row and the OTP rows. Every other table keys on `user_id`
/// as a plain `text` column with **no foreign key**, so nothing cascaded —
/// reviews kept the display name, appointments kept name/phone/notes, favourites
/// and notifications survived, deposit screenshots were never touched, and
/// `device_tokens` survived, which meant **a deleted user's phone kept receiving
/// push**.
class UserErasureService {
  UserErasureService(
    this._auth,
    this._devices,
    this._notifications,
    this._prefs,
    this._favorites,
    this._reviews,
    this._appointments,
    this._clients,
    this._storage, {
    http.Client? client,
  }) : _client = client ?? http.Client();

  final AuthRepository _auth;
  final DeviceTokenRepository _devices;
  final NotificationsRepository _notifications;
  final NotificationPrefsRepository _prefs;
  final FavoritesRepository _favorites;
  final ReviewsRepository _reviews;
  final AppointmentRepository _appointments;
  final ClientsService _clients;
  final StorageService _storage;
  final http.Client _client;

  /// Erase everything [userId] left behind, then the identity itself.
  ///
  /// Returns `not_found` when there is no such user — which is also what a
  /// second call returns, and that is the point (see the invariant below).
  ///
  /// ## Children first, identity last
  ///
  /// **This reverses the order the route used to run in.** It deleted the
  /// `users` row *first* and anonymised `salon_clients` second, so a throw in
  /// step 2 left the salon CRM holding that person's name and phone forever —
  /// with no token left to retry with, because the identity backing it was
  /// already gone.
  ///
  /// There is no cross-repository transaction here and there cannot be one: the
  /// storage erasure is an HTTP call outside any database session. Atomicity is
  /// therefore replaced by an invariant, and the invariant is gated:
  ///
  /// > **Every step is idempotent, so a failed erasure leaves a live account
  /// > whose owner can press Delete again, and the retry converges.**
  ///
  /// That holds only while the identity goes last. Move [AuthRepository.deleteUser]
  /// up and the guarantee inverts: a partial failure becomes unrecoverable, and
  /// silently so.
  Future<({bool ok, String? error})> eraseUser(String userId) async {
    if (await _auth.userById(userId) == null) {
      return (ok: false, error: 'not_found');
    }

    // **Settle the agenda first** — the same rule `ProviderAccountService` has
    // enforced since audit 11.5, now on the consumer side (owner decision; §21
    // row 48 recorded the asymmetry).
    //
    // A salon holds a slot for a named person. If that person can vanish without
    // cancelling, the salon keeps a confirmed appointment it can neither contact
    // nor fill: `booking_notifier` resolves no recipient once the phone is NULL,
    // so even the reminder silently no-ops, and `appointments_slot_unique` keeps
    // the slot blocked. Deleting is the user's right; stranding a business is
    // not part of it.
    //
    // Before every other step, so a refusal is never a half-erasure.
    // `DateTime.now()` directly, matching `provider_account_service.dart:56` —
    // the backend has no clock seam (A10's `AppClock` is mobile-only), and
    // inventing one for a single comparison is a slice of its own.
    final now = DateTime.now().toUtc();
    final booked = await _appointments.listForUser(userId);
    final hasFuture = booked.any((a) {
      final status = a['status'] as String?;
      if (status != 'pending' && status != 'confirmed') return false;
      final date = DateTime.tryParse(a['appointmentDate'] as String? ?? '');
      return date != null && date.toUtc().isAfter(now);
    });
    if (hasFuture) return (ok: false, error: 'future_bookings');

    // 1. Stop the ringing first. This is the live bug, and it is the one step
    //    whose delay a user would actually notice.
    await _devices.deleteForUser(userId);

    // 2. The feed and its preferences.
    await _notifications.deleteForUser(userId);
    await _prefs.deleteForUser(userId);

    // 3. Favourites.
    await _favorites.deleteForUser(userId);

    // 4. The content survives, the author does not — plus the reports this user
    //    filed, which cannot be tombstoned (a UNIQUE constraint would collide).
    //    Returns the PUBLIC photo keys it detached: review photo URLs are
    //    `review/{userId}/…`, so leaving them served would keep the id legible
    //    in the address bar and let every review be grouped back together by
    //    prefix — the tombstone would be defeated by the payload beside it.
    final reviewPhotos = await _reviews.anonymizeUser(userId);

    // 5. The bookings are stripped, not deleted: the salon keeps its book.
    //    Returns the deposit keys it just cleared, which is the only place they
    //    can still be read.
    final depositKeys = await _appointments.anonymizeUser(userId);

    // 6. Module `clients` T48 — the identity disappears from every salon's
    //    client base (rows unlink, aggregates survive). Unchanged behaviour,
    //    moved here so the whole cascade has one owner.
    await _clients.anonymizeUser(userId);

    // 7. The objects. Own-prefix only, exactly as the KYC path does it — a
    //    foreign key sitting on this user's own row is skipped rather than
    //    trusted.
    //
    //    **Best-effort, and the user-facing copy says « nous supprimons » with
    //    that caveat rather than a guarantee.** A storage failure does not block
    //    the erasure, because the rows go next and a surviving DEPOSIT object is
    //    uuid-named in a private bucket with nothing pointing at it.
    //
    //    A surviving REVIEW photo is different — it is public — so this runs
    //    before the identity delete and its failure is the one worth retrying.
    //    The keys are gone from the database after the first attempt (both
    //    statements clear as they read), so a retry cannot re-derive them; that
    //    is the one place this cascade does not converge, and it is recorded in
    //    docs/design/account-deletion-erasure.md §11 rather than papered over.
    await _eraseObjects(depositKeys, 'deposit/$userId/', StorageBucket.deposit);
    await _eraseObjects(reviewPhotos, 'review/$userId/', StorageBucket.public);

    // 8. And only now the identity.
    final ok = await _auth.deleteUser(userId);
    return ok ? (ok: true, error: null) : (ok: false, error: 'not_found');
  }

  /// Erase [keys] from [bucket], keeping only those under [ownPrefix].
  ///
  /// Public review photos arrive here as full URLs (that is what the column
  /// stores); deposit screenshots arrive as bare keys. Both are normalised to a
  /// key before the prefix check, so a URL can never smuggle a foreign path
  /// past it.
  Future<void> _eraseObjects(
    List<String> keys,
    String ownPrefix,
    StorageBucket bucket,
  ) async {
    for (final raw in keys) {
      final key = _keyOf(raw);
      if (!key.startsWith(ownPrefix)) continue;
      try {
        final url = _storage.presignDelete(key: key, bucket: bucket);
        await _client.delete(Uri.parse(url));
      } catch (_) {
        // Tolerated — see the caller.
      }
    }
  }

  /// `https://cdn…/review/u1/x.jpg` → `review/u1/x.jpg`; a bare key is returned
  /// unchanged.
  static String _keyOf(String raw) {
    final i = raw.indexOf('://');
    if (i < 0) return raw;
    final slash = raw.indexOf('/', i + 3);
    return slash < 0 ? raw : raw.substring(slash + 1);
  }
}
