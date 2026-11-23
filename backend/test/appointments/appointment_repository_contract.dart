import 'dart:convert';

import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/appointments/booking_service.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:test/test.dart';

/// The contract of [AppointmentRepository], run against BOTH twins — the
/// in-memory one (`appointment_repository_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself: each caller
/// runs it inside its own group, on an empty `appointments` table.
///
/// docs/design/appointment-currency-stamp.md §8.2.
///
/// **Why it exists.** The booking service stamped every booking with its
/// salon's currency, and the Postgres repository dropped it on the floor: no
/// column in the INSERT, no key in the read. Every service and handler test
/// runs on the in-memory twin, which stores the caller's own map, so none of
/// them could see it. The defect was not « `currency` is missing », it was
/// « the twins disagree about which keys survive », and this contract is
/// aimed at that class: the next key the service writes without a column turns
/// it red, whatever the key is called.
///
/// [repo] builds the repository under test (each test calls it once).
void appointmentRepositoryContract({
  required AppointmentRepository Function() repo,
}) {
  /// A salon of its own — never the shared, MUTABLE `seedProviders` entry —
  /// in a currency that is not XOF, so no XOF default or fallback can pass.
  /// A deposit is required so the deposit and balance are not both zero.
  InMemoryProvidersRepository salon() {
    final doc =
        jsonDecode(jsonEncode(seedProviders.first)) as Map<String, dynamic>
          ..['id'] = 'p_currency_contract'
          ..['slug'] = 'p-currency-contract'
          ..['currency'] = 'XAF'
          ..['depositRequired'] = true;
    final services = (doc['services'] as List).cast<Map<String, dynamic>>();
    for (final s in services) {
      s['providerId'] = 'p_currency_contract';
    }
    (doc['availability'] as Map<String, dynamic>)['providerId'] =
        'p_currency_contract';
    return InMemoryProvidersRepository([doc]);
  }

  /// A future Mon–Sat 09:00 UTC — an open slot in the seed schedule, far
  /// enough ahead for the notice and inside the horizon.
  DateTime slot() {
    final now = DateTime.now().toUtc();
    var d = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 7));
    while (d.weekday == DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime.utc(d.year, d.month, d.day, 9);
  }

  /// Comparable form of a stored value: every number as a double, every ISO
  /// instant as microseconds since the epoch, lists element by element. The
  /// twins may spell `0` as `0.0` or a date with a different suffix; neither
  /// is a lost value, and both would make a plain `equals` red for the wrong
  /// reason.
  Object? norm(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String && v.contains('T')) {
      final t = DateTime.tryParse(v);
      if (t != null) return t.toUtc().microsecondsSinceEpoch;
    }
    if (v is List) return [for (final e in v) norm(e)];
    return v;
  }

  /// Every key of [written] is in [read], with the same value — except the
  /// keys a read path changed on purpose.
  void expectCarries(
    Map<String, dynamic>? read,
    Map<String, dynamic> written, {
    required String where,
    Set<String> except = const {},
  }) {
    expect(read, isNotNull, reason: '$where returned nothing');
    for (final k in written.keys) {
      if (except.contains(k)) continue;
      expect(
        read!.containsKey(k),
        isTrue,
        reason: '$where lost "$k": the service wrote it, the read dropped it',
      );
      expect(norm(read[k]), norm(written[k]), reason: '$where changed "$k"');
    }
  }

  group('every key the booking service writes comes back from every read', () {
    test('book (a client booking)', () async {
      final rec = _Recording(repo());
      final providers = salon();
      final at = slot();
      final r =
          await BookingService(
            providers,
            rec,
            SlotService(providers, rec),
          ).book(
            userId: 'u_contract',
            providerId: 'p_currency_contract',
            serviceIds: const ['service1'],
            appointmentDateTime: at,
          );
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      final written = rec.written.single;
      expect(
        written['currency'],
        'XAF',
        reason: 'the service stamps the SALON currency at write time',
      );
      final id = written['id'] as String;

      expectCarries(r.appointment, written, where: 'create');
      expectCarries(await rec.byId(id), written, where: 'byId');
      expectCarries(
        (await rec.listForUser('u_contract')).single,
        written,
        where: 'listForUser',
      );
      expectCarries(
        (await rec.listForProvider('p_currency_contract')).single,
        written,
        where: 'listForProvider',
      );

      // `book` creates `pending`; confirming it is a change of `status` on
      // purpose, and the reminder window only sees `confirmed` rows.
      final confirmed = await rec.update(id, {'status': 'confirmed'});
      expectCarries(
        confirmed,
        written,
        where: 'update',
        except: const {'status'},
      );
      expectCarries(
        (await rec.confirmedInWindow(
          at.subtract(const Duration(minutes: 1)),
          at,
        )).single,
        written,
        where: 'confirmedInWindow',
        except: const {'status'},
      );
    });

    test('bookManual (the salon’s own entry)', () async {
      final rec = _Recording(repo());
      final providers = salon();
      final at = slot();
      final r =
          await BookingService(
            providers,
            rec,
            SlotService(providers, rec),
          ).bookManual(
            providerId: 'p_currency_contract',
            serviceIds: const ['service1'],
            appointmentDateTime: at,
            clientName: 'Awa',
            clientPhone: '+2250700000777',
            notes: 'Première visite',
          );
      expect(r.ok, isTrue, reason: 'error was ${r.error}');
      final written = rec.written.single;
      expect(written['currency'], 'XAF');
      final id = written['id'] as String;

      expectCarries(r.appointment, written, where: 'create');
      expectCarries(await rec.byId(id), written, where: 'byId');
      expectCarries(
        (await rec.listForUser('manual')).single,
        written,
        where: 'listForUser',
      );
      expectCarries(
        (await rec.listForProvider('p_currency_contract')).single,
        written,
        where: 'listForProvider',
      );
      expectCarries(
        (await rec.confirmedInWindow(
          at.subtract(const Duration(minutes: 1)),
          at,
        )).single,
        written,
        where: 'confirmedInWindow',
      );
      // `bookManual` writes `confirmed`; an arrival is a change on purpose.
      expectCarries(
        await rec.update(id, {'arrivedAt': at.toIso8601String()}),
        written,
        where: 'update',
      );
    });
  });

  test('the currency is immutable: an update never changes it', () async {
    final r = repo();
    await r.create(_booking(id: 'a_immutable', currency: 'XAF'));
    final updated = await r.update('a_immutable', {
      'currency': 'EUR',
      'status': 'confirmed',
    });
    expect(updated!['status'], 'confirmed', reason: 'the update did apply');
    expect(
      updated['currency'],
      'XAF',
      reason:
          'a booking is priced in the currency it was made in (the Fresha '
          'rule): no update path may rewrite it',
    );
    expect((await r.byId('a_immutable'))!['currency'], 'XAF');
  });
}

