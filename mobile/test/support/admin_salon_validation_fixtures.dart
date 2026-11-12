/// The B0.18 admin routes' bodies, as the backend builds them
/// (`SalonValidationService.queue` / `.detail`, salon_validation_dto.dart) —
/// for the console's service and provider tests.
library;

Map<String, dynamic> validationJson({
  String state = 'pending',
  bool wentLive = false,
  String? decidedAt,
  Map<String, dynamic>? refusal,
}) => {
  'state': state,
  'submittedAt': '2026-11-12T09:00:00.000Z',
  'decidedAt': ?decidedAt,
  'wentLive': wentLive,
  'refusal': ?refusal,
};

Map<String, dynamic> queueItem({
  String id = 'provider_1',
  String name = 'Beauté Divine',
  String state = 'pending',
  bool wentLive = false,
}) => {
  'providerId': id,
  'name': name,
  'commune': 'Cocody',
  'city': 'Abidjan',
  'countryCode': 'CI',
  'salonStatus': 'draft',
  'validation': validationJson(state: state, wentLive: wentLive),
  'ownerContact': 'awa@example.com',
  'kycDocCount': 0,
};

Map<String, dynamic> queuePage({
  int total = 1,
  int page = 1,
  List<Map<String, dynamic>>? items,
}) => {
  'items': items ?? [queueItem()],
  'page': page,
  'pageSize': 50,
  'total': total,
};

Map<String, dynamic> detailJson({
  String id = 'provider_1',
  String name = 'Beauté Divine',
  String salonStatus = 'draft',
  Map<String, dynamic>? validation,
  bool neverAsked = false,
}) => {
  'salon': {
    'id': id,
    'name': name,
    'category': 'coiffure',
    'description': 'Tresses et soins',
    'status': salonStatus,
    'imageUrls': [
      'https://cdn.myweli.com/a.jpg',
      'https://cdn.myweli.com/b.jpg',
      'https://cdn.myweli.com/c.jpg',
    ],
    'logoUrl': null,
    'services': [
      {
        'id': 's1',
        'name': 'Tresses',
        'price': 15000,
        'priceMax': 25000,
        'durationMinutes': 120,
        'active': true,
      },
      {
        'id': 's2',
        'name': 'Brushing',
        'price': 5000,
        'durationMinutes': 45,
        'active': false,
      },
    ],
    'availability': {
      'providerId': id,
      'weeklySchedule': {
        '0': [
          {
            'startTime': '2024-01-01T09:00:00.000',
            'endTime': '2024-01-01T18:00:00.000',
            'isAvailable': true,
          },
        ],
        '6': <Map<String, dynamic>>[],
      },
      'blockedDates': <String>[],
      'bufferMinutes': 0,
    },
    'address': 'Rue des Jardins',
    'commune': 'Cocody',
    'city': 'Abidjan',
    'areaId': 'ci-abidjan-cocody',
    'countryCode': 'CI',
    'timezone': 'Africa/Abidjan',
    'currency': 'XOF',
    'latitude': 5.36,
    'longitude': -3.99,
    'phoneNumber': '+2250707070707',
    'whatsapp': null,
  },
  'offer': {
    'tier': 'pro',
    'status': 'trial',
    'trialEndsAt': '2027-02-10T00:00:00.000Z',
    'paidUntil': null,
    'graceEndsAt': '2027-02-17T00:00:00.000Z',
    'unpublishedForBilling': false,
    'seats': {'cap': 5, 'used': 1},
  },
  'owner': {
    'accountId': 'acc_1',
    'name': 'Awa Koné',
    'businessName': 'Beauté Divine',
    'email': 'awa@example.com',
    'phone': '+2250707070707',
    'contact': 'awa@example.com',
    'createdAt': '2026-10-31T09:00:00.000Z',
    'accountAgeDays': 12,
    'kycStatus': 'pending',
    'kycDocCount': 0,
    'otherSalons': [
      {'id': 'provider_2', 'name': 'Beauté Divine 2', 'status': 'draft'},
    ],
  },
  'validation': neverAsked
      ? null
      : (validation ?? {...validationJson(), 'decidedBy': null}),
  'events': neverAsked
      ? <Map<String, dynamic>>[]
      : [
          {
            'kind': 'submitted',
            'at': '2026-11-12T09:00:00.000Z',
            'by': null,
            'refusalCode': null,
            'refusalNote': null,
          },
        ],
};
