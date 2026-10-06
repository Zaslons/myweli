import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/salon_subscription.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';

/// The mock publish mirrors the server's offer rule
/// (docs/design/pro-companion-path.md §3.1, §5) — the EXPIRED half, which
/// needs its own isolate: `serviceLocator.subscriptionService` is late-final,
/// and here it is seeded with an offer that already ran out. (The no-row half,
/// where publishing starts the trial, lives in `multi_salon_test.dart`.)
void main() {
  final expiredAt = DateTime.now().subtract(const Duration(days: 30));
  final subs = MockSubscriptionService(
    initial: SalonSubscription(
      tier: SalonTier.pro,
      status: SalonOfferStatus.expired,
      trialEndsAt: expiredAt,
      graceEndsAt: expiredAt.add(const Duration(days: 7)),
      unpublishedForBilling: true,
      seats: const SalonSeats(cap: 5, used: 1),
    ),
  );

  setUpAll(() => serviceLocator.subscriptionService = subs);

  test('an EXPIRED offer refuses the publish with the neutral sentence — and '
      'never grants a second trial', () async {
    final res = await MockProService().publishSalon('provider1');

    expect(res.success, isFalse);
    expect(res.code, 'offer_required');
    expect(
      res.error,
      'La mise en ligne est indisponible : l’offre de votre salon n’est '
      'plus active.',
    );
    final state = await subs.getSalonSubscription('provider1');
    expect(state.data!.status, SalonOfferStatus.expired);
    expect(state.data!.trialEndsAt, expiredAt);
  });
}
