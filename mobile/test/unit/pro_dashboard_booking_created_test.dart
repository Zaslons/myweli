import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
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

  /// null = the figures, else 'error' or 'throw'.
  String? failure;

  /// While set, answers wait for it.
  Completer<void>? gate;

  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(
    String providerId,
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

  Appointment booking({String providerId = 'p1'}) => Appointment(
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
    await p.loadDashboardStats('p1');
    expect(p.stats!.todayAppointments, 2);
    return p;
  }

  test('the figures are fetched once per salon: a second load — the '
      'pull-to-refresh — asks for nothing', () async {
    // Not this slice's doing, and not fixed by it: recorded because §2.5's
    // « the next pull-to-refresh asks again » only holds when the figures are
    // known to be stale (below).
    final p = await loaded();
    service.today = 3;
    await p.loadDashboardStats('p1');
    expect(service.calls, 1);
    expect(p.stats!.todayAppointments, 2);
  });

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
      await p.loadDashboardStats('p1');
      expect(service.calls, 3);
      expect(p.stats!.todayAppointments, 2);
      expect(p.error, isNull);

      // Back online.
      service.failure = null;
      service.today = 3;
      await p.loadDashboardStats('p1');
      expect(service.calls, 4);
      expect(p.stats!.todayAppointments, 3);

      // Confirmed by the server: no longer stale, the cache is back.
      await p.loadDashboardStats('p1');
      expect(service.calls, 4);
      expect(loadingSeen, everyElement(isFalse));
    });
  }

  test('another salon’s booking is ignored', () async {
    final p = await loaded();
    p.bookingCreated(booking(providerId: 'p2'));
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
      final load = p.loadDashboardStats('p1'); // decided: 2
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

  test('a salon switch drops a refetch in flight', () async {
    final p = await loaded();
    service.today = 3;
    service.gate = Completer<void>();
    p.bookingCreated(booking());
    await pumpEventQueue();

    p.resetForSalonSwitch();
    service.gate!.complete();
    await pumpEventQueue();
    expect(p.stats, isNull, reason: 'the previous salon’s figures');
  });
}
