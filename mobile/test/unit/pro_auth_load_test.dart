import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

/// The constructor starts the session load and keeps it as `ready`; the Pro
/// splash awaits that one (pro-open-animation.md §5) — they must share ONE
/// load, not race two sets of authenticated requests at cold start
/// (session-refresh.md). And `restored` marks the stored session, read before
/// the live refresh, which is what the splash routes on past its deadline.
class _CountingAuth extends MockAuthService {
  int loads = 0;

  /// The stored session, when the test wants one.
  ProviderUser? stored;

  @override
  Future<ProviderUser?> getCurrentProvider() async {
    loads++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return stored ?? await super.getCurrentProvider();
  }
}

/// GET /me/provider that answers only when the test says so.
class _SlowProService extends MockProService {
  Completer<ApiResponse<MyProviderInfo>>? pending;

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId}) =>
      (pending = Completer<ApiResponse<MyProviderInfo>>()).future;
}

void main() {
  // `serviceLocator.*` are late finals: set once per test file.
  final counting = _CountingAuth();
  final pro = _SlowProService();
  setUpAll(() {
    serviceLocator.authService = counting;
    serviceLocator.proService = pro;
  });
  setUp(() {
    counting
      ..loads = 0
      ..stored = null;
  });

  test(
    'ready IS the constructor\'s load — awaiting it starts nothing',
    () async {
      final auth = ProAuthProvider(); // starts a load
      await auth.ready;
      await auth.ready;

      expect(counting.loads, 1);
    },
  );

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
    await auth.ready;
    await auth.loadCurrentProvider();

    expect(counting.loads, 2);
  });

  test(
    'restored lands with the stored session, before the live refresh',
    () async {
      counting.stored = ProviderUser(
        id: 'acct_1',
        phoneNumber: '+2250700000001',
        businessName: 'Salon Test',
        businessType: BusinessType.salon,
        createdAt: DateTime.utc(2026),
      );
      final auth = ProAuthProvider();
      var ready = false;
      unawaited(auth.ready.then((_) => ready = true));

      await auth.restored;
      expect(auth.isAuthenticated, isTrue, reason: 'answered from storage');
      expect(pro.pending, isNotNull, reason: 'the live refresh has started');
      expect(ready, isFalse, reason: 'and is still running');

      pro.pending!.complete(ApiResponse.error('offline'));
      await auth.ready;
      expect(auth.isAuthenticated, isTrue, reason: 'a failed refresh keeps it');
    },
  );

  test('restored lands for a signed-out start too', () async {
    final auth = ProAuthProvider();
    await auth.restored;
    expect(auth.isAuthenticated, isFalse);
  });
}
