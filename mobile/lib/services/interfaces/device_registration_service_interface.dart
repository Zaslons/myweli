import '../../models/api_response.dart';

/// Registers/unregisters this device's push token with the backend
/// (`POST/DELETE /me/devices`, self-scoped to the authed principal).
/// Design: docs/design/push-notifications-app.md.
abstract class DeviceRegistrationServiceInterface {
  /// Upsert the token for the current user. [platform] is `android|ios|web`.
  Future<ApiResponse<bool>> register(String token, String platform);

  /// Remove the token (e.g. on logout).
  Future<ApiResponse<bool>> unregister(String token);
}
