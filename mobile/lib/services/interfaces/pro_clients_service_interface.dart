import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/salon_client.dart';

/// The salon client base (module `clients` C1 — docs/design/clients-c1.md).
/// Reads are audited server-side; everything is salon-scoped (T45).
abstract class ProClientsServiceInterface {
  /// Paginated, sorted by last visit. [query] matches name or phone digits;
  /// [tag] filters exact. Page 1 carries `availableTags`. [pageSize] absent =
  /// the server's default (20); the server clamps it to 1–50 and echoes the
  /// size it used in [SalonClientsPage.pageSize] — the data export walks the
  /// whole base with it (docs/design/app-pro-export-completeness.md §4).
  Future<ApiResponse<SalonClientsPage>> listClients(
    String providerId, {
    String? query,
    String? tag,
    int page = 1,
    int? pageSize,
  });

  Future<ApiResponse<SalonClientCard>> getCard(
    String providerId,
    String clientId,
  );

  /// The client's visits AT THIS SALON, newest first (paginated).
  Future<ApiResponse<List<Appointment>>> getVisits(
    String providerId,
    String clientId, {
    int page = 1,
  });

  /// Manual add — phone REQUIRED (dedupe/link key, decision §11.4).
  /// Returns the client id; a duplicate phone succeeds-by-redirect: the
  /// response carries code `client_exists` + the EXISTING card's id.
  Future<ApiResponse<String>> addClient(
    String providerId, {
    required String name,
    required String phone,
    String? note,
  });

  Future<ApiResponse<SalonClient>> updateTags(
    String providerId,
    String clientId,
    List<String> tags,
  );

  /// Changes a GUEST card's number (docs/design/phone-leftovers.md §8) —
  /// `PATCH` with `phone`. Its history follows: the server moves THIS salon's
  /// walk-in bookings under the old number to the new one, in the same
  /// transaction (never another salon's — T45). Success carries the updated
  /// card (the same number is a success with nothing done). Refusals, by
  /// [ApiResponse.code]: `client_linked` (a card linked to an account keeps
  /// the account's number), `invalid_phone`, `client_exists` (data carries
  /// the card that already has the number — [SalonClientPhoneChange.taken]),
  /// `not_found`, `forbidden`.
  Future<ApiResponse<SalonClientPhoneChange>> updatePhone(
    String providerId,
    String clientId,
    String phone,
  );

  Future<ApiResponse<SalonClientNote>> addNote(
    String providerId,
    String clientId,
    String body,
  );

  Future<ApiResponse<bool>> deleteNote(
    String providerId,
    String clientId,
    String noteId,
  );
}
