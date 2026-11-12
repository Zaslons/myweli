/// The admin console's side of « a salon goes public only once MyWeli
/// validates it » (B0.18 — docs/design/salon-go-live-approval.md §3.5, §4):
/// the queue, the request's detail, and what the decisions answer. Shaped to
/// the DTOs in docs/api/openapi.yaml (`/admin/salon-validations`,
/// `/admin/salons/{id}/validation`, `…/approve`, `/admin/providers/{id}/restore`).
///
/// **Lenient on purpose.** The salon under review is by definition possibly
/// incomplete — no description, no services, no pin — so nothing here throws
/// on a missing field the app's strict `Provider.fromJson` would refuse.
library;

import 'package:equatable/equatable.dart';

import '../core/utils/salon_id.dart';
import 'salon_subscription.dart';
import 'salon_validation.dart';

/// One row of « Salons à valider » (openapi `SalonValidationQueueItem`).
class SalonValidationQueueItem extends Equatable {
  const SalonValidationQueueItem({
    required this.providerId,
    required this.validation,
    required this.kycDocCount,
    this.name,
    this.commune,
    this.city,
    this.countryCode,
    this.salonStatus,
    this.ownerContact,
  });

  final SalonId providerId;

  /// Null only when the salon row is gone.
  final String? name;
  final String? commune;
  final String? city;

  /// ISO-3166 alpha-2 — decision 123's first evidence.
  final String? countryCode;

  /// `draft` · `active` · `suspended`, or null when the salon row is gone.
  final String? salonStatus;

  final SalonValidation validation;

  /// The owner's e-mail, or their phone when there is none; null without an
  /// active owner.
  final String? ownerContact;

  /// KYC documents sent — 0 reads « aucun ».
  final int kycDocCount;

  /// The time a tab shows: when the salon asked on « En attente », when MyWeli
  /// decided on « Refusés » and « Validés ». Null on a backfilled row (no
  /// request) or a decision not yet taken.
  DateTime? dateFor(SalonValidationState tab) =>
      tab == SalonValidationState.pending
      ? validation.submittedAt
      : validation.decidedAt;

  factory SalonValidationQueueItem.fromJson(Map<String, dynamic> json) =>
      SalonValidationQueueItem(
        providerId: SalonId(json['providerId'] as String),
        name: json['name'] as String?,
        commune: json['commune'] as String?,
        city: json['city'] as String?,
        countryCode: json['countryCode'] as String?,
        salonStatus: json['salonStatus'] as String?,
        validation: SalonValidation.fromJson(_map(json['validation'])),
        ownerContact: json['ownerContact'] as String?,
        kycDocCount: (json['kycDocCount'] as num?)?.toInt() ?? 0,
      );

  /// The same row with the validation a decision returned.
  SalonValidationQueueItem withValidation(SalonValidation v) =>
      SalonValidationQueueItem(
        providerId: providerId,
        name: name,
        commune: commune,
        city: city,
        countryCode: countryCode,
        salonStatus: salonStatus,
        validation: v,
        ownerContact: ownerContact,
        kycDocCount: kycDocCount,
      );

  @override
  List<Object?> get props => [
    providerId,
    name,
    commune,
    city,
    countryCode,
    salonStatus,
    validation,
    ownerContact,
    kycDocCount,
  ];
}

/// One page of a tab: `{ items, page, pageSize, total }`.
class SalonValidationPage extends Equatable {
  const SalonValidationPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<SalonValidationQueueItem> items;
  final int page;
  final int pageSize;
  final int total;

  factory SalonValidationPage.fromJson(Map<String, dynamic> json) {
    final items = [
      for (final e in (json['items'] as List?) ?? const [])
        SalonValidationQueueItem.fromJson(_map(e)),
    ];
    return SalonValidationPage(
      items: List.unmodifiable(items),
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? items.length,
      total: (json['total'] as num?)?.toInt() ?? items.length,
    );
  }

  @override
  List<Object?> get props => [items, page, pageSize, total];
}

/// A service as the salon priced it (the stored `services[]` entry).
class ValidationSalonService extends Equatable {
  const ValidationSalonService({
    required this.name,
    required this.active,
    this.price,
    this.priceMax,
    this.durationMinutes,
  });

  final String name;

  /// The « from » price in the salon's currency; null when never set.
  final num? price;
  final num? priceMax;
  final int? durationMinutes;

  /// False: hidden from booking — and not counted by the go-live gate.
  final bool active;

  factory ValidationSalonService.fromJson(Map<String, dynamic> json) =>
      ValidationSalonService(
        name: (json['name'] as String?) ?? '',
        price: json['price'] as num?,
        priceMax: json['priceMax'] as num?,
        durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
        active: json['active'] != false,
      );

  @override
  List<Object?> get props => [name, price, priceMax, durationMinutes, active];
}

