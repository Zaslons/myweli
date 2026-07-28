import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/review.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/widgets/common/otp_code_row.dart';
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

/// A live [OtpCodeRow], with its controllers and nodes disposed on tear-down
/// (A11 C3).
///
/// **Why the row is a fixture at all.** Until C3 the six boxes were inline
/// inside two `build` methods, so the only way to measure them was to pump a
/// whole screen — and every a11y gate in this suite is component-level. That is
/// the concrete reason the row was extracted: `androidTapTargetGuideline` could
/// not see it, and after C3 the boxes land at **exactly 48.0dp at 360**, which is
/// the §13.2 floor with no slack at all. A rule met exactly is a rule that needs
/// a gate.
///
/// The boxes carry a digit so the paragraph inside them is real; they are
/// deliberately **not focused**, because a focused `EditableText` runs a cursor
/// blink `Timer` and `pumpForA11y` ends in `pumpAndSettle`. The 60-second resend
/// cooldown belongs to the screens, not to the row, so there is nothing else to
/// drain.
OtpCodeRow otpRow({bool enabled = true, bool hasError = false}) {
  final controllers = List.generate(
    OtpCodeRow.length,
    (_) => TextEditingController(text: '8'),
  );
  final nodes = List.generate(OtpCodeRow.length, (_) => FocusNode());
  addTearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    for (final n in nodes) {
      n.dispose();
    }
  });
  return OtpCodeRow(
    controllers: controllers,
    focusNodes: nodes,
    onChanged: (_) {},
    enabled: enabled,
    hasError: hasError,
  );
}

AppNotification note() => AppNotification(
      id: '1',
      type: AppNotificationType.bookingConfirmed,
      title: 'Rendez-vous confirmé',
      body: 'Salon Excellence, Cocody — jeudi 30 juin à 10h00',
      createdAt: DateTime(2026, 6, 29, 10),
    );
