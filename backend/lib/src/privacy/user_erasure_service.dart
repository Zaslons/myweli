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
    await _reviews.anonymizeUser(userId);

    // 5. The bookings are stripped, not deleted: the salon keeps its book.
    //    Returns the deposit keys it just cleared, which is the only place they
    //    can still be read.
    final depositKeys = await _appointments.anonymizeUser(userId);

    // 6. Module `clients` T48 — the identity disappears from every salon's
    //    client base (rows unlink, aggregates survive). Unchanged behaviour,
    //    moved here so the whole cascade has one owner.
    await _clients.anonymizeUser(userId);

    // 7. The deposit screenshots. Own-prefix only, exactly as the KYC path does
    //    it — a foreign key on this user's own row is skipped rather than
    //    trusted. Best-effort: a storage hiccup never blocks the erasure,
    //    because the rows go next and any survivor is uuid-named in a private
    //    bucket with nothing pointing at it.
    for (final key in depositKeys) {
      if (!key.startsWith('deposit/$userId/')) continue;
      try {
        final url = _storage.presignDelete(
          key: key,
          bucket: StorageBucket.deposit,
        );
        await _client.delete(Uri.parse(url));
      } catch (_) {
        // Tolerated — see above.
      }
    }

    // 8. And only now the identity.
    final ok = await _auth.deleteUser(userId);
    return ok ? (ok: true, error: null) : (ok: false, error: 'not_found');
  }
}