/// One working window of a weekday (`availability.weeklySchedule["0".."6"]`).
/// Only the time of day is significant; the date is a placeholder.
class ValidationOpeningWindow extends Equatable {
  const ValidationOpeningWindow({
    required this.isAvailable,
    this.start,
    this.end,
  });

  final DateTime? start;
  final DateTime? end;
  final bool isAvailable;

  factory ValidationOpeningWindow.fromJson(Map<String, dynamic> json) =>
      ValidationOpeningWindow(
        start: _instant(json['startTime']),
        end: _instant(json['endTime']),
        isAvailable: json['isAvailable'] != false,
      );

  @override
  List<Object?> get props => [start, end, isAvailable];
}

/// The salon under review, as the admin provider detail reads it (the full
/// stored document, any status) — the fields the decision is taken on.
class ValidationSalon extends Equatable {
  const ValidationSalon({
    required this.id,
    required this.imageUrls,
    required this.services,
    required this.weeklyHours,
    this.name,
    this.category,
    this.description,
    this.logoUrl,
    this.address,
    this.commune,
    this.city,
    this.areaId,
    this.countryCode,
    this.timezone,
    this.currency,
    this.latitude,
    this.longitude,
    this.phoneNumber,
    this.whatsapp,
    this.status,
  });

  final SalonId id;
  final String? name;

  /// The salon's type (`category`).
  final String? category;
  final String? description;

  /// The photos, in the salon's order (the gate needs three).
  final List<String> imageUrls;
  final String? logoUrl;
  final List<ValidationSalonService> services;

  /// Weekday (0 = Monday … 6 = Sunday) → its working windows; a day absent or
  /// empty is closed.
  final Map<int, List<ValidationOpeningWindow>> weeklyHours;

  final String? address;
  final String? commune;
  final String? city;
  final String? areaId;
  final String? countryCode;

  /// IANA — the salon's own time, for every time shown about it.
  final String? timezone;
  final String? currency;

  /// The pin — decision 123's evidence, with the phone's prefix.
  final double? latitude;
  final double? longitude;

  /// As stored; the prefix tells Dakar from Abidjan (decision 123).
  final String? phoneNumber;
  final String? whatsapp;

  /// `draft` · `active` · `suspended`.
  final String? status;

  bool get isSuspended => status == 'suspended';
  bool get hasPin => latitude != null && longitude != null;

  factory ValidationSalon.fromJson(Map<String, dynamic> json) {
    final schedule = _map(_map(json['availability'])['weeklySchedule']);
    return ValidationSalon(
      id: SalonId((json['id'] as String?) ?? ''),
      name: json['name'] as String?,
      category: json['category'] as String?,
      description: json['description'] as String?,
      imageUrls: List.unmodifiable([
        for (final u in (json['imageUrls'] as List?) ?? const [])
          if (u is String && u.isNotEmpty) u,
      ]),
      logoUrl: json['logoUrl'] as String?,
      services: List.unmodifiable([
        for (final s in (json['services'] as List?) ?? const [])
          if (s is Map) ValidationSalonService.fromJson(_map(s)),
      ]),
      weeklyHours: Map.unmodifiable({
        for (final e in schedule.entries)
          if (int.tryParse(e.key) case final day?
              when day >= 0 && day <= 6 && e.value is List)
            day: List<ValidationOpeningWindow>.unmodifiable([
              for (final w in e.value as List)
                if (w is Map) ValidationOpeningWindow.fromJson(_map(w)),
            ]),
      }),
      address: json['address'] as String?,
      commune: json['commune'] as String?,
      city: json['city'] as String?,
      areaId: json['areaId'] as String?,
      countryCode: json['countryCode'] as String?,
      timezone: json['timezone'] as String?,
      currency: json['currency'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      phoneNumber: json['phoneNumber'] as String?,
      whatsapp: json['whatsapp'] as String?,
      status: json['status'] as String?,
    );
  }

  /// The same salon in another status — what a validation answers
  /// (`salonStatus`).
  ValidationSalon withStatus(String? next) => ValidationSalon(
    id: id,
    name: name,
    category: category,
    description: description,
    imageUrls: imageUrls,
    logoUrl: logoUrl,
    services: services,
    weeklyHours: weeklyHours,
    address: address,
    commune: commune,
    city: city,
    areaId: areaId,
    countryCode: countryCode,
    timezone: timezone,
    currency: currency,
    latitude: latitude,
    longitude: longitude,
    phoneNumber: phoneNumber,
    whatsapp: whatsapp,
    status: next,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    category,
    description,
    imageUrls,
    logoUrl,
    services,
    weeklyHours,
    address,
    commune,
    city,
    areaId,
    countryCode,
    timezone,
    currency,
    latitude,
    longitude,
    phoneNumber,
    whatsapp,
    status,
  ];
}

/// Another salon the same owner holds.
class ValidationOwnedSalon extends Equatable {
  const ValidationOwnedSalon({
    required this.id,
    required this.name,
    required this.status,
  });

