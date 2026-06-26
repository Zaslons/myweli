import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

void main() {
  test('login posts creds + stores session; data calls carry the bearer',
      () async {
    final store = InMemorySessionStore();
    final client = MockClient((req) async {
      if (req.url.path == '/admin/auth/login') {
        expect((jsonDecode(req.body) as Map)['email'], 'a@myweli.ci');
        return http.Response(
          jsonEncode({'accessToken': 'tok', 'refreshToken': 'r'}),
          200,
        );
      }
      if (req.url.path == '/admin/analytics/overview') {
        expect(req.headers['Authorization'], 'Bearer tok');
        return http.Response(
          jsonEncode({
            'bookings': {'total': 3},
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final svc = AdminService(client: client, baseUrl: 'http://x', store: store);

    final login = await svc.login('a@myweli.ci', 'pw');
    expect(login.success, isTrue);
    expect(await svc.hasSession(), isTrue);

    final ov = await svc.overview();
    expect(ov.success, isTrue);
    expect((ov.data!['bookings'] as Map)['total'], 3);
  });

  test('login surfaces locked_out (429) and invalid creds (401)', () async {
    final locked = AdminService(
      client: MockClient((_) async => http.Response('{}', 429)),
      baseUrl: 'http://x',
      store: InMemorySessionStore(),
    );
    expect((await locked.login('a', 'b')).code, 'locked_out');

    final bad = AdminService(
      client: MockClient((_) async => http.Response('{}', 401)),
      baseUrl: 'http://x',
      store: InMemorySessionStore(),
    );
    final res = await bad.login('a', 'b');
    expect(res.success, isFalse);
    expect(res.code, 'invalid_credentials');
  });

  test('rejectKyc posts the reason to the right path', () async {
    final store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 'tok', 'refreshToken': 'r'}));
    final client = MockClient((req) async {
      expect(req.url.path, '/admin/kyc/acc1/reject');
      expect((jsonDecode(req.body) as Map)['reason'], 'flou');
      return http.Response(jsonEncode({'verificationStatus': 'rejected'}), 200);
    });
    final svc = AdminService(client: client, baseUrl: 'http://x', store: store);
    final res = await svc.rejectKyc('acc1', 'flou');
    expect(res.success, isTrue);
    expect(res.data!['verificationStatus'], 'rejected');
  });
}
