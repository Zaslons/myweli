import '../../models/appointment.dart';
import '../../models/artist.dart';
import '../../models/availability.dart';
import '../../models/before_after_pair.dart';
import '../../models/payment.dart';
import '../../models/provider.dart';
import '../../models/provider_user.dart';
import '../../models/review.dart';
import '../../models/service.dart';
import '../../models/user.dart';

class MockData {
  // Sample Users
  static final List<User> users = [
    User(
      id: 'user1',
      phoneNumber: '+225 07 12 34 56',
      name: 'Jean Kouassi',
      createdAt: DateTime(2024, 1, 1),
    ),
    User(
      id: 'user2',
      phoneNumber: '+225 05 98 76 54',
      name: 'Marie Diallo',
      createdAt: DateTime(2024, 1, 15),
    ),
  ];

  // Sample Provider Users (providerId links to consumer Provider)
  static final List<ProviderUser> providerUsers = [
    ProviderUser(
      id: 'provider_user1',
      phoneNumber: '+225 07 11 22 33 44',
      name: 'Jean Kouassi',
      businessName: 'Salon Excellence',
      businessType: BusinessType.barber,
      address: 'Cocody, Angré 7ème Tranche',
      verificationStatus: VerificationStatus.verified,
      createdAt: DateTime(2024, 1, 1),
      providerId: 'provider1',
    ),
    ProviderUser(
      id: 'provider_user2',
      phoneNumber: '+225 05 44 55 66 77',
      name: 'Marie Diallo',
      businessName: 'Beauté Divine',
      businessType: BusinessType.salon,
      address: 'Marcory, Zone 4',
      verificationStatus: VerificationStatus.verified,
      createdAt: DateTime(2024, 1, 15),
      providerId: 'provider2',
    ),
  ];

  // Build a simple per-day working-hours map (one range per listed weekday).
  static Map<int, List<TimeSlot>> _weekdayHours({
    required int startHour,
    required int endHour,
    required List<int> days,
  }) {
    return {
      for (final d in days)
        d: [
          TimeSlot(
            startTime: DateTime(2000, 1, 1, startHour),
            endTime: DateTime(2000, 1, 1, endHour),
            isAvailable: true,
          ),
        ],
    };
  }

  // Sample Artists
  static List<Artist> getArtistsForProvider(String providerId) {
    if (providerId == 'provider1') {
      return [
        const Artist(
          id: 'artist1',
          name: 'Kouassi Jean',
          providerId: 'provider1',
          specialization: 'Barbier',
          rating: 4.8,
          reviewCount: 45,
        ),
        const Artist(
          id: 'artist2',
          name: 'Diallo Amadou',
          providerId: 'provider1',
          specialization: 'Coiffeur',
          rating: 4.6,
          reviewCount: 32,
        ),
      ];
    } else if (providerId == 'provider2') {
      return [
        const Artist(
          id: 'artist3',
          name: 'Marie Kouassi',
          providerId: 'provider2',
          specialization: 'Coiffeuse',
          rating: 4.9,
          reviewCount: 67,
        ),
        const Artist(
          id: 'artist4',
          name: 'Fatou Diallo',
          providerId: 'provider2',
          specialization: 'Esthéticienne',
          rating: 4.7,
          reviewCount: 28,
        ),
        Artist(
          id: 'artist5',
          name: 'Aminata Traoré',
          providerId: 'provider2',
          specialization: 'Coiffeuse',
          rating: 4.5,
          reviewCount: 19,
          // Part-time: Tue–Sat 10:00–17:00, off Monday & Sunday.
          workingHours: _weekdayHours(
            startHour: 10,
            endHour: 17,
            days: const [1, 2, 3, 4, 5],
          ),
        ),
      ];
    } else if (providerId == 'provider3') {
      return [
        const Artist(
          id: 'artist6',
          name: 'Sophie Martin',
          providerId: 'provider3',
          specialization: 'Massothérapeute',
          rating: 4.8,
          reviewCount: 52,
        ),
        const Artist(
          id: 'artist7',
          name: 'Claire Dubois',
          providerId: 'provider3',
          specialization: 'Esthéticienne',
          rating: 4.6,
          reviewCount: 38,
        ),
      ];
    } else {
      return [
        const Artist(
          id: 'artist8',
          name: 'Yves Kouassi',
          providerId: 'provider4',
          specialization: 'Barbier',
          rating: 4.7,
          reviewCount: 41,
        ),
      ];
    }
  }

