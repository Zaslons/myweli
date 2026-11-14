import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/admin/admin_provider_account_service.dart';
import 'package:myweli_backend/src/admin/audit_log_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/provider_account_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

import '../routes/admin/_middleware.dart' as admin_mw;
import '../routes/admin/provider-accounts/[id]/erase.dart' as erase_route;
import '../routes/admin/provider-accounts/lookup.dart' as lookup_route;
import 'http/observed.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// The loser of two concurrent erases (§4.3): both passed the account read,
/// the other one's identity delete won, and `deleteAccount` answers
/// `forbidden` — the code it gives an account that is not there.
class _RaceLost extends ProviderAccountService {
  _RaceLost(
    super.auth,
    super.providers,
    super.appointments,
    super.storage,
    super.memberships,
  );

  @override
  Future<({bool ok, String? error})> deleteAccount(String accountId) async =>
      (ok: false, error: 'forbidden');
}

/// B0.25's server half — a support erase of a Pro account, and the read-only
/// lookup that finds it (docs/design/admin-pro-account-erase.md §3, §4, §8).
///
/// In memory, through the REAL `ProviderAccountService`: the erase must be
/// `deleteAccount` itself — the demo lock, the bookings gate and every step —
/// so a hand-written subset here would be the defect, not the fixture. Every
/// request goes through the real `/admin` gate and the real outermost
/// middleware (`observed`), which is where a wrong JSON type becomes a 400.
void main() {
  final tokens = TokenService(secret: 'test-secret');
  final adminToken = tokens
      .issueAccessToken(subject: 'admin_1', role: 'admin')
      .token;

  late InMemoryProviderAuthRepository auth;
  late InMemoryProvidersRepository providers;
  late InMemoryAppointmentRepository appointments;
  late InMemoryMembershipRepository members;
  late InMemoryAuditLogRepository audit;
  late AdminProviderAccountService svc;

  const caseRef = 'MWP-7K2Q9D';
  const ownerEmail = 'owner@salon.test';

  /// A salon as an owner's erasure finds it: public, with the PERSON's
  /// numbers, address and map pin on it, and a deposit that needs the number.
  Map<String, dynamic> salon(String id) => {
    'id': id,
    'slug': 'salon-$id',
    'name': 'Salon $id',
    'status': 'active',
    'phoneNumber': '+2250700000101',
    'address': 'Rue des Jardins, Cocody',
    'latitude': 5.3599,
    'longitude': -3.9876,
    'whatsapp': '+2250700000102',
    'depositRequired': true,
    'depositMobileMoneyNumber': '+2250700000103',
    'depositMobileMoneyOperator': 'orange',
  };

  setUp(() {
    auth = InMemoryProviderAuthRepository(tokens: tokens, echoDevCode: true);
    providers = InMemoryProvidersRepository([
      for (final id in ['s1', 's2', 's3', 'sd']) salon(id),
    ]);
    appointments = InMemoryAppointmentRepository();
    members = InMemoryMembershipRepository();
    audit = InMemoryAuditLogRepository();
    final accounts = ProviderAccountService(
      auth,
      providers,
      appointments,
      FakeStorageService(),
      members,
      client: MockClient((_) async => http.Response('', 204)),
    );
    svc = AdminProviderAccountService(
      accounts,
      auth,
      members,
      providers,
      audit,
    );
  });

  /// An owner exactly as production makes one, with the whole blast radius:
  /// `s1` by the scalar link and its owner row, `s2` by an owner row only,
  /// and `s3`, where the account is only a MANAGER — never touched.
  Future<String> owner({String email = ownerEmail}) async {
    final reg = await auth.register(
      businessName: 'Salon Awa',
      businessType: 'salon',
      phoneNumber: '+2250700000100',
      email: email,
      authProvider: 'google',
      googleSub: 'sub-$email',
      providerId: 's1',
    );
    final id = reg.provider!.id;
    reg.provider!.name = 'Awa Koné';
    for (final s in ['s1', 's2']) {
      await members.ensureOwner(providerId: s, accountId: id, email: email);
    }
    final invite = await members.invite(
      providerId: 's3',
      email: email,
      role: 'manager',
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
    );
    await members.activate(invite!.id, id);
    return id;
  }

  /// The demo identity, owning `sd` — the store-review account (T69).
  Future<String> demo() async {
    final reg = await auth.register(
      businessName: 'Démo',
      businessType: 'salon',
      phoneNumber: '+2250700000200',
      email: kDemoProviderEmail,
      authProvider: 'google',
      googleSub: 'sub-demo',
      providerId: 'sd',
    );
    await members.ensureOwner(
      providerId: 'sd',
      accountId: reg.provider!.id,
      email: kDemoProviderEmail,
    );
    return reg.provider!.id;
  }

  Map<String, Object?> eraseBody({
    Object? confirmEmail = ownerEmail,
    Object? reason = 'support_no_sign_in',
    Object? ref = caseRef,
  }) => {'confirmEmail': ?confirmEmail, 'reason': ?reason, 'caseRef': ?ref};

  /// [body]: a Map/List is JSON-encoded, a String is sent as it is, null is
  /// no body at all.
  RequestContext ctx(
    String method,
    String path, {
    Object? body,
    String? bearer = 'admin',
  }) {
    final token = bearer == 'admin' ? adminToken : bearer;
    final c = _MockRequestContext();
    when(() => c.request).thenReturn(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {
          'Authorization': ?(token == null ? null : 'Bearer $token'),
          if (body != null) 'content-type': 'application/json',
        },
        body: body == null
            ? null
            : body is String
            ? body
            : jsonEncode(body),
      ),
    );
    when(() => c.read<TokenService>()).thenReturn(tokens);
    when(() => c.read<AdminProviderAccountService>()).thenReturn(svc);
    return c;
  }

  Future<Response> erase(
    String id, {
    String method = 'DELETE',
    Object? body,
    String? bearer = 'admin',
  }) {
    final c = ctx(
      method,
      '/admin/provider-accounts/$id/erase',
      body: body,
      bearer: bearer,
    );
    return observed(
      admin_mw.middleware((c) => erase_route.onRequest(c, id)),
      c,
    );
  }

  Future<Response> lookup({
    String method = 'POST',
    Object? body,
    String? bearer = 'admin',
  }) {
    final c = ctx(
      method,
      '/admin/provider-accounts/lookup',
      body: body,
      bearer: bearer,
    );
    return observed(admin_mw.middleware(lookup_route.onRequest), c);
  }

  Future<List<Map<String, dynamic>>> auditRows() async =>
      (await audit.list(pageSize: 50)).items;

  /// Nothing written: the identity, every salon as it was, no audit row.
  Future<void> expectNothingWritten(String? id) async {
    if (id != null) {
      expect(await auth.accountById(id), isNotNull, reason: 'the identity');
    }
    for (final s in ['s1', 's2', 's3', 'sd']) {
      final doc = (await providers.byId(s))!;
      expect(doc['status'], 'active', reason: '$s status');
      expect(doc['phoneNumber'], '+2250700000101', reason: '$s phone');
    }
    expect(await auditRows(), isEmpty, reason: 'no audit row');
  }

  // ---- 1. The verbs -------------------------------------------------------

  group('1 — one verb per route', () {
    for (final verb in const ['GET', 'POST', 'PUT', 'PATCH']) {
      test('$verb …/erase → 405, nothing erased', () async {
        final id = await owner();
        final r = await erase(
          id,
          method: verb,
          body: verb == 'GET' ? null : eraseBody(),
        );
        expect(r.statusCode, HttpStatus.methodNotAllowed);
        expect(await r.json(), {'error': 'method_not_allowed'});
        await expectNothingWritten(id);
      });
    }

    for (final verb in const ['GET', 'DELETE']) {
      test('$verb …/lookup → 405', () async {
        await owner();
        final r = await lookup(
          method: verb,
          body: verb == 'GET' ? null : {'email': ownerEmail},
        );
        expect(r.statusCode, HttpStatus.methodNotAllowed);
        expect(await r.json(), {'error': 'method_not_allowed'});
      });
    }
  });

  // ---- 2. The gate --------------------------------------------------------

  group('2 — behind the /admin gate (T17), per route', () {
    final provider = tokens.issueAccessToken(subject: 'p1', role: 'provider');
    final consumer = tokens.issueAccessToken(subject: 'u1', role: 'user');

    test('erase: no token → 401; a provider or a consumer token → 403; '
        'nothing erased', () async {
      final id = await owner();
      final anon = await erase(id, body: eraseBody(), bearer: null);
      expect(anon.statusCode, HttpStatus.unauthorized);
      expect(await anon.json(), {'error': 'unauthorized'});
      for (final t in [provider.token, consumer.token]) {
        final r = await erase(id, body: eraseBody(), bearer: t);
        expect(r.statusCode, HttpStatus.forbidden);
        expect(await r.json(), {'error': 'forbidden'});
      }
      await expectNothingWritten(id);
    });

    test('lookup: no token → 401; a provider or a consumer token → 403 — '
        'no address read back', () async {
      await owner();
      final anon = await lookup(body: {'email': ownerEmail}, bearer: null);
      expect(anon.statusCode, HttpStatus.unauthorized);
      expect(await anon.json(), {'error': 'unauthorized'});
      for (final t in [provider.token, consumer.token]) {
        final r = await lookup(body: {'email': ownerEmail}, bearer: t);
        expect(r.statusCode, HttpStatus.forbidden);
        expect(await r.json(), {'error': 'forbidden'});
      }
    });

    // An ADMIN's token the gate must refuse as if there were none: one
    // whose `exp` has passed — §10.2 step 6 reads a 401 as « the token
    // expired » and sends the owner back to sign in — and one signed with
    // another key. Built as test/auth/tokens_test.dart builds them.
    int epoch(Duration fromNow) =>
        DateTime.now().add(fromNow).millisecondsSinceEpoch ~/ 1000;
    String handBuilt(Duration expiresIn) => JWT({
      'role': 'admin',
      'exp': epoch(expiresIn),
    }, subject: 'admin_1').sign(SecretKey('test-secret'));
    final refused = {
      'an expired admin token': handBuilt(const Duration(hours: -1)),
      'an admin token signed with another secret': TokenService(
        secret: 'another-secret',
      ).issueAccessToken(subject: 'admin_1', role: 'admin').token,
    };
    for (final MapEntry(key: what, value: token) in refused.entries) {
      test('erase, $what → 401 unauthorized, nothing erased', () async {
        final id = await owner();
        final r = await erase(id, body: eraseBody(), bearer: token);
        expect(r.statusCode, HttpStatus.unauthorized);
        expect(await r.json(), {'error': 'unauthorized'});
        await expectNothingWritten(id);
      });

      test('lookup, $what → 401 unauthorized — no address read back', () async {
        await owner();
        final r = await lookup(body: {'email': ownerEmail}, bearer: token);
        expect(r.statusCode, HttpStatus.unauthorized);
        expect(await r.json(), {'error': 'unauthorized'});
      });
    }

    test('the control: the same hand-built admin token, unexpired, passes '
        'the gate — so the 401s above are the expiry and the key', () async {
      await owner();
      final r = await lookup(
        body: {'email': ownerEmail},
        bearer: handBuilt(const Duration(minutes: 10)),
      );
      expect(r.statusCode, HttpStatus.ok);
    });
  });

  // ---- 3, 4. The erase, and its audit row ---------------------------------

  group('3, 4 — the erase is deleteAccount itself, audited after it', () {
    test('204: the identity goes; each OWNED salon is hidden and loses the '
        'person\'s numbers and address; the member-only salon is '
        'untouched', () async {
      final id = await owner();

      final r = await erase(id, body: eraseBody());

      expect(r.statusCode, HttpStatus.noContent);
      expect(await auth.accountById(id), isNull, reason: 'the identity');
      expect(await auth.accountByEmail(ownerEmail), isNull);
      for (final s in ['s1', 's2']) {
        final doc = (await providers.byId(s))!;
        expect(doc['status'], 'draft', reason: '$s hidden');
        expect(doc['name'], 'Salon $s', reason: '$s keeps its name');
        expect(doc['phoneNumber'], '', reason: '$s phone');
        expect(doc['address'], '', reason: '$s address');
        // B0.22: the pin goes with the address (pro-deletion-erase-gaps §3.1).
        expect(doc['latitude'], isNull, reason: '$s pin latitude');
        expect(doc['longitude'], isNull, reason: '$s pin longitude');
        expect(doc['whatsapp'], isNull, reason: '$s WhatsApp');
        expect(doc['depositMobileMoneyNumber'], isNull, reason: '$s MoMo');
        expect(doc['depositMobileMoneyOperator'], isNull, reason: '$s op');
        expect(doc['depositRequired'], isFalse, reason: '$s deposit off');
      }
      final kept = (await providers.byId('s3'))!;
      expect(kept['status'], 'active', reason: 'member-only: untouched');
      expect(kept['phoneNumber'], '+2250700000101');
      expect(kept['address'], 'Rue des Jardins, Cocody');
      expect(kept['latitude'], 5.3599, reason: 'member-only: pin kept');
      expect(kept['longitude'], -3.9876);
      expect(kept['whatsapp'], '+2250700000102');
      expect(
        await members.listForAccount(id),
        isEmpty,
        reason: 'the memberships go with the identity',
      );
    });

    test('one provider_account.erase row: that id, that closed code, '
        '{caseRef} — and neither the e-mail nor a name', () async {
      final id = await owner();

      final r = await erase(
        id,
        body: eraseBody(reason: 'support_access_removed'),
      );
      expect(r.statusCode, HttpStatus.noContent);

      final rows = await auditRows();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['actorAdminId'], 'admin_1');
      expect(row['action'], 'provider_account.erase');
      expect(row['targetType'], 'provider_account');
      expect(row['targetId'], id);
      expect(row['reason'], 'support_access_removed');
      expect(row['metadata'], {'caseRef': caseRef});
      // A tombstone, not a copy: the audit log is kept with no limit.
      final serialised = jsonEncode(row).toLowerCase();
      for (final pii in [
        ownerEmail,
        'awa koné',
        'salon awa',
        '+2250700000100',
        'salon s1',
      ]) {
        expect(serialised, isNot(contains(pii)), reason: pii);
      }
    });
  });

  // ---- 5. The operator-error guard ----------------------------------------

  group('5 — confirmEmail against a wrongly copied id', () {
    test(
      'another address → 409 confirmation_mismatch, nothing written',
      () async {
        final id = await owner();
        final r = await erase(
          id,
          body: eraseBody(confirmEmail: 'someone@else.test'),
        );
        expect(r.statusCode, HttpStatus.conflict);
        expect(await r.json(), {'error': 'confirmation_mismatch'});
        await expectNothingWritten(id);
      },
    );

    test('a case and space variant of the stored address passes', () async {
      final id = await owner();
      final r = await erase(
        id,
        body: eraseBody(confirmEmail: '  Owner@SALON.Test '),
      );
      expect(r.statusCode, HttpStatus.noContent);
      expect(await auth.accountById(id), isNull);
    });

    test('no e-mail on file → 409 confirmation_mismatch, whatever is '
        'typed', () async {
      final id = await owner();
      (await auth.accountById(id))!.email = null;
      final r = await erase(id, body: eraseBody());
      expect(r.statusCode, HttpStatus.conflict);
      expect(await r.json(), {'error': 'confirmation_mismatch'});
      await expectNothingWritten(id);
    });
  });

  // ---- 6. The body --------------------------------------------------------

  group('6 — every field read before any is acted on', () {
    final invalidBody = <String, Object?>{
      'no body': null,
      'a JSON array': '[1, 2]',
      'a JSON string': '"owner@salon.test"',
      'not JSON': 'confirmEmail=owner@salon.test',
      'confirmEmail a number': eraseBody(confirmEmail: 5),
      'reason a list': eraseBody(reason: ['support_no_sign_in']),
      'caseRef an object': eraseBody(ref: {'v': caseRef}),
    };
    for (final MapEntry(:key, :value) in invalidBody.entries) {
      test('erase, $key → 400 invalid_body, nothing written', () async {
        final id = await owner();
        final r = await erase(id, body: value);
        expect(r.statusCode, HttpStatus.badRequest);
        expect(await r.json(), {'error': 'invalid_body'});
        await expectNothingWritten(id);
      });
    }

    final invalidInput = <String, Map<String, Object?>>{
      'confirmEmail missing': eraseBody(confirmEmail: null),
      'confirmEmail empty': eraseBody(confirmEmail: ''),
      'confirmEmail blank': eraseBody(confirmEmail: '   '),
      'reason missing': eraseBody(reason: null),
      'reason empty': eraseBody(reason: ''),
      'reason outside the set': eraseBody(reason: 'other'),
      'reason free text': eraseBody(reason: 'Demande de Mme Koné'),
      'caseRef missing': eraseBody(ref: null),
      'caseRef empty': eraseBody(ref: ''),
      'caseRef short': eraseBody(ref: 'MWP-7K2Q9'),
      'caseRef long': eraseBody(ref: 'MWP-7K2Q9DX'),
      'caseRef lower case': eraseBody(ref: 'mwp-7k2q9d'),
      'caseRef another prefix': eraseBody(ref: 'MWX-7K2Q9D'),
      'caseRef with a space': eraseBody(ref: 'MWP-7K2Q9D '),
    };
    for (final MapEntry(:key, :value) in invalidInput.entries) {
      test('erase, $key → 400 invalid_input, nothing written', () async {
        final id = await owner();
        final r = await erase(id, body: value);
        expect(r.statusCode, HttpStatus.badRequest);
        expect(await r.json(), {'error': 'invalid_input'});
        await expectNothingWritten(id);
      });
    }

    test('erase: an unknown key, free text included, is ignored — 204, and '
        'it is stored nowhere (the contract\'s body is open)', () async {
      final id = await owner();
      final r = await erase(
        id,
        body: {...eraseBody(), 'note': 'Demande de Mme Koné, 07 00 00 01 04'},
      );
      expect(r.statusCode, HttpStatus.noContent);
      final row = (await auditRows()).single;
      expect(row['metadata'], {'caseRef': caseRef});
      final serialised = jsonEncode(row);
      for (final typed in ['note', 'Koné', '07 00 00 01 04']) {
        expect(serialised, isNot(contains(typed)), reason: typed);
      }
    });

    test('erase: a bad body on an UNKNOWN id is still the 400 — the body is '
        'read first', () async {
      final r = await erase('nope', body: eraseBody(ref: 'x'));
      expect(r.statusCode, HttpStatus.badRequest);
      expect(await r.json(), {'error': 'invalid_input'});
    });

    final lookupInvalidBody = <String, Object?>{
      'no body': null,
      'a JSON array': '["owner@salon.test"]',
      'email a number': {'email': 5},
      'email a list': {
        'email': [ownerEmail],
      },
    };
    for (final MapEntry(:key, :value) in lookupInvalidBody.entries) {
      test('lookup, $key → 400 invalid_body', () async {
        await owner();
        final r = await lookup(body: value);
        expect(r.statusCode, HttpStatus.badRequest);
        expect(await r.json(), {'error': 'invalid_body'});
      });
    }

    final lookupInvalidInput = <String, Map<String, Object?>>{
      'email missing': {},
      'email empty': {'email': ''},
      'email blank': {'email': '   '},
      'email of two characters': {'email': 'a@'},
      'email with no @': {'email': 'owner.salon.test'},
      'email with two @': {'email': 'owner@salon@test'},
      'email over 254 characters': {'email': '${'a' * 250}@salon.test'},
    };
    for (final MapEntry(:key, :value) in lookupInvalidInput.entries) {
      test('lookup, $key → 400 invalid_input', () async {
        await owner();
        final r = await lookup(body: value);
        expect(r.statusCode, HttpStatus.badRequest);
        expect(await r.json(), {'error': 'invalid_input'});
      });
    }
  });

  // ---- 7–10. The refusals and the repeat ----------------------------------

  group('7–10 — the refusals, each under its own status, and the repeat', () {
    test('7: unknown id → 404 not_found, no row', () async {
      await owner();
      final r = await erase('provider_does_not_exist', body: eraseBody());
      expect(r.statusCode, HttpStatus.notFound);
      expect(await r.json(), {'error': 'not_found'});
      await expectNothingWritten(null);
    });

    test('8: a future booking in an owned salon → 409 future_bookings; the '
        'salon still public, no row — no admin override', () async {
      final id = await owner();
      await appointments.create({
        'userId': 'u1',
        'providerId': 's2',
        'status': 'pending',
        'appointmentDate': DateTime.now()
            .toUtc()
            .add(const Duration(days: 3))
            .toIso8601String(),
      });
      final r = await erase(id, body: eraseBody());
      expect(r.statusCode, HttpStatus.conflict);
      expect(await r.json(), {'error': 'future_bookings'});
      await expectNothingWritten(id);
    });

    test('9: the demo identity → 403 demo_account_locked (not the '
        'precedent\'s 404), nothing written, no row', () async {
      final id = await demo();
      final r = await erase(
        id,
        body: eraseBody(confirmEmail: kDemoProviderEmail),
      );
      expect(r.statusCode, HttpStatus.forbidden);
      expect(await r.json(), {'error': 'demo_account_locked'});
      await expectNothingWritten(id);
    });

    test('10: a second call → 404, and still one row', () async {
      final id = await owner();
      final first = await erase(id, body: eraseBody());
      expect(first.statusCode, HttpStatus.noContent);
      final again = await erase(id, body: eraseBody());
      expect(again.statusCode, HttpStatus.notFound);
      expect(await again.json(), {'error': 'not_found'});
      expect(await auditRows(), hasLength(1));
    });

    test('10b: a concurrent call that lost the identity delete — '
        'deleteAccount says `forbidden` — → 404 not_found, no row', () async {
      final id = await owner();
      svc = AdminProviderAccountService(
        _RaceLost(auth, providers, appointments, FakeStorageService(), members),
        auth,
        members,
        providers,
        audit,
      );
      final r = await erase(id, body: eraseBody());
      expect(r.statusCode, HttpStatus.notFound);
      expect(await r.json(), {'error': 'not_found'});
      expect(await auditRows(), isEmpty);
    });
  });

  // ---- 11. The wiring -----------------------------------------------------

  group('11 — one ProviderAccountService, and one call to it', () {
    /// Comments stripped BEFORE matching: the sources carry comments that
    /// quote the very strings these look for.
    String stripped(String path) => File(path)
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    final deps = stripped('lib/src/dependencies.dart');

    test('the admin service is constructed WITH the singleton — never a '
        'fresh ProviderAccountService, whose optional dependencies default '
        'to nothing', () {
      final open = RegExp(
        r'=\s*AdminProviderAccountService\(',
      ).firstMatch(deps);
      expect(open, isNotNull, reason: 'constructed in dependencies.dart');
      // Its ARGUMENTS, from after the opening parenthesis to the `);`.
      final arguments = deps.substring(open!.end, deps.indexOf(');', open.end));
      expect(
        arguments,
        matches(RegExp(r'^\s*providerAccountService\s*,')),
        reason: 'the singleton, as the first argument',
      );
      expect(
        arguments,
        isNot(matches(RegExp(r'\bProviderAccountService\('))),
        reason: 'never a fresh one built in place',
      );
      expect(
        RegExp(r'\bProviderAccountService\(').allMatches(deps),
        hasLength(1),
        reason: 'dependencies.dart builds ONE ProviderAccountService',
      );
    });

    test('the routes provide it, beside AdminUserService', () {
      expect(
        stripped('routes/_middleware.dart'),
        matches(
          RegExp(
            r'provider<AdminProviderAccountService>\(\s*'
            r'\(_\)\s*=>\s*adminProviderAccountService\s*,?\s*\)',
          ),
        ),
      );
    });

    test('in the service, exactly one deleteAccount( — on the '
        'ProviderAccountService field, none on the repository', () {
      final src = stripped('lib/src/admin/admin_provider_account_service.dart');
      final serviceField = RegExp(
        r'final\s+ProviderAccountService\s+(\w+)\s*;',
      ).firstMatch(src);
      final repoField = RegExp(
        r'final\s+ProviderAuthRepository\s+(\w+)\s*;',
      ).firstMatch(src);
      expect(serviceField, isNotNull, reason: 'a ProviderAccountService field');
      expect(repoField, isNotNull, reason: 'a ProviderAuthRepository field');
      expect(
        RegExp(r'deleteAccount\(').allMatches(src),
        hasLength(1),
        reason: 'one deletion call',
      );
      expect(
        src,
        matches(RegExp('${serviceField!.group(1)}\\s*\\.deleteAccount\\(')),
      );
      expect(
        src,
        isNot(matches(RegExp('${repoField!.group(1)}\\s*\\.deleteAccount\\('))),
      );
    });

    test('neither route names deleteAccount', () {
      for (final path in [
        'routes/admin/provider-accounts/[id]/erase.dart',
        'routes/admin/provider-accounts/lookup.dart',
      ]) {
        expect(stripped(path), isNot(contains('deleteAccount(')), reason: path);
      }
    });
  });

  // ---- 12. The lookup -----------------------------------------------------

  group('12 — the lookup: one exact address, the blast radius, no more', () {
    test('200 with exactly the five keys; owned salons and memberships as the '
        'erase will see them; no name, phone or KYC', () async {
      final id = await owner();

      final r = await lookup(body: {'email': '  OWNER@Salon.test '});
      expect(r.statusCode, HttpStatus.ok);
      final body = await r.json() as Map<String, dynamic>;
      expect(body.keys.toSet(), {
        'accountId',
        'email',
        'createdAt',
        'ownedSalons',
        'memberships',
      });
      expect(body['accountId'], id);
      expect(body['email'], ownerEmail, reason: 'the STORED address');
      expect(DateTime.tryParse(body['createdAt'] as String), isNotNull);
      expect(body['ownedSalons'], [
        {'id': 's1', 'name': 'Salon s1', 'status': 'active'},
        {'id': 's2', 'name': 'Salon s2', 'status': 'active'},
      ]);
      final memberships = (body['memberships'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        {for (final m in memberships) m['providerId']: m},
        {
          's1': {
            'providerId': 's1',
            'salonName': 'Salon s1',
            'role': 'owner',
            'status': 'active',
          },
          's2': {
            'providerId': 's2',
            'salonName': 'Salon s2',
            'role': 'owner',
            'status': 'active',
          },
          's3': {
            'providerId': 's3',
            'salonName': 'Salon s3',
            'role': 'manager',
            'status': 'active',
          },
        },
      );
      final text = jsonEncode(body);
      for (final absent in [
        'Awa Koné',
        '+2250700000100',
        'kycDocs',
        'phoneNumber',
        'verificationStatus',
        'Rue des Jardins',
      ]) {
        expect(text, isNot(contains(absent)), reason: absent);
      }

      // The salons the lookup names are exactly the ones the erase hides.
      final owned = {
        for (final s in body['ownedSalons'] as List) (s as Map)['id'],
      };
      expect(
        (await erase(id, body: eraseBody())).statusCode,
        HttpStatus.noContent,
      );
      for (final s in ['s1', 's2', 's3', 'sd']) {
        final status = (await providers.byId(s))!['status'];
        expect(
          status == 'draft',
          owned.contains(s),
          reason: '$s: hidden iff the lookup listed it as owned',
        );
      }
    });

    test('a salon linked by the scalar field ONLY — no owner row, as a '
        'provisioning that stopped between its two writes leaves it — is '
        'owned: the lookup lists it, and the erase hides it', () async {
      // `salon_provisioning_service.dart` calls `linkProvider`, then
      // `_ensureOwnerRow`: two writes, no transaction. `owner()` gives s1
      // both links, so there the scalar one never decides anything.
      final reg = await auth.register(
        businessName: 'Salon Awa',
        businessType: 'salon',
        phoneNumber: '+2250700000100',
        email: ownerEmail,
        authProvider: 'google',
        googleSub: 'sub-scalar',
        providerId: 's1',
      );
      final id = reg.provider!.id;
      await members.ensureOwner(
        providerId: 's2',
        accountId: id,
        email: ownerEmail,
      );
      expect(
        [for (final m in await members.listForAccount(id)) m.providerId],
        ['s2'],
        reason: 'the fixture: no row for s1',
      );

      final r = await lookup(body: {'email': ownerEmail});
      expect(r.statusCode, HttpStatus.ok);
      final body = await r.json() as Map<String, dynamic>;
      expect(
        {for (final s in body['ownedSalons'] as List) (s as Map)['id']},
        {'s1', 's2'},
        reason: 's1 is owned through the scalar link alone',
      );

      expect(
        (await erase(id, body: eraseBody())).statusCode,
        HttpStatus.noContent,
      );
      for (final s in ['s1', 's2', 's3', 'sd']) {
        final status = (await providers.byId(s))!['status'];
        expect(
          status,
          s == 's1' || s == 's2' ? 'draft' : 'active',
          reason: '$s: hidden iff owned',
        );
      }
    });

    test('an exact match only: a prefix, another address, an erased one → '
        '404 not_found', () async {
      final id = await owner();
      for (final email in [
        'owner@salon.tes',
        'wner@salon.test',
        'personne@myweli.test',
      ]) {
        final r = await lookup(body: {'email': email});
        expect(r.statusCode, HttpStatus.notFound, reason: email);
        expect(await r.json(), {'error': 'not_found'});
      }
      await erase(id, body: eraseBody());
      final gone = await lookup(body: {'email': ownerEmail});
      expect(gone.statusCode, HttpStatus.notFound);
    });

    test('read-only: no audit row, nothing changed', () async {
      final id = await owner();
      expect((await lookup(body: {'email': ownerEmail})).statusCode, 200);
      await expectNothingWritten(id);
    });
  });
}
