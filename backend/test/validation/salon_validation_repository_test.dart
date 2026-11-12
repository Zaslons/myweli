import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/validation/salon_validation_repository.dart';
import 'package:test/test.dart';

import 'salon_validation_contract.dart';

/// The in-memory twins of B0.18's data layer
/// (docs/design/salon-go-live-approval.md §2, §3.4, §3.7). The same contract
/// runs on Postgres in `db/postgres_repositories_test.dart`.
void main() {
  /// The document list behind each providers twin. A fresh list per world,
  /// so the shared `seedProviders` is never mutated; salons are appended
  /// with fixed ids rather than through `createSalon`, whose id is the clock's
  /// microsecond.
  final docsOf = Expando<List<Map<String, dynamic>>>();
  var n = 0;

  InMemoryProvidersRepository newProviders() {
    final docs = <Map<String, dynamic>>[];
    final providers = InMemoryProvidersRepository(docs);
    docsOf[providers] = docs;
    return providers;
  }

  String addDraft(ProvidersRepository providers) {
    n++;
    final id = 'salon_$n';
    docsOf[providers]!.add(
      draftSalonDocument(
        id: id,
        slug: 'salon-$n',
        name: 'Salon $n',
        category: 'salon',
        phoneNumber: '+2250700000044',
      ),
    );
    return id;
  }

  /// A world with no seeded salon.
  ValidationWorld world() {
    final providers = newProviders();
    final members = InMemoryMembershipRepository();
    return (
      validations: InMemorySalonValidationRepository(
        providers: providers,
        members: members,
      ),
      providers: providers,
      members: members,
    );
  }

  Future<String> salon(ValidationWorld w, {bool withOwner = true}) async {
    final id = addDraft(w.providers);
    if (withOwner) {
      await w.members.ensureOwner(
        providerId: id,
        accountId: 'acc_$id',
        email: 'owner-$id@salon.pro',
      );
    }
    return id;
  }

  group('SalonValidationRepository — the twin contract (in-memory)', () {
    salonValidationContract(world: world, salon: salon);
  });

  group('providers.suspended_from — the twin contract (in-memory)', () {
    suspendedFromContract(repo: newProviders, salon: (r) async => addDraft(r));
  });

  group('the in-memory twin seeds the dev world (§3.7)', () {
    test('every ACTIVE salon is validated and live at construction, nothing '
        'else — the dev boot backfill’s mirror', () async {
      final providers = InMemoryProvidersRepository([
        {'id': 'seeded'}, // a seed document: no status → the column default
        {'id': 'live', 'status': 'active'},
        {'id': 'draft', 'status': 'draft'},
        {'id': 'suspended', 'status': 'suspended'},
      ]);
      final repo = InMemorySalonValidationRepository(
        providers: providers,
        members: InMemoryMembershipRepository(),
      );
      for (final id in ['seeded', 'live']) {
        final v = (await repo.get(id))!;
        expect(v.state, ValidationStates.approved, reason: id);
        expect(v.wentLive, isTrue, reason: id);
        expect(v.submittedAt, isNull, reason: 'never asked: $id');
        expect(v.decidedBy, isNull, reason: 'no admin decided: $id');
      }
      expect(await repo.get('draft'), isNull);
      expect(await repo.get('suspended'), isNull);
      expect(await repo.countPending(), 0, reason: 'no queue flood');
      expect(await repo.events('seeded'), isEmpty);
    });

    test(
      'the default seed: the four demo salons are validated and live',
      () async {
        // The composition root builds the twin over the shared seed; read it
        // without writing to it.
        final repo = InMemorySalonValidationRepository(
          providers: InMemoryProvidersRepository(),
          members: InMemoryMembershipRepository(),
        );
        final ids = [for (final p in seedProviders) p['id'] as String];
        final rows = await repo.getMany(ids);
        expect(rows.keys.toSet(), ids.toSet());
        expect(rows.values.every((v) => v.wentLive), isTrue);
      },
    );
  });

  group('the synchronous helpers the twin reads through', () {
    test('statusNow: the stored status, active for a status-less seed '
        'document, null for no salon', () {
      final r = InMemoryProvidersRepository([
        {'id': 'a'},
        {'id': 'b', 'status': 'draft'},
      ]);
      expect(r.statusNow('a'), 'active');
      expect(r.statusNow('b'), 'draft');
      expect(r.statusNow('zz'), isNull);
    });

    test('compareAndSetStatusNow writes only from the expected status', () {
      final r = InMemoryProvidersRepository([
        {'id': 'b', 'status': 'draft'},
      ]);
      expect(
        r.compareAndSetStatusNow('b', from: 'active', to: 'draft'),
        isFalse,
      );
      expect(r.statusNow('b'), 'draft');
      expect(
        r.compareAndSetStatusNow('b', from: 'draft', to: 'active'),
        isTrue,
      );
      expect(r.statusNow('b'), 'active');
      expect(
        r.compareAndSetStatusNow('zz', from: 'draft', to: 'active'),
        isFalse,
      );
    });

    test('hasActiveOwnerNow: an active owner row only — not an invitation, '
        'not another role, not another salon', () async {
      final m = InMemoryMembershipRepository();
      expect(m.hasActiveOwnerNow('s1'), isFalse);
      await m.invite(
        providerId: 's1',
        email: 'manager@salon.pro',
        role: 'manager',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 7)),
      );
      expect(m.hasActiveOwnerNow('s1'), isFalse);
      await m.ensureOwner(
        providerId: 's2',
        accountId: 'acc_2',
        email: 'owner@other.pro',
      );
      expect(m.hasActiveOwnerNow('s1'), isFalse);
      await m.ensureOwner(
        providerId: 's1',
        accountId: 'acc_1',
        email: 'owner@salon.pro',
      );
      expect(m.hasActiveOwnerNow('s1'), isTrue);
      await m.deleteAllForAccount('acc_1'); // erasure
      expect(m.hasActiveOwnerNow('s1'), isFalse);
    });
  });
}
