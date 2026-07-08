import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/clients_repository.dart';
import 'package:myweli_backend/src/clients/clients_service.dart';
import 'package:myweli_backend/src/clients/provider_audit_log.dart';
import 'package:test/test.dart';

import '../routes/me/index.dart' as me_route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockAuth extends Mock implements AuthRepository {}

/// A real ClientsService over empty in-memory repos — `DELETE /me` calls its
/// [ClientsService.anonymizeUser] (module `clients` T48).
ClientsService _clientsService(TokenService tokens, AuthRepository auth) =>
    ClientsService(
      InMemoryProviderAuthRepository(tokens: tokens, isProd: false),
      auth,
      InMemoryClientsRepository(),
      InMemoryAppointmentRepository(),
      InMemoryProviderAuditLogRepository(),
    );

void main() {
  group('routes /me GET', () {
    final tokens = TokenService(secret: 'test-secret');
    late _MockAuth auth;

    setUp(() {
      auth = _MockAuth();
      when(() => auth.userById('u1')).thenAnswer(
        (_) async => AuthUser(
          id: 'u1',
          phoneNumber: '+2250700000001',
          name: 'Awa',
          createdAt: DateTime.utc(2026),
        ),
      );
    });

    RequestContext ctx(Request request) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      when(() => c.read<AuthRepository>()).thenReturn(auth);
      when(
        () => c.read<ClientsService>(),
      ).thenReturn(_clientsService(tokens, auth));
      return c;
    }

    Request req(String method, {String? token}) => Request(
      method,
      Uri.parse('http://localhost/me'),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    );

    String tok(String sub) =>
        tokens.issueAccessToken(subject: sub, role: 'user').token;

    test('GET returns the signed-in profile', () async {
      final res = await me_route.onRequest(ctx(req('GET', token: tok('u1'))));
      expect(res.statusCode, HttpStatus.ok);
      final m = await res.json() as Map;
      expect(m['id'], 'u1');
      expect(m['name'], 'Awa');
      expect(m['phoneNumber'], '+2250700000001');
    });

    test('anonymous → 401', () async {
      final res = await me_route.onRequest(ctx(req('GET')));
      expect(res.statusCode, HttpStatus.unauthorized);
    });

    test('unknown user → 404', () async {
      when(() => auth.userById('ghost')).thenAnswer((_) async => null);
      final res = await me_route.onRequest(
        ctx(req('GET', token: tok('ghost'))),
      );
      expect(res.statusCode, HttpStatus.notFound);
    });

    test('unsupported verb → 405', () async {
      final res = await me_route.onRequest(ctx(req('PUT', token: tok('u1'))));
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
