import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/access/team_service.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/clients/provider_audit_log.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:test/test.dart';

import '../../routes/auth/provider/email/otp/request.dart' as pe_request;
import '../../routes/auth/provider/email/otp/verify.dart' as pe_verify;
import '../../routes/auth/provider/google.dart' as p_google;
import '../../routes/auth/provider/otp/request.dart' as p_request;
import '../../routes/auth/provider/refresh.dart' as p_refresh;
import '../../routes/auth/provider/register.dart' as p_register;

class _MockRequestContext extends Mock implements RequestContext {}

class _FakeGoogle extends GoogleIdTokenVerifier {
  _FakeGoogle(this.result) : super(clientIds: const ['test']);
  final IdTokenResult result;
  @override
  Future<IdTokenResult> verify(String token, {String? nonce}) async => result;
}

const IdTokenResult _googleClaims = (
  ok: true,
  error: null,
  sub: 'g-sub-1',
  email: 'salon@x.com',
  emailVerified: true,
  name: 'Awa',
  avatarUrl: null,
);

const _phone = '+2250544556677';

void main() {
  TokenService ts() => TokenService(secret: 'test-secret');

  /// Registers a salon with a Google identity (no OTP needed).
  Future<ProviderVerifyResult> registerGoogle(
    ProviderAuthRepository repo, {
    String email = 'salon@x.com',
    String sub = 'g-sub-1',
    String phone = _phone,
    String? providerId,
  }) => repo.register(
    businessName: 'Élégance',
    businessType: 'salon',
    phoneNumber: phone,
    email: email,
    authProvider: 'google',
    googleSub: sub,
    providerId: providerId,
  );

  group('InMemoryProviderAuthRepository — auth overhaul', () {
    test('register (google identity) creates the salon + a LIVE session; '
        'duplicate identity → provider_exists', () async {
      final repo = InMemoryProviderAuthRepository(tokens: ts(), isProd: false);
      final reg = await registerGoogle(repo);
      expect(reg.ok, isTrue);
      expect(reg.provider!.businessName, 'Élégance');
      expect(reg.provider!.email, 'salon@x.com');
      expect(reg.provider!.authProvider, 'google');
      expect(reg.tokens!.accessToken, isNotEmpty);

      final dupEmail = await registerGoogle(repo, sub: 'other-sub');
      expect(dupEmail.error, 'provider_exists');
      final dupSub = await registerGoogle(repo, email: 'other@x.com');
      expect(dupSub.error, 'provider_exists');
    });

    test('loginWithSocial: by sub → ok; unknown → provider_not_found '
        '(never auto-creates)', () async {
      final repo = InMemoryProviderAuthRepository(tokens: ts(), isProd: false);
      final none = await repo.loginWithSocial(
        provider: 'google',
        sub: 'g-sub-1',
        email: 'salon@x.com',
        emailVerified: true,
      );
      expect(none.error, 'provider_not_found');

      await registerGoogle(repo);
      final ok = await repo.loginWithSocial(provider: 'google', sub: 'g-sub-1');
      expect(ok.ok, isTrue);
      expect(ok.tokens!.accessToken, isNotEmpty);
    });

    test('a VERIFIED email links a new provider sub to the account; an '
        'unverified one never does (T35)', () async {
      final repo = InMemoryProviderAuthRepository(tokens: ts(), isProd: false);
      final reg = await registerGoogle(repo);

      // Apple with the same verified email → linked, same account.
      final apple = await repo.loginWithSocial(
        provider: 'apple',
        sub: 'a-sub-1',
        email: 'Salon@X.com',
        emailVerified: true,
      );
      expect(apple.ok, isTrue);
      expect(apple.provider!.id, reg.provider!.id);

      // Unverified email → no link.
      final bad = await repo.loginWithSocial(
        provider: 'apple',
        sub: 'a-sub-2',
        email: 'salon@x.com',
        emailVerified: false,
      );
      expect(bad.error, 'provider_not_found');
    });

    test('email flow: login-only verify does NOT consume the code on '
        'provider_not_found → the same code registers', () async {
      final repo = InMemoryProviderAuthRepository(tokens: ts(), isProd: false);
      final sent = await repo.requestEmailOtp('new@salon.ci');
      final code = sent.devCode!;

      // No salon yet: correct code → not found, code kept.
      final login = await repo.verifyEmailOtp('new@salon.ci', code);
      expect(login.error, 'provider_not_found');

      // The register screen reuses the SAME code.
      final reg = await repo.register(
        businessName: 'Chez Awa',
        businessType: 'barber',
        phoneNumber: _phone,
        email: 'New@Salon.ci',
        authProvider: 'email',
        emailCode: code,
      );
      expect(reg.ok, isTrue);
      expect(reg.provider!.email, 'new@salon.ci');
      expect(reg.tokens!.refreshToken, isNotEmpty);

      // Registered: a fresh code now logs in.
      final sent2 = await repo.requestEmailOtp('new@salon.ci');
      final again = await repo.verifyEmailOtp('new@salon.ci', sent2.devCode!);
      expect(again.ok, isTrue);
      expect(again.provider!.id, reg.provider!.id);
    });

    test(
      'register with a wrong email code → otp_invalid; lockout works',
      () async {
        final repo = InMemoryProviderAuthRepository(
          tokens: ts(),
          isProd: false,
          maxAttempts: 2,
        );
        final sent = await repo.requestEmailOtp('a@salon.ci');
        final wrong = sent.devCode == '111111' ? '222222' : '111111';
        Future<ProviderVerifyResult> tryReg() => repo.register(
          businessName: 'X',
          businessType: 'salon',
          phoneNumber: _phone,
          email: 'a@salon.ci',
          authProvider: 'email',
          emailCode: wrong,
        );
        expect((await tryReg()).error, 'otp_invalid');
        expect((await tryReg()).error, 'otp_locked');
      },
    );

    test('phone OTP still works at the repo level (dormant path)', () async {
      final repo = InMemoryProviderAuthRepository(tokens: ts(), isProd: false);
      await registerGoogle(repo);
      final otp = await repo.requestOtp(_phone);
      final ok = await repo.verifyOtp(_phone, otp.devCode!);
      expect(ok.ok, isTrue);
      expect(ok.provider!.phoneNumber, _phone);
    });

    test('refresh rotates; replay revokes the family', () async {
      final repo = InMemoryProviderAuthRepository(tokens: ts(), isProd: false);
      final first = (await registerGoogle(repo)).tokens!;

      final rotated = await repo.refresh(first.refreshToken);
      expect(rotated.ok, isTrue);
      expect(rotated.tokens!.refreshToken, isNot(first.refreshToken));

      final reuse = await repo.refresh(first.refreshToken);
      expect(reuse.error, 'refresh_reused');
      expect(
        (await repo.refresh(rotated.tokens!.refreshToken)).error,
        'refresh_invalid',
      );
    });

    test(
      'an expired email code does not count against the resend budget',
      () async {
        final repo = InMemoryProviderAuthRepository(
          tokens: ts(),
          isProd: false,
          otpValidity: Duration.zero,
          maxResends: 1,
        );
        expect((await repo.requestEmailOtp('a@salon.ci')).ok, isTrue);
        expect((await repo.requestEmailOtp('a@salon.ci')).ok, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect((await repo.requestEmailOtp('a@salon.ci')).ok, isTrue);
      },
    );
  });

  group('routes', () {
    late InMemoryProviderAuthRepository repo;
    late InMemoryProvidersRepository salons;
    late AuthMethods methods;
    late GoogleIdTokenVerifier google;
    late EmailProvider email;

    setUp(() {
      repo = InMemoryProviderAuthRepository(tokens: ts(), isProd: false);
      salons = InMemoryProvidersRepository([]);
      methods = const AuthMethods(AuthMethods.defaults);
      google = _FakeGoogle(_googleClaims);
      email = LogEmailProvider();
    });

    RequestContext ctx(Request request) {
      final context = _MockRequestContext();
      when(() => context.request).thenReturn(request);
      when(() => context.read<ProviderAuthRepository>()).thenReturn(repo);
      when(() => context.read<AuthMethods>()).thenReturn(methods);
      when(() => context.read<GoogleIdTokenVerifier>()).thenReturn(google);
      when(() => context.read<EmailProvider>()).thenReturn(email);
      when(() => context.read<SalonProvisioningService>()).thenReturn(
        SalonProvisioningService(salons, repo, InMemoryMembershipRepository()),
      );
      // The R2b login bridge reads TeamService on provider_not_found; an
      // empty membership store keeps the legacy 404 behaviour under test.
      final bridgeMembers = InMemoryMembershipRepository();
      final bridgeResolver = MembershipService(bridgeMembers, repo);
      when(() => context.read<TeamService>()).thenReturn(
        TeamService(
          bridgeMembers,
          bridgeResolver,
          salons,
          SalonSubscriptionService(
            InMemorySalonSubscriptionRepository(),
            bridgeResolver,
            bridgeMembers,
            salons,
            repo,
          ),
          email,
          InMemoryProviderAuditLogRepository(),
        ),
      );
      return context;
    }

    Request post(String path, Object body) => Request.post(
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
    );

    Future<Map<String, dynamic>> jsonOf(Response r) async =>
        await r.json() as Map<String, dynamic>;

    Map<String, Object?> regBody({String? email, String? code}) => {
      'phoneNumber': _phone,
      'businessName': 'Élégance',
      'businessType': 'salon',
      if (email != null) 'email': email,
      if (code != null) 'code': code,
    };

    test(
      'register with a Google identity → 201 FLAT session; duplicate → 409',
      () async {
        final res = await p_register.onRequest(
          ctx(
            post('/auth/provider/register', {...regBody(), 'idToken': 'tok'}),
          ),
        );
        expect(res.statusCode, HttpStatus.created);
        final body = await jsonOf(res);
        expect((body['provider'] as Map)['businessName'], 'Élégance');
        expect(body['accessToken'], isNotEmpty);
        expect(body['refreshToken'], isNotEmpty);

        // Salon lifecycle (pro-salon-lifecycle.md): registration PROVISIONS
        // a linked DRAFT salon — the dashboard works from second one.
        final providerId = (body['provider'] as Map)['providerId'] as String?;
        expect(providerId, isNotNull);
        final salon = await salons.byId(providerId!);
        expect(salon, isNotNull);
        expect(salon!['status'], 'draft');
        expect(salon['name'], 'Élégance');
        // …and drafts are NOT discoverable (T51).
        expect(await salons.query(), isEmpty);

        final dup = await p_register.onRequest(
          ctx(
            post('/auth/provider/register', {...regBody(), 'idToken': 'tok'}),
          ),
        );
        expect(dup.statusCode, HttpStatus.conflict);
      },
    );

    test(
      'register with email+code → 201; wrong code → 400; no identity → 400',
      () async {
        final sent = await repo.requestEmailOtp('new@salon.ci');
        final res = await p_register.onRequest(
          ctx(
            post(
              '/auth/provider/register',
              regBody(email: 'new@salon.ci', code: sent.devCode),
            ),
          ),
        );
        expect(res.statusCode, HttpStatus.created);

        final sent2 = await repo.requestEmailOtp('other@salon.ci');
        expect(sent2.ok, isTrue);
        final wrong = await p_register.onRequest(
          ctx(
            post(
              '/auth/provider/register',
              regBody(email: 'other@salon.ci', code: '000000'),
            ),
          ),
        );
        expect(wrong.statusCode, HttpStatus.badRequest);

        final none = await p_register.onRequest(
          ctx(post('/auth/provider/register', regBody())),
        );
        expect(none.statusCode, HttpStatus.badRequest);
      },
    );

    test('register rejects an unknown business type with 400', () async {
      final res = await p_register.onRequest(
        ctx(
          post('/auth/provider/register', {
            'phoneNumber': _phone,
            'businessName': 'X',
            'businessType': 'not_a_type',
            'idToken': 'tok',
          }),
        ),
      );
      expect(res.statusCode, HttpStatus.badRequest);
    });

    test(
      'provider google login: no salon → 404; after register → 200',
      () async {
        final missing = await p_google.onRequest(
          ctx(post('/auth/provider/google', {'idToken': 'tok'})),
        );
        expect(missing.statusCode, HttpStatus.notFound);
        expect((await jsonOf(missing))['error'], 'provider_not_found');

        await p_register.onRequest(
          ctx(
            post('/auth/provider/register', {...regBody(), 'idToken': 'tok'}),
          ),
        );
        final ok = await p_google.onRequest(
          ctx(post('/auth/provider/google', {'idToken': 'tok'})),
        );
        expect(ok.statusCode, HttpStatus.ok);
        expect((await jsonOf(ok))['accessToken'], isNotEmpty);
      },
    );

    test('provider email OTP routes: 202 devCode → login-only 404 → after '
        'register a fresh code logs in (200)', () async {
      final sent = await pe_request.onRequest(
        ctx(post('/auth/provider/email/otp/request', {'email': 'a@salon.ci'})),
      );
      expect(sent.statusCode, HttpStatus.accepted);
      final code = (await jsonOf(sent))['devCode'] as String;

      final notFound = await pe_verify.onRequest(
        ctx(
          post('/auth/provider/email/otp/verify', {
            'email': 'a@salon.ci',
            'code': code,
          }),
        ),
      );
      expect(notFound.statusCode, HttpStatus.notFound);

      // Same code registers (not consumed by the login attempt).
      final reg = await p_register.onRequest(
        ctx(
          post(
            '/auth/provider/register',
            regBody(email: 'a@salon.ci', code: code),
          ),
        ),
      );
      expect(reg.statusCode, HttpStatus.created);

      final sent2 = await pe_request.onRequest(
        ctx(post('/auth/provider/email/otp/request', {'email': 'a@salon.ci'})),
      );
      final code2 = (await jsonOf(sent2))['devCode'] as String;
      final login = await pe_verify.onRequest(
        ctx(
          post('/auth/provider/email/otp/verify', {
            'email': 'a@salon.ci',
            'code': code2,
          }),
        ),
      );
      expect(login.statusCode, HttpStatus.ok);
      expect((await jsonOf(login))['refreshToken'], isNotEmpty);
    });

    test('AUTH_METHODS gate: no phone → provider otp/request 404; '
        'no google → provider google 404', () async {
      methods = AuthMethods.parse('google,apple,email');
      final gated = await p_request.onRequest(
        ctx(post('/auth/provider/otp/request', {'phoneNumber': _phone})),
      );
      expect(gated.statusCode, HttpStatus.notFound);
      expect((await jsonOf(gated))['error'], 'auth_method_disabled');

      methods = AuthMethods.parse('email');
      final gatedGoogle = await p_google.onRequest(
        ctx(post('/auth/provider/google', {'idToken': 'tok'})),
      );
      expect(gatedGoogle.statusCode, HttpStatus.notFound);
    });

    test(
      'refresh: rotates → 200; replay → 401; bad body → 400; GET → 405',
      () async {
        final reg = await registerGoogle(repo);
        final first = reg.tokens!;

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

  group('deleteAccount (audit 11.5 — T53)', () {
    test(
      'erases every lookup + kills all sessions; unknown id → false',
      () async {
        final repo = InMemoryProviderAuthRepository(
          tokens: ts(),
          isProd: false,
        );
        final reg = await registerGoogle(repo, providerId: 'p1');
        final accountId = reg.provider!.id;
        final refreshToken = reg.tokens!.refreshToken;

        expect(await repo.deleteAccount(accountId), isTrue);

        // Identity gone from every index.
        expect(await repo.accountById(accountId), isNull);
        final relogin = await repo.loginWithSocial(
          provider: 'google',
          sub: 'g-sub-1',
        );
        expect(relogin.error, 'provider_not_found');
        // Sessions dead: the refresh token no longer works.
        final refreshed = await repo.refresh(refreshToken);
        expect(refreshed.ok, isFalse);

        expect(await repo.deleteAccount('nope'), isFalse);
      },
    );
  });
}
