import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/calendar_event.dart';

void main() {
  final start = DateTime(2026, 6, 28, 10, 0);

  test('composes title, location and service description', () {
    final e = buildAppointmentCalendarEvent(
      providerName: 'Beauté Divine',
      providerAddress: 'Cocody, Abidjan',
      serviceNames: ['Tresses', 'Soin'],
      start: start,
      totalDurationMinutes: 90,
    );
    expect(e.title, 'Rendez-vous — Beauté Divine');
    expect(e.location, 'Cocody, Abidjan');
    expect(e.description, contains('Tresses, Soin'));
    expect(e.end, start.add(const Duration(minutes: 90)));
  });

  test('floors duration to 30 min when unknown', () {
    final e = buildAppointmentCalendarEvent(
      providerName: 'X',
      serviceNames: const [],
      start: start,
      totalDurationMinutes: 0,
    );
    expect(e.end, start.add(const Duration(minutes: 30)));
  });

  test('location falls back to provider name when address is empty', () {
    final e = buildAppointmentCalendarEvent(
      providerName: 'Salon X',
      providerAddress: '   ',
      serviceNames: const ['Coupe'],
      start: start,
      totalDurationMinutes: 30,
    );
    expect(e.location, 'Salon X');
  });

  test('deposit line only present when a deposit applies', () {
    final withDeposit = buildAppointmentCalendarEvent(
      providerName: 'X',
      serviceNames: const ['Coupe'],
      start: start,
      totalDurationMinutes: 30,
      depositAmount: 6000,
      balanceDue: 14000,
    );
    expect(withDeposit.description, contains('Acompte'));

    final noDeposit = buildAppointmentCalendarEvent(
      providerName: 'X',
      serviceNames: const ['Coupe'],
      start: start,
      totalDurationMinutes: 30,
    );
    expect(noDeposit.description, isNot(contains('Acompte')));
  });

  test(
      'the deposit line renders the booking currency — XAF reads FCFA '
      '(multi-pays MP2)', () {
    final e = buildAppointmentCalendarEvent(
      providerName: 'Institut Libreville',
      serviceNames: const ['Coupe'],
      start: start,
      totalDurationMinutes: 30,
      depositAmount: 6000,
      balanceDue: 14000,
      currency: 'XAF',
    );
    expect(e.description, contains('FCFA'));
    expect(e.description, isNot(contains('XAF')));
  });
}
