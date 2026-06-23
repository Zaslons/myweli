import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/mobile_money.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/models/payment.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/services/mock/mock_pro_service.dart';

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
      expect(operatorHasDeepLink(MobileMoneyOperator.wave), isTrue);
      expect(operatorHasDeepLink(MobileMoneyOperator.orangeMoney), isFalse);
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
        depositMobileMoneyOperator: MobileMoneyOperator.wave,
        depositMobileMoneyNumber: '+2250707123456',
      );
      final back = models.Provider.fromJson(p.toJson());
      expect(back.depositMobileMoneyOperator, MobileMoneyOperator.wave);
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

  test('MockProService persists the deposit handle via the policy', () async {
    final service = MockProService();
    await service.updateDepositPolicy(
      'provider1',
      depositRequired: true,
      depositPercentage: 0.3,
      cancellationWindowHours: 24,
      mobileMoneyOperator: MobileMoneyOperator.orangeMoney,
      mobileMoneyNumber: '+2250500000000',
    );
    final policy = (await service.getDepositPolicy('provider1')).data!;
    expect(policy.depositRequired, isTrue);
    expect(policy.mobileMoneyOperator, MobileMoneyOperator.orangeMoney);
    expect(policy.mobileMoneyNumber, '+2250500000000');
  });
}
