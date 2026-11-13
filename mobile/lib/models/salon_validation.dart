/// Where a salon stands with MyWeli's validation (B0.18, decision 120 —
/// docs/design/salon-go-live-approval.md §2.3, §3.5): the `validation` object,
/// ONE shape on every read that carries it (openapi `SalonValidation`) — the
/// owner's `/me/provider` and `/me/salons`, the publish 202, the admin routes.
///
/// `{ state, submittedAt?, decidedAt?, wentLive, offerLive?, refusal?: { code,
/// note?, final } }`, plus `decidedBy` on the admin detail only. A server from
/// before B0.18 sends none of it.
library;

import 'package:equatable/equatable.dart';

/// The three states of a validation (`salon_validations.state`), and the one a
/// newer server could add.
enum SalonValidationState {
  /// Waiting for MyWeli.
  pending,

  /// Validated — final for validation; [SalonValidation.wentLive] tells a
  /// validation still finishing from a salon that went live.
  approved,

  /// Refused, with a reason ([SalonValidation.refusal]).
  refused,

  /// A state this build does not know (a newer server). Shown neutral and
  /// never acted on: no decision is ever sent `from` it.
  unknown;

  static SalonValidationState fromWire(Object? raw) => switch (raw) {
    'pending' => pending,
    'approved' => approved,
    'refused' => refused,
    _ => unknown,
  };

  /// The value the server's routes take (`?state=`, approve's `from`).
  String get wire => name;
}

/// §4.3's closed list of refusal codes, in the order the console offers them
/// — the server's `kRefusalCodes` (salon_validation_repository.dart).
const List<String> kSalonRefusalCodes = [
  'incomplete_info',
  'photos',
  'unconfirmed',
  'outside_ci',
  'test_salon',
  'other',
];

/// The refusals a salon cannot answer by asking again (§4.3): only MyWeli can
/// still validate it, from « Refusés ». The server sends the verdict as
/// `refusal.final`; this set is for the console's dialog, before any answer.
const Set<String> kFinalSalonRefusalCodes = {'outside_ci', 'test_salon'};

/// The refusal note's cap (§3.3), in **code points of the trimmed note** — the
/// server counts `trimmed.runes.length` (salon_validation_service.dart). A
/// `TextField.maxLength` counts grapheme clusters, so it cannot be the guard:
/// « 👍🏽 » is one grapheme and two code points.
const int kRefusalNoteMaxCodePoints = 500;

/// The note's length as the server counts it.
int refusalNoteLength(String note) => note.trim().runes.length;

/// What the server would refuse in a refusal before it reads the salon — the
/// same three checks, in the same order (§3.3): `invalid_input` for a code
/// outside the list, `note_required` for `other` without a note,
/// `note_too_long` beyond [kRefusalNoteMaxCodePoints]. Null when it would
/// pass. The console checks first so the error sits on the field; the server
/// stays the authority.
String? refusalInputError({required String? code, required String note}) {
  if (code == null || !kSalonRefusalCodes.contains(code)) {
    return 'invalid_input';
  }
  final trimmed = note.trim();
  if (code == 'other' && trimmed.isEmpty) return 'note_required';
  if (refusalNoteLength(trimmed) > kRefusalNoteMaxCodePoints) {
    return 'note_too_long';
  }
  return null;
}

/// The refusal a `refused` validation carries.
class SalonRefusal extends Equatable {
  const SalonRefusal({required this.code, required this.isFinal, this.note});

  /// One of [kSalonRefusalCodes] (an unknown one is kept as sent).
  final String code;

  /// The admin's note — sent to the owner and the admin only.
  final String? note;

  /// `outside_ci` and `test_salon`: the salon cannot ask again.
  final bool isFinal;

  /// Tolerant, as [SalonValidation.fromJson]: a field of the wrong type is
  /// left out, never a throw — one cell lost, not the whole read (a salon's
  /// « Mes salons » list carries one validation per row).
  factory SalonRefusal.fromJson(Map<String, dynamic> json) => SalonRefusal(
    code: _string(json['code']) ?? '',
    note: _string(json['note']),
    isFinal: json['final'] == true,
  );

