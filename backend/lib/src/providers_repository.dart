/// In-memory provider store for the B1 read slice.
///
/// The data mirrors the Flutter app's mock providers and conforms to the
/// `Provider` schema in `docs/api/openapi.yaml` (which itself mirrors
/// `mobile/lib/models/provider.dart`). It is replaced by a Postgres-backed
/// repository in a later slice — the route handlers depend only on this small
/// surface (`query` + `byId`), so that swap stays localized.
library;

import 'slug.dart' show isReservedSlug;

/// Read access to providers. In-memory now; a Postgres impl (B3b) satisfies the
/// same interface, so the route handlers are unchanged when the store swaps.
abstract interface class ProvidersRepository {
  Future<List<Map<String, dynamic>>> query({
    String? q,
    String? commune,
    String? category,
  });
  Future<Map<String, dynamic>?> byId(String id);

  /// Public read by URL slug (`myweli.ci/<slug>`), same shape as [byId] or null.
  Future<Map<String, dynamic>?> bySlug(String slug);

  /// Append [service] to [providerId]'s catalogue; returns the stored service,
  /// or null if the provider doesn't exist.
  Future<Map<String, dynamic>?> addService(
    String providerId,
    Map<String, dynamic> service,
  );

  /// Merge [changes] into a service; returns the updated service, or null if it
  /// isn't found under [providerId].
  Future<Map<String, dynamic>?> updateService(
    String providerId,
    String serviceId,
    Map<String, dynamic> changes,
  );

  /// Remove a service; false if not found under [providerId].
  Future<bool> deleteService(String providerId, String serviceId);

  /// Merge editable public-profile [changes] (name/description/address/city/
  /// commune/phoneNumber/whatsapp) into [providerId]; returns the updated
  /// provider, or null if it doesn't exist.
  Future<Map<String, dynamic>?> updateProfile(
    String providerId,
    Map<String, dynamic> changes,
  );

  /// Replace [providerId]'s availability wholesale; returns the stored value,
  /// or null if the provider doesn't exist.
  Future<Map<String, dynamic>?> replaceAvailability(
    String providerId,
    Map<String, dynamic> availability,
  );

  /// Replace [providerId]'s gallery (`imageUrls`) wholesale; returns the stored
  /// list, or null if the provider doesn't exist.
  Future<List<String>?> updateGallery(
    String providerId,
    List<String> imageUrls,
  );

  /// Replace [providerId]'s before/after pairs (`beforeAfters`) wholesale;
  /// returns the stored list, or null if the provider doesn't exist.
  Future<List<Map<String, dynamic>>?> updateBeforeAfters(
    String providerId,
    List<Map<String, dynamic>> beforeAfters,
  );

  /// Merge the deposit-policy [fields] into [providerId]'s record; returns the
  /// stored fields, or null if the provider doesn't exist. (Keys are the
  /// provider's storage names, e.g. `depositMobileMoneyOperator`.)
  Future<Map<String, dynamic>?> updateDepositPolicy(
    String providerId,
    Map<String, dynamic> fields,
  );

  /// Recompute-driven update of the provider's `rating`/`reviewCount` and, for
  /// any matching entries in `artists[]`, the per-artist `rating`/`reviewCount`
  /// (from reviews). Returns false if the provider doesn't exist.
  Future<bool> updateRatings(
    String providerId, {
    required double rating,
    required int reviewCount,
    Map<String, ({double rating, int count})> artists,
  });

  /// Append [artist] to [providerId]'s `artists`; returns the stored artist, or
  /// null if the provider doesn't exist.
  Future<Map<String, dynamic>?> addArtist(
    String providerId,
    Map<String, dynamic> artist,
  );

  /// Merge [changes] into an artist; returns the updated artist, or null if it
  /// isn't found under [providerId].
  Future<Map<String, dynamic>?> updateArtist(
    String providerId,
    String artistId,
    Map<String, dynamic> changes,
  );

  /// Remove an artist; false if not found under [providerId].
  Future<bool> deleteArtist(String providerId, String artistId);

  /// Create a minimal DRAFT salon for a new pro account (docs/design/
  /// pro-salon-lifecycle.md §2): seed-shaped document, empty catalogue,
  /// `status: 'draft'` (hidden from every public surface until published),
  /// unique slug derived from [name]. Returns the created provider.
  Future<Map<String, dynamic>> createSalon({
    required String name,
    required String category,
    required String phoneNumber,
    String? address,
  });

