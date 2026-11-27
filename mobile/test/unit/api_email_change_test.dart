import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/models/email_change_request.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

/// `ApiAuthService`'s address change (B16.3b — account-email-change.md §3.1,
/// §5.4), against the routes B16.3a deployed: the bodies it sends, what it
/// reads back, and the sentence each refusal gets.
void main() {
  Map<String, dynamic> user({String? email, bool emailVerified = true}) => {
    'id': 'user_1',
    'phoneNumber': null,
    'phoneVerified': false,
    'name': 'Awa',
    'email': email,
    'emailVerified': emailVerified,
    'authProvider': 'email',
    'avatarUrl': null,
    'createdAt': DateTime(2026).toIso8601String(),
  };

  http.Response signedIn() => http.Response(
    jsonEncode({
      'tokens': {'accessToken': 'access-1', 'refreshToken': 'refresh-1'},
      'user': user(email: 'awa@exemple.ci'),
    }),
    200,
  );

  /// A service signed in by code, whose later requests [answer] answers;
  /// every request it sees lands in [seen].
  Future<ApiAuthService> service(
    List<http.Request> seen,
    http.Response Function(http.Request req) answer, {
    SessionStore? store,
  }) async {
    final s = ApiAuthService(
      client: MockClient((req) async {
        if (req.url.path == '/auth/email/otp/verify') return signedIn();
        seen.add(req);
        return answer(req);
      }),
      baseUrl: 'http://x',
      sessionStore: store ?? InMemorySessionStore(),
    );
    final res = await s.verifyEmailOtp('awa@exemple.ci', '123456');
    expect(res.success, isTrue);
    return s;
  }

  http.Response refusal(String code, int status) =>
      http.Response(jsonEncode({'error': code}), status);

  group('requestEmailChange', () {
    test(
      'POSTs {email} to /me/email/otp/request with the bearer; reads 202',
      () async {
        final seen = <http.Request>[];
        final s = await service(
          seen,
          (_) => http.Response(
            jsonEncode({
              'expiresInSeconds': 300,
              'currentCodeSent': true,
              'devCode': '111111',
              'currentDevCode': '222222',
            }),
            202,
          ),
        );

        final res = await s.requestEmailChange('nouvelle@exemple.ci');

        expect(res.success, isTrue);
        expect(
          res.data,
          const EmailChangeRequest(
            expiresInSeconds: 300,
            currentCodeSent: true,
            devCode: '111111',
            currentDevCode: '222222',
          ),
        );
        final req = seen.single;
        expect(req.method, 'POST');
        expect(req.url.path, '/me/email/otp/request');
        expect(req.headers['Authorization'], 'Bearer access-1');
        expect(jsonDecode(req.body), {'email': 'nouvelle@exemple.ci'});
      },
    );

    test('a production 202 (no dev codes) reads as such', () async {
      final s = await service(
        [],
        (_) => http.Response(
          jsonEncode({'expiresInSeconds': 300, 'currentCodeSent': false}),
          202,
        ),
      );
      final res = await s.requestEmailChange('nouvelle@exemple.ci');
      expect(res.data!.currentCodeSent, isFalse);
      expect(res.data!.devCode, isNull);
    });

    test('`email_unchanged` keeps its code, with its own words', () async {
      final s = await service([], (_) => refusal('email_unchanged', 409));
      final res = await s.requestEmailChange('awa@exemple.ci');
      expect(res.success, isFalse);
      expect(res.code, 'email_unchanged');
      expect(res.error, 'C’est déjà votre adresse.');
    });

    test('a 202 the app cannot read is « unreadable », not a throw', () async {
      final s = await service([], (_) => http.Response('<html>', 202));
      final res = await s.requestEmailChange('nouvelle@exemple.ci');
      expect(res.success, isFalse);
      expect(res.code, 'unreadable');
      expect(res.error, kGenericErrorMessage);
    });

    test('no answer at all: « Pas de connexion. Réessayez. »', () async {
      final s = ApiAuthService(
        client: MockClient((req) async {
          if (req.url.path == '/auth/email/otp/verify') return signedIn();
          throw http.ClientException('offline');
        }),
        baseUrl: 'http://x',
      );
      await s.verifyEmailOtp('awa@exemple.ci', '123456');
      final res = await s.requestEmailChange('nouvelle@exemple.ci');
      expect(res.code, 'network');
      expect(res.error, kNoConnectionMessage);
    });

    test('signed out: refused before any request', () async {
      final seen = <http.Request>[];
      final s = ApiAuthService(
        client: MockClient((req) async {
          seen.add(req);
          return http.Response('{}', 202);
        }),
        baseUrl: 'http://x',
      );
      final res = await s.requestEmailChange('nouvelle@exemple.ci');
      expect(res.success, isFalse);
      expect(seen, isEmpty);
    });
  });

  group('confirmEmailChange', () {
    test(
      '200: POSTs {email, code} — no currentCode unless given — and the '
      'answered account becomes the current one, and the stored session\'s',
      () async {
        final seen = <http.Request>[];
        final store = InMemorySessionStore();
        final s = await service(
          seen,
          (_) => http.Response(
            jsonEncode(user(email: 'nouvelle@exemple.ci')),
            200,
          ),
          store: store,
        );

        final res = await s.confirmEmailChange('nouvelle@exemple.ci', '123456');

        expect(res.success, isTrue);
        expect(res.data!.email, 'nouvelle@exemple.ci');
        expect(seen.single.url.path, '/me/email/otp/verify');
        expect(jsonDecode(seen.single.body), {
          'email': 'nouvelle@exemple.ci',
          'code': '123456',
        });
        expect((await s.getCurrentUser())!.email, 'nouvelle@exemple.ci');
        final stored = jsonDecode((await store.read())!) as Map;
        expect((stored['user'] as Map)['email'], 'nouvelle@exemple.ci');
        expect((stored['user'] as Map)['emailVerified'], isTrue);
        expect(
          stored['refreshToken'] ?? stored['refresh_token'],
          isNotNull,
          reason: 'the merge keeps the tokens',
        );
      },
    );

    test('the current address\'s code goes as currentCode', () async {
      final seen = <http.Request>[];
      final s = await service(
        seen,
        (_) =>
            http.Response(jsonEncode(user(email: 'nouvelle@exemple.ci')), 200),
      );
      await s.confirmEmailChange(
        'nouvelle@exemple.ci',
        '123456',
        currentCode: '654321',
      );
      expect(jsonDecode(seen.single.body), {
        'email': 'nouvelle@exemple.ci',
        'code': '123456',
        'currentCode': '654321',
      });
    });

    test(
      '`email_taken`: its code, and the words that say what to do',
      () async {
        final s = await service([], (_) => refusal('email_taken', 409));
        final res = await s.confirmEmailChange('prise@exemple.ci', '123456');
        expect(res.code, 'email_taken');
        expect(res.error, kEmailTakenMessage);
        expect(
          (await s.getCurrentUser())!.email,
          'awa@exemple.ci',
          reason: 'a refusal changes nothing here',
        );
      },
    );

    for (final (code, words) in const [
      ('otp_invalid', 'Code incorrect.'),
      ('current_otp_invalid', 'Code de votre adresse actuelle incorrect.'),
      (
        'current_otp_expired',
        'Le code de votre adresse actuelle a expiré. Demandez un nouveau code.',
      ),
      (
        'current_otp_none',
        'Aucun code actif pour votre adresse actuelle. Demandez un nouveau '
            'code.',
      ),
      (
        'current_otp_locked',
        'Trop de tentatives pour le code de votre adresse actuelle. Demandez '
            'un nouveau code.',
      ),
      ('rate_limited', 'Trop de tentatives. Réessayez plus tard.'),
    ]) {
      test('`$code` keeps its code and says « $words »', () async {
        final s = await service([], (_) => refusal(code, 400));
        final res = await s.confirmEmailChange('n@exemple.ci', '123456');
        expect(res.code, code);
        expect(res.error, words);
      });
    }
  });

  test(
    '`PATCH /me` never carries an address: the parameter is gone (§5.4)',
    () async {
      final seen = <http.Request>[];
      final s = await service(
        seen,
        (_) => http.Response(jsonEncode(user(email: 'awa@exemple.ci')), 200),
      );
      await s.updateUser(name: 'Awa', phone: '');
      expect(jsonDecode(seen.single.body), {'name': 'Awa', 'phone': ''});
    },
  );

  test(
    '`email_change_requires_code` (an older client\'s edit) says where to go',
    () async {
      final s = await service(
        [],
        (_) => refusal('email_change_requires_code', 409),
      );
      final res = await s.updateUser(name: 'Awa');
      expect(res.code, 'email_change_requires_code');
      expect(res.error, contains('« Modifier »'));
    },
  );
}
