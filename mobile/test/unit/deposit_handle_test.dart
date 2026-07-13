import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/mobile_money.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('waveDeepLink', () {
    test('builds a recipient + amount link from a number', () {
      final uri = waveDeepLink(number: '+225 07 07 12 34 56', amount: 6000);
      expect(uri, isNotNull);
      expect(uri!.queryParameters['recipient'], '2250707123456');
      expect(uri.queryParameters['amount'], '6000');
    });

    test('null for an empty number; only Wave has a deep link', () {
      expect(waveDeepLink(number: '', amount: 6000), isNull);
      // The deep link is driven by the catalog's CLOSED deepLinkKind
      // vocabulary (multi-pays MP2) — only 'wave' today.
      expect(deepLinkKindIsWave('wave'), isTrue);
      expect(deepLinkKindIsWave(null), isFalse);
    });
  });

  group('models carry the deposit handle / proof', () {
    test('Provider round-trips the deposit handle (default off when absent)',
        () {
      const p = models.Provider(
        id: 'p1',
        name: 'Salon',
        description: '',
        address: 'x',
        imageUrls: [],
        rating: 4.0,
        reviewCount: 1,
        services: [],
        availability: Availability(
            providerId: 'p1', weeklySchedule: {}, blockedDates: []),
        phoneNumber: '+22500',
        category: 'salon',
        depositRequired: true,
        depositMobileMoneyOperator: 'wave',
        depositMobileMoneyNumber: '+2250707123456',
      );
      final back = models.Provider.fromJson(p.toJson());
      expect(back.depositMobileMoneyOperator, 'wave');
      expect(back.depositMobileMoneyNumber, '+2250707123456');

      final json = p.toJson()
        ..remove('depositRequired')
        ..remove('depositMobileMoneyOperator');
      final defaulted = models.Provider.fromJson(json);
      expect(defaulted.depositRequired, isFalse);
      expect(defaulted.depositMobileMoneyOperator, isNull);
    });

    test('Appointment round-trips the deposit screenshot URL', () {
      final a = Appointment(
        id: 'a1',
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDate: DateTime(2026, 6, 23, 10),
        status: AppointmentStatus.pending,
        totalPrice: 20000,
        depositAmount: 6000,
        depositScreenshotUrl: 'asset:proof.png',
        createdAt: DateTime(2026),
      );
      expect(Appointment.fromJson(a.toJson()).depositScreenshotUrl,
          'asset:proof.png');
    });
  });

  test('a deposit booking is created pending, with the screenshot attached',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final service = MockAppointmentService();

    final res = await service.bookAppointment(
      providerId: 'provider2',
      serviceIds: const ['service4'],
      appointmentDateTime: DateTime.now().add(const Duration(days: 3)),
      depositAmount: 6000,
      depositScreenshotUrl: 'asset:proof.png',
    );

    expect(res.success, isTrue);
    // Never auto-confirmed on payment — the salon confirms.
    expect(res.data!.status, AppointmentStatus.pending);
    expect(res.data!.depositAmount, 6000);
    expect(res.data!.depositScreenshotUrl, 'asset:proof.png');
  });

  test('MockProService persists the deposit handle via the policy', () async {
    final service = MockProService();
    await service.updateDepositPolicy(
      'provider1',
      depositRequired: true,
      depositPercentage: 0.3,
      cancellationWindowHours: 24,
      mobileMoneyOperator: 'orangeMoney',
      mobileMoneyNumber: '+2250500000000',
    );
    final policy = (await service.getDepositPolicy('provider1')).data!;
    expect(policy.depositRequired, isTrue);
    expect(policy.mobileMoneyOperator, 'orangeMoney');
    expect(policy.mobileMoneyNumber, '+2250500000000');
  });
}
