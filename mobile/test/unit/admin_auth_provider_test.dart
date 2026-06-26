import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/providers/admin/admin_auth_provider.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

AdminService _svc(int status) => AdminService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'accessToken': 't', 'refreshToken': 'r'}),
          status,
        ),
      ),
      baseUrl: 'http://x',
      store: InMemorySessionStore(),
    );

void main() {
  test('login success → authenticated', () async {
    final p = AdminAuthProvider(service: _svc(200));
    expect(await p.login('a@myweli.ci', 'pw'), isTrue);
    expect(p.isAuthenticated, isTrue);
    expect(p.error, isNull);
  });

  test('bad credentials → error, not authenticated', () async {
    final p = AdminAuthProvider(service: _svc(401));
    expect(await p.login('a@myweli.ci', 'wrong'), isFalse);
    expect(p.isAuthenticated, isFalse);
    expect(p.error, isNotNull);
  });

  test('logout clears the session', () async {
    final p = AdminAuthProvider(service: _svc(200));
    await p.login('a@myweli.ci', 'pw');
    await p.logout();
    expect(p.isAuthenticated, isFalse);
  });
}
