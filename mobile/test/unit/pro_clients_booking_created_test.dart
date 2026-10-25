import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_access_guard.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';

/// « Fiche client » after the salon creates a booking for that client
/// (docs/design/pro-journal-shows-new-booking.md §2.5): « Prochain
/// rendez-vous » and the visit history are asked for again, quietly.
class _Service extends MockProClientsService {
  static const phone = '+2250700000101';

  Map<String, dynamic>? upcoming;
  List<Appointment> visits = [];
  final cardCalls = <String>[];
  int visitCalls = 0;

  /// null = the card, else 'error', 'forbidden' or 'throw'.
  String? failure;

  /// While set, card answers wait for it.
  Completer<void>? gate;

  /// While set, visit answers wait for it.
  Completer<void>? visitsGate;

  SalonClientCard _card(String clientId) => SalonClientCard(
    client: SalonClient(
      id: clientId,
      displayName: clientId == 'sc1' ? 'Koffi' : 'Aminata',
      phone: clientId == 'sc1' ? phone : '+2250700000202',
      tags: const [],
      linked: false,
    ),
    stats: const SalonClientStats(
      visits: 3,
      spentFcfa: 45000,
      noShows: 0,
      cancellations: 0,
    ),
    notes: const [],
    upcoming: upcoming,
  );

  @override
  Future<ApiResponse<SalonClientCard>> getCard(
    SalonId providerId,
    String clientId,
  ) async {
    cardCalls.add(clientId);
    // Decided on arrival, like a server.
    final failure = this.failure;
    final card = _card(clientId);
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (failure == 'throw') throw Exception('SocketException');
    if (failure == 'error') return ApiResponse.error('Erreur réseau.');
    if (failure == 'forbidden') {
      return ApiResponse.error('Accès refusé', code: 'forbidden');
    }
    return ApiResponse.success(card);
  }

  @override
  Future<ApiResponse<List<Appointment>>> getVisits(
    SalonId providerId,
    String clientId, {
    int page = 1,
  }) async {
    visitCalls++;
    final answer = List.of(visits); // decided on arrival
    final gate = visitsGate;
    if (gate != null) await gate.future;
    return ApiResponse.success(answer);
  }
}

