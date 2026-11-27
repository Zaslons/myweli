import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `Text` that DRAWS [address], whether or not it carries the break marks
/// `Formatters.breakableEmail` puts before its « @ » and the « . » of its name
/// part (U+200B, SYSTEM.md §13.3). `find.text(address)` misses a marked
/// drawing; this finds both, so a test can tap a row by the address it shows.
Finder drawnEmail(String address) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll('\u200B', '') == address,
  description: 'the Text drawing « $address »',
);
