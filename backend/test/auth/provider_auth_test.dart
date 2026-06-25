import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:test/test.dart';

import '../../routes/auth/provider/otp/request.dart' as p_request;
import '../../routes/auth/provider/otp/verify.dart' as p_verify;
import '../../routes/auth/provider/refresh.dart' as p_refresh;
import '../../routes/auth/provider/register.dart' as p_register;

class _MockRequestContext extends Mock implements RequestContext {}

const _phone = '+2250544556677';

void main() {
  TokenService ts() => TokenService(secret: 'test-secret');

  group('InMemoryProviderAuthRepository', () {
    test(
      'register creates the account + sends a code; duplicate is rejected',
      () async {
        final repo = InMemoryProviderAuthRepository(
          tokens: ts(),
          isProd: false,
        );
        final reg = await repo.register(
          phoneNumber: _phone,
          businessName: 'Élégance',
          businessType: 'salon',
        );
        expect(reg.ok, isTrue);
        expect(reg.provider!.businessName, 'Élégance');
        expect(reg.devCode, isNotNull);

        final dup = await repo.register(
          phoneNumber: _phone,
          businessName: 'Other',
          businessType: 'barber',
        );
        expect(dup.ok, isFalse);
        expect(dup.error, 'provider_exists');
      },
    );

    test(
      'verify requires registration, then returns a provider-role token',
      () async {
        final tokens = ts();
        final repo = InMemoryProviderAuthRepository(
          tokens: tokens,
          isProd: false,
        );

        // Not registered: a code can be issued, but verify rejects it.
        final pre = await repo.requestOtp(_phone);
        final none = await repo.verifyOtp(_phone, pre.devCode!);
        expect(none.error, 'provider_not_found');

        final reg = await repo.register(
          phoneNumber: _phone,
          businessName: 'Élégance',
          businessType: 'salon',
        );
        final ok = await repo.verifyOtp(_phone, reg.devCode!);
        expect(ok.ok, isTrue);
        expect(ok.provider!.phoneNumber, _phone);
        final jwt = tokens.verifyAccessToken(ok.tokens!.accessToken);
        expect(jwt!.payload, containsPair('role', 'provider'));
        expect(ok.tokens!.refreshToken, isNotEmpty);
      },
    );

    test(
      'refresh rotates; replaying a rotated token revokes the family',
      () async {
        final repo = InMemoryProviderAuthRepository(
          tokens: ts(),
          isProd: false,
        );
        final reg = await repo.register(
          phoneNumber: _phone,
          businessName: 'Élégance',
          businessType: 'salon',
        );
        final first = (await repo.verifyOtp(_phone, reg.devCode!)).tokens!;

        final rotated = await repo.refresh(first.refreshToken);
        expect(rotated.ok, isTrue);
        expect(rotated.tokens!.refreshToken, isNot(first.refreshToken));

        // Replaying the now-rotated first token is theft → family revoked.
        final reuse = await repo.refresh(first.refreshToken);
        expect(reuse.error, 'refresh_reused');
        // The token handed out by the rotation is revoked along with the family.
        expect(
          (await repo.refresh(rotated.tokens!.refreshToken)).error,
          'refresh_invalid',
        );
      },
    );

    test('an unknown refresh token → refresh_invalid', () async {
      final repo = InMemoryProviderAuthRepository(tokens: ts(), isProd: false);
      expect((await repo.refresh('nope')).error, 'refresh_invalid');
    });

    test('wrong code decrements then locks out', () async {
      final repo = InMemoryProviderAuthRepository(
        tokens: ts(),
        isProd: false,
        maxAttempts: 2,
      );
      final reg = await repo.register(
        phoneNumber: _phone,
        businessName: 'X',
        businessType: 'salon',
      );
      final wrong = reg.devCode == '111111' ? '222222' : '111111';
      expect((await repo.verifyOtp(_phone, wrong)).error, 'otp_invalid');
      expect((await repo.verifyOtp(_phone, wrong)).error, 'otp_locked');
    });

    test('resend budget is enforced', () async {
      final repo = InMemoryProviderAuthRepository(
        tokens: ts(),
        isProd: false,
        maxResends: 1,
      );
      await repo.register(
        phoneNumber: _phone,
        businessName: 'X',
        businessType: 'salon',
      );
      // register issued one; the budget allows maxResends more requests.
      expect((await repo.requestOtp(_phone)).ok, isTrue);
      expect((await repo.requestOtp(_phone)).error, 'otp_resend_limit');
    });
  });

  group('routes', () {
    late InMemoryProviderAuthRepository repo;
    setUp(
      () => repo = InMemoryProviderAuthRepository(tokens: ts(), isProd: false),
    );

    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<ProviderAuthRepository>()).thenReturn(repo);
      return context;
    }

    Request post(String path, Object body) => Request.post(
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
    );

    Future<Map<String, dynamic>> jsonOf(Response r) async =>
        await r.json() as Map<String, dynamic>;

    test('register → 201 + provider + devCode; duplicate → 409', () async {
      final res = await p_register.onRequest(
        ctx(
          post('/auth/provider/register', {
            'phoneNumber': _phone,
            'businessName': 'Élégance',
            'businessType': 'salon',
          }),
        ),
      );
      expect(res.statusCode, HttpStatus.created);
      final body = await jsonOf(res);
      expect((body['provider'] as Map)['businessName'], 'Élégance');
      expect(body['devCode'], isNotNull);

      final dup = await p_register.onRequest(
        ctx(
          post('/auth/provider/register', {
            'phoneNumber': _phone,
            'businessName': 'Élégance',
            'businessType': 'salon',
          }),
        ),
      );
      expect(dup.statusCode, HttpStatus.conflict);
    });

    test('register rejects an unknown business type with 400', () async {
      final res = await p_register.onRequest(
        ctx(
          post('/auth/provider/register', {
            'phoneNumber': _phone,
            'businessName': 'X',
            'businessType': 'not_a_type',
          }),
        ),
      );
      expect(res.statusCode, HttpStatus.badRequest);
    });

    test('verify → 200 provider + token; not registered → 404', () async {
      final reg = await repo.register(
        phoneNumber: _phone,
        businessName: 'Élégance',
        businessType: 'salon',
      );
      final ok = await p_verify.onRequest(
        ctx(
          post('/auth/provider/otp/verify', {
            'phoneNumber': _phone,
            'code': reg.devCode,
          }),
        ),
      );
      expect(ok.statusCode, HttpStatus.ok);
      final okBody = await jsonOf(ok);
      expect(okBody['accessToken'], isNotEmpty);
      expect(okBody['refreshToken'], isNotEmpty);
      expect(okBody['expiresAt'], isNotNull);

      // Unregistered phone: a code can be requested, but verify → 404.
      const other = '+2250700000000';
      final otp = await repo.requestOtp(other);
      final missing = await p_verify.onRequest(
        ctx(
          post('/auth/provider/otp/verify', {
            'phoneNumber': other,
            'code': otp.devCode,
          }),
        ),
      );
      expect(missing.statusCode, HttpStatus.notFound);
    });

    test(
      'refresh: rotates → 200; replay → 401; bad body → 400; GET → 405',
      () async {
        await repo.register(
          phoneNumber: _phone,
          businessName: 'Élégance',
          businessType: 'salon',
        );
        final reg = await repo.requestOtp(_phone);
        final first = (await repo.verifyOtp(_phone, reg.devCode!)).tokens!;

        final rotated = await p_refresh.onRequest(
          ctx(
            post('/auth/provider/refresh', {
              'refreshToken': first.refreshToken,
            }),
          ),
        );
        expect(rotated.statusCode, HttpStatus.ok);
        expect((await jsonOf(rotated))['refreshToken'], isNotEmpty);

        final reuse = await p_refresh.onRequest(
          ctx(
            post('/auth/provider/refresh', {
              'refreshToken': first.refreshToken,
            }),
          ),
        );
        expect(reuse.statusCode, HttpStatus.unauthorized);
        expect((await jsonOf(reuse))['error'], 'refresh_reused');

        final bad = await p_refresh.onRequest(
          ctx(post('/auth/provider/refresh', {'refreshToken': ''})),
        );
        expect(bad.statusCode, HttpStatus.badRequest);

        final wrongVerb = await p_refresh.onRequest(
          ctx(Request.get(Uri.parse('http://localhost/auth/provider/refresh'))),
        );
        expect(wrongVerb.statusCode, HttpStatus.methodNotAllowed);
      },
    );

    test('non-POST request → 405', () async {
      final res = await p_request.onRequest(
        ctx(
          Request.get(Uri.parse('http://localhost/auth/provider/otp/request')),
        ),
      );
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