void main() {
  final service = _Service();

  setUpAll(() {
    serviceLocator.proClientsService = service; // late final — one per file
  });

  setUp(() {
    service
      ..upcoming = null
      ..visits = []
      ..cardCalls.clear()
      ..visitCalls = 0
      ..failure = null
      ..gate = null
      ..visitsGate = null;
  });

  Appointment booking({
    String? phone = _Service.phone,
    SalonId providerId = const SalonId('p1'),
  }) => Appointment(
    id: 'm1',
    userId: 'manual',
    providerId: providerId,
    serviceIds: const ['s1'],
    appointmentDate: DateTime.utc(2026, 7, 13, 10),
    status: AppointmentStatus.confirmed,
    totalPrice: 5000,
    clientPhone: phone,
    createdAt: DateTime.utc(2026, 7, 1),
  );

  /// Koffi's card, open.
  Future<ProClientsProvider> opened() async {
    final p = ProClientsProvider();
    addTearDown(p.dispose);
    await p.loadCard(SalonId('p1'), 'sc1');
    expect(p.card!.upcoming, isNull);
    expect(p.visits, isEmpty);
    return p;
  }

  /// What the server holds once the booking exists.
  void serverHasTheBooking() {
    final b = booking();
    service
      ..upcoming = {'id': b.id, 'appointmentDate': '2026-07-13T10:00:00.000Z'}
      ..visits = [b];
  }

  test(
    'a booking for the card’s client: the card and its visits are asked '
    'for again and replaced, with no loader and the card never blank',
    () async {
      final p = await opened();
      final loadingSeen = <bool>[];
      final cardSeen = <SalonClientCard?>[];
      p.addListener(() {
        loadingSeen.add(p.cardLoading);
        cardSeen.add(p.card);
      });

      serverHasTheBooking();
      service.gate = Completer<void>();
      p.bookingCreated(booking());

      // In flight: the card on screen is the one that was there.
      await pumpEventQueue();
      expect(service.cardCalls, ['sc1', 'sc1']);
      expect(p.card, isNotNull);
      expect(p.card!.upcoming, isNull);
      expect(p.cardLoading, isFalse);

      service.gate!.complete();
      await pumpEventQueue();
      expect(p.card!.upcoming!['id'], 'm1');
      expect(p.visits.single.id, 'm1');
      expect(p.cardError, isNull);
      expect(loadingSeen, isNotEmpty);
      expect(loadingSeen, everyElement(isFalse), reason: 'never a loader');
      expect(cardSeen, everyElement(isNotNull), reason: 'never blank');
    },
  );

  test('a booking for someone else leaves the card alone', () async {
    final p = await opened();
    serverHasTheBooking();

    p.bookingCreated(booking(phone: '+2250700000999'));
    p.bookingCreated(booking(phone: null)); // « Client sans numéro »
    p.bookingCreated(booking(phone: ''));
    p.bookingCreated(booking(providerId: SalonId('p2'))); // another salon
    await pumpEventQueue();

    expect(service.cardCalls, ['sc1']);
    expect(p.card!.upcoming, isNull);
  });

  test('no card is open: nothing is asked', () async {
    final p = ProClientsProvider();
    addTearDown(p.dispose);
    p.bookingCreated(booking());
    await pumpEventQueue();
    expect(service.cardCalls, isEmpty);
  });

  for (final failure in ['error', 'throw']) {
    test(
      'the quiet reload fails ($failure): the card stays, no error',
      () async {
        final p = await opened();
        service.failure = failure;
        p.bookingCreated(booking());
        await pumpEventQueue();

        expect(service.cardCalls, ['sc1', 'sc1']);
        expect(p.card, isNotNull);
        expect(p.card!.client.displayName, 'Koffi');
        expect(p.cardError, isNull);
        expect(p.cardLoading, isFalse);
      },
    );
  }

  test('a refused reload still reports `forbidden` to the access seam — '
      'quiet for the salon, not for a revoked member', () async {
    final p = await opened();
    var probes = 0;
    final previous = ProAccessGuard.onForbidden;
    ProAccessGuard.onForbidden = () async => probes++;
    addTearDown(() => ProAccessGuard.onForbidden = previous);

    service.failure = 'forbidden';
    p.bookingCreated(booking());
    await pumpEventQueue();

    expect(service.cardCalls, ['sc1', 'sc1']);
    expect(probes, 1);
    expect(p.cardError, isNull);
    expect(p.card!.client.displayName, 'Koffi', reason: 'the card stays');
  });

  test('a salon switch drops the reload in flight: the previous salon’s '
      'answer changes nothing, and tells nobody', () async {
    final p = await opened();
    serverHasTheBooking();
    final held = Completer<void>();
    service.gate = held;
    p.bookingCreated(booking()); // Koffi's card, in flight
    await pumpEventQueue();
    expect(service.cardCalls, ['sc1', 'sc1']);

    p.resetForSalonSwitch();
    final cardAtSwitch = p.card;
    final visitCallsBefore = service.visitCalls;
    var notified = 0;
    p.addListener(() => notified++);

    held.complete();
    await pumpEventQueue();
    // Whatever the switch leaves of the card — today it leaves it; the day it
    // clears it, this still reads right — the late answer does not change.
    expect(p.card, same(cardAtSwitch), reason: 'asked for the salon left');
    expect(p.card?.upcoming, isNull);
    expect(service.visitCalls, visitCallsBefore);
    expect(notified, 0);
  });

  test('another card is opened meanwhile: the reload’s answer is '
      'dropped', () async {
    final p = await opened();
    serverHasTheBooking();
    final held = Completer<void>();
    service.gate = held;
    p.bookingCreated(booking()); // Koffi's card, in flight
    await pumpEventQueue();

    service.gate = null;
    await p.loadCard(SalonId('p1'), 'sc2');
    expect(p.card!.client.displayName, 'Aminata');
    final visitCallsBefore = service.visitCalls;

    held.complete();
    await pumpEventQueue();
    expect(p.card!.client.displayName, 'Aminata', reason: 'not Koffi’s card');
    expect(
      service.visitCalls,
      visitCallsBefore,
      reason: 'an outdated reload does not go on to ask for the visits',
    );
  });

  test('another card is opened while the VISITS are in flight: dropped '
      'too', () async {
    final p = await opened();
    serverHasTheBooking();
    final held = Completer<void>();
    service.visitsGate = held;
    p.bookingCreated(booking()); // Koffi's card answered, his visits held
    await pumpEventQueue();
    expect(service.cardCalls, ['sc1', 'sc1']);

    service.visitsGate = null;
    service.visits = [];
    await p.loadCard(SalonId('p1'), 'sc2');
    expect(p.card!.client.displayName, 'Aminata');
    expect(p.visits, isEmpty);

    held.complete();
    await pumpEventQueue();
    expect(p.card!.client.displayName, 'Aminata', reason: 'not Koffi’s card');
    expect(p.visits, isEmpty, reason: 'not Koffi’s visits');
  });
}
