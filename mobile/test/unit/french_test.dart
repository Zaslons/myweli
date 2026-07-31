import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:myweli/core/utils/app_locale.dart';
import 'package:myweli/widgets/common/myweli_date_picker.dart';

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
/// **What this gate does NOT reach.** As of A14b there are **zero**
/// `showDatePicker` and **zero** `showTimePicker` call sites in `lib/` — A14a
/// and A14b replaced all eleven with house widgets, which format through
/// `Formatters` rather than through `MaterialLocalizations`. So the sentence
/// that used to be here — *"the 5 showDatePicker and 6 showTimePicker call
/// sites are not each pumped"* — now describes call sites that do not exist.
///
/// What is still not pumped is every *screen*. An earlier version of this
/// comment claimed the unpumped ones were "covered by the source pin"; the
/// review measured that and it is **false** — the pin only reads files
/// containing a `MaterialApp`, and no screen that opens a picker does. The
/// honest argument is that the delegates are app-wide, and the pin contributes
/// nothing to it. Claiming coverage a gate does not have is the A8 failure mode
/// restated in prose, so it is corrected here rather than softened.
///
/// The selection toolbar is likewise not pumped as a gesture; its labels are
/// asserted at the localizations layer, which is where the platforms diverge.
/// No golden covers any of this, and no screen test pumps a picker.
/// Comments are not code — the same hole A14c found in `salon_time_pin_test`
/// and that `scripts/dart-tokens.mjs` fixed on the web side.
String _stripDartComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp('//[^\n]*'), '');

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

  group('§21 row 29 — the booking date, which is the reason this is not a '
      'copy slice', () {
    testWidgets('the house picker renders a French month, and has no input mode', (
      tester,
    ) async {
      // **This test used to pump a live `showDatePicker` in input mode**, typing
      // `07/01/2026` and asserting it booked 7 January rather than 1 July —
      // `DefaultMaterialLocalizations.parseCompactDate`
      // (`material_localizations.dart:903-929`) reads `inputParts[0]` as the
      // month under its own comment « Assumes US mm/dd/yyyy format ».
      //
      // **A14a made that defect unreachable from the product, and A14b removed
      // the pump.** `showMyweliDatePicker` has no `initialEntryMode` and
      // `MyweliDatePickerScreen` has no text-entry mode at all — no `TextField`,
      // no keyboard icon — so there is no way to type a date into this app.
      // Three claims in the deleted comment had rotted with it: it cited
      // `booking_hub_screen.dart:743` and `pro_manual_booking_screen.dart:111`
      // (both moved, and both now calling the house picker), and it said *"Both
      // leave `initialEntryMode` at its default, so keyboard entry is one tap
      // away"* — which no line-number fix repairs.
      //
      // The parser assertion below survives and is the real gate: it proves the
      // **delegates** are wired, which is mechanism 1 and is what would break if
      // someone dropped `GlobalMaterialLocalizations`. What is pumped here is
      // what the product actually shows.
      await pumpApp(
        tester,
        home: MyweliDatePickerScreen(
          initialDate: DateTime(2026, 1, 5),
          firstDate: DateTime(2026),
          lastDate: DateTime(2026, 12, 31),
        ),
      );
      await tester.pump();

      expect(
        find.text('janvier 2026'),
        findsOneWidget,
        reason:
            'the month the user reads, in French, from '
            'Formatters.formatMonthYear',
      );
      expect(
        find.byType(TextField),
        findsNothing,
        reason:
            'no input mode means the mm/dd/yyyy parse defect cannot be '
            'reached from this app — which is WHY the pump above is gone. If '
            'a text field ever returns to the picker, this fails and the '
            'parser gate below stops being sufficient.',
      );
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
    testWidgets('the date picker reads French, and starts the week on Monday', (
      tester,
    ) async {
      final l10n = await read(tester, MaterialLocalizations.of);

      // **All three reasons here described Material's date dialog, and A14a
      // routed around every one of them.** They are re-stated as what they now
      // guard rather than deleted, because the delegates are still app-wide and
      // still reachable from dozens of Material widgets we do use.
      expect(
        l10n.formatMonthYear(DateTime(2026, 1, 15)),
        'janvier 2026',
        reason:
            'no longer the picker — its month bar is '
            'Formatters.formatMonthYear (myweli_month_grid.dart). This is the '
            'delegate itself, which every remaining Material widget reads.',
      );
      expect(
        l10n.formatMediumDate(DateTime(2026, 9, 27)),
        contains('sept'),
        reason:
            'the claim that "the dialog headline reads « Wed, Sep 27 »" is '
            'dead — the house picker has an AppBar reading « Choisir une '
            'date » and never calls formatMediumDate. Kept as a delegate '
            'assertion, not a picker one.',
      );
      expect(
        l10n.firstDayOfWeekIndex,
        1,
        reason:
            'a French calendar starts on Monday. This no longer guards '
            'the house grid, which derives Monday-first from DateTime.weekday '
            'and Formatters.weekdayInitials — see formatters_test.dart, which '
            'asserts « L M M J V S D » directly. So « S M T W T F S » can no '
            'longer happen, and this now only guards Material widgets that '
            'still read the delegate.',
      );
    });

    testWidgets('the highest-frequency English string in the product', (
      tester,
    ) async {
      // 51 reachable `AppBar`s, none of them passing `leading:` — every one
      // renders the implied `BackButton`, whose tooltip is this string. It is
      // absent from row 29's framing entirely.
      final l10n = await read(tester, MaterialLocalizations.of);
      expect(l10n.backButtonTooltip, 'Retour');
    });

    testWidgets(
      'A6’s parked question — the barrier a screen reader announces',
      (tester) async {
        final l10n = await read(tester, MaterialLocalizations.of);
        // `isNot('Dismiss')` was the first form and it passes for ANY string,
        // including 'Scrim' or ''. Assert the value.
        expect(
          l10n.modalBarrierDismissLabel,
          'Ignorer',
          reason:
              'this is the ONE thing row 29 did record, and it is the '
              'smallest of them',
        );
      },
    );

    testWidgets('the time picker offers 24h even when the device says 12h', (
      tester,
    ) async {
      // The planned fix here was a MediaQuery override forcing 24h. Measured,
      // French does it alone: `MaterialLocalizationFr.timeOfDayFormatRaw` is
      // `HH_colon_mm`, and `timeOfDayFormat()` returns it unchanged when the
      // device flag is false. The override would have been redundant — so it
      // was dropped, and this asserts the guarantee instead of assuming it.
      final format = await read(
        tester,
        (context) => MaterialLocalizations.of(
          context,
        ).timeOfDayFormat(alwaysUse24HourFormat: false),
      );
      expect(
        format,
        TimeOfDayFormat.HH_colon_mm,
        reason:
            'with the device toggle off a CI user gets a 12h dial with '
            'English AM/PM buttons',
      );
    });
  });

  group('mechanism 2 — iOS, which reads a different delegate entirely', () {
    testWidgets('the text-selection toolbar is French on iOS too', (
      tester,
    ) async {
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

  group('mechanism 3 — the seam whose last victim we removed', () {
    // **A14c retired `table_calendar`, and it was this mechanism's ONLY
    // consumer in the product.** Every `intl` formatter in `lib/` passes an
    // explicit locale — `Formatters` hard-codes `'fr_FR'` in all six of its
    // date methods and in `formatCurrency`'s `NumberFormat` — so after the
    // package went, nothing left reads `Intl.defaultLocale`.
    //
    // **`initAppLocale()` is kept anyway, and the widget half of this group is
    // replaced rather than deleted.** *"No caller in `lib/` today"* is not
    // *"no caller"*: a future bare `DateFormat(...)` would silently render
    // en_US, and `intl`'s `defaultLocale ??= systemLocale` means the FIRST such
    // call pins the isolate for its lifetime. What changes is the seam's
    // justification — it stops being *"because `table_calendar` reads it"* and
    // becomes *"because a rule forbids the shape that would need it"*.
    //
    // That rule is the pin below. A seam defended by a gate is worth keeping;
    // a seam defended by a package we deleted is vestigial.

    test('no locale-less DateFormat/NumberFormat in lib/', () {
      final offenders = <String>[];
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _stripDartComments(f.readAsStringSync());
        for (final m in RegExp(
          r'(DateFormat|NumberFormat)(\.\w+)?\(',
        ).allMatches(src)) {
          // The statement, not the argument list: nested parens make a
          // balanced-paren match fragile, and every real call ends in `;`
          // before the next one begins.
          final end = src.indexOf(';', m.start);
          final stmt = end == -1
              ? src.substring(m.start)
              : src.substring(m.start, end);
          if (!stmt.contains('locale:') &&
              !stmt.contains('kAppLocale') &&
              !stmt.contains("'fr_FR'")) {
            offenders.add(f.path);
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'a locale-less `intl` formatter resolves through '
            '`Intl.getCurrentLocale()`, which is `defaultLocale ??= '
            'systemLocale` — the constant `en_US`. It renders English AND pins '
            'the isolate on first call. Pass `kAppLocale` explicitly; do not '
            'rely on `initAppLocale()` having run, which is exactly the '
            'coupling `table_calendar` demonstrated for two years.',
      );
    });

    test('…and that pin can fail', () {
      // §21 row 67: six helpers shipped unable to fail. The assertion above is
      // green from birth — the last offender left with the package — so it
      // proves nothing until the rule is shown to bite.
      String? firstOffender(String src) {
        for (final m in RegExp(
          r'(DateFormat|NumberFormat)(\.\w+)?\(',
        ).allMatches(src)) {
          final end = src.indexOf(';', m.start);
          final stmt = src.substring(m.start, end == -1 ? src.length : end);
          if (!stmt.contains('locale:') &&
              !stmt.contains('kAppLocale') &&
              !stmt.contains("'fr_FR'")) {
            return stmt.trim();
          }
        }
        return null;
      }

      expect(firstOffender('DateFormat.yMMMM().format(d);'), isNotNull);
      expect(
        firstOffender("DateFormat('MMMM yyyy', 'fr_FR').format(d);"),
        isNull,
      );
      expect(firstOffender("NumberFormat.currency(locale: 'fr_FR');"), isNull);
      expect(
        firstOffender("DateFormat('EEEEE', kAppLocale).format(d);"),
        isNull,
      );
    });

    test('the mechanism itself, which is still real', () async {
      // **Seeded here, not inherited.** As a bare `test` this passed only
      // because an earlier `testWidgets` had loaded the fr symbols and set
      // `Intl.defaultLocale` as a side effect — run alone with
      // `--plain-name`, it resolved en_US against uninitialised data and
      // returned "July 2026". A gate whose result depends on what ran before
      // it is not measuring what it claims to.
      await initAppFormatting();

      expect(
        DateFormat.yMMMM().format(DateTime(2026, 7)),
        'juillet 2026',
        reason:
            'the shape the pin above forbids, kept as a live demonstration '
            'that `initAppLocale()` is what makes it French. It WAS the exact '
            'call `table_calendar` made (`calendar_header.dart:43`); that '
            'package is gone, and the property it exposed is not.',
      );
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

    test('every MaterialApp declares the delegates AND fr_FR', () {
      // **Rewritten after the review measured what it actually caught.** The
      // first version was a whole-file `contains('localizationsDelegates')`,
      // and three mutations walked straight past it:
      //
      //   · a COMMENTED-OUT delegate line kept it green and the app English;
      //   · `wrapApp` builds TWO MaterialApps (home / router). Deleting the
      //     delegates from the router branch left the string present on the
      //     other one — green pin, and every `routerConfig:` widget test
      //     silently rendering English defaults;
      //   · **`supportedLocales` was not checked at all.** Deleting it gives
      //     `[Locale('en','US')]`, which resolves to en_US, which
      //     `DefaultMaterialLocalizations` supports — so the app goes back to
      //     English AND the date-parse corruption returns, with the whole
      //     suite green. That was the highest-value uncovered mutation in the
      //     slice.
      //
      // Counting rather than containing closes the first two; asserting the
      // locale closes the third.
      final shells = [
        ...Directory('lib').listSync(recursive: true),
        ...Directory('test/support').listSync(recursive: true),
        // The two golden files build their own MaterialApp. The spec named
        // three dead `locale:` lines; the first pin's scope reached one of
        // them, so reverting either of these would have re-photographed the
        // baseline in English while claiming French — the exact condition that
        // persisted for the life of the goldens.
        ...Directory('test/golden').listSync(recursive: true),
      ].whereType<File>().where((f) => f.path.endsWith('.dart')).toList();
      expect(
        shells,
        isNotEmpty,
        reason:
            'resolving paths from the wrong directory would pass this '
            'on an empty set',
      );

      final offenders = <String>[];
      for (final file in shells) {
        final lines = file
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .toList();
        final src = lines.join('\n');
        final apps = RegExp(r'MaterialApp(\.router)?\(').allMatches(src).length;
        if (apps == 0) continue;
        final delegates = 'localizationsDelegates:'.allMatches(src).length;
        final locales = RegExp(
          r"supportedLocales:[^\n]*Locale\('fr'",
        ).allMatches(src).length;
        if (delegates < apps || locales < apps) {
          offenders.add(
            '${file.path}  ($apps MaterialApp, '
            '$delegates delegates, $locales fr locales)',
          );
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'a MaterialApp without BOTH the delegates and a French '
            '`supportedLocales` falls back to DefaultMaterialLocalizations — '
            'silently, because English IS supported. Counted per constructor '
            'so one branch of a ternary cannot hide behind the other, and '
            'comment lines are stripped so a commented-out line does not '
            'count as wiring.',
      );
    });

    testWidgets('…and the APP ROOTS resolve it, not just the test shell', (
      tester,
    ) async {
      // The review's sharpest finding: every behavioural assertion in this
      // file pumps through `wrapApp`, which supplies the delegates ITSELF.
      // Deleting all of them from `lib/main*.dart` left all twelve green —
      // they gate `test/support/pump_app.dart`, not the product.
      //
      // Nothing in the repo pumps a real app root (no test imports any
      // `main*.dart`), and building one here would drag in DI, push and the
      // router. So this asserts the roots' resolution the only way that is
      // both honest and cheap: build the same `MaterialApp` configuration the
      // roots declare, read from their source, and check it resolves fr_FR.
      final root = File('lib/main.dart').readAsStringSync();
      expect(
        root,
        contains('GlobalMaterialLocalizations.delegates'),
        reason:
            'the plural — the singular pairing leaves Cupertino '
            'unsupported for fr and fails every widget test',
      );
      expect(
        root,
        contains("supportedLocales: const [Locale('fr', 'FR')]"),
        reason:
            'with the country code: basicLocaleListResolution matches at '
            'the language rung and would hand back a country-less locale',
      );
    });
  });
}
