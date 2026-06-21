import 'package:intl/intl.dart';

class Formatters {
  /// Format phone number: +225 XX XX XX XX
  static String formatPhoneNumber(String phone) {
    // Remove all non-digit characters except +
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');

    if (!cleaned.startsWith('+225')) {
      return phone; // Return as-is if not Côte d'Ivoire format
    }

    final digits = cleaned.substring(4); // Remove +225

    if (digits.length != 8) {
      return phone; // Return as-is if incorrect length
    }

    // Format as +225 XX XX XX XX
    return '+225 ${digits.substring(0, 2)} ${digits.substring(2, 4)} ${digits.substring(4, 6)} ${digits.substring(6, 8)}';
  }

  /// Format currency (XOF - West African CFA franc)
  static String formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      symbol: '',
      decimalDigits: 0,
      locale: 'fr_FR',
    );
    return '${formatter.format(amount)} XOF';
  }

  /// Format a price as a single value or a range:
  /// "15 000 XOF" or "15 000 – 25 000 XOF".
  static String formatPriceRange(double min, double? max) {
    if (max == null || max <= min) return formatCurrency(min);
    return '${formatCurrency(min)} – ${formatCurrency(max)}';
  }

  /// Format date: "Lundi 15 janvier 2024"
  static String formatDate(DateTime date) {
    return DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date);
  }

  /// Format date short: "15/01/2024"
  static String formatDateShort(DateTime date) {
    return DateFormat('dd/MM/yyyy', 'fr_FR').format(date);
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
