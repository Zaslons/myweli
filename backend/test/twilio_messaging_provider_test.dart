import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/messaging/twilio_messaging_provider.dart';
import 'package:test/test.dart';

void main() {
  TwilioMessagingProvider provider(MockClient client) =>
      TwilioMessagingProvider(
        accountSid: 'AC123',
        authToken: 'tok',
        smsFrom: '+15550001111',
        whatsAppFrom: '+15550002222',
        client: client,
      );

  test('SMS: posts To/From/Body with Basic auth, parses sid', () async {
    late http.Request seen;
    final p = provider(
      MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({'sid': 'SM1', 'status': 'queued'}),
          201,
        );
      }),
    );

    final res = await p.send(
      to: '+2250700000000',
      channel: MessageChannel.sms,
      body: 'Bonjour',
    );

    expect(res.ok, isTrue);
    expect(res.providerMessageId, 'SM1');
    expect(seen.url.path, '/2010-04-01/Accounts/AC123/Messages.json');
    expect(
      seen.headers['Authorization'],
      'Basic ${base64Encode(utf8.encode('AC123:tok'))}',
    );
    expect(seen.bodyFields['To'], '+2250700000000');
    expect(seen.bodyFields['From'], '+15550001111');
    expect(seen.bodyFields['Body'], 'Bonjour');
  });

  test('WhatsApp: prefixes To/From with whatsapp:', () async {
    late http.Request seen;
    final p = provider(
      MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'sid': 'WA1'}), 201);
      }),
    );

    final res = await p.send(
      to: '+2250700000000',
      channel: MessageChannel.whatsApp,
      body: 'Salut',
    );

    expect(res.ok, isTrue);
    expect(seen.bodyFields['To'], 'whatsapp:+2250700000000');
    expect(seen.bodyFields['From'], 'whatsapp:+15550002222');
  });

  test(
    'WhatsApp without a sender → not-ok (falls back to SMS), no call',
    () async {
      var called = false;
      final p = TwilioMessagingProvider(
        accountSid: 'AC123',
        authToken: 'tok',
        smsFrom: '+15550001111',
        // whatsAppFrom omitted — SMS-first launch
        client: MockClient((req) async {
          called = true;
          return http.Response('{}', 201);
        }),
      );

      final res = await p.send(
        to: '+2250700000000',
        channel: MessageChannel.whatsApp,
        body: 'Salut',
      );

      expect(res.ok, isFalse);
      expect(res.error, 'whatsapp_not_configured');
      expect(
        called,
        isFalse,
        reason: 'no network call when WhatsApp unconfigured',
      );
    },
  );

  test('SMS still works when no WhatsApp sender is configured', () async {
    final p = TwilioMessagingProvider(
      accountSid: 'AC123',
      authToken: 'tok',
      smsFrom: '+15550001111',
      client: MockClient(
        (req) async => http.Response(jsonEncode({'sid': 'SM2'}), 201),
      ),
    );
    final res = await p.send(
      to: '+2250700000000',
      channel: MessageChannel.sms,
      body: 'Bonjour',
    );
    expect(res.ok, isTrue);
    expect(res.providerMessageId, 'SM2');
  });

  test('non-2xx → failed with a coded error', () async {
    final p = provider(
      MockClient(
        (req) async => http.Response(jsonEncode({'code': 21211}), 400),
      ),
    );
    final res = await p.send(
      to: '+2250700000000',
      channel: MessageChannel.sms,
      body: 'x',
    );
    expect(res.ok, isFalse);
    expect(res.error, 'twilio_400');
  });
}
