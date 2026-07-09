import 'package:equatable/equatable.dart';

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
      );

  SalonClient copyWith({List<String>? tags}) => SalonClient(
        id: id,
        displayName: displayName,
        phone: phone,
        tags: tags ?? this.tags,
        lastVisitAt: lastVisitAt,
        linked: linked,
        visits: visits,
        noShows: noShows,
      );

  @override
  List<Object?> get props =>
      [id, displayName, phone, tags, lastVisitAt, linked, visits, noShows];
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
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
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
  }) =>
      SalonClientCard(
        client: client ?? this.client,
        stats: stats,
        notes: notes ?? this.notes,
        upcoming: upcoming,
      );

  @override
  List<Object?> get props => [client, stats, notes, upcoming];
}

/// One page of the client list.
class SalonClientsPage extends Equatable {
  const SalonClientsPage({
    required this.items,
    required this.page,
    required this.total,
    this.availableTags = const [],
  });

  final List<SalonClient> items;
  final int page;
  final int total;

  /// Page 1 only: presets + the salon's custom tags (filter chips).
  final List<String> availableTags;

  factory SalonClientsPage.fromJson(Map<String, dynamic> json) =>
      SalonClientsPage(
        items: ((json['items'] as List?) ?? const [])
            .map((e) => SalonClient.fromJson(e as Map<String, dynamic>))
            .toList(),
        page: (json['page'] as num?)?.toInt() ?? 1,
        total: (json['total'] as num?)?.toInt() ?? 0,
        availableTags:
            ((json['availableTags'] as List?) ?? const []).cast<String>(),
      );

  @override
  List<Object?> get props => [items, page, total, availableTags];
}

/// The starter tag presets (module decision clients §11.1).
const salonClientPresetTags = ['VIP', 'Fidèle', 'À risque'];

/// « +225 07 •• •• •89 » — the full number stays on the card only.
String maskClientPhone(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 6) return phone;
  final cc = phone.startsWith('+') ? '+${digits.substring(0, 3)} ' : '';
  final head = cc.isEmpty ? digits.substring(0, 2) : digits.substring(3, 5);
  return '$cc$head •• •• •${digits.substring(digits.length - 2)}';
}