  final SalonId id;
  final String name;

  /// `draft` · `active` · `suspended`.
  final String status;

  factory ValidationOwnedSalon.fromJson(Map<String, dynamic> json) =>
      ValidationOwnedSalon(
        id: SalonId((json['id'] as String?) ?? ''),
        name: (json['name'] as String?) ?? '',
        status: (json['status'] as String?) ?? '',
      );

  @override
  List<Object?> get props => [id, name, status];
}

/// The salon's owner, as the request's detail shows them.
class ValidationOwner extends Equatable {
  const ValidationOwner({
    required this.accountId,
    required this.kycDocCount,
    required this.otherSalons,
    this.name,
    this.businessName,
    this.email,
    this.phone,
    this.contact,
    this.createdAt,
    this.accountAgeDays,
    this.kycStatus,
  });

  /// The account — the target of the « KYC » link (`/admin/kyc/:id`).
  final String accountId;
  final String? name;
  final String? businessName;
  final String? email;
  final String? phone;

  /// The e-mail, or the phone when there is none.
  final String? contact;
  final DateTime? createdAt;
  final int? accountAgeDays;

  /// Almost every account reads `pending` without having sent anything —
  /// read [kycDocCount] first (§4.3).
  final String? kycStatus;
  final int kycDocCount;
  final List<ValidationOwnedSalon> otherSalons;

  factory ValidationOwner.fromJson(Map<String, dynamic> json) =>
      ValidationOwner(
        accountId: (json['accountId'] as String?) ?? '',
        name: json['name'] as String?,
        businessName: json['businessName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        contact: json['contact'] as String?,
        createdAt: _instant(json['createdAt']),
        accountAgeDays: (json['accountAgeDays'] as num?)?.toInt(),
        kycStatus: json['kycStatus'] as String?,
        kycDocCount: (json['kycDocCount'] as num?)?.toInt() ?? 0,
        otherSalons: List.unmodifiable([
          for (final s in (json['otherSalons'] as List?) ?? const [])
            if (s is Map) ValidationOwnedSalon.fromJson(_map(s)),
        ]),
      );

  @override
  List<Object?> get props => [
    accountId,
    name,
    businessName,
    email,
    phone,
    contact,
    createdAt,
    accountAgeDays,
    kycStatus,
    kycDocCount,
    otherSalons,
  ];
}

/// The kinds of the request's history (`salon_validation_events.kind`).
enum ValidationEventKind {
  submitted,
  approved,
  refused,

  /// A kind this build does not know.
  unknown;

  static ValidationEventKind fromWire(Object? raw) => switch (raw) {
    'submitted' => submitted,
    'approved' => approved,
    'refused' => refused,
    _ => unknown,
  };
}

/// One line of the request's history, oldest first.
class ValidationEvent extends Equatable {
  const ValidationEvent({
    required this.kind,
    this.at,
    this.by,
    this.refusalCode,
    this.refusalNote,
  });

  final ValidationEventKind kind;
  final DateTime? at;

  /// The admin, for a decision.
  final String? by;
  final String? refusalCode;

  /// Cleared on the owner's account erasure.
  final String? refusalNote;

  factory ValidationEvent.fromJson(Map<String, dynamic> json) =>
      ValidationEvent(
        kind: ValidationEventKind.fromWire(json['kind']),
        at: _instant(json['at']),
        by: json['by'] as String?,
        refusalCode: json['refusalCode'] as String?,
        refusalNote: json['refusalNote'] as String?,
      );

  @override
  List<Object?> get props => [kind, at, by, refusalCode, refusalNote];
}

/// `GET /admin/salons/{id}/validation`: what the decision is taken on.
class SalonValidationDetail extends Equatable {
  const SalonValidationDetail({
    required this.salon,
    required this.events,
    this.offer,
    this.owner,
    this.validation,
  });

  final ValidationSalon salon;

  /// Null in the setup state (no offer row yet — its trial starts at the
  /// validation, §3.6).
  final SalonSubscription? offer;

  /// Null when the salon has no active owner.
  final ValidationOwner? owner;

  /// Null when the salon never asked to go live.
  final SalonValidation? validation;
  final List<ValidationEvent> events;

  /// The `from` a validation sends — the state this detail read (§3.2), or
  /// null when there is nothing to validate: never asked, an unknown state,
  /// or a salon already taken live (approve would answer 409).
  SalonValidationState? get approveFrom {
    final v = validation;
    if (v == null) return null;
    return switch (v.state) {
      SalonValidationState.pending || SalonValidationState.refused => v.state,
      SalonValidationState.approved => v.wentLive ? null : v.state,
      SalonValidationState.unknown => null,
    };
  }

