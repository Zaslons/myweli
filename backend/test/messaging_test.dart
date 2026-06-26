import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/messaging/messaging_outbox_repository.dart';
import 'package:myweli_backend/src/messaging/messaging_prefs_repository.dart';
import 'package:myweli_backend/src/messaging/messaging_provider.dart';
import 'package:myweli_backend/src/messaging/messaging_service.dart';
import 'package:test/test.dart';

class _FakeProvider implements MessagingProvider {
  _FakeProvider({this.failWhatsApp = false, this.failAll = false});
  final bool failWhatsApp;
  final bool failAll;
  final List<({String to, MessageChannel channel, String body})> sent = [];
  var _seq = 0;

  @override
  Future<ProviderSendResult> send({
    required String to,
    required MessageChannel channel,
    required String body,
  }) async {
    sent.add((to: to, channel: channel, body: body));
    if (failAll || (failWhatsApp && channel == MessageChannel.whatsApp)) {
      return (ok: false, providerMessageId: null, error: 'x');
    }
    return (ok: true, providerMessageId: 'p${_seq++}', error: null);
  }
}

void main() {
  late InMemoryMessagingOutboxRepository outbox;
  late InMemoryMessagingPrefsRepository prefs;

  setUp(() {
    outbox = InMemoryMessagingOutboxRepository();
    prefs = InMemoryMessagingPrefsRepository();
  });

  MessagingService svc(MessagingProvider p) =>
      MessagingService(p, outbox, prefs);

  test('transactional message sends + records the outbox row', () async {
    final p = _FakeProvider();
    final row = await svc(p).sendTemplate(
      recipientPhone: '+2250700000000',
      template: MessageTemplate.bookingConfirmed,
      params: {'provider': 'Beauté Divine', 'date': '15/06', 'time': '14:30'},
    );
    expect(row, isNotNull);
    expect(row!['status'], 'sent');
    expect((await outbox.list()).total, 1);
    expect(p.sent.single.body, contains('Beauté Divine'));
  });

  test('promotional is skipped for an opted-out recipient', () async {
    await prefs.setOptedOut('+2250700000000', true);
    final p = _FakeProvider();
    final row = await svc(p).sendTemplate(
      recipientPhone: '+2250700000000',
      template: MessageTemplate.rebookReminder,
      params: {'provider': 'X', 'weeks': '6'},
    );
    expect(row, isNull);
    expect(p.sent, isEmpty);
    expect((await outbox.list()).total, 0);
  });

  test('falls back to SMS when WhatsApp fails', () async {
    final p = _FakeProvider(failWhatsApp: true);
    final row = await svc(p).sendTemplate(
      recipientPhone: '+2250700000000',
      template: MessageTemplate.reminder24h,
      params: {'provider': 'X', 'time': '14:30'},
    );
    expect(row!['status'], 'sent');
    expect(row['channel'], 'sms');
    expect(p.sent.map((s) => s.channel), [
      MessageChannel.whatsApp,
      MessageChannel.sms,
    ]);
  });

  test('a total provider failure records status failed', () async {
    final row = await svc(_FakeProvider(failAll: true)).sendTemplate(
      recipientPhone: '+2250700000000',
      template: MessageTemplate.cancelled,
      params: {'provider': 'X', 'date': '15/06'},
    );
    expect(row!['status'], 'failed');
  });

  test('sendOtp sends over SMS and never persists the code', () async {
    final p = _FakeProvider();
    final ok = await svc(p).sendOtp('+2250700000000', '123456');
    expect(ok, isTrue);
    expect(p.sent.single.channel, MessageChannel.sms);
    expect((await outbox.list()).total, 0); // not in the outbox
  });

  test('mapTwilioStatus maps the webhook vocabulary', () {
    expect(mapTwilioStatus('delivered'), DeliveryStatus.delivered);
    expect(mapTwilioStatus('sent'), DeliveryStatus.sent);
    expect(mapTwilioStatus('undelivered'), DeliveryStatus.failed);
    expect(mapTwilioStatus('queued'), DeliveryStatus.queued);
    expect(mapTwilioStatus('weird'), isNull);
  });

  test('updateStatus advances the outbox row', () async {
    final p = _FakeProvider();
    final row = await svc(p).sendTemplate(
      recipientPhone: '+2250700000000',
      template: MessageTemplate.bookingConfirmed,
      params: const {},
    );
    await svc(p).updateStatus(
      row!['providerMessageId'] as String,
      DeliveryStatus.delivered,
    );
    final stored = (await outbox.list()).items.single;
    expect(stored['status'], 'delivered');
  });
}