  // Sample Services
  static List<Service> getServicesForProvider(String providerId) {
    if (providerId == 'provider1') {
      return [
        const Service(
          id: 'service1',
          name: 'Coupe Homme',
          description: 'Coupe de cheveux pour homme',
          price: 5000,
          durationMinutes: 30,
          providerId: 'provider1',
          artistIds: ['artist1', 'artist2'], // Both artists can do this
        ),
        const Service(
          id: 'service2',
          name: 'Rasage',
          description: 'Rasage complet avec tondeuse',
          price: 3000,
          durationMinutes: 20,
          providerId: 'provider1',
          artistIds: ['artist1'], // Only artist1 can do this
        ),
        const Service(
          id: 'service3',
          name: 'Coupe + Rasage',
          description: 'Coupe et rasage complet',
          price: 7000,
          durationMinutes: 45,
          providerId: 'provider1',
          artistIds: ['artist1'], // Only artist1 can do this
        ),
      ];
    } else if (providerId == 'provider2') {
      return [
        const Service(
          id: 'service4',
          name: 'Tissage',
          description: 'Tissage de cheveux',
          price: 15000,
          priceMax: 25000,
          durationMinutes: 120,
          durationVariants: DurationVariants(court: 120, moyen: 180, long: 240),
          providerId: 'provider2',
          artistIds: ['artist3', 'artist5'], // Only these two can do this
        ),
        const Service(
          id: 'service5',
          name: 'Coloration',
          description: 'Coloration complète',
          price: 12000,
          priceMax: 18000,
          durationMinutes: 90,
          providerId: 'provider2',
          artistIds: ['artist3', 'artist4'], // These two can do this
        ),
        const Service(
          id: 'service6',
          name: 'Lissage',
          description: 'Lissage brésilien',
          price: 20000,
          durationMinutes: 150,
          providerId: 'provider2',
          artistIds: ['artist3'], // Only artist3 can do this
        ),
      ];
    } else {
      return [
        const Service(
          id: 'service7',
          name: 'Massage Relaxant',
          description: 'Massage complet du corps',
          price: 10000,
          durationMinutes: 60,
          providerId: 'provider3',
          artistIds: ['artist6'], // Only artist6 can do this
        ),
        const Service(
          id: 'service8',
          name: 'Manucure',
          description: 'Soin des ongles',
          price: 5000,
          durationMinutes: 45,
          providerId: 'provider3',
          artistIds: ['artist7'], // Only artist7 can do this
        ),
      ];
    }
  }

