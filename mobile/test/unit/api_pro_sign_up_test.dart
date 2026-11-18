import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/models/pro_sign_up_fields.dart';
import 'package:myweli/models/provider_login_result.dart';
import 'package:myweli/models/provider_sign_up_result.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

/// The Android sign-up's calls (docs/design/pro-android-signup.md §2.1, §3,
/// §8.2 « Unit, the API service »): the sign-in check, then register with
/// the SAME proof, the exact register body, and each answer's outcome with
/// its stage.
void main() {
  const fields = ProSignUpFields(
    businessName: 'Salon Awa',
    businessType: BusinessType.nailSalon,
    phoneNumber: '+2250707010101',
    address: 'Rue des Jardins, Cocody',
  );

  Map<String, dynamic> providerJson() => {
    'id': 'provider_1',
    'phoneNumber': '+2250707010101',
    'name': null,
    'businessName': 'Salon Awa',
    'businessType': 'nailSalon',
    'email': 'awa@salon.ci',
    'address': null,
    'verificationStatus': 'pending',
    'rejectionReason': null,
    'kycDocs': const <Map<String, dynamic>>[],
    'createdAt': DateTime(2026).toIso8601String(),
    'providerId': 'salon_1',
  };

  http.Response session(int status) => http.Response(
    jsonEncode({
      'provider': providerJson(),
      'accessToken': 'access-1',
      'refreshToken': 'refresh-1',
    }),
    status,
  );

  http.Response refusal(int status, String code) =>
      http.Response(jsonEncode({'error': code}), status);

  final invitationsBody = http.Response(
    jsonEncode({
      'invitations': [
        {
          'id': 'inv_1',
          'providerId': 'salon_9',
          'salonName': 'Chez Fanta',
          'role': 'staff',
          'roleLabel': 'Collaborateur',
          'expiresAt': null,
        },
      ],
    }),
    202,
  );

  /// The calls a service made, in order, with their bodies.
  late List<(String, Map<String, dynamic>)> calls;

  ApiAuthService service(
    http.Response Function(String path) answer, {
    GoogleIdTokenProvider? google,
    SessionStore? store,
  }) {
    calls = [];
    return ApiAuthService(
      client: MockClient((req) async {
        calls.add((req.url.path, jsonDecode(req.body) as Map<String, dynamic>));
        return answer(req.url.path);
      }),
      baseUrl: 'http://x',
      providerSessionStore: store ?? InMemorySessionStore(),
      googleIdToken: google ?? () async => 'google-token-1',
    );
  }

  group('the check, then register, with the same proof', () {
    test(
      'Google: one token, both calls; 201 → created, session kept',
      () async {
        final store = InMemorySessionStore();
        final svc = service(
          (path) => path == '/auth/provider/google'
              ? refusal(404, 'provider_not_found')
              : session(201),
          store: store,
        );
        final result = await svc.signUpProviderWithGoogle(fields);

        expect(result, isA<ProviderSignUpCreated>());
        expect(calls.map((c) => c.$1), [
          '/auth/provider/google',
          '/auth/provider/register',
        ]);
        expect(calls[0].$2, {'idToken': 'google-token-1'});
        // The exact body: the salon, one identity, no areaId when none chosen.
        expect(calls[1].$2, {
          'businessName': 'Salon Awa',
          'businessType': 'nailSalon',
          'phoneNumber': '+2250707010101',
          'address': 'Rue des Jardins, Cocody',
          'idToken': 'google-token-1',
        });
        expect(await store.read(), isNotNull, reason: 'the session persists');
        expect((await svc.getCurrentProvider())?.id, 'provider_1');
      },
    );

    test('e-mail: the verify, then register with that pair', () async {
      final svc = service(
        (path) => path == '/auth/provider/email/otp/verify'
            ? refusal(404, 'provider_not_found')
            : session(201),
      );
      final withArea = ProSignUpFields(
        businessName: fields.businessName,
        businessType: fields.businessType,
        phoneNumber: fields.phoneNumber,
        address: fields.address,
        areaId: 'cocody',
      );
      final result = await svc.signUpProviderWithEmail(
        'awa@salon.ci',
        '123456',
        withArea,
      );

      expect(result, isA<ProviderSignUpCreated>());
      expect(calls.map((c) => c.$1), [
        '/auth/provider/email/otp/verify',
        '/auth/provider/register',
      ]);
      expect(calls[0].$2, {'email': 'awa@salon.ci', 'code': '123456'});
      expect(calls[1].$2, {
        'businessName': 'Salon Awa',
        'businessType': 'nailSalon',
        'phoneNumber': '+2250707010101',
        'address': 'Rue des Jardins, Cocody',
        'areaId': 'cocody',
        'email': 'awa@salon.ci',
        'code': '123456',
      });
      expect(calls[1].$2.containsKey('idToken'), isFalse, reason: 'one proof');
    });
  });

  group('the check\'s other answers create nothing', () {
    test('200 → signed in, no register', () async {
      final svc = service((_) => session(200));
      final result = await svc.signUpProviderWithGoogle(fields);
      expect(result, isA<ProviderSignUpSignedIn>());
      expect(calls.map((c) => c.$1), ['/auth/provider/google']);
    });

    test('202 → invited, with the proof that accepts', () async {
      final svc = service((_) => invitationsBody);
      final result = await svc.signUpProviderWithEmail(
        'awa@salon.ci',
        '123456',
        fields,
      );
      final invited = result as ProviderSignUpInvited;
      expect(invited.invitations.single.salonName, 'Chez Fanta');
      final proof = invited.proof as EmailOtpInvitationProof;
      expect((proof.email, proof.code), ('awa@salon.ci', '123456'));
      expect(calls, hasLength(1));
    });

    test('a refusal keeps its code and the check\'s stage', () async {
      final svc = service((_) => refusal(400, 'otp_expired'));
      final result = await svc.signUpProviderWithEmail(
        'awa@salon.ci',
        '123456',
        fields,
      );
      final failure = result as ProviderSignUpFailure;
      expect(failure.code, 'otp_expired');
      expect(failure.stage, ProSignUpStage.check);
      expect(failure.message, 'Code expiré. Demandez un nouveau code.');
      expect(calls, hasLength(1));
    });

    test(
      'the check\'s invalid_input (a malformed code) is the check\'s',
      () async {
        final svc = service((_) => refusal(400, 'invalid_input'));
        final failure =
            await svc.signUpProviderWithEmail('awa@salon.ci', '12', fields)
                as ProviderSignUpFailure;
        expect(
          (failure.code, failure.stage),
          ('invalid_input', ProSignUpStage.check),
        );
      },
    );
  });

  group('register\'s refusals keep their code and register\'s stage', () {
    for (final code in [
      'invalid_phone',
      'invalid_area',
      'invalid_input',
      'provider_exists',
      'otp_none',
    ]) {
      test(code, () async {
        final svc = service(
          (path) => path == '/auth/provider/google'
              ? refusal(404, 'provider_not_found')
              : refusal(code == 'provider_exists' ? 409 : 400, code),
        );
        final failure =
            await svc.signUpProviderWithGoogle(fields) as ProviderSignUpFailure;
        expect(failure.code, code);
        expect(failure.stage, ProSignUpStage.register);
      });
    }

    test('no network at register: `network`, register\'s stage', () async {
      calls = [];
      var n = 0;
      final svc = ApiAuthService(
        client: MockClient((req) async {
          if (n++ == 0) return refusal(404, 'provider_not_found');
          throw Exception('timeout');
        }),
        baseUrl: 'http://x',
        googleIdToken: () async => 'google-token-1',
      );
      final failure =
          await svc.signUpProviderWithGoogle(fields) as ProviderSignUpFailure;
      expect(failure.code, 'network');
      expect(failure.stage, ProSignUpStage.register);
      expect(failure.message, kNoConnectionMessage);
    });

    test('a 500 at register: no code, register\'s stage (S12)', () async {
      final svc = service(
        (path) => path == '/auth/provider/google'
            ? refusal(404, 'provider_not_found')
            : http.Response('oops', 500),
      );
      final failure =
          await svc.signUpProviderWithGoogle(fields) as ProviderSignUpFailure;
      expect(failure.code, isNull);
      expect(failure.stage, ProSignUpStage.register);
      expect(failure.message, kGenericErrorMessage);
    });
  });

  group('registerProvider: register only, with the held proof', () {
    test('a Google proof', () async {
      final svc = service((_) => session(201));
      final result = await svc.registerProvider(
        const GoogleInvitationProof('held-token'),
        fields,
      );
      expect(result, isA<ProviderSignUpCreated>());
      expect(calls.single.$1, '/auth/provider/register');
      expect(calls.single.$2['idToken'], 'held-token');
    });

    test('an e-mail proof', () async {
      final svc = service((_) => session(201));
      await svc.registerProvider(
        const EmailOtpInvitationProof('awa@salon.ci', '654321'),
        fields,
      );
      expect(calls.single.$2['email'], 'awa@salon.ci');
      expect(calls.single.$2['code'], '654321');
      expect(calls.single.$2.containsKey('idToken'), isFalse);
    });
  });

  group('Google\'s sheet', () {
    test('closed: `cancelled`, nothing sent (S14)', () async {
      final svc = service(
        (_) => fail('nothing may be sent'),
        google: () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        ),
      );
      final failure =
          await svc.signUpProviderWithGoogle(fields) as ProviderSignUpFailure;
      expect(failure.code, 'cancelled');
      expect(failure.message, isEmpty);
      expect(calls, isEmpty);
    });

    test('a plugin failure: the sign-in\'s sentence, nothing sent', () async {
      final svc = service(
        (_) => fail('nothing may be sent'),
        google: () async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        ),
      );
      final failure =
          await svc.signUpProviderWithGoogle(fields) as ProviderSignUpFailure;
      expect(failure.code, 'google_failed');
      expect(failure.message, 'Connexion Google impossible.');
      expect(calls, isEmpty);
    });

    test('no token: `no_id_token`, nothing sent', () async {
      final svc = service(
        (_) => fail('nothing may be sent'),
        google: () async => null,
      );
      final failure =
          await svc.signUpProviderWithGoogle(fields) as ProviderSignUpFailure;
      expect(failure.code, 'no_id_token');
      expect(calls, isEmpty);
    });
  });
}
