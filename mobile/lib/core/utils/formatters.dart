import 'package:intl/intl.dart';

import 'app_clock.dart';
import 'app_locale.dart';

class Formatters {
  /// « 0 salon » · « 1 salon » · « 2 salons » — a count and its noun, in French
  /// (A13, SYSTEM.md §17.1).
  ///
  /// **French puts 0 in the SINGULAR**, and that one fact is the whole reason
  /// this exists. The app had grown four idioms for the same job — `== 1`,
  /// `<= 1`, `> 1`, and a hard-coded plural — and they disagree at exactly one
  /// value: `n == 1 ? 'visite' : 'visites'` prints « 0 visites », where French
  /// wants « 0 visite ».
  ///
  /// **Six sites already had it right** — `provider_list_screen.dart` via
  /// `<= 1`, and five more via `> 1` (`provider_detail_screen`,
  /// `client_list_screen`, `pro_subscription_screen`, `team_screen`,
  /// `submit_review_sheet`). An earlier draft of this docstring said one, which
  /// contradicted the same slice's claim that web is correct *because* it uses
  /// `> 1`. The problem was never that nobody knew the rule; it was that four
  /// spellings of it coexisted and only one value distinguishes them.
  ///
  /// **`locale:` is not defensive clutter.** `Intl.plural` without it resolves
  /// through `Intl.getCurrentLocale()`, which falls back to `en_US` — and
  /// English differs from French *only at n = 0*. So an unlocalised call is
  /// correct in every test that checks 1 and 2, and wrong at the single value
  /// this helper was written for. `initAppLocale()` does set
  /// `Intl.defaultLocale` in all three app roots and in `wrapApp`, but a unit
  /// test that constructs neither would silently measure the English rule.
  ///
  /// The CLDR data has been wired since A9 and had **zero callers** until now.
  static String count(int n, String one, String other) => Intl.plural(
        n,
        one: '$n $one',
        other: '$n $other',
        locale: kAppLocale,
      );

  /// The noun alone, for the sites that render the number separately (a big
  /// figure above a small label, e.g. `my_bookings_screen`'s summary metrics).
  static String plural(int n, String one, String other) => Intl.plural(
        n,
        one: one,
        other: other,
        locale: kAppLocale,
      );

  /// Format a phone number for display. Côte d'Ivoire (+225) numbers are grouped
  /// in pairs — both the current 10-digit and legacy 8-digit formats; any other
  /// country (or unexpected length) is returned as-is.
  static String formatPhoneNumber(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('+225')) {
      final digits = cleaned.substring(4); // strip +225
      if (digits.length == 10 || digits.length == 8) {
        final groups = <String>[];
        for (var i = 0; i < digits.length; i += 2) {
          groups.add(digits.substring(i, i + 2));
        }
        return '+225 ${groups.join(' ')}';
      }
    }
    return phone; // other country / unexpected length → as-is
  }

  /// Format currency for display: "15 000 FCFA". XOF and XAF (the two CFA
  /// francs) both read « FCFA » — the colloquial name across the zone
  /// (docs/modules/multi-pays.md §4); any other ISO code renders as itself.
  /// Null (unthreaded/pre-MP1 payloads) falls back to XOF HERE — the one
  /// designated seam — so call sites pass carriers straight through.
  static String formatCurrency(double amount, {String? currency}) {
    final formatter = NumberFormat.currency(
      symbol: '',
      decimalDigits: 0,
      locale: 'fr_FR',
    );
    final code = currency ?? 'XOF';
    final suffix = (code == 'XOF' || code == 'XAF') ? 'FCFA' : code;
    return '${formatter.format(amount)} $suffix';
  }

  /// Format a price as a single value or a range:
  /// "15 000 FCFA" or "15 000 – 25 000 FCFA".
  static String formatPriceRange(double min, double? max, {String? currency}) {
    if (max == null || max <= min) {
      return formatCurrency(min, currency: currency);
    }
    return '${formatCurrency(min, currency: currency)} – '
        '${formatCurrency(max, currency: currency)}';
  }

  /// Format date: "Lundi 15 janvier 2024"
  static String formatDate(DateTime date) {
    return DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date);
  }

  /// Format date short: "15/01/2024"
  static String formatDateShort(DateTime date) {
    return DateFormat('dd/MM/yyyy', 'fr_FR').format(date);
  }

  /// The narrow weekday initials, **Monday first** — « L M M J V S D ».
  ///
  /// §17: a French calendar starts on Monday, and `french_test.dart` asserts
  /// `firstDayOfWeekIndex == 1` under the reason *"structural, not a string"*.
  ///
  /// It lives here because a calendar widget may not build its own — the
  /// `salon_time_pin_test.dart` pin keeps every `DateFormat(` in this file, so
  /// that a French app cannot grow an English label in a corner nobody reads.
  ///
  /// The reference week is a fixed Monday (2026-01-05). It is used to *name*
  /// the weekdays and never to mean a date, so no clock is involved and the
  /// §18 salon-time rule does not apply.
  static List<String> weekdayInitials() {
    final monday = DateTime.utc(2026, 1, 5);
    final narrow = DateFormat('EEEEE', kAppLocale);
    return List<String>.generate(
      7,
      (i) => narrow.format(monday.add(Duration(days: i))),
    );
  }

  /// Format month + year: « juin 2026 ».
  static String formatMonthYear(DateTime date) {
    return DateFormat('MMMM yyyy', 'fr_FR').format(date);
  }

  /// Format time: "14:30"
  static String formatTime(DateTime time) {
    return DateFormat('HH:mm', 'fr_FR').format(time);
  }

  /// Format date and time: "Lundi 15 janvier 2024 à 14:30"
  static String formatDateTime(DateTime dateTime) {
    return '${formatDate(dateTime)} à ${formatTime(dateTime)}';
  }

  /// Format duration: "30 min" or "1h 30min"
  static String formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${remainingMinutes}min';
  }

  /// Relative time in French: « À l’instant », « il y a 5 min », « il y a 2 h »,
  /// "Hier", "il y a 3 j", otherwise a short date. Pass [now] for testing.
  static String formatRelative(DateTime time, {DateTime? now}) {
    final ref = now ?? AppClock.now();
    final diff = ref.difference(time);
    if (diff.inMinutes < 1) return 'À l’instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
    return formatDateShort(time);
  }

  /// Format time for display (e.g. "9h00", "18h30")
  static String formatTimeShort(DateTime time) {
    final h = time.hour;
    final m = time.minute;
    if (m == 0) return '${h}h00';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }
}
