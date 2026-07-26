import '../../models/appointment.dart';

/// The one French vocabulary for a booking status (SYSTEM.md §17, §18).
///
/// **Why this is in `core/` and not in each screen.** §18's rule — *"hardcoding
/// a market fact in a widget fails review even when it works for Côte
/// d'Ivoire"* — and A9 measured what happens without it: **eight** separate
/// vocabularies, rendering `noShow` three different ways. « Absent » on six
/// surfaces, « Non présenté » on two pro ones, and the **raw English enum** in
/// the admin console, where the chip's *kind* switch routed the status
/// correctly and its label switch had no case for it.
///
/// **The words are the web's**, because web already had to settle them across
/// consumer, pro and admin: `web/lib/account/appointments.ts:94-100`, where
/// `noShow: 'Absent'` carries the comment `// app label`. Mobile diverging from
/// its own twin is the regression — `web/components/StatusChip.tsx:55`
/// documents the normalisation fix as one it mirrored *from* mobile, and mobile
/// never received it.
///
/// Pinned by `test/unit/status_labels_test.dart`.
class StatusLabels {
  StatusLabels._();

  static const Map<AppointmentStatus, String> _fr = {
    AppointmentStatus.pending: 'En attente',
    AppointmentStatus.confirmed: 'Confirmé',
    AppointmentStatus.completed: 'Terminé',
    AppointmentStatus.cancelled: 'Annulé',
    AppointmentStatus.noShow: 'Absent',
  };

  /// The French label for a typed status. Total by construction — a new enum
  /// value is a compile error here rather than a raw word on screen.
  static String of(AppointmentStatus status) => _fr[status]!;

  /// Statuses the admin console receives as raw JSON, beyond the booking
  /// vocabulary above (`EXTRA_FR` in the web twin).
  static const Map<String, String> _extraFr = {
    'verified': 'Vérifié',
    'active': 'Actif',
    'resolved': 'Résolu',
    'paid': 'Payé',
    'arrived': 'Arrivé',
    'open': 'Ouvert',
    'rejected': 'Rejeté',
    'suspended': 'Suspendu',
    'banned': 'Banni',
    'hidden': 'Masqué',
  };

  /// The label for a status that arrives as a **string** — the admin console's
  /// case, where the value comes straight off the wire.
  ///
  /// **Normalisation-robust, which is the whole point.** `NO_SHOW`, `noShow`
  /// and `no-show` are one status; a lookup that matched only the exact
  /// spelling would tint the pill red and print the raw enum next to it. That
  /// is the defect this file exists to end, and it shipped for months because
  /// the *kind* switch normalised and the label switch did not.
  ///
  /// Returns `null` for an unknown status so the caller decides what to show —
  /// falling back to the raw string is exactly how English reached a user.
  static String? ofRaw(String? raw) {
    final key = (raw ?? '').toLowerCase().replaceAll(RegExp('[_\\s-]'), '');
    if (key.isEmpty) return null;
    for (final entry in _fr.entries) {
      if (entry.key.name.toLowerCase() == key) return entry.value;
    }
    return _extraFr[key];
  }
}
