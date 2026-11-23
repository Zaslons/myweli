import '../../models/appointment.dart';
import 'chip_tone.dart';
import 'status_colors.dart';
import 'status_labels.dart';

/// Where a client's own booking is listed in « Mes rendez-vous ».
enum ClientBookingTab { upcoming, past, cancelled }

/// The one rule for a client's own bookings, the same on the web
/// (docs/design/consumer-app-truth.md §2.7; web `categorize(a, now)`).
///
/// | Booking                        | Tab      | Chip         |
/// |--------------------------------|----------|--------------|
/// | pending, time after now        | À venir  | En attente   |
/// | confirmed, time after now      | À venir  | Confirmé     |
/// | pending, time now or past      | Passés   | Non confirmé |
/// | confirmed, time now or past    | Passés   | Confirmé     |
/// | completed, any time            | Passés   | Terminé      |
/// | noShow, any time               | Passés   | Absent       |
/// | cancelled                      | Annulés  | Annulé       |
///
/// **Nothing on the server closes a booking by itself**: only the salon marks
/// it « Terminé » or « Non présenté ». The app used to call every past booking
/// « Terminé » (`effectiveAppointmentStatus`, « a placeholder until the
/// backend sends real completion / no-show events »), inventing an outcome,
/// and listed a no-show in no tab. A booking exactly at now is past, as on the
/// web (`isUpcoming`: `> Date.now()`).
///
/// Client-only: Pro reads the stored status, where a past pending booking is
/// work to do, so « Non confirmé » must never reach a Pro list.
ClientBookingTab clientTab(Appointment a, DateTime now) => switch (a.status) {
  AppointmentStatus.cancelled => ClientBookingTab.cancelled,
  AppointmentStatus.completed ||
  AppointmentStatus.noShow => ClientBookingTab.past,
  AppointmentStatus.pending || AppointmentStatus.confirmed =>
    a.appointmentDate.isAfter(now)
        ? ClientBookingTab.upcoming
        : ClientBookingTab.past,
};

/// The salon never answered and the time has passed: MyWeli does not know
/// whether the visit happened, so it says only what it knows.
const String kUnconfirmedPastLabel = 'Non confirmé';

bool _isUnconfirmedPast(Appointment a, DateTime now) =>
    a.status == AppointmentStatus.pending && !a.appointmentDate.isAfter(now);

/// The chip's words for a client's own booking.
String clientStatusLabel(Appointment a, DateTime now) =>
    _isUnconfirmedPast(a, now)
    ? kUnconfirmedPastLabel
    : StatusLabels.of(a.status);

/// The chip's tone: « Non confirmé » is neutral, since nothing is awaited any
/// more; every other chip keeps its status tone.
AppChipTone clientStatusTone(Appointment a, DateTime now) =>
    _isUnconfirmedPast(a, now)
    ? AppChipTone.neutral
    : appointmentStatusTone(a.status);
