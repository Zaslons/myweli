/// In-memory provider store for the B1 read slice.
///
/// The data mirrors the Flutter app's mock providers and conforms to the
/// `Provider` schema in `docs/api/openapi.yaml` (which itself mirrors
/// `mobile/lib/models/provider.dart`). It is replaced by a Postgres-backed
/// repository in a later slice — the route handlers depend only on this small
/// surface (`query` + `byId`), so that swap stays localized.
/// Read access to providers. In-memory now; a Postgres impl (B3b) satisfies the
/// same interface, so the route handlers are unchanged when the store swaps.
abstract interface class ProvidersRepository {
  Future<List<Map<String, dynamic>>> query({
    String? q,
    String? commune,
    String? category,
  });
  Future<Map<String, dynamic>?> byId(String id);
}

class InMemoryProvidersRepository implements ProvidersRepository {
  InMemoryProvidersRepository([List<Map<String, dynamic>>? seed])
    : _all = seed ?? seedProviders;

  final List<Map<String, dynamic>> _all;

  /// Filtered by category / commune / free-text query, sorted by rating desc
  /// (so an unsorted `getProviders` and `getFeaturedProviders` agree).
  @override
  Future<List<Map<String, dynamic>>> query({
    String? q,
    String? commune,
    String? category,
  }) async {
    final list =
        _all.where((p) {
            if (category != null &&
                category.isNotEmpty &&
                p['category'] != category) {
              return false;
            }
            if (commune != null &&
                commune.isNotEmpty &&
                p['commune'] != commune) {
              return false;
            }
            if (q != null && q.isNotEmpty) {
              final hay = '${p['name']} ${p['description']} ${p['address']}'
                  .toLowerCase();
              if (!hay.contains(q.toLowerCase())) return false;
            }
            return true;
          }).toList()
          ..sort((a, b) => (b['rating'] as num).compareTo(a['rating'] as num));
    return list;
  }

  @override
  Future<Map<String, dynamic>?> byId(String id) async {
    for (final p in _all) {
      if (p['id'] == id) return p;
    }
    return null;
  }
}

Map<String, dynamic> _service({
  required String id,
  required String providerId,
  required String name,
  required String description,
  required num price,
  num? priceMax,
  required int durationMinutes,
}) {
  return {
    'id': id,
    'name': name,
    'description': description,
    'price': price,
    'priceMax': priceMax,
    'durationMinutes': durationMinutes,
    'durationVariants': <String, dynamic>{},
    'providerId': providerId,
    'artistIds': <String>[],
  };
}

Map<String, dynamic> _availability(String providerId) {
  return {
    'providerId': providerId,
    'weeklySchedule': <String, dynamic>{},
    'blockedDates': <String>[],
    'bufferMinutes': 0,
  };
}