/// A booking map shaped like the one the service builds, for the paths that
/// do not need the service.
Map<String, dynamic> _booking({required String id, required String currency}) {
  final at = DateTime.utc(2030, 6, 25, 9);
  return {
    'id': id,
    'currency': currency,
    'userId': 'u_contract',
    'providerId': 'p_currency_contract',
    'serviceIds': ['service1'],
    'artistId': null,
    'appointmentDate': at.toIso8601String(),
    'durationMinutes': 30,
    'status': 'pending',
    'totalPrice': 15000.0,
    'depositAmount': 4500.0,
    'balanceDue': 10500.0,
    'cancellationWindowHours': 24,
    'clientName': null,
    'clientPhone': null,
    'notes': null,
    'depositScreenshotUrl': null,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
  };
}

/// Delegates to [_inner] and keeps a DEEP COPY of every map handed to
/// `create`. A copy, not the reference: the in-memory twin stores the caller's
/// own map and mutates it in place on `update`, so a kept reference would
/// follow every later change and the twin would be compared with itself.
class _Recording implements AppointmentRepository {
  _Recording(this._inner);

  final AppointmentRepository _inner;
  final written = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>?> create(Map<String, dynamic> appointment) {
    written.add(jsonDecode(jsonEncode(appointment)) as Map<String, dynamic>);
    return _inner.create(appointment);
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(
    String userId, {
    String? status,
    String? matchPhone,
  }) => _inner.listForUser(userId, status: status, matchPhone: matchPhone);

  @override
  Future<List<Map<String, dynamic>>> listForProvider(
    String providerId, {
    String? status,
  }) => _inner.listForProvider(providerId, status: status);

  @override
  Future<Map<String, dynamic>?> byId(String id) => _inner.byId(id);

  @override
  Future<Map<String, dynamic>?> update(
    String id,
    Map<String, dynamic> changes,
  ) => _inner.update(id, changes);

  @override
  Future<List<String>> anonymizeUser(String userId) =>
      _inner.anonymizeUser(userId);

  @override
  Future<int> wipeForProvider(String providerId) =>
      _inner.wipeForProvider(providerId);

  @override
  Future<Map<String, int>> countsByStatus() => _inner.countsByStatus();

  @override
  Future<List<Map<String, dynamic>>> completedForAnalytics(DateTime from) =>
      _inner.completedForAnalytics(from);

  @override
  Future<List<Map<String, dynamic>>> confirmedInWindow(
    DateTime from,
    DateTime to,
  ) => _inner.confirmedInWindow(from, to);
}
