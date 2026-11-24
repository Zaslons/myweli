import '../../services/interfaces/push_notification_service_interface.dart';

/// How many times the client app offers the push sheet in all, and how far
/// apart (consumer-signin-push.md §2.10, decision 210).
const int kPushOfferMax = 3;
const Duration kPushOfferGap = Duration(days: 7);

/// What the app does after a booking, about push.
enum PushOfferAction {
  /// Permission is granted: register this phone's token, silently.
  register,

  /// Never asked, and within the limits: offer the sheet.
  offer,

  /// Nothing now — refused (Préférences shows the way), or the limits are
  /// reached (Préférences keeps « Activer les notifications »).
  none,
}

/// The rule, as one pure function of what the system says, how many times
/// the sheet was offered, when last, and now (decision 210):
///
/// - granted → register;
/// - denied → nothing;
/// - not determined → offer, while fewer than [kPushOfferMax] offers were
///   made and the last was at least [kPushOfferGap] ago (or has no date).
///
/// **Every offer counts, whatever its answer** — « Activer », « Plus tard »
/// or the sheet dismissed. Counting only « Plus tard » would let a failed
/// « Activer » (the system still « not determined ») bring the sheet back
/// after every booking, without limit.
PushOfferAction pushOfferDecision({
  required PushPermissionStatus status,
  required int offerCount,
  required DateTime? lastOfferAt,
  required DateTime now,
}) {
  switch (status) {
    case PushPermissionStatus.granted:
      return PushOfferAction.register;
    case PushPermissionStatus.denied:
      return PushOfferAction.none;
    case PushPermissionStatus.notDetermined:
      if (offerCount >= kPushOfferMax) return PushOfferAction.none;
      if (lastOfferAt != null && now.difference(lastOfferAt) < kPushOfferGap) {
        return PushOfferAction.none;
      }
      return PushOfferAction.offer;
  }
}