final List<Map<String, dynamic>> seedProviders = [
  {
    'id': 'provider1',
    'name': 'Beauté Divine',
    'description': 'Salon de coiffure et soins à Cocody.',
    'address': 'Rue des Jardins, Cocody, Abidjan',
    'city': 'Abidjan',
    'commune': 'Cocody',
    'latitude': 5.3599,
    'longitude': -3.9871,
    'imageUrls': <String>['asset:assets/images/salon1.jpg'],
    'logoUrl': null,
    'rating': 4.8,
    'reviewCount': 127,
    'services': [
      _service(
        id: 'service1',
        providerId: 'provider1',
        name: 'Tresses',
        description: 'Tresses africaines au choix.',
        price: 15000,
        priceMax: 35000,
        durationMinutes: 180,
      ),
      _service(
        id: 'service2',
        providerId: 'provider1',
        name: 'Soin du visage',
        description: 'Nettoyage et hydratation.',
        price: 12000,
        durationMinutes: 60,
      ),
    ],
    'artists': <Map<String, dynamic>>[],
    'availability': _availability('provider1'),
    'phoneNumber': '+2250707010101',
    'whatsapp': '+2250707010101',
    'category': 'salon',
    'depositRequired': false,
    'depositPercentage': 0.30,
    'depositMobileMoneyOperator': null,
    'depositMobileMoneyNumber': null,
    'cancellationWindowHours': 24,
    'reviews': <Map<String, dynamic>>[],
  },
  {
    'id': 'provider2',
    'name': 'Élégance Coiffure',
    'description': 'Coiffure et maquillage, acompte requis.',
    'address': 'Boulevard Latrille, Cocody, Abidjan',
    'city': 'Abidjan',
    'commune': 'Cocody',
    'latitude': 5.3712,
    'longitude': -3.9923,
    'imageUrls': <String>['asset:assets/images/salon2.jpg'],
    'logoUrl': null,
    'rating': 4.6,
    'reviewCount': 89,
    'services': [
      _service(
        id: 'service4',
        providerId: 'provider2',
        name: 'Maquillage évènement',
        description: 'Maquillage pour mariage ou cérémonie.',
        price: 25000,
        priceMax: 50000,
        durationMinutes: 90,
      ),
    ],
    'artists': <Map<String, dynamic>>[],
    'availability': _availability('provider2'),
    'phoneNumber': '+2250544556677',
    'whatsapp': '+2250544556677',
    'category': 'salon',
    'depositRequired': true,
    'depositPercentage': 0.50,
    'depositMobileMoneyOperator': 'wave',
    'depositMobileMoneyNumber': '+2250544556677',
    'cancellationWindowHours': 24,
    'reviews': <Map<String, dynamic>>[],
  },
  {
    'id': 'provider3',
    'name': 'Barber King',
    'description': 'Barbier moderne à Yopougon.',
    'address': 'Avenue Principale, Yopougon, Abidjan',
    'city': 'Abidjan',
    'commune': 'Yopougon',
    'latitude': 5.3456,
    'longitude': -4.0712,
    'imageUrls': <String>['asset:assets/images/barber1.jpg'],
    'logoUrl': null,
    'rating': 4.9,
    'reviewCount': 203,
    'services': [
      _service(
        id: 'service6',
        providerId: 'provider3',
        name: 'Coupe homme',
        description: 'Coupe et contours nets.',
        price: 3000,
        durationMinutes: 30,
      ),
    ],
    'artists': <Map<String, dynamic>>[],
    'availability': _availability('provider3'),
    'phoneNumber': '+2250708090910',
    'whatsapp': null,
    'category': 'barber',
    'depositRequired': false,
    'depositPercentage': 0.30,
    'depositMobileMoneyOperator': null,
    'depositMobileMoneyNumber': null,
    'cancellationWindowHours': 12,
    'reviews': <Map<String, dynamic>>[],
  },
  {
    'id': 'provider4',
    'name': 'Nails & Co',
    'description': 'Onglerie et soins des mains à Marcory.',
    'address': 'Zone 4, Marcory, Abidjan',
    'city': 'Abidjan',
    'commune': 'Marcory',
    'latitude': 5.2998,
    'longitude': -3.9876,
    'imageUrls': <String>['asset:assets/images/nails1.jpg'],
    'logoUrl': null,
    'rating': 4.5,
    'reviewCount': 64,
    'services': [
      _service(
        id: 'service8',
        providerId: 'provider4',
        name: 'Pose de capsules',
        description: 'Capsules + vernis semi-permanent.',
        price: 10000,
        priceMax: 18000,
        durationMinutes: 75,
      ),
    ],
    'artists': <Map<String, dynamic>>[],
    'availability': _availability('provider4'),
    'phoneNumber': '+2250101020203',
    'whatsapp': '+2250101020203',
    'category': 'nails',
    'depositRequired': false,
    'depositPercentage': 0.30,
    'depositMobileMoneyOperator': null,
    'depositMobileMoneyNumber': null,
    'cancellationWindowHours': 24,
    'reviews': <Map<String, dynamic>>[],
  },
];
