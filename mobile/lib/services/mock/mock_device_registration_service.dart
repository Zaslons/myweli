import '../../models/api_response.dart';
import '../interfaces/device_registration_service_interface.dart';

/// In-memory mock of [DeviceRegistrationServiceInterface]. Records the tokens it
/// would have sent to the backend, so the push flow runs and is testable without
/// a server. Design: docs/design/push-notifications-app.md.
class MockDeviceRegistrationService
    implements DeviceRegistrationServiceInterface {
  final Set<String> registeredTokens = <String>{};

  @override
  Future<ApiResponse<bool>> register(String token, String platform) async {
    await _delay();
    registeredTokens.add(token);
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> unregister(String token) async {
    await _delay();
    registeredTokens.remove(token);
    return ApiResponse.success(true);
  }

  Future<void> _delay() => Future<void>.delayed(
        const Duration(milliseconds: 50),
      );
}