  // Sample Providers
  static final List<Provider> providers = [
    Provider(
      id: 'provider1',
      name: 'Salon Excellence',
      description: 'Salon de coiffure moderne au cœur d\'Abidjan',
      address: 'Cocody, Angré 7ème Tranche',
      commune: 'Cocody',
      city: 'Abidjan',
      latitude: 5.3600,
      longitude: -4.0083,
      imageUrls: const [
        'asset:assets/images/providers/salon_excellence_photo.png',
        'asset:assets/images/providers/spa_relax_photo.png',
      ],
      beforeAfters: const [
        BeforeAfterPair(
          before: 'asset:assets/images/providers/spa_relax_photo.png',
          after: 'asset:assets/images/providers/beaute_divine_photo.png',
          caption: 'Tresses collées',
        ),
        BeforeAfterPair(
          before: 'asset:assets/images/providers/salon_excellence_photo.png',
          after: 'asset:assets/images/providers/spa_relax_photo.png',
        ),
      ],
      rating: 4.5,
      reviewCount: 120,
      services: getServicesForProvider('provider1'),
      artists: getArtistsForProvider('provider1'),
      availability: Availability(
        providerId: 'provider1',
        weeklySchedule: {
          0: const [], // Monday closed
          1: _generateTimeSlots('provider1', 9, 18), // Tuesday
          2: _generateTimeSlots('provider1', 9, 18), // Wednesday
          3: _generateTimeSlots('provider1', 9, 18), // Thursday
          4: _generateTimeSlots('provider1', 9, 18), // Friday
          5: _generateTimeSlots('provider1', 9, 16), // Saturday
          6: const [], // Sunday closed
        },
        blockedDates: const [],
        // Lunch break 13:00–14:00, Tuesday–Saturday.
        breaks: _weekdayHours(
          startHour: 13,
          endHour: 14,
          days: const [1, 2, 3, 4, 5],
        ),
      ),
      phoneNumber: '+225 07 11 22 33 44',
      whatsapp: '+225 07 11 22 33 44',
      category: 'barber',
    ),
    Provider(
      id: 'provider2',
      name: 'Beauté Divine',
      description: 'Institut de beauté pour femmes',
      address: 'Marcory, Zone 4',
      commune: 'Marcory',
      depositRequired: true,
      depositPercentage: 0.50,
      depositMobileMoneyOperator: MobileMoneyOperator.wave,
      depositMobileMoneyNumber: '+225 05 44 55 66 77',
      city: 'Abidjan',
      latitude: 5.2800,
      longitude: -4.0500,
      imageUrls: const [
        'asset:assets/images/providers/beaute_divine_photo.png',
      ],
      rating: 4.8,
      reviewCount: 89,
      services: getServicesForProvider('provider2'),
      artists: getArtistsForProvider('provider2'),
      availability: Availability(
        providerId: 'provider2',
        weeklySchedule: {
          0: _generateTimeSlots('provider2', 8, 17),
          1: _generateTimeSlots('provider2', 8, 17),
          2: _generateTimeSlots('provider2', 8, 17),
          3: _generateTimeSlots('provider2', 8, 17),
          4: _generateTimeSlots('provider2', 8, 17),
          5: _generateTimeSlots('provider2', 9, 15),
          6: const [],
        },
        blockedDates: const [],
      ),
      phoneNumber: '+225 05 44 55 66 77',
      whatsapp: '+225 05 44 55 66 77',
      category: 'salon',
    ),
    Provider(
      id: 'provider3',
      name: 'Spa Relax',
      description: 'Centre de bien-être et relaxation',
      address: 'Yopougon, Sicogi',
      commune: 'Yopougon',
      depositRequired: false,
      city: 'Abidjan',
      latitude: 5.3200,
      longitude: -4.0800,
      imageUrls: const [
        'asset:assets/images/providers/spa_relax_photo.png',
      ],
      rating: 4.7,
      reviewCount: 156,
      services: getServicesForProvider('provider3'),
      artists: getArtistsForProvider('provider3'),
      availability: Availability(
        providerId: 'provider3',
        weeklySchedule: {
          0: _generateTimeSlots('provider3', 10, 19),
          1: _generateTimeSlots('provider3', 10, 19),
          2: _generateTimeSlots('provider3', 10, 19),
          3: _generateTimeSlots('provider3', 10, 19),
          4: _generateTimeSlots('provider3', 10, 19),
          5: _generateTimeSlots('provider3', 10, 18),
          6: _generateTimeSlots('provider3', 12, 17),
        },
        blockedDates: const [],
      ),
      phoneNumber: '+225 01 22 33 44 55',
      whatsapp: '+225 01 22 33 44 55',
      category: 'spa',
    ),
    Provider(
      id: 'provider4',
      name: 'Barber Shop Pro',
      description: 'Salon de coiffure pour hommes',
      address: 'Plateau, Avenue Franchet d\'Esperey',
      commune: 'Plateau',
      city: 'Abidjan',
      latitude: 5.3200,
      longitude: -4.0300,
      imageUrls: const [
        'asset:assets/images/providers/barber_shop_pro_photo.png',
      ],
      rating: 4.6,
      reviewCount: 203,
      services: const [
        Service(
          id: 'service9',
          name: 'Coupe Classique',
          description: 'Coupe traditionnelle',
          price: 4000,
          durationMinutes: 25,
          providerId: 'provider4',
          artistIds: ['artist8'], // Only artist8 can do this
        ),
        Service(
          id: 'service10',
          name: 'Rasage à l\'ancienne',
          description: 'Rasage avec rasoir',
          price: 3500,
          durationMinutes: 15,
          providerId: 'provider4',
          artistIds: ['artist8'], // Only artist8 can do this
        ),
      ],
      artists: getArtistsForProvider('provider4'),
      availability: Availability(
        providerId: 'provider4',
        weeklySchedule: {
          0: const [],
          1: _generateTimeSlots('provider4', 8, 19),
          2: _generateTimeSlots('provider4', 8, 19),
          3: _generateTimeSlots('provider4', 8, 19),
          4: _generateTimeSlots('provider4', 8, 19),
          5: _generateTimeSlots('provider4', 8, 18),
          6: const [],
        },
        blockedDates: const [],
      ),
      phoneNumber: '+225 07 88 99 00 11',
      category: 'barber',
    ),
  ];

