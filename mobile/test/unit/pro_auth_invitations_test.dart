import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/provider_login_result.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/services/api/api_auth_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';

/// Team access R3 — the login invitation bridge end to end
/// (docs/design/team-access-r3-app.md §2.2): the 202 outcome, proof
/// retention, accept persisting the session on BOTH 200 and 201, the
/// unconsumed email code, and the decline-to-empty fallback.
void main() {
  setUp(() {
    MockData.resetTeam();
    // Accepts create bare member accounts in the STATIC providerUsers —
    // strip them so each test starts from the seeded world.
    MockData.providerUsers.removeWhere((p) => p.businessName.isEmpty);
  });

  Map<String, dynamic> invitationJson() => {
        'id': 'mem_x',
        'providerId': 'p1',
        'salonName': 'Chez Awa',
        'role': 'manager',
        'roleLabel': 'Manager',
        'expiresAt': '2026-07-19T00:00:00.000Z',
      };

  Map<String, dynamic> bareSessionJson() => {
        'provider': {
          'id': 'member_1',
          'phoneNumber': '',
          'businessName': '',
          'businessType': 'other',
          'email': 'ama@b.com',
          'verificationStatus': 'pending',
          'kycDocs': const <Map<String, dynamic>>[],
          'createdAt': DateTime(2026).toIso8601String(),
          'providerId': null,
        },
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
        'expiresAt': DateTime(2027).toIso8601String(),
      };

  group('ApiAuthService — the 202 bridge + public accept/decline', () {
    test(
        'email verify 202 → invited outcome carrying the UNCONSUMED code '
        'as proof', () async {
      final svc = ApiAuthService(
        client: MockClient((req) async {
          expect(req.url.path, '/auth/provider/email/otp/verify');
          return http.Response(
            jsonEncode({
              'invitations': [invitationJson()],
            }),
            202,
          );
        }),
        baseUrl: 'http://x',
        providerSessionStore: InMemorySessionStore(),
      );
      final res = await svc.verifyProviderEmailOtp('ama@b.com', '123456');
      expect(res.signedIn, isFalse);
      expect(res.hasInvitations, isTrue);
      expect(res.invitations.single.salonName, 'Chez Awa');
      final proof = res.proof;
      expect(proof, isA<EmailOtpInvitationProof>());
      expect((proof! as EmailOtpInvitationProof).code, '123456');
    });

    test('email verify 404 stays provider_not_found (no invitations)',
        () async {
      final svc = ApiAuthService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'provider_not_found'}),
            404,
          ),
        ),
        baseUrl: 'http://x',
        providerSessionStore: InMemorySessionStore(),
      );
      final res = await svc.verifyProviderEmailOtp('ama@b.com', '123456');
      expect(res.signedIn, isFalse);
      expect(res.hasInvitations, isFalse);
      expect(res.code, 'provider_not_found');
    });

    for (final status in [200, 201]) {
      test('public accept $status persists a WORKING provider session',
          () async {
        final store = InMemorySessionStore();
        final svc = ApiAuthService(
          client: MockClient((req) async {
            expect(req.url.path, '/auth/provider/invitations/accept');
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['invitationId'], 'mem_x');
            expect(body['email'], 'ama@b.com');
            expect(body['code'], '123456');
            return http.Response(jsonEncode(bareSessionJson()), status);
          }),
          baseUrl: 'http://x',
          providerSessionStore: store,
        );
        final res = await svc.acceptProviderInvitation(
          'mem_x',
          const EmailOtpInvitationProof('ama@b.com', '123456'),
        );
        expect(res.success, isTrue);
        expect(res.data!.providerId, isNull); // bare member account
        // The session persisted like a login.
        final saved = jsonDecode((await store.read())!) as Map<String, dynamic>;
        expect(saved['token'], 'access-1');
        expect(saved['refreshToken'], 'refresh-1');
        expect((await svc.getCurrentProvider())!.email, 'ama@b.com');
      });
    }

    test('public accept surfaces invitation_expired with French copy',
        () async {
      final svc = ApiAuthService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'invitation_expired'}),
            409,
          ),
        ),
        baseUrl: 'http://x',
        providerSessionStore: InMemorySessionStore(),
      );
      final res = await svc.acceptProviderInvitation(
        'mem_x',
        const GoogleInvitationProof('id-token'),
      );
      expect(res.success, isFalse);
      expect(res.code, 'invitation_expired');
      expect(res.error, contains('expiré'));
    });

    test('public decline posts the proof and returns true on 200', () async {
      final svc = ApiAuthService(
        client: MockClient((req) async {
          expect(req.url.path, '/auth/provider/invitations/decline');
          expect(
            (jsonDecode(req.body) as Map<String, dynamic>)['idToken'],
            'id-token',
          );
          return http.Response(jsonEncode({'declined': true}), 200);
        }),
        baseUrl: 'http://x',
        providerSessionStore: InMemorySessionStore(),
      );
      final res = await svc.declineProviderInvitation(
        'mem_x',
        const GoogleInvitationProof('id-token'),
      );
      expect(res.success, isTrue);
    });
  });

  group('ProAuthProvider — the invitations step state machine', () {
    setUpAll(() {
      serviceLocator.authService = MockAuthService();
    });

    Future<ProAuthProvider> bridgedProvider() async {
      // The singleton mock service keeps the previous test's session —
      // start signed out like a fresh login screen.
      await serviceLocator.authService.logoutProvider();
      final provider = ProAuthProvider();
      await provider.requestEmailOtp('invitee@myweli.test');
      final ok = await provider.verifyEmailOtp(
        'invitee@myweli.test',
        provider.emailDevCode!,
      );
      expect(ok, isFalse);
      expect(provider.hasPendingInvitations, isTrue);
      return provider;
    }

    test('the bridge surfaces the cards without an error banner', () async {
      final provider = await bridgedProvider();
      expect(provider.error, isNull);
      expect(provider.errorCode, isNull);
      expect(
        provider.pendingInvitations.single.salonName,
        'Salon Excellence',
      );
      expect(provider.isAuthenticated, isFalse);
    });

    test(
        'accept authenticates under the retained proof (the code was NOT '
        'consumed by the bridge) and clears the step state', () async {
      final provider = await bridgedProvider();
      final invitationId = provider.pendingInvitations.single.id;
      final ok = await provider.acceptPendingInvitation(invitationId);
      expect(ok, isTrue);
      expect(provider.isAuthenticated, isTrue);
      // Bare member account: no salon (the provisioning guard holds).
      expect(provider.provider!.providerId, isNull);
      expect(provider.provider!.businessName, isEmpty);
      expect(provider.hasPendingInvitations, isFalse);
      // The roster row flipped to active in the shared mock state.
      expect(
        MockData.teamMembers
            .singleWhere((m) => m.id == invitationId)
            .status
            .name,
        'active',
      );
    });

    test(
        'declining the LAST card falls back to provider_not_found (the '
        '« Créer un compte » path)', () async {
      final provider = await bridgedProvider();
      final ok = await provider.declinePendingInvitation(
        provider.pendingInvitations.single.id,
      );
      expect(ok, isTrue);
      expect(provider.hasPendingInvitations, isFalse);
      expect(provider.errorCode, 'provider_not_found');
      expect(provider.isAuthenticated, isFalse);
    });

    test('clearPendingInvitations resets the step (« Retour »)', () async {
      final provider = await bridgedProvider();
      provider.clearPendingInvitations();
      expect(provider.hasPendingInvitations, isFalse);
      expect(provider.error, isNull);
      expect(provider.errorCode, isNull);
    });
  });
}
