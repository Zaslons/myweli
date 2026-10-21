import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/idempotency/idempotency_store.dart';
import 'package:myweli_backend/src/notifications/notifications_repository.dart';
import 'package:myweli_backend/src/provider_account_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/push/device_token_repository.dart';
import 'package:myweli_backend/src/site/site_rebuild_notifier.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

class _MockProviders extends Mock implements ProvidersRepository {}

class _MockAppointments extends Mock implements AppointmentRepository {}

/// For the rows the in-memory repository cannot hold: it normalises every
/// address at registration, so a stored variant (or no address at all) has
/// to be handed to the service directly.
class _MockAuth extends Mock implements ProviderAuthRepository {}

/// Records what it was asked to do, so a call site can be observed.
class _RecordingNotifier implements SiteRebuildNotifier {
  final reasons = <String>[];
  @override
  Future<void> requestRebuild(String reason) async => reasons.add(reason);
}

/// T53 — the storage-erasure half of account deletion: the KYC objects go
/// with the account (own-prefix only; a storage hiccup never blocks).
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryProviderAuthRepository auth;
  late _MockProviders providers;
  late _MockAppointments appointments;

  setUp(() {
    auth = InMemoryProviderAuthRepository(tokens: tokens, echoDevCode: true);
    providers = _MockProviders();
    appointments = _MockAppointments();
    when(
      () => appointments.listForProvider(any()),
    ).thenAnswer((_) async => const []);
    when(
      () => providers.setStatus(any(), any()),
    ).thenAnswer((_) async => {'id': 'p1', 'status': 'draft'});
    // The erasure fire is GUARDED on the prior status, so the service now
    // reads each salon before unpublishing it. Live by default in this file;
    // the all-draft negative overrides per test.
    when(
      () => providers.byId(any()),
    ).thenAnswer((_) async => {'id': 'p1', 'status': 'active'});
  });

  Future<String> registerWithKyc({required List<String> keys}) async {
    final reg = await auth.register(
      businessName: 'X',
      businessType: 'salon',
      phoneNumber: '+2250700000070',
      email: 'del@test.pro',
      authProvider: 'google',
      googleSub: 'del-sub',
      providerId: 'p1',
    );
    final id = reg.provider!.id;
    await auth.submitKyc(id, [
      for (final k in keys) {'key': k, 'type': 'id_front'},
    ]);
    return id;
  }

  test('deletes each own-prefix KYC object then the account', () async {
    final deleted = <String>[];
    final memberships = InMemoryMembershipRepository();
    final service = ProviderAccountService(
      auth,
      providers,
      appointments,
      FakeStorageService(),
      memberships,
      client: MockClient((req) async {
        expect(req.method, 'DELETE');
        deleted.add(req.url.path);
        return http.Response('', 204);
      }),
    );
    final id = await registerWithKyc(
      keys: ['kyc/PLACEHOLDER/a.jpg', 'kyc/PLACEHOLDER/b.pdf'],
    );
    // Re-submit with the real account id in the prefix.
    await auth.submitKyc(id, [
      {'key': 'kyc/$id/a.jpg', 'type': 'id_front'},
      {'key': 'kyc/$id/b.pdf', 'type': 'id_back'},
      // A foreign / malformed key must be SKIPPED (defense in depth).
      {'key': 'kyc/other-account/c.jpg', 'type': 'selfie'},
    ]);

    // Module `access` (drift §2.3-2): a membership must never outlive its
    // account.
    await memberships.ensureOwner(
      providerId: 'p1',
      accountId: id,
      email: 'del@test.pro',
    );

    final r = await service.deleteAccount(id);
    expect(r.ok, isTrue);
    expect(deleted, hasLength(2));
    expect(deleted[0], contains('kyc/$id/a.jpg'));
    expect(deleted[1], contains('kyc/$id/b.pdf'));
    expect(await auth.accountById(id), isNull);
    verify(() => providers.setStatus('p1', 'draft')).called(1);
    // Deleted, not revoked — in Postgres a revoked row still references the
    // identity (docs/design/backend-provider-deletion-member-fk.md).
    expect(await memberships.listForAccount(id), isEmpty);
    expect(await memberships.listForProvider('p1'), isEmpty);
  });

  test('a deleted SALON stops receiving push too', () async {
    // The identical defect the consumer side had (L1, T59): the pro deletion
    // settled the agenda, unpublished the salons and erased the KYC documents,
    // and never touched `device_tokens` or `notifications` — so the phone of a
    // deleted salon owner kept ringing. The repository verbs are role-agnostic;
    // this is the same two lines, on the other side of the boundary.
    final devices = InMemoryDeviceTokenRepository();
    final notifications = InMemoryNotificationsRepository();
    final service = ProviderAccountService(
      auth,
      providers,
      appointments,
      FakeStorageService(),
      InMemoryMembershipRepository(),
      devices: devices,
      notifications: notifications,
      client: MockClient((_) async => http.Response('', 204)),
    );
    final id = await registerWithKyc(keys: []);
    await devices.upsert(
      token: 'tok-pro',
      userId: id,
      role: 'provider',
      platform: 'android',
    );
    await devices.upsert(
      token: 'tok-other',
      userId: 'someone-else',
      role: 'provider',
      platform: 'ios',
    );
    await notifications.add(
      userId: id,
      type: 'booking_new',
      title: 'Nouvelle réservation',
      body: 'Awa, 14:00',
    );
    await notifications.add(
      userId: 'someone-else',
      type: 'booking_new',
      title: 'Nouvelle réservation',
      body: 'Kouassi, 15:00',
    );

    expect((await service.deleteAccount(id)).ok, isTrue);

    expect(await devices.tokensForUser(id), isEmpty);
    expect(await notifications.listForUser(id, limit: 10), isEmpty);
    // The bystander salon is untouched — the same predicate that would erase
    // the fleet passes every assertion above.
    expect(await devices.tokensForUser('someone-else'), hasLength(1));
    expect(
      await notifications.listForUser('someone-else', limit: 10),
      hasLength(1),
    );
  });

  test('a deleted SALON account takes its kept answers with it', () async {
    // docs/design/write-idempotency.md §3, §6: a manual booking's kept answer
    // holds the client's name and phone for 24 h — it goes with the account.
    final idem = InMemoryIdempotencyStore();
    final service = ProviderAccountService(
      auth,
      providers,
      appointments,
      FakeStorageService(),
      InMemoryMembershipRepository(),
      idempotency: idem,
      client: MockClient((_) async => http.Response('', 204)),
    );
    final id = await registerWithKyc(keys: []);
    for (final acc in [id, 'someone-else']) {
      await idem.claim(
        accountId: acc,
        route: '/providers/p1/appointments',
        key: 'key-00000001',
        fingerprint: 'f',
      );
      await idem.complete(
        accountId: acc,
        route: '/providers/p1/appointments',
        key: 'key-00000001',
        status: 201,
        body: '{"clientPhone":"+2250700000001"}',
      );
    }

    expect((await service.deleteAccount(id)).ok, isTrue);

    Future<IdempotencyClaim> again(String acc) => idem.claim(
      accountId: acc,
      route: '/providers/p1/appointments',
      key: 'key-00000001',
      fingerprint: 'f',
    );
    expect(await again(id), isA<ClaimReserved>(), reason: 'erased');
    expect(await again('someone-else'), isA<ClaimReplay>());
  });

  test('a storage failure never blocks the account erasure', () async {
    final service = ProviderAccountService(
      auth,
      providers,
      appointments,
      FakeStorageService(),
      InMemoryMembershipRepository(),
      client: MockClient((req) async => throw Exception('storage down')),
    );
    final id = await registerWithKyc(keys: []);
    await auth.submitKyc(id, [
      {'key': 'kyc/$id/a.jpg', 'type': 'id_front'},
    ]);

    final r = await service.deleteAccount(id);
    expect(r.ok, isTrue);
    expect(await auth.accountById(id), isNull);
  });

  test('future bookings gate fires before any erasure', () async {
    final service = ProviderAccountService(
      auth,
      providers,
      appointments,
      FakeStorageService(),
      InMemoryMembershipRepository(),
      client: MockClient((req) async => fail('no storage call expected')),
    );
    final id = await registerWithKyc(keys: []);
    final future = DateTime.now()
        .toUtc()
        .add(const Duration(days: 2))
        .toIso8601String();
    when(() => appointments.listForProvider('p1')).thenAnswer(
      (_) async => [
        {'status': 'pending', 'appointmentDate': future},
      ],
    );

    final r = await service.deleteAccount(id);
    expect(r.ok, isFalse);
    expect(r.error, 'future_bookings');
    expect(await auth.accountById(id), isNotNull);
    verifyNever(() => providers.setStatus(any(), any()));
  });

  group('R6 — deletion across ALL owned salons (T53)', () {
    late InMemoryMembershipRepository memberships;
    late ProviderAccountService service;
    late _RecordingNotifier rebuild;

    setUp(() {
      memberships = InMemoryMembershipRepository();
      rebuild = _RecordingNotifier();
      service = ProviderAccountService(
        auth,
        providers,
        appointments,
        FakeStorageService(),
        memberships,
        client: MockClient((req) async => http.Response('', 204)),
        rebuild: rebuild,
      );
    });

    test('erasing an owner with a LIVE salon asks for ONE rebuild', () async {
      final id = await registerWithKyc(keys: []);
      final r = await service.deleteAccount(id);
      expect(r.ok, isTrue);
      expect(
        rebuild.reasons,
        ['account.erased'],
        reason:
            'the slug left the prebuilt set — one erasure, one build, '
            'however many salons the account owned',
      );
    });

    test('an all-draft owner asks for NO rebuild', () async {
      // The guard this pins: draft → draft changes nothing in the prebuilt
      // set, and an unguarded fire would recreate the build-nothing-but-
      // burn-the-cooldown defect this slice removed from salon creation.
      when(
        () => providers.byId(any()),
      ).thenAnswer((_) async => {'id': 'p1', 'status': 'draft'});
      final id = await registerWithKyc(keys: []);
      final r = await service.deleteAccount(id);
      expect(r.ok, isTrue);
      expect(rebuild.reasons, isEmpty);
    });

    test('a future booking in the SECOND owned salon blocks the '
        'deletion', () async {
      final id = await registerWithKyc(keys: []);
      await memberships.ensureOwner(
        providerId: 'p2',
        accountId: id,
        email: 'del@test.pro',
      );
      final future = DateTime.now()
          .toUtc()
          .add(const Duration(days: 2))
          .toIso8601String();
      when(
        () => appointments.listForProvider('p1'),
      ).thenAnswer((_) async => const []);
      when(() => appointments.listForProvider('p2')).thenAnswer(
        (_) async => [
          {'status': 'confirmed', 'appointmentDate': future},
        ],
      );

      final r = await service.deleteAccount(id);
      expect(r.ok, isFalse);
      expect(r.error, 'future_bookings');
      verifyNever(() => providers.setStatus(any(), any()));
    });

    test('both owned salons unpublish; a member-only salon stays '
        'untouched', () async {
      final id = await registerWithKyc(keys: []);
      await memberships.ensureOwner(
        providerId: 'p2',
        accountId: id,
        email: 'del@test.pro',
      );
      // A salon where the account is only a manager.
      final inv = await memberships.invite(
        providerId: 'p_managed',
        email: 'del@test.pro',
        role: 'manager',
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      await memberships.activate(inv!.id, id);

      final r = await service.deleteAccount(id);
      expect(r.ok, isTrue);
      verify(() => providers.setStatus('p1', 'draft')).called(1);
      verify(() => providers.setStatus('p2', 'draft')).called(1);
      verifyNever(() => providers.setStatus('p_managed', any()));
    });
  });

  // The store-review demo account cannot delete itself (T69). Its credential
  // is printed in both stores' review notes, the Pro app offers account
  // deletion, and nothing recreates the identity.
  // Design: docs/design/demo-account-deletion-lock.md.
  group('T69 — the demo identity cannot delete itself', () {
    late InMemoryMembershipRepository memberships;
    late InMemoryDeviceTokenRepository devices;
    late InMemoryNotificationsRepository notifications;
    late _RecordingNotifier rebuild;
    late List<String> storageCalls;

    ProviderAccountService serviceOver(ProviderAuthRepository repository) =>
        ProviderAccountService(
          repository,
          providers,
          appointments,
          FakeStorageService(),
          memberships,
          devices: devices,
          notifications: notifications,
          client: MockClient((req) async {
            storageCalls.add('${req.method} ${req.url.path}');
            return http.Response('', 204);
          }),
          rebuild: rebuild,
        );

    setUp(() {
      memberships = InMemoryMembershipRepository();
      devices = InMemoryDeviceTokenRepository();
      notifications = InMemoryNotificationsRepository();
      rebuild = _RecordingNotifier();
      storageCalls = [];
    });

    /// One row in every place a deletion writes to, for the account behind
    /// [email] — registered through the real path. The demo test and its
    /// control call this with nothing else changed, so the address is the
    /// only difference between a refusal and an erasure.
    Future<({String id, String refreshToken})> populated(String email) async {
      final reg = await auth.register(
        businessName: 'Maison Nala',
        businessType: 'salon',
        phoneNumber: '+2250700000069',
        email: email,
        authProvider: 'google',
        googleSub: 'sub-of-$email',
        providerId: 'p1',
      );
      final id = reg.provider!.id;
      await auth.submitKyc(id, [
        {'key': 'kyc/$id/id.jpg', 'type': 'id_front'},
      ]);
      await memberships.ensureOwner(
        providerId: 'p1',
        accountId: id,
        email: email,
      );
      await devices.upsert(
        token: 'tok-$id',
        userId: id,
        role: 'provider',
        platform: 'ios',
      );
      await notifications.add(
        userId: id,
        type: 'booking_new',
        title: 'Nouvelle réservation',
        body: 'Awa, 14:00',
      );
      return (id: id, refreshToken: reg.tokens!.refreshToken);
    }

    Future<void> expectNothingMutated(String id, String refreshToken) async {
      final account = await auth.accountById(id);
      expect(account, isNotNull, reason: 'the account still exists');
      expect(account!.kycDocs, hasLength(1), reason: 'the KYC rows');
      expect(storageCalls, isEmpty, reason: 'no KYC object was erased');
      verifyNever(() => providers.setStatus(any(), any()));
      expect(rebuild.reasons, isEmpty, reason: 'no rebuild was asked for');
      final rows = await memberships.listForAccount(id);
      expect(rows.single.role, 'owner');
      expect(rows.single.status, 'active', reason: 'the membership');
      expect(await devices.tokensForUser(id), hasLength(1));
      expect(await notifications.listForUser(id, limit: 10), hasLength(1));
      expect(
        (await auth.refresh(refreshToken)).ok,
        isTrue,
        reason: 'the session is alive — the reviewer stays signed in',
      );
    }

    void upcomingBookingIn(String providerId) {
      final future = DateTime.now()
          .toUtc()
          .add(const Duration(days: 2))
          .toIso8601String();
      when(() => appointments.listForProvider(providerId)).thenAnswer(
        (_) async => [
          {'status': 'confirmed', 'appointmentDate': future},
        ],
      );
    }

    test('refused with demo_account_locked, and nothing is mutated', () async {
      final demo = await populated(kDemoProviderEmail);

      final r = await serviceOver(auth).deleteAccount(demo.id);

      expect(r.ok, isFalse);
      expect(r.error, 'demo_account_locked');
      await expectNothingMutated(demo.id, demo.refreshToken);
    });

    test('CONTROL: the same rows under another address are erased, exactly '
        'as before', () async {
      // The oracle has to discriminate: everything `expectNothingMutated`
      // reads must come back DIFFERENT here, or the refusal test above
      // proves nothing about the demo identity.
      final owner = await populated('owner@salon.test');

      final r = await serviceOver(auth).deleteAccount(owner.id);

      expect(r.ok, isTrue);
      expect(r.error, isNull);
      expect(await auth.accountById(owner.id), isNull);
      expect(storageCalls.single, startsWith('DELETE '));
      expect(storageCalls.single, endsWith('kyc/${owner.id}/id.jpg'));
      verify(() => providers.setStatus('p1', 'draft')).called(1);
      expect(rebuild.reasons, ['account.erased']);
      expect(await memberships.listForAccount(owner.id), isEmpty);
      expect(await devices.tokensForUser(owner.id), isEmpty);
      expect(await notifications.listForUser(owner.id, limit: 10), isEmpty);
      expect((await auth.refresh(owner.refreshToken)).ok, isFalse);
    });

    test('the same refusal WITH upcoming bookings — the lock answers before '
        'the agenda gate', () async {
      // The weekly reset gives the demo salon upcoming bookings for about
      // two days out of seven. The answer must not depend on the day.
      final demo = await populated(kDemoProviderEmail);
      upcomingBookingIn('p1');

      final r = await serviceOver(auth).deleteAccount(demo.id);

      expect(r.error, 'demo_account_locked');
      await expectNothingMutated(demo.id, demo.refreshToken);
    });

    test('CONTROL: another account with upcoming bookings is still asked to '
        'settle them', () async {
      final owner = await populated('owner@salon.test');
      upcomingBookingIn('p1');

      final r = await serviceOver(auth).deleteAccount(owner.id);

      expect(r.error, 'future_bookings');
      await expectNothingMutated(owner.id, owner.refreshToken);
    });

    ProviderAccount stored(String? email) => ProviderAccount(
      id: 'acc',
      phoneNumber: '+2250700000068',
      businessName: 'Salon',
      businessType: 'salon',
      createdAt: DateTime.utc(2026),
      email: email,
      providerId: 'p1',
    );

    _MockAuth authHolding(ProviderAccount account) {
      final repository = _MockAuth();
      when(
        () => repository.accountById('acc'),
      ).thenAnswer((_) async => account);
      when(() => repository.deleteAccount('acc')).thenAnswer((_) async => true);
      return repository;
    }

    for (final (label, variant) in const [
      ('mixed case', 'Revue@MyWeli.Test'),
      ('upper case', 'REVUE@MYWELI.TEST'),
      ('spaces around it', ' revue@myweli.test '),
      ('a tab before and a newline after', '\trevue@myweli.test\n'),
    ]) {
      test('a stored address in $label is the demo identity too', () async {
        final repository = authHolding(stored(variant));

        final r = await serviceOver(repository).deleteAccount('acc');

        expect(r.error, 'demo_account_locked');
        verifyNever(() => repository.deleteAccount(any()));
        verifyNever(() => providers.setStatus(any(), any()));
      });
    }

    for (final other in const [
      'revue@myweli.test.fr',
      'xrevue@myweli.test',
      'revue+1@myweli.test',
      'revue@myweli.tes',
      'demo@myweli.test',
    ]) {
      test('CONTROL: $other is NOT the demo identity — an exact match, never '
          'a prefix or a suffix', () async {
        final repository = authHolding(stored(other));

        final r = await serviceOver(repository).deleteAccount('acc');

        expect(r.ok, isTrue);
        verify(() => repository.deleteAccount('acc')).called(1);
      });
    }

    test('an account with NO e-mail still deletes', () async {
      // A row without an address (the nullable column) is nobody's demo
      // account: the lock must not read « no address » as a match.
      final repository = authHolding(stored(null));

      final r = await serviceOver(repository).deleteAccount('acc');

      expect(r.ok, isTrue);
      verify(() => repository.deleteAccount('acc')).called(1);
    });

    test('an unknown account is still `forbidden`', () async {
      final repository = _MockAuth();
      when(() => repository.accountById('gone')).thenAnswer((_) async => null);

      final r = await serviceOver(repository).deleteAccount('gone');

      expect(r.ok, isFalse);
      expect(r.error, 'forbidden');
    });
  });
}
