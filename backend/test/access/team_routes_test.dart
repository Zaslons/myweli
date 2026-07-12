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
import 'package:myweli_backend/src/subscription/salon_subscription_repository.dart';
import 'package:myweli_backend/src/subscription/salon_subscription_service.dart';
import 'package:test/test.dart';

import '../../routes/auth/provider/email/otp/verify.dart' as email_verify;
import '../../routes/auth/provider/google.dart' as google_login;
import '../../routes/auth/provider/invitations/accept.dart' as public_accept;
import '../../routes/auth/provider/invitations/decline.dart' as public_decline;
import '../../routes/me/provider/invitations/[invitationId]/accept.dart'
    as my_accept;
import '../../routes/me/provider/invitations/[invitationId]/decline.dart'
    as my_decline;
import '../../routes/me/provider/invitations/index.dart' as my_invitations;
import '../../routes/me/provider/members/[memberId]/index.dart' as member_item;
import '../../routes/me/provider/members/[memberId]/resend.dart' as resend;
import '../../routes/me/provider/members/[memberId]/revoke.dart' as revoke;
import '../../routes/me/provider/members/index.dart' as members;

class _MockRequestContext extends Mock implements RequestContext {}

class _FakeGoogle extends GoogleIdTokenVerifier {
  _FakeGoogle() : super(clientIds: const ['test']);

  IdTokenResult result = (
    ok: false,
    error: 'token_rejected',
    sub: null,
    email: null,
    emailVerified: false,
    name: null,
    avatarUrl: null,
  );

  void claims({required String sub, required String email}) {
    result = (
      ok: true,
      error: null,
      sub: sub,
      email: email,
      emailVerified: true,
      name: null,
      avatarUrl: null,
    );
  }

  @override
  Future<IdTokenResult> verify(String token, {String? nonce}) async => result;
}

class _NullEmail implements EmailProvider {
  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    String? html,
  }) async => (ok: true, providerMessageId: 'm', error: null);
}

