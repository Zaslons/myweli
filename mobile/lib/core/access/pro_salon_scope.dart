import 'package:flutter/foundation.dart';

import '../../models/appointment.dart';
import '../utils/logger.dart';
import '../utils/salon_id.dart';

/// Per-salon state contract (R6 multi-salons): every ChangeNotifier that
/// caches data for ONE salon implements this so a « Mes salons » switch can
/// clear the fleet in one sweep — a switch happens WITHOUT unmounting the
/// shell, so stale cross-salon data would otherwise linger.
abstract class SalonScoped {
  /// Drop everything loaded for the previous salon (back to the initial
  /// not-yet-loaded state) and notify. Screens re-fetch on entry/rebuild.
  void resetForSalonSwitch();
}

/// A per-salon store that SHOWS the salon's bookings — « Ma journée », the
/// home figures, the client card.
///
/// Design: docs/design/pro-journal-shows-new-booking.md §5.
///
/// **Why this exists.** The manual-booking form wrote the agenda's store and
/// « Ma journée » read another one, so a booking the salon had just created was
/// missing from its own day until the list was pulled down. Each such store
/// kept its own copy and nothing told it. There is now ONE announcement —
/// [ProSalonScope.bookingCreated], made by the one piece of code that creates a
/// booking — and a store that shows bookings hears it by implementing this,
/// instead of every opener of the form remembering whom to refresh.
/// What changed about a booking the salon sees — announced ONCE, after the
/// server accepted it (docs/design/app-pro-home-journal-fresh.md §2.1, owner
/// decision 8). The writes answer `ApiResponse<bool>`, not the booking: what
/// is known is the transition itself, which the server just confirmed.
enum BookingChangeKind {
  accepted,
  rejected,
  completed,
  noShow,
  arrived,
  rescheduled,
}

class BookingChange {
  const BookingChange({
    required this.appointmentId,
    required this.providerId,
    required this.kind,
    this.newDate,
    this.arrivedAt,
    this.clientPhone,
  });

  final String appointmentId;
  final SalonId providerId;
  final BookingChangeKind kind;

  /// [BookingChangeKind.rescheduled] only: the booking's new time.
  final DateTime? newDate;

  /// [BookingChangeKind.arrived] only: when the client was marked arrived.
  final DateTime? arrivedAt;

  /// The booking's client, when the writer knows it — how the client card
  /// recognises its own client's booking (the server's rule: the same phone).
  final String? clientPhone;

  /// [booking] as it is now, as far as this change says. Only what the change
  /// names is touched; the store's quiet reload brings the rest.
  Appointment applyTo(Appointment booking) => switch (kind) {
    BookingChangeKind.accepted => booking.copyWith(
      status: AppointmentStatus.confirmed,
    ),
    BookingChangeKind.rejected => booking.copyWith(
      status: AppointmentStatus.cancelled,
    ),
    BookingChangeKind.completed => booking.copyWith(
      status: AppointmentStatus.completed,
    ),
    BookingChangeKind.noShow => booking.copyWith(
      status: AppointmentStatus.noShow,
    ),
    BookingChangeKind.arrived => booking.copyWith(
      arrivedAt: arrivedAt ?? booking.arrivedAt,
    ),
    BookingChangeKind.rescheduled => booking.copyWith(
      appointmentDate: newDate ?? booking.appointmentDate,
    ),
  };
}

/// A per-salon store that shows bookings whose status or time can change
/// elsewhere — « Ma journée », the home figures, the client card, the
/// « Rendez-vous » list (docs/design/app-pro-home-journal-fresh.md §2.1).
abstract class HearsBookingChanges implements SalonScoped {
  /// The server just accepted [change]. Do the visible part at once (the row,
  /// the dot) and reload quietly without awaiting it: the server's answer
  /// wins, a failed reload keeps what is on screen and says nothing — the
  /// change succeeded. Another salon's change is ignored.
  void bookingChanged(BookingChange change);
}

abstract class ShowsSalonBookings implements HearsBookingChanges {
  /// The salon just created [booking]: the server's own `201` body, never a
  /// client-side guess.
  ///
  /// Called synchronously, before the form closes. Do the cheap, visible part
  /// here (the row, the dot) and start the server reload without awaiting it;
  /// what the server answers wins. A failed reload keeps what is on screen and
  /// says nothing — the creation succeeded, and the next visit reconciles.
  void bookingCreated(Appointment booking);
}

/// The switch coordinator: providers register at construction (main_pro
/// wires them once for the app's lifetime); `ProAuthProvider.switchSalon`
/// calls [resetAll] after the new membership lands.
class ProSalonScope {
  ProSalonScope._();

  static final List<WeakReference<SalonScoped>> _scoped = [];

  /// Register [provider] and return it (a passthrough for MultiProvider
  /// `create:` wiring). Weak: test-created providers never leak.
  static T track<T extends SalonScoped>(T provider) {
    _scoped.add(WeakReference(provider));
    return provider;
  }

  static void resetAll() {
    for (final ref in _scoped) {
      ref.target?.resetForSalonSwitch();
    }
    _scoped.removeWhere((ref) => ref.target == null);
  }

  /// Tell every tracked store that shows bookings that the salon created one.
  ///
  /// Its single caller is `ProAppointmentProvider.createManualBooking`, on
  /// success.
  ///
  /// **A store that throws is logged and skipped, never propagated.** The
  /// caller sits inside the creation's own `try`: an exception escaping from
  /// here would be reported to the salon as a failed creation of a booking
  /// that exists — and the salon would create it a second time.
  static void bookingCreated(Appointment booking) {
    // A copy: a store reacting to the news must not be able to change the
    // list being walked.
    for (final ref in List.of(_scoped)) {
      final store = ref.target;
      if (store is! ShowsSalonBookings) continue;
      try {
        store.bookingCreated(booking);
      } catch (error, stackTrace) {
        AppLogger.error(
          'ProSalonScope.bookingCreated: ${store.runtimeType} threw',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Tell every tracked store that hears booking changes that [change]
  /// happened — except [except], the store that made it and has already
  /// applied it to itself.
  ///
  /// Called by the writes themselves, after the server's success: the four
  /// of the booking's detail (`ProAppointmentProvider`) and the gestures of
  /// « Ma journée » (`ProJournalProvider`). Like [bookingCreated], a store that
  /// throws is logged and skipped: an exception escaping from here would
  /// report a change the server accepted as a failure.
  static void bookingChanged(BookingChange change, {Object? except}) {
    for (final ref in List.of(_scoped)) {
      final store = ref.target;
      if (store is! HearsBookingChanges || identical(store, except)) continue;
      try {
        store.bookingChanged(change);
      } catch (error, stackTrace) {
        AppLogger.error(
          'ProSalonScope.bookingChanged: ${store.runtimeType} threw',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  @visibleForTesting
  static void clear() => _scoped.clear();
}
