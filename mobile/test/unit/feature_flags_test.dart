import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/config/feature_flags.dart';

void main() {
  test('V2/V3 provider features are gated off for the V1 release', () {
    expect(FeatureFlags.futureProviderFeatures, isFalse);
  });
}
