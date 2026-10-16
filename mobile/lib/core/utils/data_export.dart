import '../../models/appointment.dart';
import '../../models/artist.dart';
import '../../models/provider.dart';
import '../../models/provider_user.dart';
import '../../models/salon_client.dart';
import '../../models/service.dart';
import '../../models/user.dart';
import 'app_clock.dart';

/// Builds the user's data-export document (JSON-ready) from already-loaded
/// state. Pure and deterministic so it can be unit-tested.
Map<String, dynamic> buildUserDataExport({
  required User user,
  required List<Appointment> appointments,
  required List<String> favoriteProviderNames,
  DateTime? generatedAt,
}) {
  return {
    'generatedAt': (generatedAt ?? AppClock.now()).toIso8601String(),
    'profile': {
      'id': user.id,
      'phoneNumber': user.phoneNumber,
      'name': user.name,
      'email': user.email,
      'memberSince': user.createdAt.toIso8601String(),
    },
    'appointments': appointments
        .map(
          (a) => {
            'id': a.id,
            'providerId': a.providerId,
            'date': a.appointmentDate.toIso8601String(),
            'status': a.status.name,
            'totalPrice': a.totalPrice,
            'depositAmount': a.depositAmount,
            'serviceIds': a.serviceIds,
          },
        )
        .toList(),
    'favorites': favoriteProviderNames,
  };
}

/// The consumer export's own reads, in the order the file and the sentence
/// name them. The app takes the profile from the session rather than from a
/// read, so it names it only when the session holds no user; the web reads it
/// (`GET /me`) and names it when that read fails.
enum DataExportSection { profile, appointments, favorites }

const Map<DataExportSection, String> _sectionName = {
  DataExportSection.profile: 'votre profil',
  DataExportSection.appointments: 'vos rendez-vous',
  DataExportSection.favorites: 'vos favoris',
};

/// The refusal when a read fails (docs/design/consumer-export-completeness.md
/// §4): nothing is offered, and the user is told which data is missing. The
/// web says the same sentence (`exportFailureMessage`).
String dataExportFailureMessage(Iterable<DataExportSection> failed) {
  final names = [
    for (final s in DataExportSection.values)
      if (failed.contains(s)) _sectionName[s]!,
  ];
  final list = names.length > 1
      ? '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}'
      : names.join();
  return 'Impossible de charger $list. Vos données ne sont proposées que '
      'complètes : vérifiez votre connexion et réessayez.';
}

/// The clipboard refused the copy. The app has no download, and a
/// `PlatformException` from the clipboard is not a lasting state: the button
/// stays, and it is the retry.
const String kDataExportCopyFailed = 'La copie a échoué. Réessayez.';

/// Builds the SALON's data-export document (audit 11.5 — AUTH-005 for pros):
/// the account identity, the public listing, the catalogue and the salon's
/// own records (bookings + client base). Pure and deterministic.
Map<String, dynamic> buildProviderDataExport({
  required ProviderUser account,
  required Provider salon,
  required List<Service> services,
  required List<Artist> artists,
  required List<Appointment> appointments,
  required List<SalonClient> clients,
  DateTime? generatedAt,
}) {
  return {
    'generatedAt': (generatedAt ?? AppClock.now()).toIso8601String(),
    'account': {
      'id': account.id,
      'businessName': account.businessName,
      'businessType': account.businessType.name,
      'email': account.email,
      'phoneNumber': account.phoneNumber,
      'verificationStatus': account.verificationStatus.name,
    },
    'salon': {
      'id': salon.id,
      'name': salon.name,
      'description': salon.description,
      'address': salon.address,
      'commune': salon.commune,
      'category': salon.category,
      'rating': salon.rating,
      'reviewCount': salon.reviewCount,
    },
    'services': services
        .map(
          (x) => {
            'name': x.name,
            'price': x.price,
            'durationMinutes': x.durationMinutes,
          },
        )
        .toList(),
    'artists': artists
        .map((a) => {'name': a.name, 'specialization': a.specialization})
        .toList(),
    'appointments': appointments
        .map(
          (a) => {
            'id': a.id,
            'date': a.appointmentDate.toIso8601String(),
            'status': a.status.name,
            'totalPrice': a.totalPrice,
          },
        )
        .toList(),
    'clients': clients
        .map(
          (c) => {
            'name': c.displayName,
            'phone': c.phone,
            'tags': c.tags,
            'visits': c.visits,
          },
        )
        .toList(),
  };
}
