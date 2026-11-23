import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/config/feature_flags.dart';

import '../support/dart_source.dart';

void main() {
  test('V2/V3 provider features are gated off for the V1 release', () {
    expect(FeatureFlags.futureProviderFeatures, isFalse);
  });

  /// Decision 170 (docs/design/consumer-app-truth.md §2.1): the home stories
  /// stay in the tree, hidden, until someone manages real ones.
  ///
  /// **Red on the defect, green on the repair.** It fails when the row is
  /// turned on while its stories are still the hard-coded demo (a « -15 % »
  /// offer nobody makes, a salon that does not exist). Once managed stories
  /// replace the demo list and its pictures, the flag may flip and this stays
  /// green; it does not pin the flag's value for its own sake.
  ///
  /// **Blind spot:** it knows the demo by its three ids and pictures. Demo
  /// content added under new ids, or moved to another file, passes it.
  test('the home stories stay off while they are the hard-coded demo', () {
    const demoIds = ['promo_weekend', 'new_salon', 'last_minute'];
    final widget = File('lib/widgets/home/announcement_stories.dart');
    final code = widget.existsSync()
        ? stripDartComments(widget.readAsStringSync())
        : '';
    final demo = [
      for (final id in demoIds)
        if (code.contains("'$id'") ||
            File('assets/images/stories/$id.svg').existsSync())
          id,
    ];
    if (demo.isEmpty) return; // the repair: real stories replaced the demo
    expect(
      FeatureFlags.homeStories,
      isFalse,
      reason:
          'the home would show hard-coded demo stories (${demo.join(', ')}): '
          'replace them with managed ones before turning the row on',
    );
  });
}