/// R2b handlers end to end (team-access-r2b-invitations.md §5/§9): the
/// Équipe routes (owner-only, T36), the 202 login bridge on both identity
/// routes, the unauthenticated accept/decline (bare account + provisioning
/// guard, T37) and the session-proof authed invitation routes.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryProviderAuthRepository auth;
  late InMemoryMembershipRepository memberships;
  late InMemoryProvidersRepository providers;
  late MembershipService resolver;
  late SalonSubscriptionService subscriptions;
  late TeamService team;
  late _FakeGoogle google;
  late String ownerId;
  late DateTime now;

  setUp(() async {
    now = DateTime.now().toUtc();
    auth = InMemoryProviderAuthRepository(tokens: tokens, isProd: false);
    memberships = InMemoryMembershipRepository();
    providers = InMemoryProvidersRepository([
      {
        'id': 'p1',
        'name': 'Chez Awa',
        'status': 'published',
        'artists': [
          {'id': 'a1', 'name': 'Awa'},
        ],
      },
      {
        'id': 'p2',
        'name': 'Studio Belle',
        'status': 'published',
        'artists': <Map<String, dynamic>>[],
      },
    ]);
    resolver = MembershipService(memberships, auth);
    subscriptions = SalonSubscriptionService(
      InMemorySalonSubscriptionRepository(),
      resolver,
      memberships,
      providers,
      auth,
    );
    team = TeamService(
      memberships,
      resolver,
      providers,
      subscriptions,
      _NullEmail(),
      InMemoryProviderAuditLogRepository(),
      clock: () => now,
    );
    google = _FakeGoogle();

    final reg = await auth.register(
      businessName: 'Chez Awa',
      businessType: 'salon',
      phoneNumber: '+2250500000071',
      email: 'owner@x.pro',
      authProvider: 'google',
      googleSub: 'sub-owner',
      providerId: 'p1',
    );
    ownerId = reg.provider!.id;
    await memberships.ensureOwner(
      providerId: 'p1',
      accountId: ownerId,
      email: 'owner@x.pro',
    );
    await subscriptions.chooseOffer(ownerId, 'p1', 'pro');
  });

  RequestContext ctx(Request request) {
    final c = _MockRequestContext();
    when(() => c.request).thenReturn(request);
    when(() => c.read<TokenService>()).thenReturn(tokens);
    when(
      () => c.read<AuthMethods>(),
    ).thenReturn(AuthMethods.parse('google,apple,email'));
    when(() => c.read<GoogleIdTokenVerifier>()).thenReturn(google);
    when(() => c.read<ProviderAuthRepository>()).thenReturn(auth);
    when(() => c.read<MembershipService>()).thenReturn(resolver);
    when(() => c.read<TeamService>()).thenReturn(team);
    return c;
  }

  Request req(String method, String path, {String? token, Object? body}) =>
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: body == null ? null : jsonEncode(body),
      );

  String tok(String sub, {String role = 'provider'}) =>
      tokens.issueAccessToken(subject: sub, role: role).token;

  /// Owner invites [email]; returns the member/invitation id.
  Future<String> invited(String email, {String role = 'manager'}) async {
    final r = await team.invite(ownerId, 'p1', email: email, role: role);
    expect(r.ok, isTrue, reason: 'seed invite failed: ${r.error}');
    return ((r.data! as Map)['id']) as String;
  }

  /// A live MEMBER account (bare, email-auth) that accepted [email]'s invite.
  Future<String> activeMember(String email) async {
    final invId = await invited(email);
    final code = (await auth.requestEmailOtp(email)).devCode!;
    final created = await auth.createMemberAccount(
      email: email,
      authProvider: 'email',
      emailCode: code,
    );
    final accountId = created.provider!.id;
    await team.accept(invId, accountId: accountId, accountEmail: email);
    return accountId;
  }

  group('GET/POST /me/provider/members', () {
    test(
      '401 anonymous · 403 consumer role · 403 membership-less provider',
      () async {
        final anon = await members.onRequest(
          ctx(req('GET', '/me/provider/members')),
        );
        expect(anon.statusCode, HttpStatus.unauthorized);

        final consumer = await members.onRequest(
          ctx(
            req('GET', '/me/provider/members', token: tok('u1', role: 'user')),
          ),
        );
        expect(consumer.statusCode, HttpStatus.forbidden);

        final ghost = await members.onRequest(
          ctx(req('GET', '/me/provider/members', token: tok('ghost'))),
        );
        expect(ghost.statusCode, HttpStatus.forbidden);
      },
    );

    test('owner lists the roster (owner row first)', () async {
      await invited('mgr@b.com');
      final res = await members.onRequest(
        ctx(req('GET', '/me/provider/members', token: tok(ownerId))),
      );
      expect(res.statusCode, HttpStatus.ok);
      final items = ((await res.json() as Map)['items'] as List)
          .cast<Map<String, dynamic>>();
      expect(items, hasLength(2));
      expect(items.first['role'], 'owner');
      expect(items.last['status'], 'invited');
    });

    test('POST invites (201); duplicate → 409; bad role → 400; bad body '
        '→ 400; DELETE → 405', () async {
      final created = await members.onRequest(
        ctx(
          req(
            'POST',
            '/me/provider/members',
            token: tok(ownerId),
            body: {'email': 'ama@b.com', 'role': 'reception'},
          ),
        ),
      );
      expect(created.statusCode, HttpStatus.created);
      expect((await created.json() as Map)['status'], 'invited');

      final dup = await members.onRequest(
        ctx(
          req(
            'POST',
            '/me/provider/members',
            token: tok(ownerId),
            body: {'email': 'ama@b.com', 'role': 'manager'},
          ),
        ),
      );
      expect(dup.statusCode, HttpStatus.conflict);
      expect((await dup.json() as Map)['error'], 'member_exists');

      final badRole = await members.onRequest(
        ctx(
          req(
            'POST',
            '/me/provider/members',
            token: tok(ownerId),
            body: {'email': 'x@b.com', 'role': 'owner'},
          ),
        ),
      );
      expect(badRole.statusCode, HttpStatus.badRequest);

      final badBody = await members.onRequest(
        ctx(
          Request(
            'POST',
            Uri.parse('http://localhost/me/provider/members'),
            headers: {'Authorization': 'Bearer ${tok(ownerId)}'},
            body: 'not json',
          ),
        ),
      );
      expect(badBody.statusCode, HttpStatus.badRequest);

      final wrongVerb = await members.onRequest(
        ctx(req('DELETE', '/me/provider/members', token: tok(ownerId))),
      );
      expect(wrongVerb.statusCode, HttpStatus.methodNotAllowed);
    });

    test('T36: an ACTIVE manager cannot read or mutate the roster', () async {
      final mgrId = await activeMember('mgr@b.com');
      final list = await members.onRequest(
        ctx(req('GET', '/me/provider/members', token: tok(mgrId))),
      );
      expect(list.statusCode, HttpStatus.forbidden);

      final invite = await members.onRequest(
        ctx(
          req(
            'POST',
            '/me/provider/members',
            token: tok(mgrId),
            body: {'email': 'friend@b.com', 'role': 'manager'},
          ),
        ),
      );
      expect(invite.statusCode, HttpStatus.forbidden);
    });
  });

  group('PATCH /me/provider/members/{id} + revoke + resend', () {
    test('role change lands; the owner row → 403 owner_protected (T36); '
        'GET → 405', () async {
      final id = await invited('mgr@b.com');
      final patched = await member_item.onRequest(
        ctx(
          req(
            'PATCH',
            '/me/provider/members/$id',
            token: tok(ownerId),
            body: {'role': 'reception'},
          ),
        ),
        id,
      );
      expect(patched.statusCode, HttpStatus.ok);
      expect((await patched.json() as Map)['role'], 'reception');

      final ownerRow = (await memberships.listForProvider(
        'p1',
      )).singleWhere((m) => m.role == 'owner');
      final protected = await member_item.onRequest(
        ctx(
          req(
            'PATCH',
            '/me/provider/members/${ownerRow.id}',
            token: tok(ownerId),
            body: {'role': 'manager'},
          ),
        ),
        ownerRow.id,
      );
      expect(protected.statusCode, HttpStatus.forbidden);
      expect((await protected.json() as Map)['error'], 'owner_protected');

      final wrongVerb = await member_item.onRequest(
        ctx(req('GET', '/me/provider/members/$id', token: tok(ownerId))),
        id,
      );
      expect(wrongVerb.statusCode, HttpStatus.methodNotAllowed);
    });

    test('T38 at the surface: revoke → the member 403s on their very next '
        'request', () async {
      final mgrId = await activeMember('mgr@b.com');
      final row = (await memberships.listForProvider(
        'p1',
      )).singleWhere((m) => m.role == 'manager');

      final revoked = await revoke.onRequest(
        ctx(
          req(
            'POST',
            '/me/provider/members/${row.id}/revoke',
            token: tok(ownerId),
          ),
        ),
        row.id,
      );
      expect(revoked.statusCode, HttpStatus.ok);

      // The manager's JWT is still valid — the membership row is not.
      expect(await resolver.can(mgrId, 'p1', 'journal.manage.all'), isFalse);
      final asRevoked = await members.onRequest(
        ctx(req('GET', '/me/provider/members', token: tok(mgrId))),
      );
      expect(asRevoked.statusCode, HttpStatus.forbidden);
    });

    test('resend: 3 budgeted re-sends then 429; active member → 409', () async {
      final id = await invited('mgr@b.com');
      for (var i = 0; i < 3; i++) {
        final r = await resend.onRequest(
          ctx(
            req('POST', '/me/provider/members/$id/resend', token: tok(ownerId)),
          ),
          id,
        );
        expect(r.statusCode, HttpStatus.ok);
      }
      final exhausted = await resend.onRequest(
        ctx(
          req('POST', '/me/provider/members/$id/resend', token: tok(ownerId)),
        ),
        id,
      );
      expect(exhausted.statusCode, HttpStatus.tooManyRequests);

      final mgrId = await activeMember('act@b.com');
      final row = (await memberships.listForProvider(
        'p1',
      )).singleWhere((m) => m.accountId == mgrId);
      final active = await resend.onRequest(
        ctx(
          req(
            'POST',
            '/me/provider/members/${row.id}/resend',
            token: tok(ownerId),
          ),
        ),
        row.id,
      );
      expect(active.statusCode, HttpStatus.conflict);
    });
  });

  group('the 202 login bridge', () {
    test(
      'google: pending invitations + no account → 202 cards; none → 404',
      () async {
        await invited('ama@b.com');
        google.claims(sub: 'sub-ama', email: 'ama@b.com');
        final bridged = await google_login.onRequest(
          ctx(req('POST', '/auth/provider/google', body: {'idToken': 't'})),
        );
        expect(bridged.statusCode, HttpStatus.accepted);
        final cards = ((await bridged.json() as Map)['invitations'] as List)
            .cast<Map<String, dynamic>>();
        expect(cards.single['salonName'], 'Chez Awa');
        expect(cards.single['roleLabel'], 'Manager');

        google.claims(sub: 'sub-nobody', email: 'nobody@b.com');
        final plain = await google_login.onRequest(
          ctx(req('POST', '/auth/provider/google', body: {'idToken': 't'})),
        );
        expect(plain.statusCode, HttpStatus.notFound);
        expect((await plain.json() as Map)['error'], 'provider_not_found');
      },
    );

    test(
      'email OTP: 202 leaves the code UNCONSUMED for the accept call',
      () async {
        final invId = await invited('ama@b.com');
        final code = (await auth.requestEmailOtp('ama@b.com')).devCode!;

        final bridged = await email_verify.onRequest(
          ctx(
            req(
              'POST',
              '/auth/provider/email/otp/verify',
              body: {'email': 'ama@b.com', 'code': code},
            ),
          ),
        );
        expect(bridged.statusCode, HttpStatus.accepted);

        // The same code still works — the accept consumes it.
        final accepted = await public_accept.onRequest(
          ctx(
            req(
              'POST',
              '/auth/provider/invitations/accept',
              body: {'invitationId': invId, 'email': 'ama@b.com', 'code': code},
            ),
          ),
        );
        expect(accepted.statusCode, HttpStatus.created);
      },
    );
  });

  group('POST /auth/provider/invitations/accept', () {
    test('google path: creates a BARE member account (no salon), activates '
        'the membership, issues a WORKING session → 201', () async {
      final invId = await invited('ama@b.com');
      google.claims(sub: 'sub-ama', email: 'ama@b.com');

      final res = await public_accept.onRequest(
        ctx(
          req(
            'POST',
            '/auth/provider/invitations/accept',
            body: {'invitationId': invId, 'idToken': 't'},
          ),
        ),
      );
      expect(res.statusCode, HttpStatus.created);
      final body = await res.json() as Map<String, dynamic>;
      final accountId = (body['provider'] as Map)['id'] as String;

      // Bare: no salon was auto-created (the R1 provisioning guard).
      final account = await auth.accountById(accountId);
      expect(account!.providerId, isNull);
      expect(account.businessName, isEmpty);

      // Membership is live and capability-resolving.
      expect(await resolver.can(accountId, 'p1', 'journal.manage.all'), isTrue);

      // The session is real: the refresh token rotates.
      final refreshed = await auth.refresh(body['refreshToken'] as String);
      expect(refreshed.ok, isTrue);
    });

    test(
      'an EXISTING account accepts under itself → 200 (no new account)',
      () async {
        final memberId = await activeMember('ama@b.com');
        // A second salon invites the same person.
        final reg2 = await auth.register(
          businessName: 'Studio Belle',
          businessType: 'salon',
          phoneNumber: '+2250500000072',
          email: 'owner2@x.pro',
          authProvider: 'google',
          googleSub: 'sub-owner2',
          providerId: 'p2',
        );
        await memberships.ensureOwner(
          providerId: 'p2',
          accountId: reg2.provider!.id,
          email: 'owner2@x.pro',
        );
        await subscriptions.chooseOffer(reg2.provider!.id, 'p2', 'pro');
        final inv2 = await team.invite(
          reg2.provider!.id,
          'p2',
          email: 'ama@b.com',
          role: 'reception',
        );
        final inv2Id = ((inv2.data! as Map)['id']) as String;

        final code = (await auth.requestEmailOtp('ama@b.com')).devCode!;
        final res = await public_accept.onRequest(
          ctx(
            req(
              'POST',
              '/auth/provider/invitations/accept',
              body: {
                'invitationId': inv2Id,
                'email': 'ama@b.com',
                'code': code,
              },
            ),
          ),
        );
        expect(res.statusCode, HttpStatus.ok);
        final body = await res.json() as Map<String, dynamic>;
        expect((body['provider'] as Map)['id'], memberId);
        expect(
          await resolver.can(memberId, 'p2', 'journal.manage.all'),
          isTrue,
        );
      },
    );

    test('T37 negatives: foreign email → 403 · expired → 409 · unknown id '
        '→ 404 · bad body → 400 · GET → 405', () async {
      final invId = await invited('ama@b.com');
      google.claims(sub: 'sub-evil', email: 'evil@b.com');
      final foreign = await public_accept.onRequest(
        ctx(
          req(
            'POST',
            '/auth/provider/invitations/accept',
            body: {'invitationId': invId, 'idToken': 't'},
          ),
        ),
      );
      expect(foreign.statusCode, HttpStatus.forbidden);

      now = DateTime.now().toUtc().subtract(const Duration(days: 8));
      final staleId = await invited('late@b.com');
      now = DateTime.now().toUtc();
      google.claims(sub: 'sub-late', email: 'late@b.com');
      final expired = await public_accept.onRequest(
        ctx(
          req(
            'POST',
            '/auth/provider/invitations/accept',
            body: {'invitationId': staleId, 'idToken': 't'},
          ),
        ),
      );
      expect(expired.statusCode, HttpStatus.conflict);
      expect((await expired.json() as Map)['error'], 'invitation_expired');

      google.claims(sub: 'sub-x', email: 'x@b.com');
      final unknown = await public_accept.onRequest(
        ctx(
          req(
            'POST',
            '/auth/provider/invitations/accept',
            body: {'invitationId': 'mem_ghost', 'idToken': 't'},
          ),
        ),
      );
      expect(unknown.statusCode, HttpStatus.notFound);

      final noId = await public_accept.onRequest(
        ctx(
          req(
            'POST',
            '/auth/provider/invitations/accept',
            body: {'idToken': 't'},
          ),
        ),
      );
      expect(noId.statusCode, HttpStatus.badRequest);

      final wrongVerb = await public_accept.onRequest(
        ctx(req('GET', '/auth/provider/invitations/accept')),
      );
      expect(wrongVerb.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('POST /auth/provider/invitations/decline', () {
    test(
      'email proof declines WITHOUT consuming the code; the row is gone',
      () async {
        final invId = await invited('ama@b.com');
        final code = (await auth.requestEmailOtp('ama@b.com')).devCode!;

        final res = await public_decline.onRequest(
          ctx(
            req(
              'POST',
              '/auth/provider/invitations/decline',
              body: {'invitationId': invId, 'email': 'ama@b.com', 'code': code},
            ),
          ),
        );
        expect(res.statusCode, HttpStatus.ok);
        expect((await res.json() as Map)['declined'], isTrue);
        expect(await memberships.byId(invId), isNull);

        // The probe left the code intact: a SECOND invitation can still be
        // accepted with it.
        final inv2 = await invited('ama@b.com', role: 'reception');
        final accepted = await public_accept.onRequest(
          ctx(
            req(
              'POST',
              '/auth/provider/invitations/accept',
              body: {'invitationId': inv2, 'email': 'ama@b.com', 'code': code},
            ),
          ),
        );
        expect(accepted.statusCode, HttpStatus.created);
      },
    );

    test(
      'a third party cannot clear someone else\'s invitation (T37)',
      () async {
        final invId = await invited('ama@b.com');
        google.claims(sub: 'sub-evil', email: 'evil@b.com');
        final res = await public_decline.onRequest(
          ctx(
            req(
              'POST',
              '/auth/provider/invitations/decline',
              body: {'invitationId': invId, 'idToken': 't'},
            ),
          ),
        );
        expect(res.statusCode, HttpStatus.forbidden);
        expect(await memberships.byId(invId), isNotNull);
      },
    );
  });

  group('authed invitation routes (/me/provider/invitations*)', () {
    test('GET lists the ACCOUNT-email cards; accept joins under the '
        'session; decline deletes', () async {
      // A bare member account with two pending invitations.
      final memberId = await activeMember('ama@b.com');
      final owner2 = await auth.register(
        businessName: 'Studio Belle',
        businessType: 'salon',
        phoneNumber: '+2250500000073',
        email: 'owner2@x.pro',
        authProvider: 'google',
        googleSub: 'sub-owner2',
        providerId: 'p2',
      );
      await memberships.ensureOwner(
        providerId: 'p2',
        accountId: owner2.provider!.id,
        email: 'owner2@x.pro',
      );
      await subscriptions.chooseOffer(owner2.provider!.id, 'p2', 'pro');
      final inv = await team.invite(
        owner2.provider!.id,
        'p2',
        email: 'ama@b.com',
        role: 'reception',
      );
      final invId = ((inv.data! as Map)['id']) as String;

      final list = await my_invitations.onRequest(
        ctx(req('GET', '/me/provider/invitations', token: tok(memberId))),
      );
      expect(list.statusCode, HttpStatus.ok);
      final cards = ((await list.json() as Map)['invitations'] as List)
          .cast<Map<String, dynamic>>();
      expect(cards.single['salonName'], 'Studio Belle');

      final accepted = await my_accept.onRequest(
        ctx(
          req(
            'POST',
            '/me/provider/invitations/$invId/accept',
            token: tok(memberId),
          ),
        ),
        invId,
      );
      expect(accepted.statusCode, HttpStatus.ok);
      expect(await resolver.can(memberId, 'p2', 'journal.manage.all'), isTrue);
    });

    test('the session email must MATCH the invitation (403) and anonymous '
        'callers stay out (401)', () async {
      final invId = await invited('ama@b.com');
      final strangerId = await activeMember('stranger@b.com');

      final mismatch = await my_accept.onRequest(
        ctx(
          req(
            'POST',
            '/me/provider/invitations/$invId/accept',
            token: tok(strangerId),
          ),
        ),
        invId,
      );
      expect(mismatch.statusCode, HttpStatus.forbidden);

      final anon = await my_invitations.onRequest(
        ctx(req('GET', '/me/provider/invitations')),
      );
      expect(anon.statusCode, HttpStatus.unauthorized);
    });

    test(
      'authed decline returns {declined: true} and deletes the row',
      () async {
        // A bare account holding a still-pending invitation.
        final invId = await invited('solo@b.com', role: 'reception');
        final code = (await auth.requestEmailOtp('solo@b.com')).devCode!;
        final created = await auth.createMemberAccount(
          email: 'solo@b.com',
          authProvider: 'email',
          emailCode: code,
        );
        final memberId = created.provider!.id;
        final res = await my_decline.onRequest(
          ctx(
            req(
              'POST',
              '/me/provider/invitations/$invId/decline',
              token: tok(memberId),
            ),
          ),
          invId,
        );
        expect(res.statusCode, HttpStatus.ok);
        expect((await res.json() as Map)['declined'], isTrue);
        expect(await memberships.byId(invId), isNull);
      },
    );
  });

  group('R6 — ?salonId= on the members family', () {
    /// The owner also owns p2 (owner row + its own live offer).
    Future<void> ownP2() async {
      await memberships.ensureOwner(
        providerId: 'p2',
        accountId: ownerId,
        email: 'owner@x.pro',
      );
      await subscriptions.chooseOffer(ownerId, 'p2', 'pro');
    }

    test('the roster and invites follow the SELECTED salon (and its '
        'seats)', () async {
      await ownP2();
      // Invite into p2 explicitly; p1's roster must not grow.
      final inviteRes = await members.onRequest(
        ctx(
          req(
            'POST',
            '/me/provider/members?salonId=p2',
            token: tok(ownerId),
            body: {'email': 'deux@x.pro', 'role': 'reception'},
          ),
        ),
      );
      expect(inviteRes.statusCode, HttpStatus.created);
      expect((await inviteRes.json() as Map)['providerId'], 'p2');

      final p2List = await members.onRequest(
        ctx(req('GET', '/me/provider/members?salonId=p2', token: tok(ownerId))),
      );
      final p2Items = (await p2List.json() as Map)['items'] as List;
      expect(p2Items.map((m) => (m as Map)['email']), contains('deux@x.pro'));

      final p1List = await members.onRequest(
        ctx(req('GET', '/me/provider/members', token: tok(ownerId))),
      );
      final p1Items = (await p1List.json() as Map)['items'] as List;
      expect(
        p1Items.map((m) => (m as Map)['email']),
        isNot(contains('deux@x.pro')),
      );
    });

    test('a forged salonId → a uniform 403 forbidden (T55)', () async {
      final res = await members.onRequest(
        ctx(req('GET', '/me/provider/members?salonId=p2', token: tok(ownerId))),
      );
      // ownerId holds no membership in p2 (no ownP2 here).
      expect(res.statusCode, HttpStatus.forbidden);
      expect((await res.json() as Map)['error'], 'forbidden');
    });

    test('a MEMBER without members.manage in the selected salon → 403 '
        '(the capability gate still runs downstream)', () async {
      // An active member of p1 selects p1 explicitly: the selection passes
      // (active membership) but the team read stays owner-only.
      final memberId = await activeMember('rec@x.pro');
      final res = await members.onRequest(
        ctx(
          req('GET', '/me/provider/members?salonId=p1', token: tok(memberId)),
        ),
      );
      expect(res.statusCode, HttpStatus.forbidden);
    });

    test('PATCH a salon-A member with ?salonId=B stays denied (the '
        'ownership cross-check)', () async {
      await ownP2();
      final aMemberId = await invited('cross@x.pro');
      final res = await member_item.onRequest(
        ctx(
          req(
            'PATCH',
            '/me/provider/members/$aMemberId?salonId=p2',
            token: tok(ownerId),
            body: {'role': 'reception'},
          ),
        ),
        aMemberId,
      );
      // The member row lives in p1; acting in p2 must not reach it.
      expect(res.statusCode, HttpStatus.notFound);
    });
  });
}
