import '../../models/api_response.dart';
import '../../models/appointment.dart';
import '../../models/salon_client.dart';

/// The salon client base (module `clients` C1 — docs/design/clients-c1.md).
/// Reads are audited server-side; everything is salon-scoped (T45).
abstract class ProClientsServiceInterface {
  /// Paginated, sorted by last visit. [query] matches name or phone digits;
  /// [tag] filters exact. Page 1 carries `availableTags`.
  Future<ApiResponse<SalonClientsPage>> listClients(
    String providerId, {
    String? query,
    String? tag,
    int page = 1,
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
