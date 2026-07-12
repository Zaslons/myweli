import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/services/api/api_pro_team_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

/// Team access R3 — the REST team service: paths, bodies, expected status
/// codes and machine-code preservation (docs/design/team-access-r3-app.md).
void main() {
  Future<InMemorySessionStore> connectedStore() async {
    final store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
    return store;
  }

  Map<String, dynamic> memberJson({String status = 'invited'}) => {
        'id': 'mem_1',
        'providerId': 'p1',
        'email': 'ama@b.com',
        'role': 'manager',
        'status': status,
        'invitedAt': '2026-07-12T00:00:00.000Z',
        'resendsLeft': 3,
        'expired': false,
      };

  test('getMembers parses {items}; getMyInvitations parses {invitations}',
      () async {
    final svc = ApiProTeamService(
      client: MockClient((req) async {
        if (req.url.path == '/me/provider/members') {
          return http.Response(
            jsonEncode({
              'items': [memberJson()],
            }),
            200,
          );
        }
        expect(req.url.path, '/me/provider/invitations');
        return http.Response(
          jsonEncode({
            'invitations': [
              {
                'id': 'mem_2',
                'providerId': 'p2',
                'salonName': 'Studio Belle',
                'role': 'reception',
                'roleLabel': 'Réception',
                'expiresAt': '2026-07-19T00:00:00.000Z',
              },
            ],
          }),
          200,
        );
      }),
      baseUrl: 'http://x',
      providerSessionStore: await connectedStore(),
    );
    final members = await svc.getMembers();
    expect(members.data!.single.role, TeamRole.manager);

    final cards = await svc.getMyInvitations();
    expect(cards.data!.single.salonName, 'Studio Belle');
  });

  test('inviteMember POSTs the lowercased email and expects 201', () async {
    final svc = ApiProTeamService(
      client: MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/me/provider/members');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['email'], 'ama@b.com');
        expect(body['role'], 'staff');
        expect(body['artistId'], 'a1');
        return http.Response(jsonEncode(memberJson()), 201);
      }),
      baseUrl: 'http://x',
      providerSessionStore: await connectedStore(),
    );
    final res = await svc.inviteMember(
      email: ' Ama@B.com ',
      role: TeamRole.staff,
      artistId: 'a1',
    );
    expect(res.success, isTrue);
  });

  test('409/429 machine codes come through with the shared French copy',
      () async {
    var call = 0;
    final svc = ApiProTeamService(
      client: MockClient((req) async {
        call++;
        return call == 1
            ? http.Response(jsonEncode({'error': 'seat_limit'}), 409)
            : http.Response(jsonEncode({'error': 'invite_rate_limited'}), 429);
      }),
      baseUrl: 'http://x',
      providerSessionStore: await connectedStore(),
    );
    final seats = await svc.inviteMember(
      email: 'a@b.com',
      role: TeamRole.manager,
    );
    expect(seats.code, 'seat_limit');
    expect(seats.error, contains('places'));

    // The resend variant swaps the copy for the shared code.
    final resend = await svc.resendInvitation('mem_1');
    expect(resend.code, 'invite_rate_limited');
    expect(resend.error, contains('renvois'));
  });

  test('changeRole PATCHes; revoke/resend/accept POST the right paths',
      () async {
    final paths = <String>[];
    final svc = ApiProTeamService(
      client: MockClient((req) async {
        paths.add('${req.method} ${req.url.path}');
        return http.Response(jsonEncode(memberJson(status: 'active')), 200);
      }),
      baseUrl: 'http://x',
      providerSessionStore: await connectedStore(),
    );
    await svc.changeRole('mem_1', role: TeamRole.reception);
    await svc.revokeMember('mem_1');
    await svc.resendInvitation('mem_1');
    await svc.acceptInvitation('mem_9');
    expect(paths, [
      'PATCH /me/provider/members/mem_1',
      'POST /me/provider/members/mem_1/revoke',
      'POST /me/provider/members/mem_1/resend',
      'POST /me/provider/invitations/mem_9/accept',
    ]);
  });

  test('declineInvitation returns true on 200; not connected → error',
      () async {
    final svc = ApiProTeamService(
      client: MockClient((req) async {
        expect(req.url.path, '/me/provider/invitations/mem_9/decline');
        return http.Response(jsonEncode({'declined': true}), 200);
      }),
      baseUrl: 'http://x',
      providerSessionStore: await connectedStore(),
    );
    expect((await svc.declineInvitation('mem_9')).success, isTrue);

    final offline = ApiProTeamService(
      client: MockClient((_) async => http.Response('{}', 200)),
      baseUrl: 'http://x',
      providerSessionStore: InMemorySessionStore(),
    );
    expect((await offline.getMembers()).success, isFalse);
  });
}
