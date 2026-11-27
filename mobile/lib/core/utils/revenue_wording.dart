import '../../models/revenue_analytics.dart';
import 'formatters.dart';

/// The words of « Revenus » (docs/design/pro-revenue-analytics.md §3.3,
/// §3.6, §4.13) — pure, one place, so the screens and their tests read the
/// same sentences. **Never** « encaissé », « chiffre d'affaires » or
/// « paiements reçus »: MyWeli does not see a payment (§4.10).

// ── Labels (§3.3) ───────────────────────────────────────────────────────────

const String kNoArtistLabel = 'Sans collaborateur attribué';
const String kFormerArtistLabel = 'Ancien collaborateur';
const String kDeletedServiceLabel = 'Prestation supprimée';

/// A channel's name — the clients name them, the server sends no label.
String revenueChannelLabel(RevenueChannel channel) => switch (channel) {
  RevenueChannel.app => 'Application MyWeli',
  RevenueChannel.web => 'Site MyWeli',
  RevenueChannel.salon => 'Ajouté par le salon',
  RevenueChannel.online => 'En ligne (avant le suivi)',
};

/// The label of one row of [axis] — the table of §3.3, row by row.
String revenueRowLabel(
  RevenueAxis axis, {
  required String? key,
  required String? label,
  required RevenueRowState? state,
}) {
  switch (axis) {
    case RevenueAxis.artist:
      if (state == RevenueRowState.unassigned ||
          key == null ||
          key == RevenueQuery.kNoArtist) {
        return kNoArtistLabel;
      }
      if (state == RevenueRowState.removed) {
        return label == null
            ? kFormerArtistLabel
            : '$label · a quitté l’équipe';
      }
      return label ?? kFormerArtistLabel;
    case RevenueAxis.service:
      if (state == RevenueRowState.removed) {
        return label == null
            ? kDeletedServiceLabel
            : '$label · prestation supprimée';
      }
      return label ?? kDeletedServiceLabel;
    case RevenueAxis.channel:
      final channel = RevenueChannel.values
          .where((c) => c.name == key)
          .firstOrNull;
      return channel == null ? (label ?? '') : revenueChannelLabel(channel);
  }
}

/// [row]'s label on [axis].
String revenueLabelOf(RevenueAxis axis, RevenueRow row) =>
    revenueRowLabel(axis, key: row.key, label: row.label, state: row.state);

/// A detail's title, from the answer's filters (§4.8).
String revenueFilterLabel(RevenueAxis axis, RevenueFilters f) =>
    revenueRowLabel(
      axis,
      key: switch (axis) {
        RevenueAxis.artist => f.artistId,
        RevenueAxis.service => f.serviceId,
        RevenueAxis.channel => f.channel,
      },
      label: f.label,
      state: f.state,
    );

/// The tab names of « Répartition » (§4.7).
String revenueAxisTitle(RevenueAxis axis) => switch (axis) {
  RevenueAxis.artist => 'Collaborateurs',
  RevenueAxis.service => 'Prestations',
  RevenueAxis.channel => 'Canaux',
};

// ── Deltas (§3.6) ───────────────────────────────────────────────────────────

/// How a change reads: good, bad, or neither (« stable »).
enum RevenueDeltaTone { good, bad, neutral }

/// One delta as drawn — glyph, signed text, colour — and as spoken.
class RevenueDelta {
  const RevenueDelta({
    required this.text,
    required this.spoken,
    required this.tone,
    required this.up,
  });

  /// « +12 % » · « −8 % » · « stable » · « nouveau » · « −1,2 pt ».
  final String text;

  /// « en hausse de 12 % par rapport à octobre 2026 » (§12.3).
  final String spoken;
  final RevenueDeltaTone tone;

  /// The arrow: up, down, or none (« stable »).
  final bool? up;
}

const String _minus = '−';

String _against(String? comparison) {
  if (comparison == null) return '';
  // « par rapport au 1er – 25 oct. » reads oddly; a range is « la période ».
  final startsWithDigit = RegExp(r'^\d').hasMatch(comparison);
  return startsWithDigit
      ? ' par rapport à la période $comparison'
      : ' par rapport à $comparison';
}

/// The delta of an amount or a count (§3.6). Null when there is nothing to
/// say: no comparison, or both at 0. [upIsGood] is true for every figure but
/// « Taux d'absence » (which uses [revenueRateDelta]).
RevenueDelta? revenueDelta(
  num current,
  num? previous, {
  String? comparison,
  bool upIsGood = true,
}) {
  if (previous == null) return null;
  if (previous == 0) {
    if (current <= 0) return null;
    return RevenueDelta(
      text: 'nouveau',
      spoken: 'nouveau, rien sur la période comparée',
      tone: upIsGood ? RevenueDeltaTone.good : RevenueDeltaTone.bad,
      up: true,
    );
  }
  final pct = ((current - previous) / previous * 100).round();
  if (pct == 0) {
    return RevenueDelta(
      text: 'stable',
      spoken: 'stable${_against(comparison)}',
      tone: RevenueDeltaTone.neutral,
      up: null,
    );
  }
  final up = pct > 0;
  final figure = '${pct.abs()} %';
  return RevenueDelta(
    text: '${up ? '+' : _minus}$figure',
    spoken:
        '${up ? 'en hausse' : 'en baisse'} de $figure${_against(comparison)}',
    tone: up == upIsGood ? RevenueDeltaTone.good : RevenueDeltaTone.bad,
    up: up,
  );
}

