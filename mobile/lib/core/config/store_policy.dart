import 'package:flutter/foundation.dart';

/// What the Pro app may say about paying Myweli — App Store 3.1.1 / 3.1.3(f).
///
/// A salon's offer unlocks functionality (publishing, bookings, team seats),
/// and it is paid outside the app. On iOS that is allowed only for a free
/// companion to a web service with « no purchasing inside the app, or calls to
/// action for purchase outside of the app » (3.1.3(f)). So on iOS the app shows
/// the offer's STATE and never where or how to pay for it: « Réactivez votre
/// offre sur myweli.com » is exactly the call to action the rule names, and the
/// US-storefront exception does not reach the Côte d'Ivoire storefront.
///
/// Android and the web keep the full copy — this is a store rule, not a
/// product decision about the web. Design: docs/design/app-store-forms.md §2.
///
/// A getter, not a const: `flutter test` reports Android, so a const would make
/// the iOS branch unreachable from every test. Tests flip
/// `debugDefaultTargetPlatformOverride` to iOS and reset it in a `finally`.
bool get hidesExternalPurchaseCopy =>
    defaultTargetPlatform == TargetPlatform.iOS;
