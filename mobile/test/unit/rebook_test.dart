import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/rebook.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/appointment.dart';

void main() {
  group('sanitizeRebookSelection', () {
    test('keeps services and stylist that still exist', () {
      final r = sanitizeRebookSelection(
        serviceIds: ['s1', 's2'],
        artistId: 'a1',
        availableServiceIds: {'s1', 's2', 's3'},
        availableArtistIds: {'a1', 'a2'},
      );
      expect(r.serviceIds, ['s1', 's2']);
      expect(r.artistId, 'a1');
    });

    test('drops services that no longer exist', () {
      final r = sanitizeRebookSelection(
        serviceIds: ['s1', 'gone'],
        artistId: null,
        availableServiceIds: {'s1'},
        availableArtistIds: const {},
      );
      expect(r.serviceIds, ['s1']);
      expect(r.artistId, isNull);
    });

    test('clears a stylist who is gone', () {
      final r = sanitizeRebookSelection(
        serviceIds: ['s1'],
        artistId: 'gone',
        availableServiceIds: {'s1'},
        availableArtistIds: {'a1'},
      );
      expect(r.artistId, isNull);
    });
  });

  // A2 (appointment-detail-complete.md §2.8, decision 201): the app's detail
  // offers « Réserver à nouveau » by the web's rule (decision 183).
  group('canRebook and the route', () {
    final now = DateTime.utc(2026, 11, 23, 12);
    Appointment appt(
      AppointmentStatus status,
      int minutes, {
      String? providerStatus,
      String? artistId = 'a1',
      List<String> serviceIds = const ['s1', 's2'],
    }) => Appointment(
      id: 'a',
      userId: 'u1',
      providerId: const SalonId('p1'),
      serviceIds: serviceIds,
      artistId: artistId,
      appointmentDate: now.add(Duration(minutes: minutes)),
      status: status,
      totalPrice: 20000,
      createdAt: DateTime.utc(2026),
      providerStatus: providerStatus,
    );

    test('every booking that is not upcoming, at a live salon', () {
      final cases = <(AppointmentStatus, int, bool)>[
        (AppointmentStatus.pending, 60, false),
        (AppointmentStatus.confirmed, 60, false),
        (AppointmentStatus.pending, -60, true), // « Non confirmé »
        (AppointmentStatus.confirmed, -60, true),
        (AppointmentStatus.pending, 0, true), // exactly now is past
        (AppointmentStatus.completed, -60, true),
        (AppointmentStatus.completed, 60, true),
        (AppointmentStatus.noShow, -60, true),
        (AppointmentStatus.cancelled, -60, true),
        (AppointmentStatus.cancelled, 60, true),
      ];
      for (final (status, minutes, want) in cases) {
        expect(
          canRebook(appt(status, minutes), now),
          want,
          reason: '${status.name} $minutes',
        );
      }
    });

    test('never at a stopped salon or one this build does not know', () {
      for (final s in ['draft', 'suspended', 'archived']) {
        expect(
          canRebook(
            appt(AppointmentStatus.completed, -60, providerStatus: s),
            now,
          ),
          isFalse,
          reason: s,
        );
      }
      // The pair: no status and `active` are live.
      expect(canRebook(appt(AppointmentStatus.completed, -60), now), isTrue);
      expect(
        canRebook(
          appt(AppointmentStatus.completed, -60, providerStatus: 'active'),
          now,
        ),
        isTrue,
      );
    });

    test('the route carries the salon, the services and the specialist', () {
      final uri = Uri.parse(
        rebookLocation(appt(AppointmentStatus.completed, -60)),
      );
      expect(uri.path, '/booking');
      expect(uri.queryParameters, {
        'providerId': 'p1',
        'serviceIds': 's1,s2',
        'artistId': 'a1',
      });
      final bare = Uri.parse(
        rebookLocation(
          appt(
            AppointmentStatus.completed,
            -60,
            artistId: null,
            serviceIds: const [],
          ),
        ),
      );
      expect(bare.queryParameters, {'providerId': 'p1'});
    });
  });

  // The model's A2 fields: the place and cover round-trip, and the two
  // getters the screens ask.
  group('the booking model (A2)', () {
    Map<String, dynamic> json({Object? lat = 5.36, Object? lng = -3.99}) => {
      'id': 'a',
      'userId': 'u1',
      'providerId': 'p1',
      'serviceIds': ['s1'],
      'appointmentDate': '2026-12-01T09:00:00.000Z',
      'status': 'confirmed',
      'totalPrice': 20000,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'providerLatitude': lat,
      'providerLongitude': lng,
      'providerCommune': 'Cocody',
      'providerCity': 'Abidjan',
      'providerPhotoUrl': 'https://cdn.myweli.com/p1/cover.jpg',
    };

    test('reads the five fields, a whole number as a double', () {
      final a = Appointment.fromJson(json(lat: 5, lng: -4));
      expect(a.providerLatitude, 5.0);
      expect(a.providerLongitude, -4.0);
      expect(a.providerCommune, 'Cocody');
      expect(a.providerCity, 'Abidjan');
      expect(a.providerPhotoUrl, 'https://cdn.myweli.com/p1/cover.jpg');
      expect(a.hasPosition, isTrue);
    });

    test('round-trips through toJson', () {
      final a = Appointment.fromJson(json());
      expect(Appointment.fromJson(a.toJson()), a);
    });

    test('an older server (no keys): nulls, no position', () {
      final j = json()
        ..remove('providerLatitude')
        ..remove('providerLongitude')
        ..remove('providerPhotoUrl');
      final a = Appointment.fromJson(j);
      expect(a.providerLatitude, isNull);
      expect(a.providerPhotoUrl, isNull);
      expect(a.hasPosition, isFalse);
    });

    test('isSalonEntered reads userId == manual, not the client name', () {
      final mine = Appointment.fromJson({...json(), 'clientName': 'Awa'});
      expect(mine.isSalonEntered, isFalse);
      final salonNoName = Appointment.fromJson({
        ...json(),
        'userId': 'manual',
        'clientName': null,
      });
      expect(salonNoName.isSalonEntered, isTrue);
    });
  });
}
