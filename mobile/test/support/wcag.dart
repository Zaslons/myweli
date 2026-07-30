import 'dart:math' as math;
import 'dart:ui';

/// WCAG 2.1 contrast math (docs/design/SYSTEM.md §2).
///
/// The design system's floors are 4.5:1 for normal text, 3:1 for large text and
/// for every non-text thing that carries meaning (icons, the boundary of a
/// control, focus rings — WCAG 1.4.11). Written once here so the goldens and
/// the contrast test agree on what "passes" means.

/// WCAG 2.1 relative luminance.
double relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// The contrast ratio between two OPAQUE colors, 1.0 → 21.0.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The WCAG AA floors.
const double kFloorText = 4.5; // normal text (1.4.3)
const double kFloorLargeText = 3.0; // ≥18.66px bold / ≥24px (1.4.3)
const double kFloorNonText = 3.0; // icons, control borders, focus (1.4.11)

/// `4.76` — for rendering into a golden / a failure message.
String ratioLabel(double ratio) => ratio.toStringAsFixed(2);
