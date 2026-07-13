import 'package:intl/intl.dart';

class Formatters {
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

  /// Format month + year: "juin 2026" (used for visit-history headers).
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

  /// Relative time in French: "À l'instant", "il y a 5 min", "il y a 2 h",
  /// "Hier", "il y a 3 j", otherwise a short date. Pass [now] for testing.
  static String formatRelative(DateTime time, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final diff = ref.difference(time);
    if (diff.inMinutes < 1) return 'À l\'instant';
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
