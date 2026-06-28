import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_device_registration_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

void main() {
  late InMemorySessionStore store;

  setUp(() async {
    store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
  });

  ApiDeviceRegistrationService svc(MockClient c) =>
      ApiDeviceRegistrationService(
        client: c,
        baseUrl: 'http://x',
        sessionStore: store,
      );

  test('register POSTs /me/devices with bearer + token + platform', () async {
    String? method;
    String? auth;
    Map<String, dynamic>? sent;
    final s = svc(MockClient((req) async {
      method = req.method;
      auth = req.headers['Authorization'];
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      expect(req.url.path, '/me/devices');
      return http.Response('{}', 200);
    }));
    final res = await s.register('fcm-123', 'android');
    expect(res.success, isTrue);
    expect(method, 'POST');
    expect(auth, 'Bearer t');
    expect(sent, {'token': 'fcm-123', 'platform': 'android'});
  });

  test('unregister DELETEs /me/devices with the token', () async {
    String? method;
    Map<String, dynamic>? sent;
    final s = svc(MockClient((req) async {
      method = req.method;
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      expect(req.url.path, '/me/devices');
      return http.Response('{}', 200);
    }));
    final res = await s.unregister('fcm-123');
    expect(res.success, isTrue);
    expect(method, 'DELETE');
    expect(sent, {'token': 'fcm-123'});
  });

  test('not connected → error (no token)', () async {
    final s = ApiDeviceRegistrationService(
      client: MockClient((_) async => http.Response('{}', 200)),
      baseUrl: 'http://x',
      sessionStore: InMemorySessionStore(), // empty → no token
    );
    expect((await s.register('x', 'android')).success, isFalse);
    expect((await s.unregister('x')).success, isFalse);
  });
}
