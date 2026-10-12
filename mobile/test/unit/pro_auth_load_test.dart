import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';

/// The constructor starts the session load and the Pro splash awaits it
/// (pro-open-animation.md) — they must share ONE load, not race two sets of
/// authenticated requests at cold start (session-refresh.md).
class _CountingAuth extends MockAuthService {
  int loads = 0;

  @override
  Future<ProviderUser?> getCurrentProvider() async {
    loads++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.getCurrentProvider();
  }
}

void main() {
  // `serviceLocator.authService` is a late final: set once per test file.
  final counting = _CountingAuth();
  setUpAll(() => serviceLocator.authService = counting);
  setUp(() => counting.loads = 0);

  test(
    'concurrent loadCurrentProvider calls share the load in flight',
    () async {
      final auth = ProAuthProvider(); // starts a load
      await Future.wait([
        auth.loadCurrentProvider(),
        auth.loadCurrentProvider(),
      ]);

      expect(counting.loads, 1);
    },
  );

  test('a load after the previous one finished runs again', () async {
    final auth = ProAuthProvider();
    await auth.loadCurrentProvider();
    await auth.loadCurrentProvider();

    expect(counting.loads, 2);
  });
}
