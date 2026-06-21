import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/formatters.dart';

void main() {
  group('Formatters.formatDuration', () {
    test('under an hour shows minutes', () {
      expect(Formatters.formatDuration(30), '30 min');
      expect(Formatters.formatDuration(45), '45 min');
    });

    test('whole hours omit the minutes', () {
      expect(Formatters.formatDuration(60), '1h');
      expect(Formatters.formatDuration(120), '2h');
    });

    test('hours with a remainder show both parts', () {
      expect(Formatters.formatDuration(90), '1h 30min');
      expect(Formatters.formatDuration(150), '2h 30min');
    });
  });

  group('Formatters.formatPhoneNumber', () {
    test('formats a valid 8-digit Côte d\'Ivoire number', () {
      expect(Formatters.formatPhoneNumber('+22507123456'), '+225 07 12 34 56');
    });

    test('returns non-CI numbers unchanged', () {
      expect(Formatters.formatPhoneNumber('0601020304'), '0601020304');
    });

    test('returns wrong-length CI numbers unchanged', () {
      expect(Formatters.formatPhoneNumber('+225071234'), '+225071234');
    });
  });

  group('Formatters.formatTimeShort', () {
    test('on the hour uses the h00 form', () {
      expect(Formatters.formatTimeShort(DateTime(2024, 1, 1, 9, 0)), '9h00');
    });

    test('pads the minutes to two digits', () {
      expect(Formatters.formatTimeShort(DateTime(2024, 1, 1, 18, 30)), '18h30');
      expect(Formatters.formatTimeShort(DateTime(2024, 1, 1, 8, 5)), '8h05');
    });
  });

  group('Formatters.formatCurrency', () {
    // fr_FR formatting uses a non-breaking thousands separator, so assert on
    // the stable parts (the value digits and the XOF suffix) rather than exact
    // whitespace.
    test('produces an XOF-suffixed amount', () {
      expect(Formatters.formatCurrency(0), startsWith('0'));
      expect(Formatters.formatCurrency(0), endsWith('XOF'));
      expect(Formatters.formatCurrency(1500), endsWith('XOF'));
      expect(Formatters.formatCurrency(1500), contains('500'));
    });
  });

  group('Formatters.formatRelative', () {
    final now = DateTime(2024, 6, 24, 12, 0);

    test('shows minutes for recent times', () {
      expect(
        Formatters.formatRelative(
          now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        'il y a 5 min',
      );
    });

    test('shows hours within the day', () {
      expect(
        Formatters.formatRelative(
          now.subtract(const Duration(hours: 2)),
          now: now,
        ),
        'il y a 2 h',
      );
    });

    test('shows "Hier" for one day ago', () {
      expect(
        Formatters.formatRelative(
          now.subtract(const Duration(days: 1)),
          now: now,
        ),
        'Hier',
      );
    });

    test('shows days within the week', () {
      expect(
        Formatters.formatRelative(
          now.subtract(const Duration(days: 3)),
          now: now,
        ),
        'il y a 3 j',
      );
    });
  });
}
