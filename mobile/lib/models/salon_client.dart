import 'package:equatable/equatable.dart';

import '../core/utils/phone_numbering.dart';

/// A salon's client (module `clients` C1 — docs/design/clients-c1.md).
/// DERIVED from bookings: platform users (`linked`) + walk-in guests keyed by
/// phone. Mirrors the `SalonClient` / `SalonClientListItem` DTOs.
class SalonClient extends Equatable {
  const SalonClient({
    required this.id,
    required this.displayName,
    required this.tags,
    required this.linked,
    this.phone,
    this.lastVisitAt,
    this.visits = 0,
    this.noShows = 0,
    this.phoneEditable = false,
  });

  final String id;
  final String displayName;
  final String? phone;
  final List<String> tags;
  final DateTime? lastVisitAt;
  final bool linked;

  /// List-item stats (completed visits / no-shows at THIS salon).
  final int visits;
  final int noShows;

  /// Whether this card's number can be changed (`PATCH …/clients/{id}` with
  /// `phone`) — the SERVER's answer, sent on the card (its `GET` and every
  /// `PATCH` answer): a guest card that has a number. Only a `true` says yes:
  /// absent is a server from before the change, whose PATCH refuses a number,
  /// or a list row, which never offers it (phone-leftovers.md §8).
  final bool phoneEditable;

  factory SalonClient.fromJson(Map<String, dynamic> json) => SalonClient(
    id: json['id'] as String,
    displayName: json['displayName'] as String? ?? 'Client',
    phone: json['phone'] as String?,
    tags: ((json['tags'] as List?) ?? const []).cast<String>(),
    lastVisitAt: json['lastVisitAt'] == null
        ? null
        : DateTime.tryParse(json['lastVisitAt'] as String),
    linked: json['linked'] as bool? ?? false,
    visits: (json['visits'] as num?)?.toInt() ?? 0,
    noShows: (json['noShows'] as num?)?.toInt() ?? 0,
    phoneEditable: json['phoneEditable'] == true,
  );

  SalonClient copyWith({
    List<String>? tags,
    String? phone,
    bool? phoneEditable,
  }) => SalonClient(
    id: id,
    displayName: displayName,
    phone: phone ?? this.phone,
    tags: tags ?? this.tags,
    lastVisitAt: lastVisitAt,
    linked: linked,
    visits: visits,
    noShows: noShows,
    phoneEditable: phoneEditable ?? this.phoneEditable,
  );

  @override
  List<Object?> get props => [
    id,
    displayName,
    phone,
    tags,
    lastVisitAt,
    linked,
    visits,
    noShows,
    phoneEditable,
  ];
}

/// Salon-scoped aggregates on the client card.
class SalonClientStats extends Equatable {
  const SalonClientStats({
    required this.visits,
    required this.spentFcfa,
    required this.noShows,
    required this.cancellations,
  });

  final int visits;
  final num spentFcfa;
  final int noShows;
  final int cancellations;

