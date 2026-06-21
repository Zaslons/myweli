import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/data_export.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/user.dart';

void main() {
  final user = User(
    id: 'u1',
    phoneNumber: '+2250700000012',
    name: 'Awa Koné',
    email: 'awa@example.com',
    createdAt: DateTime(2025, 5, 1),
  );

  Appointment appointment(String id) => Appointment(
        id: id,
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1', 's2'],
        appointmentDate: DateTime(2026, 6, 21, 10),
        status: AppointmentStatus.completed,
        totalPrice: 20000,
        depositAmount: 6000,
        createdAt: DateTime(2026, 6, 1),
      );

  test('includes the profile, appointments and favorites', () {
    final export = buildUserDataExport(
      user: user,
      appointments: [appointment('a1'), appointment('a2')],
      favoriteProviderNames: const ['Salon Excellence', 'Chez Awa'],
      generatedAt: DateTime(2026, 6, 22, 9),
    );

    final profile = export['profile'] as Map<String, dynamic>;
    expect(profile['phoneNumber'], '+2250700000012');
    expect(profile['name'], 'Awa Koné');
    expect(profile['memberSince'], DateTime(2025, 5, 1).toIso8601String());

    expect(export['appointments'], hasLength(2));
    final first =
        (export['appointments'] as List).first as Map<String, dynamic>;
    expect(first['providerId'], 'p1');
    expect(first['status'], 'completed');
    expect(first['serviceIds'], ['s1', 's2']);

    expect(export['favorites'], ['Salon Excellence', 'Chez Awa']);
    expect(export['generatedAt'], DateTime(2026, 6, 22, 9).toIso8601String());
  });

  test('handles a user with no appointments or favorites', () {
    final export = buildUserDataExport(
      user: user,
      appointments: const [],
      favoriteProviderNames: const [],
    );

    expect(export['appointments'], isEmpty);
    expect(export['favorites'], isEmpty);
    expect((export['profile'] as Map<String, dynamic>)['id'], 'u1');
  });
}
