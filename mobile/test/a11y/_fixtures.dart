import 'package:myweli/models/app_notification.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// The a11y suite's fixtures, once (A11).
///
/// `review()`, `appt()`, `note()` and `favProviders()` were copy-pasted across
/// **four** files — `contrast_test`, `tap_target_test`, `label_test`,
/// `text_scale_test` — and A11's layout gate would have been the fifth.
///
/// **The copies had already diverged**, which is the argument: `Review.text` was
/// `'Super service'` in two files and `'Super service, je recommande vivement ce
/// salon.'` in a third. No assertion in any of them reads the string, so nothing
/// caught it — but a *width* gate is exactly a test that cares how long a
/// sentence is, and it would have inherited whichever copy it was pasted from.
/// Resolved to the **longer** string: a fixture too short to wrap cannot
/// exercise a wrapping paragraph.
///
/// Dates are fixed instants, not `AppClock.now()` — these fixtures feed layout
/// assertions, and A10's rule is that a test needing a specific date freezes it.
/// Nothing here needs "now"; it needs a French date long enough to be laid out.

List<SingleChildWidget> favProviders() => [
      ChangeNotifierProvider(create: (_) => FavoritesProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
    ];

Review review() => Review(
      id: 'r1',
      providerId: 'p1',
      userId: 'u1',
      userName: 'Marie Diallo',
      rating: 5,
      text: 'Super service, je recommande vivement ce salon.',
      createdAt: DateTime(2025, 2, 4),
    );

Appointment appt() => Appointment(
      id: 'a1',
      userId: 'u1',
      providerId: 'p1',
      serviceIds: const ['s1'],
      appointmentDate: DateTime(2026, 6, 30, 10),
      status: AppointmentStatus.confirmed,
      totalPrice: 20000,
      createdAt: DateTime(2026),
    );

AppNotification note() => AppNotification(
      id: '1',
      type: AppNotificationType.bookingConfirmed,
      title: 'Rendez-vous confirmé',
      body: 'Salon Excellence, Cocody — jeudi 30 juin à 10h00',
      createdAt: DateTime(2026, 6, 29, 10),
    );
