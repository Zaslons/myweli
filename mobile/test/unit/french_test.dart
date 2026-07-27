import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../support/pump_app.dart';

/// A9 — the app speaks French, including the parts we did not write
/// (SYSTEM.md §17, §21 row 29).
///
/// **Written before the wiring, and watched fail.** A8's review taught the
/// correction to "gate first": it is necessary and not sufficient. A8 wrote
/// four gate commits that all pumped `BrandLoader`, and shipped three defects
/// in the five call sites they never touched.
///
/// So this gate is spread across **mechanisms**, not widgets, because this
/// slice has three of them and any one of them can be right while the other two
/// are broken:
///
///   1. `GlobalMaterialLocalizations` — the Material defaults;
///   2. `GlobalCupertinoLocalizations` — which iOS uses for the text-selection
///      toolbar, and which `MaterialApp` will otherwise stub out with an
///      English-only delegate;
///   3. `Intl.defaultLocale` — which `table_calendar` reads instead of
///      `Localizations`, so the delegates do nothing for it.
///
/// **What this gate does NOT reach**, stated rather than implied: the 5
/// `showDatePicker` and 6 `showTimePicker` call sites are not each pumped — one
/// representative picker is, and the rest are covered by the source pin plus
/// the fact that all three mechanisms are app-wide. Neither is the selection
/// toolbar pumped as a gesture; its labels are asserted at the localizations
/// layer, which is where the two platforms diverge. No golden covers any of
/// this, and no screen test pumps a picker — measured: zero.
void main() {
  /// Capture the resolved localizations from inside the app shell.
  Future<T> read<T>(
    WidgetTester tester,
    T Function(BuildContext context) of,
  ) async {
    late T value;
    await pumpApp(
      tester,
      home: Builder(
        builder: (context) {
          value = of(context);
          return const SizedBox.shrink();
        },
      ),
    );
    await tester.pump();
    return value;
  }

  group(
      '§21 row 29 — the booking date, which is the reason this is not a '
      'copy slice', () {
    testWidgets('typing 07/01/2026 books 7 janvier, not 1 July',
        (tester) async {
      // `DefaultMaterialLocalizations.parseCompactDate`
      // (`material_localizations.dart:903-929`) reads `inputParts[0]` as the
      // month, under its own comment « Assumes US mm/dd/yyyy format ». It is
      // not overridable by any `showDatePicker` parameter, and the field's hint
      // even says `mm/dd/yyyy`.
      //
      // Reachable at `booking_hub_screen.dart:743` — the consumer funnel — and
      // at `pro_manual_booking_screen.dart:111`. Both leave `initialEntryMode`
      // at its default, so keyboard entry is one tap away.
      DateTime? picked;
      await pumpApp(
        tester,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showDatePicker(
                context: context,
                initialDate: DateTime(2026, 1, 5),
                firstDate: DateTime(2026),
                lastDate: DateTime(2026, 12, 31),
                initialEntryMode: DatePickerEntryMode.input,
              );
            },
            child: const Text('ouvrir'),
          ),
        ),
      );

      await tester.tap(find.text('ouvrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(find.byType(TextField), '07/01/2026');
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(picked, DateTime(2026, 1, 7),
          reason: 'a date typed in a French app must be read as French. '
              'Today this books 1 July — silently, with no error, on the '
              'consumer booking funnel.');
    });

    testWidgets('…and the parser itself agrees', (tester) async {
      // The end-to-end above is the one that matters, but it can only fail
      // once. This says WHY, so a future reader does not have to re-derive it.
      final parse = await read(
        tester,
        (context) =>
            MaterialLocalizations.of(context).parseCompactDate('07/01/2026'),
      );
      expect(parse, DateTime(2026, 1, 7));
    });
  });

  group('mechanism 1 — the Material defaults', () {
    testWidgets('the date picker reads French, and starts the week on Monday',
        (tester) async {
      final l10n = await read(tester, MaterialLocalizations.of);

      expect(l10n.formatMonthYear(DateTime(2026, 1, 15)), 'janvier 2026',
          reason: 'the month/year toggle — prominent, and not overridable by '
              'any showDatePicker parameter');
      expect(l10n.formatMediumDate(DateTime(2026, 9, 27)), contains('sept'),
          reason: 'the dialog headline reads « Wed, Sep 27 » today');
      expect(l10n.firstDayOfWeekIndex, 1,
          reason: 'a French calendar starts on Monday. Today the weekday row '
              'reads S M T W T F S and the grid starts on Sunday — structural, '
              'not a string, and nothing about it is a label anyone could '
              'override.');
    });

    testWidgets('the highest-frequency English string in the product',
        (tester) async {
      // 51 reachable `AppBar`s, none of them passing `leading:` — every one
      // renders the implied `BackButton`, whose tooltip is this string. It is
      // absent from row 29's framing entirely.
      final l10n = await read(tester, MaterialLocalizations.of);
      expect(l10n.backButtonTooltip, 'Retour');
    });

    testWidgets('A6’s parked question — the barrier a screen reader announces',
        (tester) async {
      final l10n = await read(tester, MaterialLocalizations.of);
      expect(l10n.modalBarrierDismissLabel, isNot('Dismiss'),
          reason: 'this is the ONE thing row 29 did record, and it is the '
              'smallest of them');
    });

    testWidgets('the time picker offers 24h even when the device says 12h',
        (tester) async {
      // The planned fix here was a MediaQuery override forcing 24h. Measured,
      // French does it alone: `MaterialLocalizationFr.timeOfDayFormatRaw` is
      // `HH_colon_mm`, and `timeOfDayFormat()` returns it unchanged when the
      // device flag is false. The override would have been redundant — so it
      // was dropped, and this asserts the guarantee instead of assuming it.
      final format = await read(
        tester,
        (context) => MaterialLocalizations.of(context)
            .timeOfDayFormat(alwaysUse24HourFormat: false),
      );
      expect(format, TimeOfDayFormat.HH_colon_mm,
          reason: 'with the device toggle off a CI user gets a 12h dial with '
              'English AM/PM buttons');
    });
  });

  group('mechanism 2 — iOS, which reads a different delegate entirely', () {
    testWidgets('the text-selection toolbar is French on iOS too',
        (tester) async {
      // `adaptive_text_selection_toolbar.dart:211` routes iOS/macOS through
      // `CupertinoLocalizations`, and `app_theme.dart` never overrides
      // `platform:` — so this branch is live on every iPhone, across 50
      // reachable text fields, in an app that imports zero Cupertino widgets.
      //
      // `MaterialApp` ALWAYS appends `DefaultCupertinoLocalizations.delegate`
      // (`material/app.dart:931`), which supports only `en`. Wiring the
      // Material delegate alone leaves this English AND makes
      // `_debugCheckLocalizations` fire — which `flutter_test` turns into a
      // hard failure in every test that pumps a `MaterialApp`.
      final l10n = await read(tester, CupertinoLocalizations.of);
      expect(l10n.cutButtonLabel, 'Couper');
      expect(l10n.pasteButtonLabel, 'Coller');
    });
  });

  group('mechanism 3 — the calendar the delegates cannot reach', () {
    testWidgets('the booking calendar header is French', (tester) async {
      // `table_calendar` formats with `intl`'s `DateFormat`, passing its own
      // `locale:` — which no call site provides — so it falls through to
      // `Intl.defaultLocale`, which is set NOWHERE in this repo. A locale-less
      // `DateFormat` formats in `en_US` and pins the isolate there on first
      // call (`intl.dart:528`, `defaultLocale ??= systemLocale`).
      //
      // So `flutter_localizations` is irrelevant here: this one needs
      // `Intl.defaultLocale = 'fr_FR'`. Gated separately for exactly that
      // reason — a gate that only proved the delegates would have certified a
      // consumer booking screen still reading "July 2026".
      await pumpApp(
        tester,
        home: Scaffold(
          body: TableCalendar<void>(
            firstDay: DateTime(2026),
            lastDay: DateTime(2026, 12, 31),
            focusedDay: DateTime(2026, 7, 1),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('juillet 2026'), findsOneWidget,
          reason: 'the consumer booking calendar renders « July 2026 » today, '
              'directly above a French screen');
    });

    test('and the mechanism behind it', () {
      expect(DateFormat.yMMMM().format(DateTime(2026, 7)), 'juillet 2026',
          reason: 'this is the exact call table_calendar makes '
              '(calendar_header.dart:43) with a null locale');
    });
  });

  group('the wiring itself', () {
    testWidgets('the resolved locale keeps its country code', (tester) async {
      // Written because a mutation caught the claim being unproven:
      // `supportedLocales: [Locale('fr')]` passed every other assertion in this
      // file. It would still be wrong — `basicLocaleListResolution` matches at
      // the language rung and hands back a country-less locale, which disagrees
      // with `kAppLocale`/`initializeDateFormatting('fr_FR')` and with anything
      // that round-trips `Localizations.localeOf(context).toString()`.
      //
      // The comment in `main.dart` asserted this; nothing checked it. Now
      // something does.
      final locale = await read(tester, Localizations.localeOf);
      expect(locale.toString(), 'fr_FR');
    });

    test('every MaterialApp declares the delegates', () {
      // Discovered, not listed — a fourth app root, or a second test shell, is
      // covered the day it lands. Modelled on `salon_time_pin_test.dart:45`.
      //
      // `test/support/` is in scope on purpose: `goldenApp` has passed
      // `locale: const Locale('fr','FR')` since the golden baseline existed,
      // and with the default `supportedLocales` it resolves to **en_US**. The
      // harness looked localized and was not.
      final sources = [
        ...Directory('lib').listSync(recursive: true),
        ...Directory('test/support').listSync(recursive: true),
      ].whereType<File>().where((f) => f.path.endsWith('.dart')).toList();
      expect(sources, isNotEmpty,
          reason: 'resolving paths from the wrong directory would pass this '
              'on an empty set');

      final offenders = <String>[];
      for (final file in sources) {
        final src = file.readAsStringSync();
        if (!src.contains('MaterialApp(') &&
            !src.contains('MaterialApp.router(')) {
          continue;
        }
        if (!src.contains('localizationsDelegates')) {
          offenders.add(file.path);
        }
      }

      expect(offenders, isEmpty,
          reason: 'a MaterialApp without delegates falls back to '
              'DefaultMaterialLocalizations, which supports English only — '
              'and does so silently, because English IS supported.');
    });
  });
}
