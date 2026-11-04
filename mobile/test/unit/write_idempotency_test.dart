import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/core/utils/submission_key.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/session.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/services/api/api_appointment_service.dart';
import 'package:myweli/services/api/api_pro_clients_service.dart';
import 'package:myweli/services/api/api_pro_service.dart';
import 'package:myweli/services/api/api_pro_team_service.dart';
import 'package:myweli/services/api/idempotent_write.dart';
import 'package:myweli/services/interfaces/session_store.dart';

/// docs/design/write-idempotency.md §4 — the app's four creating writes carry
/// one `Idempotency-Key` per submission; an answer lost on the way (nothing
/// came back, or a gateway answered) is asked again ONCE, at once, with the
/// SAME key, without a word: the server replays what it did. A 2xx whose body
/// was lost is asked again too. « Already running » waits, three times at
/// most. Still nothing: « Pas de connexion. Réessayez. », and « Réessayer »
/// sends the same key again.

/// One write's answers, in order (the last repeats). `null` = nothing came
/// back (the connection dropped).
class _Server {
  _Server(this.answers);
  final List<http.Response?> answers;
  final keys = <String?>[];
  int _i = 0;

  late final client = MockClient((req) async {
    keys.add(req.headers[kIdempotencyKeyHeader]);
    final a = answers[_i < answers.length ? _i : answers.length - 1];
    _i++;
    if (a == null) throw http.ClientException('connection reset');
    return a;
  });
}

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status);

final _appt = {
  'id': 'a1',
  'userId': 'u1',
  'providerId': 'provider1',
  'serviceIds': ['service1'],
  'appointmentDate': DateTime.utc(2026, 10, 22, 10).toIso8601String(),
  'status': 'pending',
  'totalPrice': 15000,
  'depositAmount': 5000,
  'balanceDue': 10000,
  'createdAt': DateTime.utc(2026, 10, 21).toIso8601String(),
};

Future<InMemorySessionStore> _consumer() async {
  final store = InMemorySessionStore();
  await store.save(
    jsonEncode(
      Session(
        token: 'tok',
        user: User(
          id: 'u1',
          phoneNumber: '+2250700000000',
          createdAt: DateTime.utc(2026),
        ),
      ).toJson(),
    ),
  );
  return store;
}

Future<InMemorySessionStore> _pro() async {
  final store = InMemorySessionStore();
  await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
  return store;
}

