import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/admin_console.dart';
import '../support/admin_salon_validation_fixtures.dart';
import '../support/golden.dart';

/// « Salons à valider » as the admin sees it (B0.18 —
/// docs/design/salon-go-live-approval.md §4.2, §4.3, §8.2): the queue and a
/// request, on a desktop window, in the console's frame.
///
/// **The baselines are authored on Linux** (`goldens.yml`, never on a Mac —
/// see test/support/golden.dart). Until they are committed, CI's ubuntu run
/// fails these two with « Could not be compared against non-existent file »:
/// `test/golden/goldens/admin_validation_queue.png` and
/// `admin_validation_detail.png`.
///
/// **The photos are the error placeholder, on purpose.** `flutter test`
/// answers every HTTP request 400, so each `Image.network` lands on its
/// `errorBuilder` — the same tokenised square on every run, where a real
/// photo would make the picture depend on the network.
void main() {
  group('goldens', () {
    setUpAll(loadRealFonts);

    const window = Size(1440, 960);

    testWidgets('the queue — « En attente », two requests', (t) async {
      final server = FakeAdminServer()
        ..count = jsonResponse(queuePage(total: 2))
        ..queue['pending'] = jsonResponse(
          queuePage(
            total: 2,
            items: [
              queueItem(),
              {
                ...queueItem(id: 'provider_2', name: 'Chez Fatou'),
                'commune': 'Médina',
                'city': 'Dakar',
                'countryCode': 'SN',
                'ownerContact': '+221771234567',
                'kycDocCount': 3,
              },
            ],
          ),
        );
      await pumpConsole(
        t,
        server,
        location: '/admin/salon-validations',
        size: window,
      );
      await expectGolden(t, 'admin_validation_queue');
    });

    testWidgets('a request — two columns, the sticky bar', (t) async {
      await pumpConsole(
        t,
        FakeAdminServer()
          ..detail['provider_1'] = jsonResponse(
            detailJson()
              ..['salon'] = {
                ...detailJson()['salon'] as Map<String, dynamic>,
                'category': 'salon',
              },
          ),
        location: '/admin/salon-validations/provider_1',
        size: window,
      );
      await expectGolden(t, 'admin_validation_detail');
    });
  }, skip: kGoldensSkip);
}
