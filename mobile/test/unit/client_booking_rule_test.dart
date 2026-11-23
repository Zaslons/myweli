import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/chip_tone.dart';
import 'package:myweli/core/utils/client_booking_rule.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/appointment.dart';

/// The one rule for a client's own bookings (docs/design/consumer-app-truth.md
/// §2.7), the same table as the web's `clientTab(a, now)`.
void main() {
  final now = DateTime(2026, 6, 22, 12);
  final past = DateTime(2026, 6, 1, 10);
  final future = DateTime(2026, 7, 1, 10);

  Appointment appt(AppointmentStatus status, DateTime date) => Appointment(
    id: 'a',
    userId: 'u1',
    providerId: const SalonId('p1'),
    serviceIds: const ['s1'],
    appointmentDate: date,
    status: status,
    totalPrice: 20000,
    createdAt: DateTime(2026),
  );

  // (status, time, tab, chip, tone) — the spec's table, row by row.
  final rows = [
    (
      AppointmentStatus.pending,
      future,
      ClientBookingTab.upcoming,
      'En attente',
      AppChipTone.warning,
    ),
    (
      AppointmentStatus.confirmed,
      future,
      ClientBookingTab.upcoming,
      'Confirmé',
      AppChipTone.success,
    ),
    (
      AppointmentStatus.pending,
      past,
      ClientBookingTab.past,
      'Non confirmé',
      AppChipTone.neutral,
    ),
    (
      AppointmentStatus.confirmed,
      past,
      ClientBookingTab.past,
      'Confirmé',
      AppChipTone.success,
    ),
    (
      AppointmentStatus.completed,
      past,
      ClientBookingTab.past,
      'Terminé',
      AppChipTone.neutral,
    ),
    (
      AppointmentStatus.completed,
      future,
      ClientBookingTab.past,
      'Terminé',
      AppChipTone.neutral,
    ),
    (
      AppointmentStatus.noShow,
      past,
      ClientBookingTab.past,
      'Absent',
      AppChipTone.error,
    ),
    (
      AppointmentStatus.noShow,
      future,
      ClientBookingTab.past,
      'Absent',
      AppChipTone.error,
    ),
    (
      AppointmentStatus.cancelled,
      past,
      ClientBookingTab.cancelled,
      'Annulé',
      AppChipTone.error,
    ),
    (
      AppointmentStatus.cancelled,
      future,
      ClientBookingTab.cancelled,
      'Annulé',
      AppChipTone.error,
    ),
  ];

  for (final (status, date, tab, label, tone) in rows) {
    final when = date.isAfter(now) ? 'ahead' : 'past';
    test('${status.name}, $when → $tab, « $label »', () {
      final a = appt(status, date);
      expect(clientTab(a, now), tab);
      expect(clientStatusLabel(a, now), label);
      expect(clientStatusTone(a, now), tone);
    });
  }

  test('a past booking is never relabelled « Terminé »', () {
    for (final s in [AppointmentStatus.pending, AppointmentStatus.confirmed]) {
      expect(clientStatusLabel(appt(s, past), now), isNot('Terminé'));
    }
  });

  // docs/design/web-account-bookings-truth.md §2.8: the web's
  // `client-booking-rule-table.test.ts` reads the same file. A rule changed on
  // one surface turns that surface red; a row changed in the file turns both
  // red until both follow.
  group('the shared table (docs/design/fixtures/client-booking-rule.json)', () {
    final table =
        jsonDecode(
              File(
                '../docs/design/fixtures/client-booking-rule.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final rows = (table['rows'] as List).cast<Map<String, dynamic>>();

    test('has the seven rows plus the edges — an emptied file cannot pass', () {
      expect(rows.length, greaterThanOrEqualTo(13));
      expect(rows.map((r) => r['status']).toSet(), {
        'pending',
        'confirmed',
        'completed',
        'noShow',
        'cancelled',
      });
      expect(rows.any((r) => r['minutesFromNow'] == 0), isTrue);
    });

    for (final r in rows) {
      final status = r['status'] as String;
      final minutes = r['minutesFromNow'] as int;
      test('$status at $minutes min → ${r['tab']}, « ${r['label']} »', () {
        final a = appt(
          AppointmentStatus.values.byName(status),
          now.add(Duration(minutes: minutes)),
        );
        expect(
          clientTab(a, now),
          ClientBookingTab.values.byName(r['tab'] as String),
        );
        expect(clientStatusLabel(a, now), r['label']);
        expect(
          clientStatusTone(a, now),
          AppChipTone.values.byName(r['tone'] as String),
        );
      });
    }
  });

  test('a booking exactly at now is past, as on the web', () {
    final a = appt(AppointmentStatus.pending, now);
    expect(clientTab(a, now), ClientBookingTab.past);
    expect(clientStatusLabel(a, now), 'Non confirmé');
    // One minute ahead is still upcoming.
    final b = appt(
      AppointmentStatus.pending,
      now.add(const Duration(minutes: 1)),
    );
    expect(clientTab(b, now), ClientBookingTab.upcoming);
  });
}
