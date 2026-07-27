import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// The app's locale seam (SYSTEM.md §17, A9) — the `intl` half of "French
/// everywhere", which the localization delegates do **not** cover.
///
/// **Why this exists at all.** `flutter_localizations` fixes what
/// `Localizations.of(context)` returns. It does nothing for code that formats
/// through `intl` directly with no `locale:` — and `table_calendar` is exactly
/// that (`calendar_header.dart:43` → `DateFormat.yMMMM(locale)` with a null
/// locale). A locale-less `DateFormat` resolves via
/// `Intl.getCurrentLocale()`, which is `defaultLocale ??= systemLocale`
/// (`intl.dart:528`) — and `systemLocale` is the constant `'en_US'`.
///
/// So before A9 the consumer booking calendar rendered « July 2026 » with a
/// « Mon Tue Wed » weekday row, one widget below a fully French screen. Worse,
/// the `??=` means the *first* such call permanently pins the isolate.
///
/// **Why a seam and not a line in `main()`.** A line in `main()` is correct for
/// the product and invisible to every test, because tests never run `main()`.
/// That is the same split that let `goldenApp` claim `locale: fr_FR` for the
/// entire life of the golden baseline while resolving to `en_US`. This is
/// called by the three app roots *and* by `wrapApp`, so the thing under test is
/// the thing that ships — the `initSalonTime()` idiom, applied to language.
///
/// Idempotent: safe to call per-test.
void initAppLocale() {
  Intl.defaultLocale = kAppLocale;
}

/// The one locale this product speaks (PRD FR-L10N-001, V1). English and Nouchi
/// are FR-L10N-002, scoped to V3 — see §21's NFR-I18N-001 row for why A9
/// deliberately did not build the externalisation layer they would need.
const String kAppLocale = 'fr_FR';

/// `initializeDateFormatting` + [initAppLocale], in the order that matters.
///
/// `initializeDateSymbols` is a **no-op once the table is seeded**
/// (`date_format_internal.dart:60`), and
/// `GlobalMaterialLocalizations.delegate.load()` seeds it with
/// flutter_localizations' own subset. Load the CLDR data first, or the later
/// call silently does nothing.
Future<void> initAppFormatting() async {
  await initializeDateFormatting(kAppLocale, null);
  initAppLocale();
}
