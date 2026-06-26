import 'package:flutter/material.dart';

/// Myweli Color Palette - Black & White Design System
class AppColors {
  // Primary Colors (Black & White)
  static const Color primary = Color(0xFF000000); // Pure Black
  static const Color primaryLight = Color(0xFF1A1A1A); // Near black for hover
  static const Color primaryDark = Color(0xFF000000); // Pressed state

  static const Color secondary = Color(0xFFFFFFFF); // White
  static const Color secondaryVariant = Color(0xFFF5F5F5); // Off-white

  static const Color accent = Color(0xFF000000); // Black for emphasis

  // Neutral Colors (Grayscale)
  // Slightly off-white background to create contrast with white cards.
  static const Color background = Color(0xFFF6F7F9);
  static const Color surface = Color(0xFFFAFAFA); // Very light gray
  static const Color surfaceVariant = Color(0xFFF5F5F5); // Slightly darker

  // Text Colors
  static const Color textPrimary = Color(0xFF000000); // Pure Black
  static const Color textSecondary = Color(0xFF4A4A4A); // Dark gray
  static const Color textTertiary = Color(0xFF8A8A8A); // Medium gray
  static const Color textDisabled = Color(0xFFC0C0C0); // Light gray

  // Border & Divider
  static const Color divider = Color(0xFFE0E0E0); // Light gray
  static const Color border = Color(0xFFD0D0D0); // Medium-light gray
  static const Color borderFocus = Color(0xFF000000); // Black

  // Semantic Colors (Minimal, Muted)
  static const Color success = Color(0xFF2D5016); // Dark green
  static const Color successLight = Color(0xFF4A7C2A); // Lighter green

  static const Color error = Color(0xFF8B0000); // Dark red
  static const Color errorLight = Color(0xFFDC143C); // Lighter red

  static const Color warning = Color(0xFF6B5B00); // Dark amber
  static const Color warningLight = Color(0xFFFFB800); // Lighter amber

  static const Color info = Color(0xFF1A1A2E); // Dark blue-gray
  static const Color infoLight = Color(0xFF2D3561); // Lighter blue-gray

  // UI accents — purpose-named so screens use a token, not a literal.
  static const Color starRating = Color(0xFFFFB800); // amber rating stars
  static const Color favorite = Color(0xFFE53935); // favorite heart

  // Dark Mode (Future)
  static const Color backgroundDark = Color(0xFF111827);
  static const Color surfaceDark = Color(0xFF1F2937);
  static const Color textPrimaryDark = Color(0xFFF9FAFB);
  static const Color textSecondaryDark = Color(0xFFD1D5DB);
}