  /// « Valider la mise en ligne » (or « Validation à terminer ») is enabled:
  /// there is something to validate and the salon is not suspended — the
  /// server refuses a suspended one (409 `provider_suspended`).
  bool get canApprove => approveFrom != null && !salon.isSuspended;

  /// « Refuser » applies to a pending request only — the server's
  /// compare-and-set is from `pending` (§3.3).
  bool get canRefuse => validation?.state == SalonValidationState.pending;

  /// A validation interrupted before it took the salon live (§3.2).
  bool get isFinishing => validation?.isFinishing ?? false;

  factory SalonValidationDetail.fromJson(Map<String, dynamic> json) {
    final offer = json['offer'];
    final owner = json['owner'];
    final validation = json['validation'];
    return SalonValidationDetail(
      salon: ValidationSalon.fromJson(_map(json['salon'])),
      offer: offer is Map
          ? SalonSubscription.fromJson(offer.cast<String, dynamic>())
          : null,
      owner: owner is Map
          ? ValidationOwner.fromJson(owner.cast<String, dynamic>())
          : null,
      validation: validation is Map
          ? SalonValidation.fromJson(validation.cast<String, dynamic>())
          : null,
      events: List.unmodifiable([
        for (final e in (json['events'] as List?) ?? const [])
          if (e is Map) ValidationEvent.fromJson(_map(e)),
      ]),
    );
  }

  /// The detail after a decision answered — its validation and, for a
  /// validation, the salon's new status. The history is re-read on the next
  /// load.
  SalonValidationDetail decided(SalonValidation? next, {String? salonStatus}) =>
      SalonValidationDetail(
        salon: salonStatus == null ? salon : salon.withStatus(salonStatus),
        offer: offer,
        owner: owner,
        validation: next ?? validation,
        events: events,
      );

  @override
  List<Object?> get props => [salon, offer, owner, validation, events];
}

/// What a validation answers (200): the salon is `active`.
///
/// **Read, never assumed:** a 2xx without its `salonStatus` (an empty body,
/// `[]`, `{}`) throws, which the service answers `bad_response` — never a
/// « Salon validé : il est en ligne. » on a salon whose state is unknown.
class SalonApproval extends Equatable {
  const SalonApproval({required this.salonStatus, this.validation});

  final String salonStatus;
  final SalonValidation? validation;

  factory SalonApproval.fromJson(Map<String, dynamic> json) {
    final status = json['salonStatus'];
    if (status is! String) {
      throw const FormatException('a validation answers its salonStatus');
    }
    final v = json['validation'];
    return SalonApproval(
      salonStatus: status,
      validation: v is Map
          ? SalonValidation.fromJson(v.cast<String, dynamic>())
          : null,
    );
  }

  @override
  List<Object?> get props => [salonStatus, validation];
}

/// What « Lever la suspension » answers — from two servers (§9.2: the console
/// goes live before the backend).
///
/// - **B0.18 and later:** `{ status: active | draft, reason }` — `reason` null
///   for `active`, else why the salon stays offline (`not_validated`,
///   `no_owner`, `offer_not_live`, `unpaid`, `unknown_prior`).
/// - **Before B0.18:** the whole salon document, written `active`
///   unconditionally, with **no `reason` key** — [legacy].
///
/// The `reason` KEY is the discriminator: the new server always sends it, as
/// `null` when live; the salon document never has one.
///
/// **Read, never assumed:** a 2xx that is neither — no `status` string, or a
/// B0.18 status other than `active`/`draft` — throws, which the service
/// answers `bad_response`. An empty body used to read as the older server's
/// salon and show « Salon remis en ligne » for a state nobody knew.
class RestoreOutcome extends Equatable {
  const RestoreOutcome({
    required this.status,
    this.reason,
    this.legacy = false,
  });

  /// `active` or `draft`.
  final String status;
  final String? reason;

  /// The older server's answer — always live.
  final bool legacy;

  bool get isLive => status == 'active';

  factory RestoreOutcome.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    if (!json.containsKey('reason')) {
      // The older server's salon carries its status, always.
      if (status is! String) {
        throw const FormatException('a lifted salon carries its status');
      }
      return RestoreOutcome(status: status, legacy: true);
    }
    if (status != 'active' && status != 'draft') {
      throw const FormatException('a lift answers active or draft');
    }
    return RestoreOutcome(
      status: status as String,
      reason: json['reason'] as String?,
    );
  }

  @override
  List<Object?> get props => [status, reason, legacy];
}

Map<String, dynamic> _map(Object? raw) =>
    raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};

DateTime? _instant(Object? raw) =>
    raw is String ? DateTime.tryParse(raw) : null;
