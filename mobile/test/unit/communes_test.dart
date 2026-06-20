import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/communes.dart';

void main() {
  group('abidjanCommunes', () {
    test('includes the launch communes', () {
      final names = abidjanCommunes.map((c) => c.name).toList();
      expect(names, containsAll(['Cocody', 'Marcory', 'Plateau']));
    });
  });

  group('nearestCommune', () {
    test('resolves a point on Cocody to Cocody', () {
      final c = nearestCommune(5.3600, -4.0083);
      expect(c, isNotNull);
      expect(c!.name, 'Cocody');
    });

    test('resolves a point on Marcory to Marcory', () {
      final c = nearestCommune(5.2800, -4.0500);
      expect(c!.name, 'Marcory');
    });
  });
}