  factory SalonClientStats.fromJson(Map<String, dynamic> json) =>
      SalonClientStats(
        visits: (json['visits'] as num?)?.toInt() ?? 0,
        spentFcfa: (json['spentFcfa'] as num?) ?? 0,
        noShows: (json['noShows'] as num?)?.toInt() ?? 0,
        cancellations: (json['cancellations'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [visits, spentFcfa, noShows, cancellations];
}

/// A team-internal note — NEVER shown to the consumer (threat T47).
class SalonClientNote extends Equatable {
  const SalonClientNote({
    required this.id,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String authorName;
  final String body;
  final DateTime createdAt;

  factory SalonClientNote.fromJson(Map<String, dynamic> json) =>
      SalonClientNote(
        id: json['id'] as String,
        authorName: json['authorName'] as String? ?? 'Équipe',
        body: json['body'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  @override
  List<Object?> get props => [id, authorName, body, createdAt];
}

/// The full card: client + stats + upcoming + notes.
class SalonClientCard extends Equatable {
  const SalonClientCard({
    required this.client,
    required this.stats,
    required this.notes,
    this.upcoming,
  });

  final SalonClient client;
  final SalonClientStats stats;
  final List<SalonClientNote> notes;

  /// The next pending/confirmed booking, as the raw appointment json
  /// (rendered with the existing appointment widgets).
  final Map<String, dynamic>? upcoming;

  factory SalonClientCard.fromJson(Map<String, dynamic> json) =>
      SalonClientCard(
        client: SalonClient.fromJson(json),
        stats: SalonClientStats.fromJson(
          (json['stats'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        notes: ((json['notes'] as List?) ?? const [])
            .map((e) => SalonClientNote.fromJson(e as Map<String, dynamic>))
            .toList(),
        upcoming: (json['upcoming'] as Map?)?.cast<String, dynamic>(),
      );

  SalonClientCard copyWith({
    SalonClient? client,
    List<SalonClientNote>? notes,
  }) => SalonClientCard(
    client: client ?? this.client,
    stats: stats,
    notes: notes ?? this.notes,
    upcoming: upcoming,
  );

  @override
  List<Object?> get props => [client, stats, notes, upcoming];
}

/// The answer to a number change on a guest card (`PATCH …/clients/{id}`
/// with `phone` — docs/design/phone-leftovers.md §8): the card as it now is,
/// or — refused because the number is already on another card of the salon
/// (`client_exists`) — that card's id, the shape `POST …/clients` answers a
/// duplicate with.
class SalonClientPhoneChange extends Equatable {
  /// Changed (or it already was this number): the card, history re-read.
  const SalonClientPhoneChange.changed(SalonClientCard this.card)
    : takenBy = null;

  /// Refused: [takenBy] is the card that already has the number.
  const SalonClientPhoneChange.taken(String this.takenBy) : card = null;

  final SalonClientCard? card;
  final String? takenBy;

  @override
  List<Object?> get props => [card, takenBy];
}

/// One page of the client list.
class SalonClientsPage extends Equatable {
  const SalonClientsPage({
    required this.items,
    required this.page,
    required this.total,
    this.pageSize,
    this.availableTags = const [],
  });

  final List<SalonClient> items;
  final int page;
  final int total;

  /// The page size the SERVER used (its echo, after its 1–50 clamp) — the
  /// one its offsets were computed with, so a walk over every page counts
  /// pages with it. Null when the answer carried none: such a page is never
  /// walked (docs/design/app-pro-export-completeness.md §4).
  final int? pageSize;

  /// Page 1 only: presets + the salon's custom tags (filter chips).
  final List<String> availableTags;

  /// Throws a [FormatException] when `items` is not a list or `total` not a
  /// number. The server always sends both, so a readable page without them
  /// means a changed contract or something other than the API answering —
  /// read as « no clients, total 0 », it passed the export's walk as an empty
  /// base, complete (docs/design/export-unreadable-200.md §1).
  /// `ApiProClientsService.listClients` turns the throw into its « Erreur »,
  /// so every screen gets an error answer. `pageSize` stays tolerant.
  factory SalonClientsPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    final total = json['total'];
    if (items is! List) {
      throw const FormatException('A clients page without its items');
    }
    if (total is! num) {
      throw const FormatException('A clients page without its total');
    }
    return SalonClientsPage(
      items: items
          .map((e) => SalonClient.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: (json['page'] as num?)?.toInt() ?? 1,
      total: total.toInt(),
      pageSize: (json['pageSize'] as num?)?.toInt(),
      availableTags: ((json['availableTags'] as List?) ?? const [])
          .cast<String>(),
    );
  }

  @override
  List<Object?> get props => [items, page, total, pageSize, availableTags];
}

/// The starter tag presets (module decision clients §11.1).
const salonClientPresetTags = ['VIP', 'Fidèle', 'À risque'];

/// « +225 07 •• •• •89 » — the full number stays on the card only.
///
/// The calling code is the longest one the number starts with
/// (`PhoneNumbering.callingCodeOf`, the reading `PhoneNumberField` gives a
/// stored number). It used to be the first three digits whatever the country,
/// so a French client's row read « +336 12 … » (phone-leftovers.md §8).
String maskClientPhone(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 6) return phone;
  final international = phone.startsWith('+');
  final code = international ? PhoneNumbering.callingCodeOf(digits) : '';
  final national = digits.substring(code.length);
  if (national.length < 4) return phone;
  final cc = !international
      ? ''
      : code.isEmpty
      ? '+'
      : '+$code ';
  return '$cc${national.substring(0, 2)} •• •• '
      '•${national.substring(national.length - 2)}';
}
