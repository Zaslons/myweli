import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/data_export.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/availability.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/models/salon_client.dart';
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

  test('buildProviderDataExport assembles the salon document (11.5)', () {
    final export = buildProviderDataExport(
      account: ProviderUser(
        id: 'pu1',
        phoneNumber: '+2250700000000',
        businessName: 'Salon X',
        businessType: BusinessType.salon,
        createdAt: DateTime(2026),
        providerId: 'p1',
      ),
      salon: const models.Provider(
        id: 'p1',
        name: 'Salon X',
        description: 'desc',
        address: 'Cocody',
        imageUrls: [],
        rating: 4.5,
        reviewCount: 3,
        services: [],
        availability: Availability(
          providerId: 'p1',
          weeklySchedule: {},
          blockedDates: [],
        ),
        phoneNumber: '+22500',
        category: 'salon',
      ),
      services: const [],
      artists: const [],
      appointments: const [],
      clients: const [
        SalonClient(
          id: 'sc1',
          displayName: 'Koffi',
          phone: '+2250700000001',
          tags: ['VIP'],
          linked: false,
          visits: 4,
          noShows: 0,
        ),
      ],
      generatedAt: DateTime.utc(2026, 7, 11),
    );

    expect((export['account'] as Map)['businessName'], 'Salon X');
    expect((export['salon'] as Map)['commune'], isNull);
    final clients = export['clients'] as List;
    expect((clients.first as Map)['name'], 'Koffi');
    expect((clients.first as Map)['visits'], 4);
    expect(export['generatedAt'], '2026-07-11T00:00:00.000Z');
  });

  // docs/design/app-pro-export-completeness.md §4 — the web's
  // `wholeClientBase` (web/lib/pro/export.ts), the same five cases.
  group('wholeClientBase', () {
    SalonClient client(String id) =>
        SalonClient(id: id, displayName: id, tags: const [], linked: false);
    SalonClientsPage page(int n, int total, List<String> ids) =>
        SalonClientsPage(
          items: [for (final id in ids) client(id)],
          page: n,
          total: total,
          pageSize: 2,
        );

    test('a whole walk → every client, once, in walk order', () {
      final base = wholeClientBase([
        page(1, 5, ['a', 'b']),
        page(2, 5, ['c', 'd']),
        page(3, 5, ['e']),
      ]);
      expect(base?.map((c) => c.id), ['a', 'b', 'c', 'd', 'e']);
    });

    test('an empty base → an empty list, not a refusal', () {
      expect(wholeClientBase([page(1, 0, [])]), isEmpty);
    });

    test('a total that moves → refused, even when the ids add up', () {
      // 4 distinct ids against the first page's total of 4: only the
      // moved total gives the walk away.
      expect(
        wholeClientBase([
          page(1, 4, ['a', 'b']),
          page(2, 5, ['c', 'd']),
        ]),
        isNull,
      );
    });

    test('a repeated row (an offset that slid) → refused', () {
      expect(
        wholeClientBase([
          page(1, 4, ['a', 'b']),
          page(2, 4, ['b', 'c']),
        ]),
        isNull,
      );
    });

    test('a walk that falls short → refused', () {
      expect(
        wholeClientBase([
          page(1, 3, ['a', 'b']),
        ]),
        isNull,
      );
    });

    test('no pages → refused', () {
      expect(wholeClientBase(const []), isNull);
    });
  });

  group('proExportFailureMessage', () {
    const tail = 'Vérifiez votre connexion et réessayez.';

    test('one section', () {
      expect(
        proExportFailureMessage({ProExportSection.clients}),
        'Export interrompu : impossible de charger le fichier clients. $tail',
      );
    });

    test('two sections, in the file’s order, joined with « et »', () {
      expect(
        proExportFailureMessage({
          ProExportSection.clients,
          ProExportSection.salon,
        }),
        'Export interrompu : impossible de charger la fiche du salon et '
        'le fichier clients. $tail',
      );
    });

    test('three or more: commas, then « et »', () {
      expect(
        proExportFailureMessage({
          ProExportSection.appointments,
          ProExportSection.artists,
          ProExportSection.services,
        }),
        'Export interrompu : impossible de charger les services, l’équipe '
        'et les rendez-vous. $tail',
      );
    });
  });
}
