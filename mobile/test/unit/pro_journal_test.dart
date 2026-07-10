import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/journal_day.dart';
import 'package:myweli/providers/pro_journal_provider.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

/// Module `journal` J1b (docs/design/journal-j1b-app.md): the day model +
/// ProJournalProvider (load / filter / cancelled toggle / actions).
void main() {
  group('JournalDay.fromJson', () {
    test('parses hours, artists and appointments', () {
      final day = JournalDay.fromJson({
        'date': '2026-07-13',
        'hours': {
          'open': '09:00',
          'close': '18:00',
          'breaks': [
            {'start': '12:30', 'end': '13:30'},
          ],
        },
        'artists': [
          {'id': 'ar1', 'name': 'Awa'},
        ],
        'appointments': [
          {
            'id': 'a1',
            'userId': 'u1',
            'providerId': 'p1',
            'serviceIds': ['s1'],
            'artistId': 'ar1',
            'appointmentDate': '2026-07-13T10:00:00.000Z',
            'status': 'confirmed',
            'totalPrice': 15000,
            'durationMinutes': 60,
            'arrivedAt': '2026-07-13T10:05:00.000Z',
            'createdAt': '2026-07-13T08:00:00.000Z',
          },
        ],
      });
      expect(day.hours!.open, '09:00');
      expect(day.hours!.breaks.single.start, '12:30');
      expect(day.artists.single.name, 'Awa');
      final a = day.appointments.single;
      expect(a.durationMinutes, 60);
      expect(a.arrivedAt, isNotNull);
    });

    test('closed day → hours null', () {
      final day = JournalDay.fromJson({
        'date': '2026-07-13',
        'hours': null,
        'artists': [],
        'appointments': [],
      });
      expect(day.hours, isNull);
    });
  });

  group('ProJournalProvider', () {
    final fake = _FakeProService();

    setUpAll(() {
      serviceLocator.proService = fake; // late final — assign once
    });
    setUp(fake.reset);

    Appointment appt({
      required String id,
      String status = 'confirmed',
      String? artistId,
      String date = '2026-07-13T10:00:00.000Z',
      int noShow = 0,
      DateTime? arrivedAt,
    }) =>
        Appointment(
          id: id,
          userId: 'u1',
          providerId: 'p1',
          serviceIds: const ['s1'],
          artistId: artistId,
          appointmentDate: DateTime.parse(date),
          status: AppointmentStatus.values.byName(status),
          totalPrice: 10000,
          durationMinutes: 60,
          clientNoShowCount: noShow,
          arrivedAt: arrivedAt,
          createdAt: DateTime.parse('2026-07-13T08:00:00.000Z'),
        );

    test('load populates the day; error path clears it', () async {
      fake.day = JournalDay(
        date: '2026-07-13',
        artists: const [JournalArtist(id: 'ar1', name: 'Awa')],
        appointments: [appt(id: 'a1', artistId: 'ar1')],
      );
      final p = ProJournalProvider();
      await p.load('p1');
      expect(p.day, isNotNull);
      expect(p.visibleAppointments, hasLength(1));

      fake.fail = true;
      await p.refresh();
      expect(p.day, isNull);
      expect(p.error, isNotNull);
    });

    test('artist filter + « Sans artiste » + cancelled toggle', () async {
      fake.day = JournalDay(
        date: '2026-07-13',
        artists: const [JournalArtist(id: 'ar1', name: 'Awa')],
        appointments: [
          appt(id: 'a1', artistId: 'ar1'),
          appt(id: 'a2', artistId: null), // unassigned
          appt(id: 'a3', artistId: 'ar1', status: 'cancelled'),
        ],
      );
      final p = ProJournalProvider();
      await p.load('p1');

      // Cancelled hidden by default.
      expect(p.visibleAppointments.map((a) => a.id), ['a1', 'a2']);
      expect(p.hasUnassigned, isTrue);

      p.setArtistFilter('ar1');
      expect(p.visibleAppointments.map((a) => a.id), ['a1']);

      p.setArtistFilter(''); // « Sans artiste »
      expect(p.visibleAppointments.map((a) => a.id), ['a2']);

      p.setArtistFilter(null);
      p.toggleCancelled();
      expect(p.visibleAppointments.map((a) => a.id), ['a1', 'a2', 'a3']);
    });

    test('arrive delegates to the service then refetches', () async {
      fake.day = JournalDay(
        date: '2026-07-13',
        artists: const [],
        appointments: [appt(id: 'a1')],
      );
      final p = ProJournalProvider();
      await p.load('p1');
      final ok = await p.arrive('a1');
      expect(ok, isTrue);
      expect(fake.arrivedIds, contains('a1'));
    });

    test('a failing action surfaces the error, returns false', () async {
      fake.day = JournalDay(
        date: '2026-07-13',
        artists: const [],
        appointments: [appt(id: 'a1', status: 'pending')],
      );
      final p = ProJournalProvider();
      await p.load('p1');
      fake.actionFails = true;
      final ok = await p.accept('a1');
      expect(ok, isFalse);
      expect(p.error, isNotNull);
    });
  });

  group('MockProService.getJournalDay', () {
    test('returns the seeded provider day', () async {
      final r = await MockProService().getJournalDay(
        'provider_1',
        DateTime.now(),
      );
      expect(r.success, isTrue);
      expect(r.data, isA<JournalDay>());
    });
  });
}

/// A minimal fake so the provider tests don't depend on static MockData.
class _FakeProService extends MockProService {
  JournalDay? day;
  bool fail = false;
  bool actionFails = false;
  final arrivedIds = <String>[];

  void reset() {
    day = null;
    fail = false;
    actionFails = false;
    arrivedIds.clear();
  }

  @override
  Future<ApiResponse<JournalDay>> getJournalDay(
    String providerId,
    DateTime date,
  ) async {
    if (fail) return ApiResponse.error('boom');
    return ApiResponse.success(day!);
  }

  @override
  Future<ApiResponse<bool>> markArrived(String id) async {
    if (actionFails) return ApiResponse.error('nope');
    arrivedIds.add(id);
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> acceptAppointment(String id) async {
    if (actionFails) return ApiResponse.error('nope');
    return ApiResponse.success(true);
  }
}
