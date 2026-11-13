import '../../models/appointment.dart';
import '../../models/artist.dart';
import '../../models/provider.dart';
import '../../models/provider_user.dart';
import '../../models/salon_client.dart';
import '../../models/salon_validation.dart';
import '../../models/service.dart';
import '../../models/user.dart';
import '../../services/interfaces/pro_service_interface.dart';
import '../constants/salon_validation_copy.dart';
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

/// Every read answered, and the file still could not be made from them: its
/// own sentence — naming the reads would blame what worked
/// (docs/design/web-client-polish.md §2.3). The web's two exports say the
/// same (`EXPORT_BUILD_FAILED`).
const String kDataExportBuildFailed =
    'Le fichier n’a pas pu être préparé. Réessayez.';

/// The clipboard refused the copy. The app has no download, and a
/// `PlatformException` from the clipboard is not a lasting state: the button
/// stays, and it is the retry.
const String kDataExportCopyFailed = 'La copie a échoué. Réessayez.';

/// Builds the SALON's data-export document (audit 11.5 — AUTH-005 for pros):
/// the account identity, the public listing, the catalogue and the salon's
/// own records (bookings + client base). Pure and deterministic.
///
/// [validation] is where the salon stands with MyWeli's validation (B0.18 —
/// salon-go-live-approval §6.4; the website's shape, web-salon-validation.md
/// §6), from the same GET /me/provider the salon came from — no read of its
/// own. A top-level `validation` beside `salon`, as the read puts it beside
/// `provider`, ONLY when the server sent the key ([validationSent]): `null`
/// says « never asked », and a server from before B0.18 asked nobody.
Map<String, dynamic> buildProviderDataExport({
  required ProviderUser account,
  required Provider salon,
  required List<Service> services,
  required List<Artist> artists,
  required List<Appointment> appointments,
  required List<SalonClient> clients,
  required EarningsData earnings,
  bool validationSent = false,
  SalonValidation? validation,
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
    if (validationSent) 'validation': validationForExport(validation),
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
    // The web's shape exactly (web/lib/pro/export.ts): the total and a COUNT
    // of transactions — not the list (pro-app-batch7.md §2.8, B7.8).
    'earnings': {
      'totalEarnings': earnings.totalEarnings,
      'transactions': earnings.transactions.length,
    },
  };
}

/// The salon export's six reads, in the order the file holds them — and the
/// order a refusal names them (docs/design/app-pro-export-completeness.md §3;
/// the earnings since pro-app-batch7.md §2.8, as on the web).
enum ProExportSection {
  salon('la fiche du salon'),
  services('les services'),
  artists('l’équipe'),
  appointments('les rendez-vous'),
  clients('le fichier clients'),
  earnings('les revenus');

  const ProExportSection(this.label);

  /// How the refusal names the section.
  final String label;
}

/// The refusal when a read fails: nothing is exported, and the salon is told
/// which data could not be loaded. The web's wording
/// (`exportFailureMessage`, web/lib/pro/export.ts), ending on the app's
/// connection hint; « Réessayer » sits under it.
String proExportFailureMessage(Iterable<ProExportSection> failed) {
  final names = [
    for (final section in ProExportSection.values)
      if (failed.contains(section)) section.label,
  ];
  final list = names.length > 1
      ? '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}'
      : names.join();
  return 'Export interrompu : impossible de charger $list. '
      'Vérifiez votre connexion et réessayez.';
}

/// The client base, from every page of one walk — or null when the walk does
/// not add up (§4). An offset walk over a list that moves (a client added, a
/// visit re-sorting the list) can repeat one row and skip another; a skipped
/// row is exactly the hole the export must not ship. So every page has to
/// report the same `total`, and the distinct ids have to reach it. The twin
/// of the web's `wholeClientBase`.
List<SalonClient>? wholeClientBase(List<SalonClientsPage> pages) {
  if (pages.isEmpty) return null;
  final total = pages.first.total;
  if (pages.any((p) => p.total != total)) return null;
  final byId = <String, SalonClient>{};
  for (final page in pages) {
    for (final client in page.items) {
      byId.putIfAbsent(client.id, () => client);
    }
  }
  return byId.length == total ? byId.values.toList() : null;
}

/// The salon's validation as its data export carries it (web-salon-
/// validation.md §6, the website's `validationForExport`): the wire's
/// values — state, the request's and the decision's times, whether it went
/// live — and the refusal with its code, whether it is final, the admin's
/// note, and `reason`, the one French value: the sentence the salon reads
/// (null for `other`, whose note is the reason). `offerLive` is billing
/// state and stays out. Null: never asked.
Map<String, dynamic>? validationForExport(SalonValidation? validation) {
  if (validation == null) return null;
  final refusal = validation.refusal;
  return {
    'state': validation.state.wire,
    'submittedAt': validation.submittedAt?.toIso8601String(),
    'decidedAt': validation.decidedAt?.toIso8601String(),
    'wentLive': validation.wentLive,
    'refusal': refusal == null
        ? null
        : {
            'code': refusal.code,
            'final': refusal.isFinal,
            'note': refusal.note,
            'reason': SalonValidationCopy.refusalSentences[refusal.code],
          },
  };
}