/// The delta of « Taux d'absence », in **points** with one decimal
/// (« −1,2 pt »); up is bad. Null when either rate is undefined.
RevenueDelta? revenueRateDelta(
  double? current,
  double? previous, {
  String? comparison,
}) {
  if (current == null || previous == null) return null;
  final tenths = ((current - previous) * 1000).round();
  if (tenths == 0) {
    return RevenueDelta(
      text: 'stable',
      spoken: 'stable${_against(comparison)}',
      tone: RevenueDeltaTone.neutral,
      up: null,
    );
  }
  final up = tenths > 0;
  final points = tenths.abs() / 10;
  final figure = Formatters.formatOneDecimal(points);
  final unit = points < 2 ? 'point' : 'points';
  return RevenueDelta(
    text: '${up ? '+' : _minus}$figure pt',
    spoken:
        '${up ? 'en hausse' : 'en baisse'} de $figure $unit'
        '${_against(comparison)}',
    tone: up ? RevenueDeltaTone.bad : RevenueDeltaTone.good,
    up: up,
  );
}

// ── Counts (§4.13 — plurals through Formatters, never « (s) ») ─────────────

String revenueAbsences(int n) => Formatters.count(n, 'absence', 'absences');

String revenueUpcomingLine(int n) =>
    '${Formatters.count(n, 'rendez-vous confirmé', 'rendez-vous confirmés')} '
    'à venir';

String revenuePendingLine(int n) =>
    '+ ${Formatters.count(n, 'demande', 'demandes')} en attente';

String revenueToCloseTitle(int n) =>
    '${Formatters.count(n, 'rendez-vous passé', 'rendez-vous passés')} '
    'à clôturer';

// ── The ledger (§4.9) ───────────────────────────────────────────────────────

/// « Fatou B. · Tresses, Coupe · Awa Koné ».
String revenueLedgerLine(RevenueLedgerRow r) {
  final client = r.clientDisplayName ?? 'Client';
  final services = r.serviceNames.isEmpty
      ? kDeletedServiceLabel
      : r.serviceNames.map((s) => s ?? kDeletedServiceLabel).join(', ');
  final artist = switch (r.artistState) {
    RevenueRowState.unassigned => 'Sans collaborateur',
    _ => r.artistLabel ?? kFormerArtistLabel,
  };
  return '$client · $services · $artist';
}

/// The ledger's filter chips (§4.9).
String revenueLedgerStatusLabel(RevenueLedgerStatus s) => switch (s) {
  RevenueLedgerStatus.completed => 'Terminés',
  RevenueLedgerStatus.upcoming => 'À venir',
  RevenueLedgerStatus.toClose => 'À clôturer',
  RevenueLedgerStatus.noShow => 'Absents',
  RevenueLedgerStatus.cancelled => 'Annulés',
};

/// « Aucun rendez-vous {filtre} sur cette période. » (§4.13).
String revenueLedgerEmpty(RevenueLedgerStatus s) => switch (s) {
  RevenueLedgerStatus.completed =>
    'Aucun rendez-vous terminé sur cette période.',
  RevenueLedgerStatus.upcoming =>
    'Aucun rendez-vous à venir sur cette période.',
  RevenueLedgerStatus.toClose =>
    'Aucun rendez-vous à clôturer sur cette période.',
  RevenueLedgerStatus.noShow => 'Aucune absence sur cette période.',
  RevenueLedgerStatus.cancelled =>
    'Aucun rendez-vous annulé ou refusé sur cette période.',
};

// ── Footnotes (§4.10) ───────────────────────────────────────────────────────

const String kRevenuePriceFootnote =
    'Montants calculés au prix affiché lors de la réservation. Les paiements '
    'se font entre vous et vos clients : MyWeli n’encaisse rien.';

const String kRevenueServicesFootnote =
    'Un rendez-vous à plusieurs prestations compte pour chacune.';

/// The day R1 started keeping each booking's lines (deployed 2026-11-26,
/// §14): an older booking's prestation amounts are estimated (§3.4).
const String kRevenueEstimatedFootnote =
    'Estimé : réservation faite avant le 26 novembre 2026, répartie selon '
    'les prix actuels de vos prestations.';
