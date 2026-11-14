/// Where a salon stands with MyWeli's validation, in the Pro app (B0.18 —
/// docs/design/salon-go-live-approval.md §6.1, §6.6): the state derived ONCE,
/// the same way the website derives it (`goLiveState`,
/// web/lib/pro/salon-validation.ts; docs/design/web-salon-validation.md §2,
/// row for row), and the words each surface shows for it — picked from
/// [SalonValidationCopy], never written here.
///
/// **The two servers (decision 136 item 10).** A backend from before B0.18
/// sends no `validation` key: [GoLiveState.legacy], today's screens and
/// words. The B0.18 backend always sends the key — `null` while the salon
/// never asked. Only the KEY's presence opens the new states
/// ([readSalonValidationKey]).
///
/// **Who reads what.** Every member reads the state; `offerLive` and the
/// refusal's note go only to the owner (`salon.publish`), so a member who is
/// not the owner lands on [GoLiveState.offline] where the owner reads
/// [GoLiveState.offlineUnpaid] or [GoLiveState.offlineRepublish] — the role
/// is carried by the server's view, not passed here. Who sees the card at
/// all stays the screens' `can(ProCap.salonPublish)`.
library;

import '../../models/salon_validation.dart';
import '../constants/salon_validation_copy.dart';
import 'formatters.dart';
import 'salon_time.dart';

enum GoLiveState {
  /// A server from before B0.18 (no `validation` key): today's screens.
  legacy,

  suspended,
  live,
  neverAsked,

  /// `pending`, or `approved` while the admin's validation finishes.
  pending,

  refused,
  refusedFinal,

  /// Validated and live once, back to `draft`, its offer live: « Remettre en
  /// ligne » (the publish answers 200).
  offlineRepublish,

  /// The same, its offer lapsed: the billing pointer.
  offlineUnpaid,

  /// The same, seen by a member who is not the owner (`offerLive` is the
  /// owner's only): the line, never a card.
  offline,
}

/// web-salon-validation.md §2's table, first match wins:
///
/// | # | Condition | State |
/// |---|---|---|
/// | 1 | no `validation` key | `legacy` |
/// | 2 | `status == 'suspended'` | `suspended` |
/// | 3 | `status == 'active'` (or no status) | `live` |
/// | 4 | `validation == null` | `neverAsked` |
/// | 5 | `pending`, or `approved` with `wentLive` false | `pending` |
/// | 6 | `refused`, `refusal.final` | `refusedFinal` |
/// | 7 | `refused` | `refused` |
/// | 8 | `approved`, `wentLive`, `offerLive == true` | `offlineRepublish` |
/// | 9 | `approved`, `wentLive`, `offerLive == false` | `offlineUnpaid` |
/// | 10 | `approved`, `wentLive`, no `offerLive` (not the owner) | `offline` |
///
/// `suspended` before `live` and before the validation (a pending salon an
/// admin suspends reads « Suspendu »); `live` before the validation (an
/// `active` salon is public whatever its row says — a rollback). A state
/// this build does not know never claims one: `neverAsked`, as the website.
///
/// [status] is the salon's `status` (`Provider.status`, where null reads
/// `active` — seeded documents carry none; or « Mes salons »'
/// `salonStatus`). Empty reads as none, as the website's `!status`.
GoLiveState goLiveState({
  required String? status,
  required bool validationSent,
  required SalonValidation? validation,
}) {
  if (!validationSent) return GoLiveState.legacy;
  if (status == 'suspended') return GoLiveState.suspended;
  // The website's `!status || status === 'active'`: an empty status is
  // « no status » there, so it is here (row 3, row for row).
  if (status == null || status.isEmpty || status == 'active') {
    return GoLiveState.live;
  }
  if (validation == null) return GoLiveState.neverAsked;
  switch (validation.state) {
    case SalonValidationState.pending:
      return GoLiveState.pending;
    case SalonValidationState.refused:
      return validation.refusal?.isFinal == true
          ? GoLiveState.refusedFinal
          : GoLiveState.refused;
    case SalonValidationState.approved:
      if (!validation.wentLive) return GoLiveState.pending;
      return switch (validation.offerLive) {
        true => GoLiveState.offlineRepublish,
        false => GoLiveState.offlineUnpaid,
        null => GoLiveState.offline,
      };
    case SalonValidationState.unknown:
      return GoLiveState.neverAsked;
  }
}

/// The state's line on a salon's row of the picker (§6.1 « Badge / row
/// line »; decision 136 item 8: every row, the user's own salons or not).
/// Null for [GoLiveState.legacy]: the row keeps today's words.
String? goLiveLine(GoLiveState state) => switch (state) {
  GoLiveState.legacy => null,
  GoLiveState.neverAsked => SalonValidationCopy.lineNeverAsked,
  GoLiveState.pending => SalonValidationCopy.linePending,
  GoLiveState.refused ||
  GoLiveState.refusedFinal => SalonValidationCopy.lineRefused,
  GoLiveState.live => SalonValidationCopy.lineLive,
  GoLiveState.offlineRepublish ||
  GoLiveState.offlineUnpaid ||
  GoLiveState.offline => SalonValidationCopy.lineOffline,
  GoLiveState.suspended => SalonValidationCopy.lineSuspended,
};