void main() {
  final waits = <Duration>[];
  setUp(() {
    waits.clear();
    idempotencyWait = (d) async => waits.add(d);
  });
  tearDown(() => idempotencyWait = Future.delayed);

  group('SubmissionKey — one key per submission of a form', () {
    test('the same form → the same key; a changed form → a new one', () {
      final k = SubmissionKey();
      final first = k.forForm({'slot': '10:00'});
      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{8,128}$')));
      expect(k.forForm({'slot': '10:00'}), first);
      expect(k.forForm({'slot': '11:00'}), isNot(first));
      expect(
        k.forForm({'slot': '10:00'}),
        isNot(first),
        reason: 'back to the first form: a new submission',
      );
    });

    test('after a success the next submission takes a new key', () {
      final k = SubmissionKey();
      final first = k.forForm({'body': 'OK'});
      k.settle();
      expect(k.forForm({'body': 'OK'}), isNot(first));
    });
  });

  group('the client’s booking', () {
    Future<(ApiAppointmentService, _Server)> svc(
      List<http.Response?> answers,
    ) async {
      final s = _Server(answers);
      return (
        ApiAppointmentService(
          client: s.client,
          baseUrl: 'http://x',
          sessionStore: await _consumer(),
        ),
        s,
      );
    }

    Future<ApiResponse<Appointment>> book(
      ApiAppointmentService a, {
      String? key = 'k-000001',
    }) => a.bookAppointment(
      providerId: SalonId('provider1'),
      serviceIds: ['service1'],
      appointmentDateTime: DateTime.utc(2026, 10, 22, 10),
      idempotencyKey: key,
    );

    test('the key crosses; an answer that arrives is the answer', () async {
      final (a, s) = await svc([_json(201, _appt)]);
      final r = await book(a);
      expect(r.success, isTrue);
      expect(s.keys, ['k-000001']);
    });

    test(
      'nothing came back → asked again ONCE with the same key → the booking, deposit included',
      () async {
        final (a, s) = await svc([null, _json(201, _appt)]);
        final r = await book(a);
        expect(r.success, isTrue);
        expect(r.data!.depositAmount, 5000);
        expect(s.keys, ['k-000001', 'k-000001']);
      },
    );

    test('a gateway’s answer (502, 503, 504) is a lost answer too', () async {
      for (final status in [502, 503, 504]) {
        final (a, s) = await svc([
          http.Response('<html>', status),
          _json(201, _appt),
        ]);
        expect((await book(a)).success, isTrue, reason: '$status');
        expect(s.keys, hasLength(2));
      }
    });

    test(
      'lost twice → « Pas de connexion. Réessayez. » (network), never a third try',
      () async {
        final (a, s) = await svc([null]);
        final r = await book(a);
        expect(r.success, isFalse);
        expect(r.error, 'Pas de connexion. Réessayez.');
        expect(r.code, 'network');
        expect(s.keys, hasLength(2));
      },
    );

    test('a 2xx whose body was lost → asked again → the booking', () async {
      final (a, s) = await svc([
        http.Response('{"id":', 201),
        _json(201, _appt),
      ]);
      expect((await book(a)).success, isTrue);
      expect(s.keys, ['k-000001', 'k-000001']);
    });

    test(
      'a 2xx without its body twice → « Pas de connexion » — the retry replays it',
      () async {
        final (a, s) = await svc([http.Response('', 201)]);
        final r = await book(a);
        expect(r.success, isFalse);
        expect(r.code, 'network');
        expect(s.keys, hasLength(2));
      },
    );

    test(
      '« already running » → wait, ask again with the same key, three times at most',
      () async {
        final busy = _json(409, {'error': 'request_in_progress'});
        final (a, s) = await svc([busy, busy, _json(201, _appt)]);
        expect((await book(a)).success, isTrue);
        expect(waits, hasLength(2));
        expect(waits.every((d) => d > Duration.zero), isTrue);
        expect(s.keys.toSet(), {'k-000001'});

        waits.clear();
        final (b, t) = await svc([busy]);
        final r = await book(b);
        expect(r.code, 'network', reason: 'still running: nothing answered');
        expect(t.keys, hasLength(1 + kMaxInProgressWaits));
      },
    );

    test('a real refusal is the answer — never asked again', () async {
      for (final (status, code) in [
        (409, 'slot_unavailable'),
        (400, 'invalid_input'),
        (500, 'internal'),
      ]) {
        final (a, s) = await svc([
          _json(status, {'error': code}),
        ]);
        final r = await book(a);
        expect(r.success, isFalse);
        expect(s.keys, hasLength(1), reason: code);
      }
    });

    test(
      'no key: the write goes as before — no header, no second try',
      () async {
        final (a, s) = await svc([null]);
        await book(a, key: null);
        expect(s.keys, [null]);
      },
    );
  });

  group('the salon’s three writes', () {
    test(
      '« Créer » (a booking for a client): the key, and one re-ask',
      () async {
        final s = _Server([null, _json(201, _appt)]);
        final svc = ApiProService(
          client: s.client,
          baseUrl: 'http://x',
          providerSessionStore: await _pro(),
        );
        final r = await svc.createManualBooking(
          providerId: SalonId('provider1'),
          serviceIds: ['service1'],
          appointmentDateTime: DateTime.utc(2026, 10, 22, 10),
          idempotencyKey: 'm-000001',
        );
        expect(r.success, isTrue);
        expect(s.keys, ['m-000001', 'm-000001']);
      },
    );

    test('a note: the key, and one re-ask', () async {
      final s = _Server([
        http.Response('', 201),
        _json(201, {
          'id': 'n1',
          'body': 'Allergie',
          'authorName': 'Moi',
          'createdAt': DateTime.utc(2026, 10, 21).toIso8601String(),
        }),
      ]);
      final svc = ApiProClientsService(
        client: s.client,
        baseUrl: 'http://x',
        providerSessionStore: await _pro(),
      );
      final r = await svc.addNote(
        SalonId('provider1'),
        'c1',
        'Allergie',
        idempotencyKey: 'n-000001',
      );
      expect(r.success, isTrue);
      expect(r.data!.id, 'n1');
      expect(s.keys, ['n-000001', 'n-000001']);
    });

    test('an invitation: the key, and one re-ask', () async {
      final s = _Server([
        http.Response('', 502),
        _json(201, {
          'id': 'mem1',
          'providerId': 'provider1',
          'email': 'mgr@salon.ci',
          'role': 'manager',
          'status': 'invited',
          'invitedAt': DateTime.utc(2026, 10, 21).toIso8601String(),
        }),
      ]);
      final svc = ApiProTeamService(
        client: s.client,
        baseUrl: 'http://x',
        providerSessionStore: await _pro(),
      );
      final r = await svc.inviteMember(
        email: 'mgr@salon.ci',
        role: TeamRole.manager,
        idempotencyKey: 'i-000001',
      );
      expect(r.success, isTrue);
      expect(s.keys, ['i-000001', 'i-000001']);
    });

    // §8: no new words on the salon's side — each keeps the sentence its
    // service already says when nothing answers.
    test('lost twice: each says its own « nothing answered »', () async {
      final store = await _pro();
      final s = _Server([null]);
      final pro = ApiProService(
        client: s.client,
        baseUrl: 'http://x',
        providerSessionStore: store,
      );
      final clients = ApiProClientsService(
        client: s.client,
        baseUrl: 'http://x',
        providerSessionStore: store,
      );
      final team = ApiProTeamService(
        client: s.client,
        baseUrl: 'http://x',
        providerSessionStore: store,
      );
      final booked = await pro.createManualBooking(
        providerId: SalonId('provider1'),
        serviceIds: ['service1'],
        appointmentDateTime: DateTime.utc(2026, 10, 22, 10),
        idempotencyKey: 'm-000001',
      );
      expect(booked.success, isFalse);
      // One sentence for « nothing answered » since batch 3 (B3.2).
      expect(booked.error, 'Pas de connexion. Réessayez.');
      for (final r in [
        await clients.addNote(
          SalonId('provider1'),
          'c1',
          'x',
          idempotencyKey: 'n-000001',
        ),
        await team.inviteMember(
          email: 'mgr@salon.ci',
          role: TeamRole.manager,
          idempotencyKey: 'i-000001',
        ),
      ]) {
        expect(r.success, isFalse);
        expect(r.error, 'Pas de connexion. Réessayez.');
      }
      expect(s.keys, hasLength(6));
    });
  });
}
