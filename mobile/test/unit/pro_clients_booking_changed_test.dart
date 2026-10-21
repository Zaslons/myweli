import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/providers/pro_clients_provider.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';

/// The open client card hears a booking that changed elsewhere
/// (docs/design/app-pro-home-journal-fresh.md §2.1, owner decision 8): when
/// the booking is its client's — the same phone, the server's own rule, or a
/// visit the card already lists — it is read again, quietly; anyone else's
/// booking leaves it alone.

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
    String providerId,
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
    String providerId,
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

  Future<ProClientsProvider> opened() async {
    final p = ProClientsProvider();
    addTearDown(p.dispose);
    await p.loadCard('p1', 'sc1');
    expect(service.cardCalls, ['sc1']);
    return p;
  }

  BookingChange change({
    String id = 'a1',
    String providerId = 'p1',
    String? phone = _Service.phone,
    BookingChangeKind kind = BookingChangeKind.noShow,
  }) => BookingChange(
    appointmentId: id,
    providerId: providerId,
    kind: kind,
    clientPhone: phone,
  );

  test(
    'its client’s booking (same phone): the card is read again, quietly',
    () async {
      final p = await opened();
      p.bookingChanged(change());
      expect(p.cardLoading, isFalse, reason: 'no loader');
      await pumpEventQueue();
      expect(service.cardCalls, ['sc1', 'sc1']);
      expect(p.card, isNotNull);
    },
  );

  test(
    'a booking already among the card’s visits, phone unknown: read again too',
    () async {
      service.visits = [
        Appointment(
          id: 'v9',
          userId: 'u1',
          providerId: 'p1',
          serviceIds: const ['s1'],
          appointmentDate: DateTime.utc(2026, 7, 1, 10),
          status: AppointmentStatus.confirmed,
          totalPrice: 5000,
          createdAt: DateTime.utc(2026, 6, 20),
        ),
      ];
      final p = await opened();
      p.bookingChanged(change(id: 'v9', phone: null));
      await pumpEventQueue();
      expect(service.cardCalls, ['sc1', 'sc1']);
    },
  );

  test(
    'someone else’s booking, or another salon’s: the card is left alone',
    () async {
      final p = await opened();
      p.bookingChanged(change(phone: '+2250700000999'));
      p.bookingChanged(change(providerId: 'p2'));
      await pumpEventQueue();
      expect(service.cardCalls, ['sc1']);
    },
  );

  test('the quiet read fails: the card stays as it was', () async {
    final p = await opened();
    service.failure = 'throw';
    p.bookingChanged(change());
    await pumpEventQueue();
    expect(p.card, isNotNull);
    expect(p.cardError, isNull);
  });
}