/// The home card « Configurer mon profil »'s subtitle (decision 136 item 1).
/// [state] null is a state not read yet (an offline cold start — §6.2): the
/// card keeps today's subtitle, as on a server from before B0.18 and while
/// the salon never asked.
String homeCardSubtitle(GoLiveState? state) => switch (state) {
  null ||
  GoLiveState.legacy ||
  GoLiveState.neverAsked => SalonValidationCopy.homeSetUp,
  GoLiveState.pending => SalonValidationCopy.linePending,
  GoLiveState.refused ||
  GoLiveState.refusedFinal => SalonValidationCopy.lineRefused,
  GoLiveState.offlineRepublish ||
  GoLiveState.offlineUnpaid ||
  GoLiveState.offline => SalonValidationCopy.lineOffline,
  GoLiveState.suspended => SalonValidationCopy.lineSuspended,
  GoLiveState.live => SalonValidationCopy.homeLive,
};

/// The banner's tone — the KYC banner's pattern (§6.2). As the website
/// (web-salon-validation.md §4.1): waiting is neutral, a refusal and a
/// suspension are errors, offline is a warning.
enum GoLiveTone { neutral, error, warning }

/// The banner on « Configuration » (§6.1 « Banner title » and « Banner
/// text »).
class GoLiveBanner {
  const GoLiveBanner({
    required this.tone,
    required this.title,
    required this.lines,
  });

  final GoLiveTone tone;
  final String title;

  /// Each on its own line: a refusal's sentence, then the admin's note (a
  /// salon's typed text, never joined to the sentence).
  final List<String> lines;
}

/// A refusal's lines: the code's sentence, then the note on its own line.
/// Either is left out when absent (`other` has no sentence; a member who is
/// not the owner gets no note; a blank note is no note).
List<String> refusalLines(SalonRefusal? refusal) {
  if (refusal == null) return const [];
  final sentence = SalonValidationCopy.refusalSentences[refusal.code];
  final note = refusal.note?.trim();
  return [?sentence, if (note != null && note.isNotEmpty) note];
}

/// The banner for [state], or null for the states without one (`legacy` and
/// `neverAsked` keep the checklist's own header; `live` shows none; and
/// `offline` has no card — its reader is not the owner).
GoLiveBanner? goLiveBanner(GoLiveState state, SalonValidation? validation) =>
    switch (state) {
      GoLiveState.pending => const GoLiveBanner(
        tone: GoLiveTone.neutral,
        title: SalonValidationCopy.pendingTitle,
        lines: [SalonValidationCopy.pendingText],
      ),
      GoLiveState.refused => GoLiveBanner(
        tone: GoLiveTone.error,
        title: SalonValidationCopy.refusedTitle,
        lines: [
          ...refusalLines(validation?.refusal),
          SalonValidationCopy.resubmit,
        ],
      ),
      GoLiveState.refusedFinal => GoLiveBanner(
        tone: GoLiveTone.error,
        title: SalonValidationCopy.refusedTitle,
        lines: refusalLines(validation?.refusal),
      ),
      GoLiveState.offlineUnpaid => const GoLiveBanner(
        tone: GoLiveTone.warning,
        title: SalonValidationCopy.offlineTitle,
        lines: [SalonValidationCopy.offlineUnpaidText],
      ),
      GoLiveState.offlineRepublish => const GoLiveBanner(
        tone: GoLiveTone.warning,
        title: SalonValidationCopy.offlineTitle,
        lines: [SalonValidationCopy.offlineRepublishText],
      ),
      GoLiveState.suspended => const GoLiveBanner(
        tone: GoLiveTone.error,
        title: SalonValidationCopy.suspendedTitle,
        lines: [SalonValidationCopy.suspendedText],
      ),
      GoLiveState.legacy ||
      GoLiveState.neverAsked ||
      GoLiveState.live ||
      GoLiveState.offline => null,
    };

/// The publish button's label, or null for the states without one
/// (`pending` shows « Demande envoyée le … » instead; `refusedFinal`,
/// `suspended`, `live` and `offline` have none; `offlineUnpaid` has the
/// billing pointer, which is not a publish).
String? publishButtonLabel(GoLiveState state) => switch (state) {
  GoLiveState.legacy => SalonValidationCopy.legacyButton,
  GoLiveState.neverAsked => SalonValidationCopy.requestButton,
  GoLiveState.refused => SalonValidationCopy.resubmitButton,
  GoLiveState.offlineRepublish => SalonValidationCopy.republishButton,
  GoLiveState.suspended ||
  GoLiveState.live ||
  GoLiveState.pending ||
  GoLiveState.refusedFinal ||
  GoLiveState.offlineUnpaid ||
  GoLiveState.offline => null,
};

/// The hint beside a DISABLED publish button (the checklist not complete),
/// as the website: today's for `legacy`, the request's for `neverAsked` and
/// `refused`, none otherwise.
String? publishHint(GoLiveState state) => switch (state) {
  GoLiveState.legacy => SalonValidationCopy.legacyHint,
  GoLiveState.neverAsked ||
  GoLiveState.refused => SalonValidationCopy.requestHint,
  _ => null,
};

/// « Demande envoyée le 13 novembre 2026 » — the day in the SALON's clock
/// ([tz], `Provider.timezone`), no weekday (decision 136 item 6); null when
/// the request has no time (a row the 0044 backfill wrote).
String? requestSentLine(DateTime? submittedAt, {String? tz}) {
  if (submittedAt == null) return null;
  return SalonValidationCopy.requestSentOn(
    Formatters.formatDayMonthYear(toSalonTime(submittedAt, tz: tz)),
  );
}