  // Sample Reviews (per provider)
  static final List<Review> reviews = [
    Review(
      id: 'review1',
      providerId: 'provider1',
      userId: 'user2',
      userName: 'Marie Diallo',
      rating: 5,
      text: 'Très bon accueil et coupe impeccable. Je recommande.',
      verified: true,
      artistName: 'Kouassi Jean',
      photoUrls: const [
        'asset:assets/images/providers/salon_excellence_photo.png',
        'asset:assets/images/providers/spa_relax_photo.png',
      ],
      createdAt: DateTime(2025, 2, 4),
    ),
    Review(
      id: 'review2',
      providerId: 'provider1',
      userId: 'user2',
      userName: 'Marie Diallo',
      rating: 4,
      text: 'Bon salon, un peu d\'attente le samedi. Service soigné.',
      verified: true,
      artistName: 'Kouassi Jean',
      createdAt: DateTime(2025, 1, 8),
    ),
    Review(
      id: 'review3',
      providerId: 'provider1',
      userId: 'user2',
      userName: 'Marie Diallo',
      rating: 5,
      text: 'Idéal pour une coupe homme. Rapide et propre.',
      createdAt: DateTime(2024, 9, 4),
    ),
    Review(
      id: 'review4',
      providerId: 'provider2',
      userId: 'user1',
      userName: 'Jean Kouassi',
      rating: 5,
      text: 'Institut très propre, équipe professionnelle.',
      verified: true,
      createdAt: DateTime(2025, 1, 15),
    ),
    Review(
      id: 'review5',
      providerId: 'provider2',
      userId: 'user2',
      userName: 'Marie Diallo',
      rating: 4,
      text: 'Beaux soins, un peu cher mais la qualité est au rendez-vous.',
      createdAt: DateTime(2024, 12, 10),
    ),
    Review(
      id: 'review6',
      providerId: 'provider3',
      userId: 'user1',
      userName: 'Jean Kouassi',
      rating: 5,
      text: 'Massage relaxant, cadre agréable. À refaire.',
      createdAt: DateTime(2025, 1, 20),
    ),
    Review(
      id: 'review7',
      providerId: 'provider4',
      userId: 'user2',
      userName: 'Marie Diallo',
      rating: 4,
      text: 'Bon rapport qualité-prix pour la barbe.',
      createdAt: DateTime(2024, 11, 5),
    ),
  ];

  // Sample Appointments
  static final List<Appointment> appointments = [
    Appointment(
      id: 'appointment1',
      userId: 'user1',
      providerId: 'provider1',
      serviceIds: const ['service1'],
      appointmentDate: DateTime.now().add(const Duration(days: 2)),
      status: AppointmentStatus.confirmed,
      totalPrice: 5000,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    Appointment(
      id: 'appointment2',
      userId: 'user1',
      providerId: 'provider2',
      serviceIds: const ['service4'],
      appointmentDate: DateTime.now().add(const Duration(days: 5)),
      status: AppointmentStatus.pending,
      totalPrice: 15000,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    // Completed booking so user1 can see "Donner mon avis" on Salon Excellence (provider1)
    Appointment(
      id: 'appointment_completed1',
      userId: 'user1',
      providerId: 'provider1',
      serviceIds: const ['service1'],
      appointmentDate: DateTime.now().subtract(const Duration(days: 10)),
      status: AppointmentStatus.completed,
      totalPrice: 5000,
      createdAt: DateTime.now().subtract(const Duration(days: 15)),
    ),
    // Completed booking so user2 can see "Donner mon avis" on Beauté Divine (provider2)
    Appointment(
      id: 'appointment_completed2',
      userId: 'user2',
      providerId: 'provider2',
      serviceIds: const ['service4'],
      appointmentDate: DateTime.now().subtract(const Duration(days: 7)),
      status: AppointmentStatus.completed,
      totalPrice: 15000,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
  ];

  // Helper to generate time slots
  // Note: These slots use today's date as a template, but the actual date
  // will be applied when checking availability for a specific date
  static List<TimeSlot> _generateTimeSlots(
    String providerId,
    int startHour,
    int endHour,
  ) {
    final slots = <TimeSlot>[];
    final now = DateTime.now();

    // Generate 30-minute slots from startHour to endHour
    for (int hour = startHour; hour < endHour; hour++) {
      for (int minute = 0; minute < 60; minute += 30) {
        final start = DateTime(now.year, now.month, now.day, hour, minute);
        final end = start.add(const Duration(minutes: 30));

        // Make most slots available (≈90%) for better UX in mock.
        // IMPORTANT: don't use "% 10" on hour/minute (0/30) or everything becomes unavailable.
        // Use a deterministic pattern based on total minutes since midnight.
        final totalMinutes = hour * 60 + minute;
        final isAvailable =
            totalMinutes % 13 != 0; // ~92% available, stable across runs

        slots.add(TimeSlot(
          startTime: start,
          endTime: end,
          isAvailable: isAvailable,
        ));
      }
    }

    return slots;
  }
}
