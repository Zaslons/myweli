import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

const _phone = '+2250707010101';

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

  test('a transport failure becomes a friendly error', () async {
    final client = MockClient((req) async => throw Exception('down'));
    final service = ApiAuthService(client: client, baseUrl: 'http://x');

    final res = await service.sendOtp(_phone);

    expect(res.success, isFalse);
    expect(res.error, isNotNull);
  });

  test('provider auth is delegated (no backend slice yet)', () async {
    // No HTTP should be hit for provider OTP — it goes to the mock fallback.
    final client =
        MockClient((req) async => throw Exception('should not call'));
    final service = ApiAuthService(client: client, baseUrl: 'http://x');

    final res = await service.sendOtpToProvider(_phone);

    expect(res.success, isTrue);
  });
}
