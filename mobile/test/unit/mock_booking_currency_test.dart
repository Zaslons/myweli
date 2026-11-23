import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/services/mock/mock_appointment_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/frozen_clock.dart';

/// The mock returns what the server returns (docs/design/
/// appointment-currency-stamp.md §5.3, B14.3): a booking it creates is
/// stamped with its salon's currency, as `booking_service.dart` stamps it and
/// as the server stores it since migration 0047. It used to set only
/// `providerCurrency`, mirroring the production defect B14.1 fixed — and a
/// mock that mirrors a defect hides it from every test built on it.
void main() {
  setUpAll(() => AppClock.freeze(kFixedNow));
  tearDownAll(AppClock.restore);

  test('a booking the mock creates carries its salon’s currency', () async {
    SharedPreferences.setMockInitialValues({});
    final salon = MockData.providers.first;
    expect(salon.currency, isNotNull, reason: 'the control: the salon has one');

    final res = await MockAppointmentService().bookAppointment(
      providerId: salon.id,
      serviceIds: [salon.services.first.id],
      appointmentDateTime: kFixedNow.add(const Duration(days: 2)),
      // Named, so the mock's own artist pick cannot refuse the slot.
      artistId: 'any',
    );
    expect(res.success, isTrue, reason: '${res.error}');
    expect(res.data!.currency, salon.currency);
  });
}
