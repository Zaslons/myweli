import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_access_guard.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

/// « Accueil » after the salon creates a booking
/// (docs/design/pro-journal-shows-new-booking.md §2.5): its figures are asked
/// for again, quietly — the cards keep their numbers, nothing spins, nothing
/// is said on a failure.
class _Service extends MockProService {
  int today = 2;
  int calls = 0;

  /// null = the figures, else 'error', 'forbidden' or 'throw'.
  String? failure;

  /// While set, answers wait for it.
  Completer<void>? gate;

  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(
    SalonId providerId,
  ) async {
    calls++;
    // Decided on arrival, like a server.
    final failure = this.failure;
    final stats = DashboardStats(
      todayAppointments: today,
      pendingRequests: 0,
      totalAppointments: today,
      todayRevenue: today * 5000,
    );
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (failure == 'throw') throw Exception('SocketException');
    if (failure == 'error') return ApiResponse.error('Erreur réseau.');
    if (failure == 'forbidden') {
      return ApiResponse.error('Accès refusé', code: 'forbidden');
    }
    return ApiResponse.success(stats);
  }
}

void main() {
  final service = _Service();

  setUpAll(() {
    serviceLocator.proService = service; // late final — one fake for the file
  });

  setUp(() {
    service
      ..today = 2
      ..calls = 0
      ..failure = null
      ..gate = null;
  });

  Appointment booking({SalonId providerId = const SalonId('p1')}) =>
      Appointment(
        id: 'm1',
        userId: 'manual',
        providerId: providerId,
        serviceIds: const ['s1'],
        appointmentDate: DateTime.utc(2026, 7, 13, 10),
        status: AppointmentStatus.confirmed,
        totalPrice: 5000,
        createdAt: DateTime.utc(2026, 7, 1),
      );

  Future<ProDashboardProvider> loaded() async {
    final p = ProDashboardProvider();
    addTearDown(p.dispose);
    await p.loadDashboardStats(SalonId('p1'));
    expect(p.stats!.todayAppointments, 2);
    return p;
  }

  test(
    'the KNOWN DEFECT this case used to pin is repaired '
    '(docs/design/app-pro-home-journal-fresh.md §2.2): entering « Accueil » '
    'again uses what is loaded, and the pull — `refresh` — asks the server',
    () async {
      // It recorded « the pull-to-refresh asks for nothing » and said it would
      // go red the day the pull was repaired, to be rewritten then. This is the
      // rewrite: the pull is `refresh`, and it always asks.
      final p = await loaded();
      service.today = 3;
      await p.loadDashboardStats(SalonId('p1'));
      expect(service.calls, 1);
      expect(p.stats!.todayAppointments, 2);
      await p.refresh(SalonId('p1'));
      expect(service.calls, 2);
      expect(p.stats!.todayAppointments, 3);
    },
  );

  test('a booking is created: the figures are asked for again and replaced, '
      'with no loader', () async {
    final p = await loaded();
    final loadingSeen = <bool>[];
    final statsSeen = <DashboardStats?>[];
    p.addListener(() {
      loadingSeen.add(p.isLoading);
      statsSeen.add(p.stats);
    });

    service.today = 3;
    service.gate = Completer<void>();
    p.bookingCreated(booking());

    // In flight: the cards keep their numbers.
    await pumpEventQueue();
    expect(service.calls, 2);
    expect(p.stats!.todayAppointments, 2);
    expect(p.isLoading, isFalse);

    service.gate!.complete();
    await pumpEventQueue();
    expect(p.stats!.todayAppointments, 3);
    expect(p.stats!.todayRevenue, 15000);
    expect(p.error, isNull);
    expect(loadingSeen, isNotEmpty);
    expect(loadingSeen, everyElement(isFalse), reason: 'never a loader');
    expect(statsSeen, everyElement(isNotNull), reason: 'never blank');
  });

  for (final failure in ['error', 'throw']) {
    test('the quiet refetch fails ($failure): the figures stay, no error — '
        'and the next pull-to-refresh asks again, still quietly', () async {
      final p = await loaded();
      final loadingSeen = <bool>[];
      p.addListener(() => loadingSeen.add(p.isLoading));

      service.failure = failure;
      p.bookingCreated(booking());
      await pumpEventQueue();
      expect(service.calls, 2);
      expect(p.stats!.todayAppointments, 2);
      expect(p.error, isNull);
      expect(p.isLoading, isFalse);

      // Still failing: the pull changes nothing and says nothing.
      await p.loadDashboardStats(SalonId('p1'));
      expect(service.calls, 3);
      expect(p.stats!.todayAppointments, 2);
      expect(p.error, isNull);

      // Back online.
      service.failure = null;
      service.today = 3;
      await p.loadDashboardStats(SalonId('p1'));
      expect(service.calls, 4);
      expect(p.stats!.todayAppointments, 3);

      // Confirmed by the server: no longer stale — entering « Accueil »
      // again does not ask (only the pull does, app-pro-home-journal-fresh.md).
      await p.loadDashboardStats(SalonId('p1'));
      expect(service.calls, 4);
      expect(loadingSeen, everyElement(isFalse));
    });
  }

  test('a refused refetch still reports `forbidden` to the access seam — '
      'quiet for the salon, not for a revoked member', () async {
    final p = await loaded();
    var probes = 0;
    final previous = ProAccessGuard.onForbidden;
    ProAccessGuard.onForbidden = () async => probes++;
    addTearDown(() => ProAccessGuard.onForbidden = previous);

    service.failure = 'forbidden';
    p.bookingCreated(booking());
    await pumpEventQueue();

    expect(service.calls, 2);
    expect(probes, 1);
    expect(p.error, isNull);
    expect(p.stats!.todayAppointments, 2, reason: 'the figures stay');
  });

  test('the figures had FAILED to load — nothing is on screen to keep '
      'right: a booking asks for nothing', () async {
    // What « Accueil » shows then is a sentence with no way out (§11.2).
    // Using a created booking as its retry would be that screen's decision,
    // not this slice's: the quiet refetch only ever replaces figures that
    // are on screen. This case records that boundary, not a wish — the day
    // the decision is taken it goes red, and is rewritten with it.
    final p = ProDashboardProvider();
    addTearDown(p.dispose);
    service.failure = 'error';
    await p.loadDashboardStats(SalonId('p1'));
    expect(p.stats, isNull);
    expect(p.error, isNotNull);
    expect(service.calls, 1);

    service.failure = null;
    p.bookingCreated(booking());
    await pumpEventQueue();

    expect(service.calls, 1);
    expect(p.stats, isNull);
    expect(p.error, isNotNull);
  });

  test('another salon’s booking is ignored', () async {
    final p = await loaded();
    p.bookingCreated(booking(providerId: SalonId('p2')));
    await pumpEventQueue();
    expect(service.calls, 1);
  });

  test('« Accueil » was never loaded: nothing is asked', () async {
    final p = ProDashboardProvider();
    addTearDown(p.dispose);
    p.bookingCreated(booking());
    await pumpEventQueue();
    expect(service.calls, 0);
    expect(p.stats, isNull);
  });

  test(
    'the first load is still in flight: its answer may predate the '
    'booking, so the figures are asked for once more when it lands',
    () async {
      final p = ProDashboardProvider();
      addTearDown(p.dispose);
      service.gate = Completer<void>();
      final load = p.loadDashboardStats(SalonId('p1')); // decided: 2
      await pumpEventQueue();
      expect(p.isLoading, isTrue);

      service.today = 3;
      p.bookingCreated(booking());
      expect(service.calls, 1, reason: 'not while the load is in flight');

      service.gate!.complete();
      service.gate = null;
      await load;
      await pumpEventQueue();
      expect(service.calls, 2);
      expect(p.stats!.todayAppointments, 3);
    },
  );

  test('two bookings in a row: the older refetch cannot overwrite the newer '
      'one', () async {
    final p = await loaded();
    service.today = 3;
    final first = Completer<void>();
    service.gate = first;
    p.bookingCreated(booking()); // decided: 3
    await pumpEventQueue();

    service.today = 4;
    service.gate = null;
    p.bookingCreated(booking()); // decided: 4, answered at once
    await pumpEventQueue();
    expect(p.stats!.todayAppointments, 4);

    first.complete(); // the older answer lands last
    await pumpEventQueue();
    expect(p.stats!.todayAppointments, 4);
  });

  test('a booking lands while the first load is in flight, and that load '
      'FAILS: the retry is a fresh load — asked after the booking existed, '
      'it leaves nothing to confirm', () async {
    final p = ProDashboardProvider();
    addTearDown(p.dispose);
    service.gate = Completer<void>();
    service.failure = 'error';
    final load = p.loadDashboardStats(SalonId('p1')); // decided: a failure
    await pumpEventQueue();
    p.bookingCreated(booking()); // remembered: the load may predate it
    service.gate!.complete();
    service.gate = null;
    await load;
    await pumpEventQueue();
    expect(p.stats, isNull);
    expect(service.calls, 1, reason: 'no figures to refetch behind');

    service.failure = null;
    service.today = 3;
    await p.loadDashboardStats(SalonId('p1')); // « Accueil » reopened
    await pumpEventQueue();
    expect(p.stats!.todayAppointments, 3);
    expect(service.calls, 2, reason: 'one request, not one and its double');
  });

  test('the store is asked for ANOTHER salon while a refetch is in flight: '
      'the first salon’s figures do not land on the second', () async {
    final p = await loaded(); // p1: 2
    service.today = 3;
    final held = Completer<void>();
    service.gate = held;
    p.bookingCreated(booking()); // p1's refetch, decided: 3
    await pumpEventQueue();

    service.today = 9;
    service.gate = null;
    await p.loadDashboardStats(SalonId('p2')); // decided: 9, answered at once
    expect(p.stats!.todayAppointments, 9);

    held.complete(); // p1's answer lands last
    await pumpEventQueue();
    expect(p.stats!.todayAppointments, 9, reason: 'p1’s figures under p2');
  });

  for (final (name, forget) in <(String, void Function(ProDashboardProvider))>[
    ('a salon switch', (p) => p.resetForSalonSwitch()),
    ('clearStats', (p) => p.clearStats()),
  ]) {
    test('$name drops a refetch in flight', () async {
      final p = await loaded();
      service.today = 3;
      service.gate = Completer<void>();
      p.bookingCreated(booking());
      await pumpEventQueue();
      expect(service.calls, 2);

      forget(p);
      service.gate!.complete();
      await pumpEventQueue();
      expect(p.stats, isNull, reason: 'the previous salon’s figures');
    });
  }
}