  // --- Admin marketplace management — design: docs/design/admin-console.md §12
  /// Set a provider's `status` (`active`/`suspended`). Suspended → excluded from
  /// discovery + new bookings. Returns the updated provider, or null.
  Future<Map<String, dynamic>?> setStatus(String providerId, String status);

  /// Toggle homepage `featured` placement. Returns the updated provider, or null.
  Future<Map<String, dynamic>?> setFeatured(String providerId, bool featured);

  /// Admin list (includes suspended), filterable by status + free-text, paged.
  Future<({List<Map<String, dynamic>> items, int total})> listForAdmin({
    String? status,
    String? q,
    int page,
    int pageSize,
  });
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
            // Hide suspended AND unpublished drafts (T51).
            if (p['status'] == 'suspended' || p['status'] == 'draft') {
              return false;
            }
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
          // Featured first, then by rating.
          ..sort((a, b) {
            final f = ((b['featured'] == true) ? 1 : 0).compareTo(
              (a['featured'] == true) ? 1 : 0,
            );
            if (f != 0) return f;
            return (b['rating'] as num).compareTo(a['rating'] as num);
          });
    return list;
  }

  @override
  Future<Map<String, dynamic>?> byId(String id) async {
    for (final p in _all) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> bySlug(String slug) async {
    for (final p in _all) {
      if (p['slug'] == slug) return p;
    }
    return null;
  }

  List<Map<String, dynamic>> _servicesOf(Map<String, dynamic> p) =>
      (p['services'] as List? ?? (p['services'] = <Map<String, dynamic>>[]))
          .cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> _artistsOf(Map<String, dynamic> p) =>
      (p['artists'] as List? ?? (p['artists'] = <Map<String, dynamic>>[]))
          .cast<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>?> addService(
    String providerId,
    Map<String, dynamic> service,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    _servicesOf(p).add(service);
    return service;
  }

  @override
  Future<Map<String, dynamic>?> updateService(
    String providerId,
    String serviceId,
    Map<String, dynamic> changes,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    for (final s in _servicesOf(p)) {
      if (s['id'] == serviceId) {
        s.addAll(changes);
        return s;
      }
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> updateProfile(
    String providerId,
    Map<String, dynamic> changes,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    p.addAll(changes);
    return p;
  }

  @override
  Future<bool> deleteService(String providerId, String serviceId) async {
    final p = await byId(providerId);
    if (p == null) return false;
    final services = _servicesOf(p);
    final before = services.length;
    services.removeWhere((s) => s['id'] == serviceId);
    return services.length < before;
  }

  @override
  Future<Map<String, dynamic>?> replaceAvailability(
    String providerId,
    Map<String, dynamic> availability,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    p['availability'] = availability;
    return availability;
  }

  @override
  Future<List<String>?> updateGallery(
    String providerId,
    List<String> imageUrls,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    p['imageUrls'] = List<String>.from(imageUrls);
    return List<String>.from(imageUrls);
  }

  @override
  Future<List<Map<String, dynamic>>?> updateBeforeAfters(
    String providerId,
    List<Map<String, dynamic>> beforeAfters,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    final stored = [for (final e in beforeAfters) Map<String, dynamic>.from(e)];
    p['beforeAfters'] = stored;
    return [for (final e in stored) Map<String, dynamic>.from(e)];
  }

  @override
  Future<Map<String, dynamic>?> updateDepositPolicy(
    String providerId,
    Map<String, dynamic> fields,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    p.addAll(fields);
    return Map<String, dynamic>.from(fields);
  }

  @override
  Future<bool> updateRatings(
    String providerId, {
    required double rating,
    required int reviewCount,
    Map<String, ({double rating, int count})> artists = const {},
  }) async {
    final p = await byId(providerId);
    if (p == null) return false;
    p['rating'] = rating;
    p['reviewCount'] = reviewCount;
    for (final a in (p['artists'] as List?) ?? const []) {
      final m = a as Map<String, dynamic>;
      final agg = artists[m['id']];
      if (agg != null) {
        m['rating'] = agg.rating;
        m['reviewCount'] = agg.count;
      }
    }
    return true;
  }

  @override
  Future<Map<String, dynamic>?> addArtist(
    String providerId,
    Map<String, dynamic> artist,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    _artistsOf(p).add(artist);
    return artist;
  }

  @override
  Future<Map<String, dynamic>?> updateArtist(
    String providerId,
    String artistId,
    Map<String, dynamic> changes,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    for (final a in _artistsOf(p)) {
      if (a['id'] == artistId) {
        a.addAll(changes);
        return a;
      }
    }
    return null;
  }

  @override
  Future<bool> deleteArtist(String providerId, String artistId) async {
    final p = await byId(providerId);
    if (p == null) return false;
    final artists = _artistsOf(p);
    final before = artists.length;
    artists.removeWhere((a) => a['id'] == artistId);
    return artists.length < before;
  }

  @override
  Future<Map<String, dynamic>> createSalon({
    required String name,
    required String category,
    required String phoneNumber,
    String? address,
  }) async {
    final id = 'provider_${DateTime.now().microsecondsSinceEpoch}';
    var slug = slugifySalonName(name);
    var n = 2;
    // Reserved slugs (multi-pays MP1): taxonomy roots / city slugs / web
    // routes are never claimable — « Coiffure » becomes coiffure-2.
    while (isReservedSlug(slug) || await bySlug(slug) != null) {
      slug = '${slugifySalonName(name)}-${n++}';
    }
    final salon = draftSalonDocument(
      id: id,
      slug: slug,
      name: name,
      category: category,
      phoneNumber: phoneNumber,
      address: address,
    );
    _all.add(salon);
    return salon;
  }

  @override
  Future<Map<String, dynamic>?> setStatus(
    String providerId,
    String status,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    p['status'] = status;
    return p;
  }

  @override
  Future<Map<String, dynamic>?> setFeatured(
    String providerId,
    bool featured,
  ) async {
    final p = await byId(providerId);
    if (p == null) return null;
    p['featured'] = featured;
    return p;
  }

  @override
  Future<({List<Map<String, dynamic>> items, int total})> listForAdmin({
    String? status,
    String? q,
    int page = 1,
    int pageSize = 20,
  }) async {
    final all = _all.where((p) {
      if (status != null && status.isNotEmpty) {
        if ((p['status'] ?? 'active') != status) return false;
      }
      if (q != null && q.isNotEmpty) {
        final hay = '${p['name']} ${p['address']}'.toLowerCase();
        if (!hay.contains(q.toLowerCase())) return false;
      }
      return true;
    }).toList();
    final start = (page - 1) * pageSize;
    final items = start >= all.length
        ? <Map<String, dynamic>>[]
        : all.sublist(start, (start + pageSize).clamp(0, all.length));
    return (items: items, total: all.length);
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
    'weeklySchedule': _defaultWeeklySchedule(),
    'blockedDates': <String>[],
    'bufferMinutes': 10,
  };
}

/// Mon–Sat (weekday 0..5), 09:00–18:00 as 30-minute opening slots. Times are
/// wall-clock (the date part is ignored by the slot engine; Abidjan is UTC+0).
Map<String, dynamic> _defaultWeeklySchedule() {
  final slots = <Map<String, dynamic>>[];
  for (var minutes = 9 * 60; minutes < 18 * 60; minutes += 30) {
    final start = DateTime.utc(2024, 1, 1, minutes ~/ 60, minutes % 60);
    slots.add({
      'startTime': start.toIso8601String(),
      'endTime': start.add(const Duration(minutes: 30)).toIso8601String(),
      'isAvailable': true,
    });
  }
  return {for (var day = 0; day <= 5; day++) '$day': slots};
}

final List<Map<String, dynamic>> seedProviders = [
  {
    'id': 'provider1',
    'slug': 'beaute-divine',
    'name': 'Beauté Divine',
    'description': 'Salon de coiffure et soins à Cocody.',
    'address': 'Rue des Jardins, Cocody, Abidjan',
    'city': 'Abidjan',
    'commune': 'Cocody',
    'areaId': 'cocody',
    'citySlug': 'abidjan',
    'countryCode': 'CI',
    'timezone': 'Africa/Abidjan',
    'currency': 'XOF',
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
    'verified': true,
    'depositRequired': false,
    'depositPercentage': 0.30,
    'depositMobileMoneyOperator': null,
    'depositMobileMoneyNumber': null,
    'cancellationWindowHours': 24,
    'reviews': <Map<String, dynamic>>[],
  },
  {
    'id': 'provider2',
    'slug': 'elegance-coiffure',
    'name': 'Élégance Coiffure',
    'description': 'Coiffure et maquillage, acompte requis.',
    'address': 'Boulevard Latrille, Cocody, Abidjan',
    'city': 'Abidjan',
    'commune': 'Cocody',
    'areaId': 'cocody',
    'citySlug': 'abidjan',
    'countryCode': 'CI',
    'timezone': 'Africa/Abidjan',
    'currency': 'XOF',
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
    'verified': true,
    'depositRequired': true,
    'depositPercentage': 0.50,
    'depositMobileMoneyOperator': 'wave',
    'depositMobileMoneyNumber': '+2250544556677',
    'cancellationWindowHours': 24,
    'reviews': <Map<String, dynamic>>[],
  },
  {
    'id': 'provider3',
    'slug': 'barber-king',
    'name': 'Barber King',
    'description': 'Barbier moderne à Yopougon.',
    'address': 'Avenue Principale, Yopougon, Abidjan',
    'city': 'Abidjan',
    'commune': 'Yopougon',
    'areaId': 'yopougon',
    'citySlug': 'abidjan',
    'countryCode': 'CI',
    'timezone': 'Africa/Abidjan',
    'currency': 'XOF',
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
    'verified': true,
    'depositRequired': false,
    'depositPercentage': 0.30,
    'depositMobileMoneyOperator': null,
    'depositMobileMoneyNumber': null,
    'cancellationWindowHours': 12,
    'reviews': <Map<String, dynamic>>[],
  },
  {
    'id': 'provider4',
    'slug': 'nails-co',
    'name': 'Nails & Co',
    'description': 'Onglerie et soins des mains à Marcory.',
    'address': 'Zone 4, Marcory, Abidjan',
    'city': 'Abidjan',
    'commune': 'Marcory',
    'areaId': 'marcory',
    'citySlug': 'abidjan',
    'countryCode': 'CI',
    'timezone': 'Africa/Abidjan',
    'currency': 'XOF',
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
    'verified': true,
    'depositRequired': false,
    'depositPercentage': 0.30,
    'depositMobileMoneyOperator': null,
    'depositMobileMoneyNumber': null,
    'cancellationWindowHours': 24,
    'reviews': <Map<String, dynamic>>[],
  },
];

/// URL slug from a salon name: lowercased, accents stripped, non-alphanumerics
/// collapsed to single dashes (`Ébène & Co` → `ebene-co`).
String slugifySalonName(String name) {
  const accents = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const plain = 'aaaaaaceeeeiiiinooooouuuuyy';
  final lower = name.trim().toLowerCase();
  final sb = StringBuffer();
  for (final ch in lower.split('')) {
    final i = accents.indexOf(ch);
    sb.write(i >= 0 ? plain[i] : ch);
  }
  final slug = sb
      .toString()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('(^-+|-+\$)'), '');
  return slug.isEmpty ? 'salon' : slug;
}

/// The minimal seed-shaped provider document a fresh registration gets
/// (docs/design/pro-salon-lifecycle.md §2). Everything the read slices touch
/// is present; the catalogue starts empty; `status: 'draft'` keeps it off
/// every public surface until `POST /providers/{id}/publish`.
Map<String, dynamic> draftSalonDocument({
  required String id,
  required String slug,
  required String name,
  required String category,
  required String phoneNumber,
  String? address,
}) => {
  'id': id,
  'slug': slug,
  'name': name,
  'description': '',
  'address': address ?? '',
  'city': 'Abidjan',
  'commune': null,
  // Multi-pays Wave-0 defaults — re-derived on every areaId write
  // (docs/design/multi-pays-end-version.md §2; registration is
  // CI-scoped until a multi-country registration UX exists).
  'areaId': null,
  'citySlug': null,
  'countryCode': 'CI',
  'timezone': 'Africa/Abidjan',
  'currency': 'XOF',
  'latitude': null,
  'longitude': null,
  'imageUrls': <String>[],
  'logoUrl': null,
  'rating': 0,
  'reviewCount': 0,
  'services': <Map<String, dynamic>>[],
  'artists': <Map<String, dynamic>>[],
  'availability': {
    'providerId': id,
    'weeklySchedule': <String, dynamic>{},
    'blockedDates': <String>[],
    'bufferMinutes': 0,
  },
  'phoneNumber': phoneNumber,
  'whatsapp': phoneNumber,
  'category': category,
  'depositRequired': false,
  'depositPercentage': 0.0,
  'depositMobileMoneyOperator': null,
  'depositMobileMoneyNumber': null,
  'cancellationWindowHours': 24,
  'status': 'draft',
  'verified': false,
};
