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
        const DepositPolicy(
          depositRequired: true,
          depositPercentage: 0.50,
          cancellationWindowHours: 48,
        ),
      ),
    );

    final provider = ProDepositSettingsProvider();
    await provider.load('p1');

    expect(provider.depositRequired, isTrue);
    expect(provider.depositPercentage, 0.50);
    expect(provider.cancellationWindowHours, 48);
    expect(provider.loadFailed, isFalse);
  });

  // ---- acompte-off-parity.md §2: 0 % is « not chosen yet » ----------------
  //
  // Every new salon is stored with `depositPercentage: 0`, and the web wrote
  // more of them when deposits were turned off. `load` copied it: the label
  // said « 0 % », and switching deposits on then saving was refused by the
  // server (`depositRequired && pct <= 0`).

  void stubLoad(DepositPolicy policy) {
    when(
      () => service.getDepositPolicy(any()),
    ).thenAnswer((_) async => ApiResponse.success(policy));
  }

  test(
    'load reads a stored 0 % as not chosen yet: the form proposes 30 %',
    () async {
      final provider = ProDepositSettingsProvider();
      // The provider lives as long as the app and the screen loads on every
      // visit: start from a value that is NOT the default, or « left as it
      // was » and « proposes 30 % » would look the same.
      provider.setDepositPercentage(0.60);
      stubLoad(
        const DepositPolicy(depositRequired: false, depositPercentage: 0),
      );
      await provider.load('p1');

      expect(provider.depositPercentage, 0.30);
    },
  );

  test('load keeps any chosen percentage, however small — only 0 is '
      '« not chosen »', () async {
    // The web takes 1–100 %, below the app slider's 5 %: a 1 % deposit is
    // the salon's, not a gap for the default to fill.
    stubLoad(
      const DepositPolicy(depositRequired: true, depositPercentage: 0.01),
    );

    final provider = ProDepositSettingsProvider();
    await provider.load('p1');

    expect(provider.depositPercentage, 0.01);
  });

  test('load keeps a chosen percentage, deposits off too', () async {
    stubLoad(
      const DepositPolicy(depositRequired: false, depositPercentage: 0.5),
    );

    final provider = ProDepositSettingsProvider();
    await provider.load('p1');

    expect(provider.depositPercentage, 0.5);
  });

  test('the form starts from 30 % — before any load, and after a salon '
      'switch', () async {
    final provider = ProDepositSettingsProvider();
    expect(provider.depositPercentage, 0.30);

    stubLoad(
      const DepositPolicy(depositRequired: true, depositPercentage: 0.5),
    );
    await provider.load('p1');
    provider.resetForSalonSwitch();

    expect(provider.depositPercentage, 0.30);
  });

  test('load marks loadFailed on error', () async {
    when(
      () => service.getDepositPolicy(any()),
    ).thenAnswer((_) async => ApiResponse.error('boom'));

    final provider = ProDepositSettingsProvider();
    await provider.load('p1');

    expect(provider.loadFailed, isTrue);
    expect(provider.error, 'boom');
  });

  test('load marks loadFailed when the read throws — the screen shows its '
      'error state, never a form to save over the policy', () async {
    // The web showed a blank form here (acompte-off-parity.md D3); the app is
    // the reference it now follows — pinned.
    when(
      () => service.getDepositPolicy(any()),
    ).thenThrow(const FormatException('malformed body'));

    final provider = ProDepositSettingsProvider();
    await provider.load('p1');

    expect(provider.loadFailed, isTrue);
    expect(provider.isLoading, isFalse);
  });

  test('save sends the edited policy and returns true', () async {
    when(
      () => service.updateDepositPolicy(
        any(),
        depositRequired: any(named: 'depositRequired'),
        depositPercentage: any(named: 'depositPercentage'),
        cancellationWindowHours: any(named: 'cancellationWindowHours'),
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
        cancellationWindowHours: any(named: 'cancellationWindowHours'),
      ),
    ).called(1);
  });

  // ---- acompte-off-parity.md §2 decision 1: the PUT replaces the whole policy
  //
  // The web sent `mobileMoneyOperator: null` and `depositPercentage: 0` as
  // soon as deposits were off, so a client who still owed a deposit lost the
  // operator to pay with. The app sends what it holds — this pins it.

  void stubSaveOk() {
    when(
      () => service.updateDepositPolicy(
        any(),
        depositRequired: any(named: 'depositRequired'),
        depositPercentage: any(named: 'depositPercentage'),
        cancellationWindowHours: any(named: 'cancellationWindowHours'),
        mobileMoneyOperator: any(named: 'mobileMoneyOperator'),
        mobileMoneyNumber: any(named: 'mobileMoneyNumber'),
      ),
    ).thenAnswer(
      (_) async => ApiResponse.success(
        const DepositPolicy(depositRequired: false, depositPercentage: 0.40),
      ),
    );
  }

  test('save with deposits off sends the operator and the percentage it '
      'holds', () async {
    stubLoad(
      const DepositPolicy(
        depositRequired: true,
        depositPercentage: 0.40,
        mobileMoneyOperator: 'wave',
        mobileMoneyNumber: '+2250707123456',
      ),
    );
    stubSaveOk();

    final provider = ProDepositSettingsProvider();
    await provider.load('p1');
    provider.setDepositRequired(false);
    final ok = await provider.save('p1');

    expect(ok, isTrue);
    verify(
      () => service.updateDepositPolicy(
        'p1',
        depositRequired: false,
        depositPercentage: 0.40,
        cancellationWindowHours: 24,
        mobileMoneyOperator: 'wave',
        mobileMoneyNumber: '+2250707123456',
      ),
    ).called(1);
  });

  test(
    'a salon that never chose and saves with deposits off stores 30 %',
    () async {
      // The intended consequence of decisions 1 + 2 — no effect on bookings,
      // which read the percentage only when a deposit is required.
      stubLoad(
        const DepositPolicy(depositRequired: false, depositPercentage: 0),
      );
      stubSaveOk();

      final provider = ProDepositSettingsProvider();
      await provider.load('p1');
      await provider.save('p1');

      verify(
        () => service.updateDepositPolicy(
          'p1',
          depositRequired: false,
          depositPercentage: 0.30,
          cancellationWindowHours: 24,
        ),
      ).called(1);
    },
  );

  test('save returns false on failure', () async {
    when(
      () => service.updateDepositPolicy(
        any(),
        depositRequired: any(named: 'depositRequired'),
        depositPercentage: any(named: 'depositPercentage'),
        cancellationWindowHours: any(named: 'cancellationWindowHours'),
      ),
    ).thenAnswer((_) async => ApiResponse.error('nope'));

    final provider = ProDepositSettingsProvider();
    final ok = await provider.save('p1');

    expect(ok, isFalse);
    expect(provider.error, 'nope');
  });
}