  /// The wire shape (`salon_validation_dto.dart`): `note` only when there is
  /// one.
  Map<String, dynamic> toJson() => {
    'code': code,
    'note': ?note,
    'final': isFinal,
  };

  @override
  List<Object?> get props => [code, note, isFinal];
}

class SalonValidation extends Equatable {
  const SalonValidation({
    required this.state,
    required this.wentLive,
    this.submittedAt,
    this.decidedAt,
    this.offerLive,
    this.refusal,
    this.decidedBy,
  });

  final SalonValidationState state;

  /// The last request. Absent on a salon the 0044 backfill validated.
  final DateTime? submittedAt;

  final DateTime? decidedAt;

  /// The validation took the salon live at least once (§3.5).
  final bool wentLive;

  /// Sent only for an `approved` salon that is not `active`, and only to its
  /// owner (never on the admin reads).
  final bool? offerLive;

  /// Present only while [state] is `refused`.
  final SalonRefusal? refusal;

  /// The admin who decided — the admin detail only, never a salon.
  final String? decidedBy;

  /// Approved, never live: a validation interrupted before it took the salon
  /// public — « Validation à terminer » in the console (§3.2, §4.4).
  bool get isFinishing => state == SalonValidationState.approved && !wentLive;

  /// Tolerant: a field of the wrong type is left out, never a throw (see
  /// [_instant]).
  factory SalonValidation.fromJson(Map<String, dynamic> json) {
    final refusal = json['refusal'];
    final offerLive = json['offerLive'];
    return SalonValidation(
      state: SalonValidationState.fromWire(json['state']),
      submittedAt: _instant(json['submittedAt']),
      decidedAt: _instant(json['decidedAt']),
      wentLive: json['wentLive'] == true,
      offerLive: offerLive is bool ? offerLive : null,
      refusal: refusal is Map
          ? SalonRefusal.fromJson(refusal.cast<String, dynamic>())
          : null,
      decidedBy: _string(json['decidedBy']),
    );
  }

  /// The wire shape (`salon_validation_dto.dart`): every optional key only
  /// when it has a value. An [SalonValidationState.unknown] state writes
  /// `unknown`, which reads back as itself.
  Map<String, dynamic> toJson() => {
    'state': state.wire,
    'submittedAt': ?submittedAt?.toIso8601String(),
    'decidedAt': ?decidedAt?.toIso8601String(),
    'wentLive': wentLive,
    'offerLive': ?offerLive,
    'refusal': ?refusal?.toJson(),
    'decidedBy': ?decidedBy,
  };

  @override
  List<Object?> get props => [
    state,
    submittedAt,
    decidedAt,
    wentLive,
    offerLive,
    refusal,
    decidedBy,
  ];
}

/// A read's `validation` key, kept apart from its value (B0.18, decision 136
/// item 10 — docs/design/web-salon-validation.md §1).
///
/// The salon side's reads (`GET /me/provider`, each « Mes salons » entry of
/// `GET /me/salons`) carry the key on a B0.18 server, `null` while the salon
/// never asked; a server from before B0.18 (a rollback) sends no key at all,
/// and the app then keeps today's screens. So « absent » and « null » are two
/// different answers, and only the KEY's presence opens the new states.
///
/// - absent → `sent: false` (a server before B0.18);
/// - `null` → `sent: true`, no validation (never asked);
/// - an object → `sent: true`, the validation;
/// - anything else → `sent: true`, no validation: a value this build cannot
///   read never claims a state, and lands where the website's derivation
///   lands it (`goLiveState`'s default: never asked).
({bool sent, SalonValidation? validation}) readSalonValidationKey(
  Map<String, dynamic> json, {
  String key = 'validation',
}) {
  if (!json.containsKey(key)) return (sent: false, validation: null);
  final raw = json[key];
  return (
    sent: true,
    validation: raw is Map
        ? SalonValidation.fromJson(raw.cast<String, dynamic>())
        : null,
  );
}

/// An ISO-8601 instant off the wire, or null — never a throw: a malformed
/// date costs one cell, not the whole answer.
DateTime? _instant(Object? raw) =>
    raw is String ? DateTime.tryParse(raw) : null;

/// A string off the wire, or null when it is anything else — never a throw.
String? _string(Object? raw) => raw is String ? raw : null;
