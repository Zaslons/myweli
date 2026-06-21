import '../../models/appointment.dart';
import '../../models/user.dart';

/// Builds the user's data-export document (JSON-ready) from already-loaded
/// state. Pure and deterministic so it can be unit-tested.
Map<String, dynamic> buildUserDataExport({
  required User user,
  required List<Appointment> appointments,
  required List<String> favoriteProviderNames,
  DateTime? generatedAt,
}) {
  return {
    'generatedAt': (generatedAt ?? DateTime.now()).toIso8601String(),
    'profile': {
      'id': user.id,
      'phoneNumber': user.phoneNumber,
      'name': user.name,
      'email': user.email,
      'memberSince': user.createdAt.toIso8601String(),
    },
    'appointments': appointments
        .map((a) => {
              'id': a.id,
              'providerId': a.providerId,
              'date': a.appointmentDate.toIso8601String(),
              'status': a.status.name,
              'totalPrice': a.totalPrice,
              'depositAmount': a.depositAmount,
              'serviceIds': a.serviceIds,
            })
        .toList(),
    'favorites': favoriteProviderNames,
  };
}
