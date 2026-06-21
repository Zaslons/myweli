import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/providers/pro_deposit_settings_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';

class _MockProService extends Mock implements ProServiceInterface {}

void main() {
  late _MockProService service;

  setUpAll(() {
    service = _MockProService();
    serviceLocator.proService = service;
  });

  setUp(() => reset(service));

  test('load pulls the provider deposit policy', () async {
    when(() => service.getDepositPolicy(any())).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(depositRequired: true, depositPercentage: 0.50),
      ),
    );

    final provider = ProDepositSettingsProvider();
    await provider.load('p1');

    expect(provider.depositRequired, isTrue);
    expect(provider.depositPercentage, 0.50);
    expect(provider.loadFailed, isFalse);
  });

  test('load marks loadFailed on error', () async {
    when(() => service.getDepositPolicy(any()))
        .thenAnswer((_) async => ApiResponse.error('boom'));

    final provider = ProDepositSettingsProvider();
    await provider.load('p1');

    expect(provider.loadFailed, isTrue);
    expect(provider.error, 'boom');
  });

  test('save sends the edited policy and returns true', () async {
    when(
      () => service.updateDepositPolicy(
        any(),
        depositRequired: any(named: 'depositRequired'),
        depositPercentage: any(named: 'depositPercentage'),
      ),
    ).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(depositRequired: false, depositPercentage: 0.30),
      ),
    );

    final provider = ProDepositSettingsProvider();
    provider.setDepositRequired(false);
    final ok = await provider.save('p1');

    expect(ok, isTrue);
    verify(
      () => service.updateDepositPolicy(
        'p1',
        depositRequired: false,
        depositPercentage: any(named: 'depositPercentage'),
      ),
    ).called(1);
  });

  test('save returns false on failure', () async {
    when(
      () => service.updateDepositPolicy(
        any(),
        depositRequired: any(named: 'depositRequired'),
        depositPercentage: any(named: 'depositPercentage'),
      ),
    ).thenAnswer((_) async => ApiResponse.error('nope'));

    final provider = ProDepositSettingsProvider();
    final ok = await provider.save('p1');

    expect(ok, isFalse);
    expect(provider.error, 'nope');
  });
}
