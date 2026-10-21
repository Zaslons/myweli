import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/auth/apple_tokens.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/id_token_verifier.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:test/test.dart';

import '../../routes/auth/provider/apple.dart' as p_apple;
import '../../routes/auth/provider/register.dart' as p_register;
import '../http/observed.dart';
import 'apple_token_fake.dart';

class _MockRequestContext extends Mock implements RequestContext {}

class _FakeApple extends AppleIdTokenVerifier {
  _FakeApple(this.result) : super(clientIds: const ['ci.myweli.pro']);
  final IdTokenResult result;
  @override
  Future<IdTokenResult> verify(String token, {String? nonce}) async => result;
  @override
  String? audienceOf(String verifiedToken) => 'ci.myweli.pro';
}

const IdTokenResult _claims = (
  ok: true,
  error: null,
  sub: 'a-sub-1',
  email: 'salon@privaterelay.appleid.com',
  emailVerified: true,
  name: null,
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

/// docs/design/backend-integrity-batch6.md §13 (B6.7) — the Pro's two Apple
/// doors (sign-in, and the Apple branch of sign-up) hand the sign-in's
/// `authorizationCode` over to be exchanged for a refresh token, kept under
/// the PRO account — the one its deletion revokes.
void main() {
  late InMemoryProviderAuthRepository repo;
  late InMemoryProvidersRepository salons;
  late AppleIdTokenVerifier apple;
  late RecordingAppleTokens appleTokens;

  setUp(() {
    repo = InMemoryProviderAuthRepository(
      tokens: TokenService(secret: 'test-secret'),
      echoDevCode: true,
    );
    salons = InMemoryProvidersRepository([]);
    apple = _FakeApple(_claims);
    appleTokens = RecordingAppleTokens();
  });

  RequestContext ctx(Request request) {
    final context = _MockRequestContext();
    when(() => context.request).thenReturn(request);
    when(() => context.read<ProviderAuthRepository>()).thenReturn(repo);
    when(
      () => context.read<AuthMethods>(),
    ).thenReturn(const AuthMethods(AuthMethods.defaults));
    when(() => context.read<AppleIdTokenVerifier>()).thenReturn(apple);
    when(() => context.read<AppleTokenService>()).thenReturn(appleTokens);
    when(() => context.read<SalonProvisioningService>()).thenReturn(
      SalonProvisioningService(salons, repo, InMemoryMembershipRepository()),
    );
    return context;
  }

  Request post(String path, Object body) =>
      Request.post(Uri.parse('http://localhost$path'), body: jsonEncode(body));

  Future<String> appleAccount() async {
    final reg = await repo.register(
      businessName: 'Élégance',
      businessType: 'salon',
      phoneNumber: '+2250544556677',
      email: 'salon@privaterelay.appleid.com',
      authProvider: 'apple',
      appleSub: 'a-sub-1',
    );
    return reg.provider!.id;
  }

  group('POST /auth/provider/apple', () {
    test('a code → exchanged for THIS Pro account, with the token\'s '
        'audience and its verified sub', () async {
      final id = await appleAccount();
      final res = await p_apple.onRequest(
        ctx(
          post('/auth/provider/apple', {
            'identityToken': 'tok',
            'authorizationCode': 'code-1',
            'redirectUri': 'https://myweli.com/connexion',
          }),
        ),
      );
      expect(res.statusCode, HttpStatus.ok);
      expect(appleTokens.kept, [
        {
          'kind': 'provider',
          'accountId': id,
          'clientId': 'ci.myweli.pro',
          'sub': 'a-sub-1',
          'code': 'code-1',
          'redirectUri': 'https://myweli.com/connexion',
        },
      ]);
    });

    test('no code → nothing exchanged', () async {
      await appleAccount();
      final res = await p_apple.onRequest(
        ctx(post('/auth/provider/apple', {'identityToken': 'tok'})),
      );
      expect(res.statusCode, HttpStatus.ok);
      expect(appleTokens.kept, isEmpty);
    });

    test('a refused token → nothing exchanged', () async {
      await appleAccount();
      apple = _FakeApple(_rejected);
      await p_apple.onRequest(
        ctx(
          post('/auth/provider/apple', {
            'identityToken': 'tok',
            'authorizationCode': 'code-1',
          }),
        ),
      );
      expect(appleTokens.kept, isEmpty);
    });

    test('no such Pro account (sign-in refused) → nothing exchanged', () async {
      final res = await p_apple.onRequest(
        ctx(
          post('/auth/provider/apple', {
            'identityToken': 'tok',
            'authorizationCode': 'code-1',
          }),
        ),
      );
      expect(res.statusCode, isNot(HttpStatus.ok));
      expect(appleTokens.kept, isEmpty);
    });
  });

  test('sign-in: a code of the wrong JSON type → 400 invalid_body, BEFORE '
      'the sign-in — no session', () async {
    await appleAccount();
    final res = await observed(
      p_apple.onRequest,
      ctx(
        post('/auth/provider/apple', {
          'identityToken': 'tok',
          'authorizationCode': 5,
        }),
      ),
    );
    expect(res.statusCode, HttpStatus.badRequest);
    final body = jsonDecode(await res.body()) as Map;
    expect(body['error'], 'invalid_body');
    expect(body.containsKey('accessToken'), isFalse);
    expect(appleTokens.kept, isEmpty);
  });

  test('sign-up: a code of the wrong JSON type → 400 invalid_body, nothing '
      'created — the same identity, well-typed, then registers', () async {
    Map<String, Object?> reg(Object? code) => {
      'phoneNumber': '+2250544556677',
      'businessName': 'Élégance',
      'businessType': 'salon',
      'identityToken': 'tok',
      'authorizationCode': code,
    };
    final bad = await observed(
      p_register.onRequest,
      ctx(post('/auth/provider/register', reg(const ['c']))),
    );
    expect(bad.statusCode, HttpStatus.badRequest);
    expect((jsonDecode(await bad.body()) as Map)['error'], 'invalid_body');
    expect(appleTokens.kept, isEmpty);
    final good = await p_register.onRequest(
      ctx(post('/auth/provider/register', reg('code-1'))),
    );
    expect(good.statusCode, HttpStatus.created);
  });

  group('POST /auth/provider/register — the Apple branch', () {
    Map<String, Object?> body({String? code}) => {
      'phoneNumber': '+2250544556677',
      'businessName': 'Élégance',
      'businessType': 'salon',
      'identityToken': 'tok',
      'authorizationCode': ?code,
    };

    test('a code → exchanged for the NEW account', () async {
      final res = await p_register.onRequest(
        ctx(post('/auth/provider/register', body(code: 'code-1'))),
      );
      expect(res.statusCode, HttpStatus.created);
      final id =
          ((jsonDecode(await res.body()) as Map)['provider'] as Map)['id'];
      expect(appleTokens.kept.single['kind'], 'provider');
      expect(appleTokens.kept.single['accountId'], id);
      expect(appleTokens.kept.single['clientId'], 'ci.myweli.pro');
      expect(appleTokens.kept.single['code'], 'code-1');
    });

    test('no code → nothing exchanged', () async {
      final res = await p_register.onRequest(
        ctx(post('/auth/provider/register', body())),
      );
      expect(res.statusCode, HttpStatus.created);
      expect(appleTokens.kept, isEmpty);
    });

    test('a duplicate (409) → nothing exchanged', () async {
      await appleAccount();
      final res = await p_register.onRequest(
        ctx(post('/auth/provider/register', body(code: 'code-1'))),
      );
      expect(res.statusCode, HttpStatus.conflict);
      expect(appleTokens.kept, isEmpty);
    });
  });
}
