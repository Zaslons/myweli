import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/message_templates.dart';
import 'package:myweli/models/messaging.dart';
import 'package:myweli/providers/messaging_provider.dart';
import 'package:myweli/services/mock/mock_messaging_service.dart';

void main() {
  group('renderTemplate', () {
    test('booking confirmation substitutes its params', () {
      final body = renderTemplate(MessageTemplate.bookingConfirmed, const {
        'provider': 'Beauté Divine',
        'date': '23 juin',
        'time': '10:00',
        'deposit': '6 000 FCFA',
      });
      expect(body, contains('Beauté Divine'));
      expect(body, contains('23 juin'));
      expect(body, contains('6 000 FCFA'));
    });

    test('missing params render as empty, not an error', () {
      expect(() => renderTemplate(MessageTemplate.reminder24h, const {}),
          returnsNormally);
    });
  });

  group('MockMessagingService', () {
    late MockMessagingService service;
    setUp(() => service = MockMessagingService());

    test('sends over WhatsApp and records to the outbox', () async {
      final res = await service.send(
        recipientPhone: '+2250701020305',
        template: MessageTemplate.bookingConfirmed,
        params: const {'provider': 'Salon X'},
      );
      expect(res.success, isTrue);
      expect(res.data!.channel, MessageChannel.whatsApp);
      expect(res.data!.status, DeliveryStatus.delivered);
      expect(res.data!.body, contains('Salon X'));

      final outbox = await service.getOutbox();
      expect(outbox.data, hasLength(1));
    });

    test('falls back to SMS when WhatsApp is unavailable', () async {
      final res = await service.send(
        recipientPhone: '+2250000000000', // ends in 0 → no WhatsApp
        template: MessageTemplate.bookingConfirmed,
      );
      expect(res.data!.channel, MessageChannel.sms);
    });

    test('rejects an empty recipient', () async {
      final res = await service.send(
        recipientPhone: '   ',
        template: MessageTemplate.bookingConfirmed,
      );
      expect(res.success, isFalse);
    });

    test('blocks promotional messages to opted-out recipients', () async {
      const phone = '+2250701020301';
      service.setOptedOut(phone, true);

      final promo = await service.send(
        recipientPhone: phone,
        template: MessageTemplate.rebookReminder,
      );
      expect(promo.success, isFalse);

      // Transactional still goes through despite the opt-out.
      final txn = await service.send(
        recipientPhone: phone,
        template: MessageTemplate.bookingConfirmed,
      );
      expect(txn.success, isTrue);
    });
  });

  group('MessagingProvider', () {
    setUpAll(() async {
      await initializeDateFormatting('fr_FR', null);
      serviceLocator.messagingService = MockMessagingService();
    });

    test('sendBookingConfirmation adds a confirmation to the outbox', () async {
      final provider = MessagingProvider();
      await provider.sendBookingConfirmation(
        recipientPhone: '+2250701020305',
        providerName: 'Beauté Divine',
        dateTime: DateTime(2026, 6, 23, 10),
        depositAmount: 6000,
      );
      expect(provider.outbox, isNotEmpty);
      expect(provider.outbox.last.template, MessageTemplate.bookingConfirmed);
    });
  });
}
