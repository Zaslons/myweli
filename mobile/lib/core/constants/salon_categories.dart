/// The listing categories a salon can choose (the canonical taxonomy —
/// mirrors the server's PATCH validation, pro-salon-lifecycle L1/L2). One
/// list for the editor (« Profil du salon ») and every place that shows a
/// salon's category (docs/design/r6-salon-fact-reads.md §5).
const salonCategories = [
  ('salon', 'Salon de coiffure'),
  ('barber', 'Barbier'),
  ('spa', 'Spa'),
  ('nails', 'Onglerie'),
  ('massage', 'Massage & bien-être'),
];

/// The French label of a salon's [category] key — null for a key outside the
/// taxonomy (a legacy seed), which a caller hides rather than print a key.
String? salonCategoryLabel(String category) {
  for (final (key, label) in salonCategories) {
    if (key == category) return label;
  }
  return null;
}
