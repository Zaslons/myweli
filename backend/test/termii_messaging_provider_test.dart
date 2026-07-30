import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli_backend/src/messaging/messaging_models.dart';
import 'package:myweli_backend/src/messaging/termii_messaging_provider.dart';
import 'package:test/test.dart';

void main() {
  TermiiMessagingProvider provider(MockClient client) =>
      TermiiMessagingProvider(
        apiKey: 'key_123',
        senderId: 'Myweli',
        baseUrl: 'https://api.example.test',
        client: client,
      );

  test('SMS: JSON-posts /api/sms/send, strips +, parses message_id', () async {
    late http.Request seen;
    final p = provider(
      MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({'message_id': 'MSG1', 'message': 'Successfully Sent.'}),
          200,
        );
      }),
    );

    final res = await p.send(
      to: '+2250700000000',
      channel: MessageChannel.sms,
      body: 'Votre code Myweli : 123456',
    );

    expect(res.ok, isTrue);
    expect(res.providerMessageId, 'MSG1');
    expect(seen.url.path, '/api/sms/send');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['to'], '2250700000000'); // '+' stripped for Termii
    expect(body['from'], 'Myweli');
    expect(body['sms'], 'Votre code Myweli : 123456');
    expect(body['type'], 'plain');
    expect(body['channel'], 'generic');
    expect(body['api_key'], 'key_123');
  });

  test('WhatsApp → not-ok (falls back to SMS), no network call', () async {
    var called = false;
    final p = provider(
      MockClient((req) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    final res = await p.send(
      to: '+2250700000000',
      channel: MessageChannel.whatsApp,
      body: 'x',
    );

    expect(res.ok, isFalse);
    expect(res.error, 'whatsapp_not_configured');
    expect(called, isFalse, reason: 'no call when WhatsApp unconfigured');
  });

  test('2xx without message_id → rejected', () async {
    final p = provider(
      MockClient(
        (req) async =>
            http.Response(jsonEncode({'code': 'insufficient_balance'}), 200),
      ),
    );
    final res = await p.send(
      to: '+2250700000000',
      channel: MessageChannel.sms,
      body: 'x',
    );
    expect(res.ok, isFalse);
    expect(res.error, 'termii_rejected');
  });

  test('non-2xx → failed with a coded error', () async {
    final p = provider(
      MockClient(
        (req) async =>
            http.Response(jsonEncode({'message': 'Invalid API Key'}), 401),
      ),
    );
    final res = await p.send(
      to: '+2250700000000',
      channel: MessageChannel.sms,
      body: 'x',
    );
    expect(res.ok, isFalse);
    expect(res.error, 'termii_401');
  });

  test('network failure → unreachable, never throws', () async {
    final p = provider(MockClient((req) async => throw Exception('down')));
    final res = await p.send(
      to: '+2250700000000',
      channel: MessageChannel.sms,
      body: 'x',
    );
    expect(res.ok, isFalse);
    expect(res.error, 'termii_unreachable');
  });

  test('custom route is forwarded as the Termii channel', () async {
    late http.Request seen;
    final p = TermiiMessagingProvider(
      apiKey: 'k',
      senderId: 'S',
      baseUrl: 'https://api.example.test',
      route: 'dnd',
      client: MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'message_id': 'M'}), 200);
      }),
    );
    await p.send(to: '+2250700000000', channel: MessageChannel.sms, body: 'x');
    expect((jsonDecode(seen.body) as Map<String, dynamic>)['channel'], 'dnd');
  });
}
