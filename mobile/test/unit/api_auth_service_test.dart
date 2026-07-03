import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

const _phone = '+2250707010101';

Map<String, dynamic> _providerJson() => {
      'id': 'provider_1',
      'phoneNumber': _phone,
      'name': null,
      'businessName': 'Élégance',
      'businessType': 'salon',
      'email': null,
      'address': null,
      'verificationStatus': 'pending',
      'rejectionReason': null,
      'kycDocs': const <Map<String, dynamic>>[],
      'createdAt': DateTime(2026).toIso8601String(),
      'providerId': 'provider1',
    };

Map<String, dynamic> _userJson() => {
      'id': 'user_1',
      'phoneNumber': _phone,
      'name': null,
      'email': null,
      'avatarUrl': null,
      'createdAt': DateTime(2026).toIso8601String(),
    };

http.Response _verifyOk() => http.Response(
      jsonEncode({
        'tokens': {
          'accessToken': 'access-123',
          'refreshToken': 'refresh-123',
          'expiresAt': DateTime(2026).toIso8601String(),
        },
        'user': _userJson(),
      }),
      200,
    );

void main() {
  test('sendOtp returns the dev code on 202', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/auth/otp/request');
      return http.Response(
          jsonEncode({'expiresInSeconds': 300, 'devCode': '123456'}), 202);
    });
    final service = ApiAuthService(client: client, baseUrl: 'http://x');

    final res = await service.sendOtp(_phone);

    expect(res.success, isTrue);
    expect(res.data, '123456');
  });

  test('verifyOtp stores the session and exposes the user', () async {
    final client = MockClient((req) async => _verifyOk());
    final service = ApiAuthService(
      client: client,
      baseUrl: 'http://x',
      sessionStore: InMemorySessionStore(),
    );

    final res = await service.verifyOtp(_phone, '123456');

    expect(res.success, isTrue);
    expect(res.data!.id, 'user_1');
    expect((await service.getCurrentUser())!.id, 'user_1');
  });

  test('verifyOtp surfaces the backend error code unchanged', () async {
    final client = MockClient(
      (req) async => http.Response(jsonEncode({'error': 'otp_invalid'}), 400),
    );
    final service = ApiAuthService(client: client, baseUrl: 'http://x');

    final res = await service.verifyOtp(_phone, '000000');

    expect(res.success, isFalse);
    expect(res.code, 'otp_invalid');
  });

  test('updateUser PATCHes /me with the bearer token', () async {
    String? authHeader;
    final client = MockClient((req) async {
      if (req.url.path == '/auth/otp/verify') return _verifyOk();
      // /me PATCH
      authHeader = req.headers['Authorization'] ?? req.headers['authorization'];
      final updated = _userJson()..['name'] = 'Awa';
      return http.Response(jsonEncode(updated), 200);
    });
    final service = ApiAuthService(client: client, baseUrl: 'http://x');
    await service.verifyOtp(_phone, '123456');

    final res = await service.updateUser(name: 'Awa');

    expect(res.success, isTrue);
    expect(res.data!.name, 'Awa');
    expect(authHeader, 'Bearer access-123');
  });

  test('verifyOtp persists the refresh token for later silent refresh',
      () async {
    final store = InMemorySessionStore();
    final client = MockClient((req) async => _verifyOk());
    final service = ApiAuthService(
        client: client, baseUrl: 'http://x', sessionStore: store);

    await service.verifyOtp(_phone, '123456');

    final stored = jsonDecode((await store.read())!) as Map<String, dynamic>;
    expect(stored['token'], 'access-123');
    expect(stored['refreshToken'], 'refresh-123');
  });

  test('updateUser silently refreshes on a 401, then retries and rotates',
      () async {
    final store = InMemorySessionStore();
    var refreshed = false;
    final client = MockClient((req) async {
      if (req.url.path == '/auth/otp/verify') return _verifyOk();
      if (req.url.path == '/auth/refresh') {
        refreshed = true;
        return http.Response(
          jsonEncode({
            'accessToken': 'access-456',
            'refreshToken': 'refresh-456',
            'expiresAt': DateTime(2030).toIso8601String(),
          }),
          200,
        );
      }
      // /me PATCH: reject the stale token once, accept the refreshed one.
      final auth = req.headers['Authorization'] ?? req.headers['authorization'];
      if (auth == 'Bearer access-456') {
        return http.Response(jsonEncode(_userJson()..['name'] = 'Awa'), 200);
      }
      return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
    });
    final service = ApiAuthService(
        client: client, baseUrl: 'http://x', sessionStore: store);
    await service.verifyOtp(_phone, '123456');

    final res = await service.updateUser(name: 'Awa');

    expect(res.success, isTrue);
    expect(res.data!.name, 'Awa');
    expect(refreshed, isTrue);
    final stored = jsonDecode((await store.read())!) as Map<String, dynamic>;
    expect(stored['token'], 'access-456'); // rotated
    expect(stored['refreshToken'], 'refresh-456');
    expect((stored['user'] as Map)['name'], 'Awa'); // profile update kept
  });

  test('a transport failure becomes a friendly error', () async {
    final client = MockClient((req) async => throw Exception('down'));
    final service = ApiAuthService(client: client, baseUrl: 'http://x');

    final res = await service.sendOtp(_phone);

    expect(res.success, isFalse);
    expect(res.error, isNotNull);
  });

  test('sendOtpToProvider hits the provider OTP route, returns the dev code',
      () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/auth/provider/otp/request');
      return http.Response(
          jsonEncode({'expiresInSeconds': 300, 'devCode': '654321'}), 202);
    });
    final service = ApiAuthService(client: client, baseUrl: 'http://x');

    final res = await service.sendOtpToProvider(_phone);

    expect(res.success, isTrue);
    expect(res.data, '654321');
  });

  test(
      'registerProviderWithEmail POSTs identity + business fields and '
      'signs in immediately (auth overhaul P4)', () async {
    final store = InMemorySessionStore();
    final client = MockClient((req) async {
      expect(req.url.path, '/auth/provider/register');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['businessType'], 'salon');
      expect(body['email'], 'salon@x.com');
      expect(body['code'], '123456');
      return http.Response(
        jsonEncode({
          'provider': _providerJson(),
          'accessToken': 'prov-reg-123',
          'refreshToken': 'prov-reg-refresh',
          'expiresAt': DateTime(2030).toIso8601String(),
        }),
        201,
      );
    });
    final service = ApiAuthService(
      client: client,
      baseUrl: 'http://x',
      providerSessionStore: store,
    );

    final res = await service.registerProviderWithEmail(
      email: 'salon@x.com',
      code: '123456',
      phoneNumber: _phone,
      businessName: 'Élégance',
      businessType: BusinessType.salon,
    );

    expect(res.success, isTrue);
    expect(res.data!.id, 'provider_1');
    // Registration NOW signs in (one submit) — the session is persisted.
    expect(await store.read(), isNotNull);
    expect((await service.getCurrentProvider())!.id, 'provider_1');
  });

  test('verifyOtpForProvider persists the provider session and restores it',
      () async {
    final store = InMemorySessionStore();
    final client = MockClient((req) async {
      expect(req.url.path, '/auth/provider/otp/verify');
      return http.Response(
        jsonEncode({
          'provider': _providerJson(),
          'accessToken': 'prov-123',
          'refreshToken': 'prov-refresh-123',
          'expiresAt': DateTime(2030).toIso8601String(),
        }),
        200,
      );
    });
    final service = ApiAuthService(
      client: client,
      baseUrl: 'http://x',
      providerSessionStore: store,
    );

    final res = await service.verifyOtpForProvider(_phone, '123456');

    expect(res.success, isTrue);
    expect(res.data!.id, 'provider_1');
    // Persisted under the provider store (incl. the refresh token for silent
    // refresh), and restorable after a cold start.
    final stored = jsonDecode((await store.read())!) as Map<String, dynamic>;
    expect(stored['token'], 'prov-123');
    expect(stored['refreshToken'], 'prov-refresh-123');
    final restored =
        await ApiAuthService(baseUrl: 'http://x', providerSessionStore: store)
            .getCurrentProvider();
    expect(restored!.id, 'provider_1');
  });

  test('verifyOtpForProvider surfaces provider_not_found', () async {
    final client = MockClient(
      (req) async =>
          http.Response(jsonEncode({'error': 'provider_not_found'}), 404),
    );
    final service = ApiAuthService(client: client, baseUrl: 'http://x');

    final res = await service.verifyOtpForProvider(_phone, '000000');

    expect(res.success, isFalse);
    expect(res.code, 'provider_not_found');
  });

  test('logoutProvider clears the persisted provider session', () async {
    final store = InMemorySessionStore();
    final client = MockClient(
      (req) async => http.Response(
        jsonEncode({'provider': _providerJson(), 'accessToken': 'prov-123'}),
        200,
      ),
    );
    final service = ApiAuthService(
      client: client,
      baseUrl: 'http://x',
      providerSessionStore: store,
    );
    await service.verifyOtpForProvider(_phone, '123456');

    await service.logoutProvider();

    expect(await store.read(), isNull);
    expect(await service.getCurrentProvider(), isNull);
  });
}
