import '../core/utils/salon_id.dart';
import 'pro_membership.dart';
import 'provider_user.dart';
import 'salon_facts.dart';
import 'salon_market.dart';

/// The salon a provider session ACTS IN (team access R6) — the one rule:
/// the switched-to salon ([selected]), else the account's own salon
/// ([linked], an owner's default), else its membership's salon
/// ([membership], a member account with no salon of its own). An empty id
/// names no salon. ProAuthProvider.activeSalonId and the services that read
/// the salon from the persisted session ([ProviderSession.actingSalonId])
/// both resolve through it, so a screen and the request it sends cannot
/// pick different salons. Design: docs/design/services-acting-salon.md.
SalonId? resolveActingSalonId({
  required SalonId? selected,
  required SalonId? linked,
  required SalonId? membership,
}) {
  for (final id in [selected, linked, membership]) {
    if (id != null && id.isNotEmpty) return id;
  }
  return null;
}

/// A persisted **provider** auth session: the access token (role `provider`),
/// the rotating [refreshToken] used to silently renew it, and the account it
/// belongs to. Kept separate from the consumer [Session] (different
/// secure-storage key) so a phone used as both consumer and provider on one
/// device doesn't overwrite the other. No client-side expiry — renewal is
/// 401-driven via `/auth/provider/refresh`.
///
/// [membership] (team access R4b) caches the last-fetched role/capabilities
/// so the app shapes correctly on the FIRST cold-start frame; it is refreshed
/// from `GET /me/provider` on every start (never trusted long-term — the
/// server resolves per request, T38).
class ProviderSession {
  final String token;
  final String? refreshToken;
  final ProviderUser provider;
  final ProMembership? membership;

  /// R6 multi-salons: the salon the user last SWITCHED to (null = the
  /// default). Restored at cold start and revalidated by the first
  /// `GET /me/provider?salonId=` — a 403 silently falls back to default.
  final SalonId? selectedSalonId;

  /// The acting salon's market facts from the last GET /me/provider — its
  /// clock and currency when a cold start's refresh fails
  /// (docs/design/pro-app-salon-not-loaded.md §3.1). Like [membership],
  /// shaping only; they count for [SalonMarket.salonId] alone.
  final SalonMarket? salonMarket;

  /// What « Profil » shows of the acting salon, from the last GET
  /// /me/provider — its card when a cold start is offline (B8.3). Like
  /// [salonMarket], they count for [SalonFacts.salonId] alone.
  final SalonFacts? salonFacts;

  const ProviderSession({
    required this.token,
    required this.provider,
    this.refreshToken,
    this.membership,
    this.selectedSalonId,
    this.salonMarket,
    this.salonFacts,
  });

  /// The salon this session acts in — [resolveActingSalonId] over the
  /// persisted selection, the account's own salon and the cached membership.
  /// Null = no salon anywhere (signed in, not linked).
  SalonId? get actingSalonId => resolveActingSalonId(
    selected: selectedSalonId,
    linked: provider.providerId,
    membership: membership?.salonId,
  );

  ProviderSession copyWith({
    ProMembership? membership,
    bool clearMembership = false,
    SalonId? selectedSalonId,
    bool clearSelectedSalon = false,
    SalonMarket? salonMarket,
    bool clearSalonMarket = false,
    SalonFacts? salonFacts,
    bool clearSalonFacts = false,
  }) => ProviderSession(
    token: token,
    refreshToken: refreshToken,
    provider: provider,
    membership: clearMembership ? null : (membership ?? this.membership),
    selectedSalonId: clearSelectedSalon
        ? null
        : (selectedSalonId ?? this.selectedSalonId),
    salonMarket: clearSalonMarket ? null : (salonMarket ?? this.salonMarket),
    salonFacts: clearSalonFacts ? null : (salonFacts ?? this.salonFacts),
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'refreshToken': refreshToken,
    'provider': provider.toJson(),
    if (membership != null) 'membership': membership!.toJson(),
    if (selectedSalonId != null) 'selectedSalonId': selectedSalonId,
    if (salonMarket != null) 'salonMarket': salonMarket!.toJson(),
    if (salonFacts != null) 'salonFacts': salonFacts!.toJson(),
  };

  factory ProviderSession.fromJson(
    Map<String, dynamic> json,
  ) => ProviderSession(
    token: json['token'] as String,
    refreshToken: json['refreshToken'] as String?,
    provider: ProviderUser.fromJson(json['provider'] as Map<String, dynamic>),
    // Legacy sessions (pre-R4b) simply have no cached membership.
    membership: json['membership'] == null
        ? null
        : ProMembership.fromJson(json['membership'] as Map<String, dynamic>),
    // Legacy sessions (pre-R6) simply have no selection.
    selectedSalonId: switch (json['selectedSalonId']) {
      final String id => SalonId(id),
      _ => null,
    },
    // Sessions stored before the facts were kept have none: the salon is
    // unknown until GET /me/provider answers.
    salonMarket: json['salonMarket'] == null
        ? null
        : SalonMarket.fromJson(json['salonMarket'] as Map<String, dynamic>),
    // Sessions stored before B8.3 have none: offline, the card says so.
    salonFacts: json['salonFacts'] == null
        ? null
        : SalonFacts.fromJson(json['salonFacts'] as Map<String, dynamic>),
  );
}
