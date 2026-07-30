import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:test/test.dart';

import '../../routes/auth/apple.dart' as apple_route;
import '../../routes/auth/email/otp/request.dart' as email_request;
import '../../routes/auth/email/otp/verify.dart' as email_verify;
import '../../routes/auth/google.dart' as google_route;
import '../../routes/auth/otp/request.dart' as phone_request;

class _MockRequestContext extends Mock implements RequestContext {}

/// Stubbed verifiers — the real verification logic is covered by
/// id_token_verifier_test.dart; routes only need the outcome.
class _FakeGoogle extends GoogleIdTokenVerifier {
  _FakeGoogle(this.result) : super(clientIds: const ['test']);
  final IdTokenResult result;
  @override
  Future<IdTokenResult> verify(String token, {String? nonce}) async => result;
}

class _FakeApple extends AppleIdTokenVerifier {
  _FakeApple(this.result) : super(clientIds: const ['test']);
  final IdTokenResult result;
  String? seenNonce;
  @override
  Future<IdTokenResult> verify(String token, {String? nonce}) async {
    seenNonce = nonce;
    return result;
  }
}

const IdTokenResult _okClaims = (
  ok: true,
  error: null,
  sub: 'sub-1',
  email: 'ama@x.com',
  emailVerified: true,
  name: 'Ama',
  avatarUrl: null,
);

const IdTokenResult _rejected = (
  ok: false,
  error: 'token_rejected',
  sub: null,
  email: null,
  emailVerified: false,
  name: null,
  avatarUrl: null,
);

Uri _u(String path) => Uri.parse('http://localhost$path');

void main() {
  late AuthRepository repo;
  late AuthMethods methods;
  late GoogleIdTokenVerifier google;
  late AppleIdTokenVerifier apple;
  late EmailProvider email;

  setUp(() {
    repo = InMemoryAuthRepository(
      tokens: TokenService(secret: 'test-secret'),
      isProd: false,
    );
    methods = const AuthMethods(AuthMethods.defaults);
    google = _FakeGoogle(_okClaims);
    apple = _FakeApple(_okClaims);
    email = LogEmailProvider();
  });

  RequestContext ctx(Request request) {
    final context = _MockRequestContext();
    when(() => context.request).thenReturn(request);
    when(() => context.read<AuthRepository>()).thenReturn(repo);
    when(() => context.read<AuthMethods>()).thenReturn(methods);
    when(() => context.read<GoogleIdTokenVerifier>()).thenReturn(google);
    when(() => context.read<AppleIdTokenVerifier>()).thenReturn(apple);
    when(() => context.read<EmailProvider>()).thenReturn(email);
    return context;
  }

  Request post(String path, Object body) =>
      Request.post(_u(path), body: jsonEncode(body));

  Future<Map<String, dynamic>> jsonOf(Response r) async =>
      await r.json() as Map<String, dynamic>;

  test('google: 200 AuthSession (nested tokens + user)', () async {
    final res = await google_route.onRequest(
      ctx(post('/auth/google', {'idToken': 'tok'})),
    );
    expect(res.statusCode, HttpStatus.ok);
    final body = await jsonOf(res);
    expect(body['tokens'], isA<Map<String, dynamic>>());
    expect((body['tokens'] as Map)['accessToken'], isNotEmpty);
    expect((body['user'] as Map)['email'], 'ama@x.com');
    expect((body['user'] as Map)['authProvider'], 'google');
  });

  test('google: rejected token → 401; missing token → 400; 405', () async {
    google = _FakeGoogle(_rejected);
    final rejected = await google_route.onRequest(
      ctx(post('/auth/google', {'idToken': 'bad'})),
    );
    expect(rejected.statusCode, HttpStatus.unauthorized);

    final missing = await google_route.onRequest(
      ctx(post('/auth/google', <String, dynamic>{})),
    );
    expect(missing.statusCode, HttpStatus.badRequest);

    final wrongVerb = await google_route.onRequest(
      ctx(Request.get(_u('/auth/google'))),
    );
    expect(wrongVerb.statusCode, HttpStatus.methodNotAllowed);
  });

  test('google: banned account → 403', () async {
    final first = await repo.loginWithSocial(
      provider: 'google',
      sub: 'sub-1',
      email: 'ama@x.com',
      emailVerified: true,
    );
    await repo.setStatus(first.user!.id, 'banned');
    final res = await google_route.onRequest(
      ctx(post('/auth/google', {'idToken': 'tok'})),
    );
    expect(res.statusCode, HttpStatus.forbidden);
  });

  test('apple: 200 + forwards the nonce + first-auth fullName', () async {
    final res = await apple_route.onRequest(
      ctx(
        post('/auth/apple', {
          'identityToken': 'tok',
          'nonce': 'n-1',
          'fullName': 'Ama Koné',
        }),
      ),
    );
    expect(res.statusCode, HttpStatus.ok);
    expect((apple as _FakeApple).seenNonce, 'n-1');
    final body = await jsonOf(res);
    expect((body['user'] as Map)['name'], 'Ama Koné');
  });

  test('email otp: 202 + devCode → verify → 200 session', () async {
    final req = await email_request.onRequest(
      ctx(post('/auth/email/otp/request', {'email': 'ama@x.com'})),
    );
    expect(req.statusCode, HttpStatus.accepted);
    final devCode = (await jsonOf(req))['devCode'] as String;

    final ver = await email_verify.onRequest(
      ctx(
        post('/auth/email/otp/verify', {'email': 'ama@x.com', 'code': devCode}),
      ),
    );
    expect(ver.statusCode, HttpStatus.ok);
    final body = await jsonOf(ver);
    expect((body['tokens'] as Map)['refreshToken'], isNotEmpty);
    expect((body['user'] as Map)['email'], 'ama@x.com');
  });

  test('email otp: invalid email → 400; wrong code → 400', () async {
    final bad = await email_request.onRequest(
      ctx(post('/auth/email/otp/request', {'email': 'not-an-email'})),
    );
    expect(bad.statusCode, HttpStatus.badRequest);

    await email_request.onRequest(
      ctx(post('/auth/email/otp/request', {'email': 'ama@x.com'})),
    );
    final wrong = await email_verify.onRequest(
      ctx(
        post('/auth/email/otp/verify', {
          'email': 'ama@x.com',
          'code': '000000',
        }),
      ),
    );
    expect(wrong.statusCode, HttpStatus.badRequest);
    expect((await jsonOf(wrong))['error'], 'otp_invalid');
  });

  group('AUTH_METHODS gate (launch: google,apple,email — no phone)', () {
    setUp(() => methods = AuthMethods.parse('google,apple,email'));

    test('phone otp/request → 404 auth_method_disabled', () async {
      final res = await phone_request.onRequest(
        ctx(post('/auth/otp/request', {'phoneNumber': '+2250707010101'})),
      );
      expect(res.statusCode, HttpStatus.notFound);
      expect((await jsonOf(res))['error'], 'auth_method_disabled');
    });

    test('google stays enabled', () async {
      final res = await google_route.onRequest(
        ctx(post('/auth/google', {'idToken': 'tok'})),
      );
      expect(res.statusCode, HttpStatus.ok);
    });

    test('disabling google gates the route', () async {
      methods = AuthMethods.parse('email');
      final res = await google_route.onRequest(
        ctx(post('/auth/google', {'idToken': 'tok'})),
      );
      expect(res.statusCode, HttpStatus.notFound);
    });
  });
}
