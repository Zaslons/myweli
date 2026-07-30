import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/common/app_snack_bar.dart';

/// Opening something outside the app (L1 — docs/design/legal-l1.md §5).
///
/// **Two functions, and deliberately not eleven.** There are eleven `launchUrl`
/// call sites in `lib/`, and they are five different behaviours, not one:
///
///   * `helpers.dart:37-124` is a *navigation-app chooser* — it probes five map
///     apps with `canLaunchUrl`, adds an Android `geo:` fallback, and shows a
///     picker sheet when several are present;
///   * `appointment_detail_screen`, `provider_detail_screen` and
///     `client_detail_screen` are **contact** actions with `tel:` ↔ `wa.me`
///     fallback semantics;
///   * `deposit_payment_sheet` + `mobile_money.dart` are **operator deep links**.
///
/// A single `openUrl()` swallowing all five would be a lowest-common-denominator
/// wrapper that erases exactly the differences that matter, and rewriting them
/// inside a store-submission PR is unrelated risk. This file collapses the two
/// that genuinely *were* duplicates — the byte-identical `wa.me` blocks in
/// `profile_screen` and `pro_subscription_screen`, down to their duplicated
/// failure copy — and serves the new legal links. The remaining eight are
/// recorded as a follow-up rather than swept.
///
/// Both capture the `ScaffoldMessenger` **before** the await: the widget may be
/// gone by the time the platform answers, and reading `context` afterwards is
/// the classic use-after-dispose in this codebase.

/// Open [url] in the system browser (or the handling app).
///
/// `LaunchMode.externalApplication` matches the deliberate call sites; three
/// existing ones omit the mode and get the platform default, which on Android is
/// a Custom Tab — inconsistent, recorded, not changed here.
Future<void> openExternalUrl(
  BuildContext context,
  String url, {
  String failureMessage = 'Impossible d’ouvrir le lien.',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(url);
  if (uri == null) {
    AppSnackBar.showOn(messenger, failureMessage, kind: SnackKind.error);
    return;
  }
  bool ok;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // A device with no browser at all, or a platform channel failure. Silence
    // here would look exactly like success.
    ok = false;
  }
  if (!ok) {
    AppSnackBar.showOn(messenger, failureMessage, kind: SnackKind.error);
  }
}

/// Open a WhatsApp conversation with [number] (E.164 without `+`), prefilled
/// with [message].
///
/// An empty [number] is the un-configured build (`AppConfig.supportWhatsApp`
/// defaults to empty), and it degrades to a message rather than a dead link —
/// the behaviour both original call sites already had, written twice.
Future<void> openWhatsApp(
  BuildContext context, {
  required String number,
  required String message,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (number.isEmpty) {
    AppSnackBar.showOn(messenger, 'Contact bientôt disponible.');
    return;
  }
  final uri = Uri.parse(
    'https://wa.me/$number?text=${Uri.encodeComponent(message)}',
  );
  bool ok;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    AppSnackBar.showOn(
      messenger,
      'Impossible d’ouvrir WhatsApp.',
      kind: SnackKind.error,
    );
  }
}
