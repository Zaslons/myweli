import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/resend_email_provider.dart';
import 'package:test/test.dart';

void main() {
  ResendEmailProvider provider(MockClient client) => ResendEmailProvider(
    apiKey: 'key_123',
    from: 'MyWeli <no-reply@myweli.com>',
    baseUrl: 'https://api.example.test',
    client: client,
  );

  test('posts /emails with bearer auth, text + html alternative', () async {
    late http.Request seen;
    final p = provider(
      MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'id': 'em_1'}), 200);
      }),
    );

    final res = await p.send(
      to: 'ama@x.com',
      subject: otpEmailSubject,
      text: renderOtpEmailText('123456'),
      html: renderOtpEmailHtml('123456'),
    );

    expect(res.ok, isTrue);
    expect(res.providerMessageId, 'em_1');
    expect(seen.url.path, '/emails');
    expect(seen.headers['Authorization'], 'Bearer key_123');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['from'], 'MyWeli <no-reply@myweli.com>');
    expect(body['to'], ['ama@x.com']);
    expect(body['text'], contains('123456'));
    expect(body['html'], contains('123456'));
    expect(body['html'], contains('myweli_lockup_horizontal_black.png'));
  });

  test('html omitted when not provided', () async {
    late http.Request seen;
    final p = provider(
      MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'id': 'em_2'}), 200);
      }),
    );
    await p.send(to: 'a@x.com', subject: 's', text: 't');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body.containsKey('html'), isFalse);
  });

  test('non-2xx → coded error; network failure → unreachable', () async {
    final bad = provider(
      MockClient((req) async => http.Response('{"message":"nope"}', 401)),
    );
    expect(
      (await bad.send(to: 'a@x.com', subject: 's', text: 't')).error,
      'resend_401',
    );

    final down = provider(MockClient((req) async => throw Exception('down')));
    final res = await down.send(to: 'a@x.com', subject: 's', text: 't');
    expect(res.ok, isFalse);
    expect(res.error, 'resend_unreachable');
  });
}
