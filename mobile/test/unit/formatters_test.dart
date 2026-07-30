import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/utils/formatters.dart';

void main() {
  // The date helpers ask `intl` for French month and weekday names, and a bare
  // unit test has no locale data — the app roots load it at startup. Without
  // this every assertion below throws `UninitializedLocaleData`, which is one of
  // the reasons these six went untested for as long as they did.
  setUpAll(() => initializeDateFormatting('fr_FR', null));

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
    test('formats a current 10-digit Côte d’Ivoire number', () {
      expect(
        Formatters.formatPhoneNumber('+2250712345678'),
        '+225 07 12 34 56 78',
      );
    });

    test('still formats a legacy 8-digit Côte d’Ivoire number', () {
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
    // the stable parts (the value digits and the FCFA suffix) rather than
    // exact whitespace.
    test(
      'produces an FCFA-suffixed amount (the display name, multi-pays §4)',
      () {
        expect(Formatters.formatCurrency(0), startsWith('0'));
        expect(Formatters.formatCurrency(0), endsWith('FCFA'));
        expect(Formatters.formatCurrency(1500), endsWith('FCFA'));
        expect(Formatters.formatCurrency(1500), contains('500'));
      },
    );

    test(
      'a NULL currency (unthreaded/pre-MP1) falls back to FCFA in the seam',
      () {
        expect(
          Formatters.formatCurrency(1500, currency: null),
          endsWith('FCFA'),
        );
      },
    );

    test(
      'XOF and XAF both read FCFA; other ISO codes render as themselves',
      () {
        expect(
          Formatters.formatCurrency(1500, currency: 'XOF'),
          endsWith('FCFA'),
        );
        expect(
          Formatters.formatCurrency(1500, currency: 'XAF'),
          endsWith('FCFA'),
        );
        expect(
          Formatters.formatCurrency(1500, currency: 'GHS'),
          endsWith('GHS'),
        );
      },
    );
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

  group('Formatters.formatPriceRange', () {
    test('single value when there is no max', () {
      final s = Formatters.formatPriceRange(15000, null);
      expect(s, endsWith('FCFA'));
      expect(s, isNot(contains('–')));
    });

    test('a dash-separated range when max is greater', () {
      final s = Formatters.formatPriceRange(15000, 25000);
      expect(s, contains('–'));
      expect(s, contains('15'));
      expect(s, contains('25'));
    });

    test('single value when max is not greater than min', () {
      expect(Formatters.formatPriceRange(15000, 15000), isNot(contains('–')));
    });
  });

  // ── A14b, debt 1: the six date/time helpers that had NO test.
  //
  // This file had six groups and none of them was these, which A14a's §6
  // recorded as a promise it did not keep. A14a then made four of them
  // load-bearing:
  //
  //   · `formatDate` is **every day cell's accessibility label** — it is what a
  //     screen reader says when the user lands on a day in the calendar;
  //   · `formatMonthYear` is the month bar *and* its `Semantics.label`;
  //   · `weekdayInitials` is the « L M M J V S D » row;
  //   · `formatDateShort` labels the manual-booking date field and A14b's
  //     combined-picker date chip.
  //
  // So the four strings a blind user hears from the house calendar were, until
  // now, asserted by nothing at all.

  group('Formatters.formatDate', () {
    // Lowercase « mercredi », not « Mercredi » — French does not capitalise
    // weekday names, and the docstring on `formatDate` says "Lundi 15 janvier"
    // while the function has always produced "lundi 15 janvier". The assertion
    // follows the code, which is right; the docstring is the thing that is wrong.
    test('« mercredi 11 mars 2026 » — French, full weekday and month', () {
      expect(
        Formatters.formatDate(DateTime(2026, 3, 11)),
        'mercredi 11 mars 2026',
      );
    });

    test('a single-digit day is NOT zero-padded', () {
      // « 5 mars » reads as French; « 05 mars » does not. `DateFormat('d')`
      // rather than `dd` is doing that, and it is easy to "fix" the wrong way.
      expect(Formatters.formatDate(DateTime(2026, 3, 5)), 'jeudi 5 mars 2026');
    });

    test('an accented month keeps its accent', () {
      // février / août — the two that reveal a locale silently resolved to en_US
      // (which would render « February » and never look like an accent bug).
      expect(Formatters.formatDate(DateTime(2026, 2, 1)), contains('février'));
      expect(Formatters.formatDate(DateTime(2026, 8, 1)), contains('août'));
    });
  });

  group('Formatters.formatDateShort', () {
    test('« 11/03/2026 » — day first, zero-padded', () {
      // Day-first is the whole point: `03/11/2026` is a different date to a
      // French reader, and §21 row 29 was about exactly this confusion on input.
      expect(Formatters.formatDateShort(DateTime(2026, 3, 11)), '11/03/2026');
    });

    test('both parts are padded to two digits', () {
      expect(Formatters.formatDateShort(DateTime(2026, 1, 5)), '05/01/2026');
    });
  });

  group('Formatters.formatMonthYear', () {
    test('« mars 2026 » — lowercase, as the picker renders it', () {
      // Lowercase is deliberate and is what the date-picker golden shows. Web's
      // MonthCalendar capitalises via CSS, which is a recorded divergence rather
      // than an accident — so this assertion is also what would catch someone
      // "aligning" them here instead of there.
      expect(Formatters.formatMonthYear(DateTime(2026, 3, 11)), 'mars 2026');
    });

    test('the day is not in the output', () {
      expect(
        Formatters.formatMonthYear(DateTime(2026, 3, 11)),
        Formatters.formatMonthYear(DateTime(2026, 3, 28)),
      );
    });
  });

  group('Formatters.weekdayInitials', () {
    test('« L M M J V S D » — seven, Monday first', () {
      expect(Formatters.weekdayInitials(), ['L', 'M', 'M', 'J', 'V', 'S', 'D']);
    });

    test('it does not start on Sunday', () {
      // The defect this replaced: Material rendered « S M T W T F S » with the
      // grid starting on Sunday. `french_test.dart` asserted
      // `firstDayOfWeekIndex == 1` to catch it — but the house calendar no
      // longer consults `MaterialLocalizations`, so that assertion no longer
      // guards this. This does.
      expect(Formatters.weekdayInitials().first, 'L');
      expect(Formatters.weekdayInitials().last, 'D');
    });
  });

  group('Formatters.formatTime and formatDateTime', () {
    test('« 14:30 » — 24-hour, no AM/PM', () {
      expect(Formatters.formatTime(DateTime(2026, 3, 11, 14, 30)), '14:30');
      expect(Formatters.formatTime(DateTime(2026, 3, 11, 9, 5)), '09:05');
    });

    test('« … à 14:30 » joins the two halves', () {
      expect(
        Formatters.formatDateTime(DateTime(2026, 3, 11, 14, 30)),
        'mercredi 11 mars 2026 à 14:30',
      );
    });
  });

  group('Formatters.formatHourMinute', () {
    // A14b's addition, and the reason it exists: `weekly_hours_editor` had a
    // private `_fmt` doing this with two `padLeft`s, so the repo had a third
    // spelling of « 14:30 » before anyone wrote a fourth.
    test('pads both halves and never invents a date', () {
      expect(Formatters.formatHourMinute(14, 30), '14:30');
      expect(Formatters.formatHourMinute(9, 5), '09:05');
      expect(Formatters.formatHourMinute(0, 0), '00:00');
    });

    test(
      'agrees with formatTime, which is the point of having one of them',
      () {
        for (final (h, m) in const [(0, 0), (9, 5), (14, 30), (23, 55)]) {
          expect(
            Formatters.formatHourMinute(h, m),
            Formatters.formatTime(DateTime(2026, 3, 11, h, m)),
            reason:
                'two spellings of one job that disagree at some value is '
                'exactly what A13 found in the plural rule',
          );
        }
      },
    );
  });
}
