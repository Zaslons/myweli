import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/salon_categories.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/core/utils/category_colors.dart';
import 'package:myweli/widgets/common/salon_map_marker.dart';

/// docs/design/consumer-search.md §2.4 (decision 229): one category list for
/// the chips, the Pro editor and the map, held to the server's and the
/// website's own lists so the three cannot drift apart again.
void main() {
  test('the five categories, in the website order', () {
    expect(
      [for (final c in discoveryCategories) c.key],
      ['salon', 'barber', 'nails', 'spa', 'massage'],
    );
    expect(
      [for (final c in discoveryCategories) c.chipLabel],
      ['Coiffure', 'Barbier', 'Onglerie', 'Spa', 'Massage'],
    );
  });

  test('the server accepts exactly these keys', () {
    // The PATCH validation of a salon's category (pro-salon-lifecycle L1/L2).
    final source = File(
      '../backend/lib/src/provider_catalog_service.dart',
    ).readAsStringSync();
    final set = RegExp(
      r'const categories = \{([^}]*)\}',
    ).firstMatch(source)?.group(1);
    expect(set, isNotNull, reason: 'the server list moved: find it again');
    final keys = RegExp(
      r"'([a-z]+)'",
    ).allMatches(set!).map((m) => m.group(1)).toSet();
    expect(keys, {for (final c in discoveryCategories) c.key});
  });

  test('the chips say what the website says, for the same key', () {
    final source = File('../web/lib/landing.ts').readAsStringSync();
    final pairs = {
      for (final m in RegExp(
        r"apiKey: '([a-z]+)', label: '([^']+)'",
      ).allMatches(source))
        m.group(1)!: m.group(2)!,
    };
    expect(pairs, hasLength(5), reason: 'the website list moved');
    expect(pairs, {for (final c in discoveryCategories) c.key: c.chipLabel});
  });

  test('the long labels are the ones the salon page and the editor show', () {
    expect(salonCategories, const [
      ('salon', 'Salon de coiffure'),
      ('barber', 'Barbier'),
      ('nails', 'Onglerie'),
      ('spa', 'Spa'),
      ('massage', 'Massage & bien-être'),
    ]);
    expect(salonCategoryLabel('massage'), 'Massage & bien-être');
    expect(salonCategoryLabel('coiffure'), isNull);
  });

  test('an unknown key is no category — the website\'s old « nail »', () {
    expect(discoveryCategory('nail'), isNull);
    expect(discoveryCategory(null), isNull);
    expect(discoveryCategory(''), isNull);
    expect(discoveryCategory('nails')?.chipLabel, 'Onglerie');
  });

  test('the map marker is unchanged: the website draws the same pin', () {
    // `web/components/map/salon-pin.tsx` and `web/lib/discovery/map.ts`
    // know salon, barber and spa; everything else is the shop in ink.
    expect(salonCategoryIcon('salon'), Icons.face_retouching_natural);
    expect(salonCategoryIcon('barber'), Icons.content_cut);
    expect(salonCategoryIcon('spa'), Icons.spa);
    for (final other in ['nails', 'massage', 'unknown', '']) {
      expect(salonCategoryIcon(other), Icons.store_mall_directory);
      expect(categoryColor(other), AppColors.primary);
    }
    expect(categoryColor('salon'), AppColors.categorySalon);
    expect(categoryColor('barber'), AppColors.categoryBarber);
    expect(categoryColor('spa'), AppColors.categorySpa);
  });
}
