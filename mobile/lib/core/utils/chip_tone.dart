/// The tones of a status chip (`AppChip.status`, SYSTEM.md §11.3) — here,
/// beside `status_colors.dart`, so a status's tone is said where its colour
/// is without the core importing a widget. Not in `core/theme/`: that folder
/// holds the token sources the web's mirror gate parses, and a tone is a
/// name, not a value (`web/tests/tokens.mirror.test.ts`).
library;

/// What a status chip says by its colour — always with its words too.
enum AppChipTone {
  /// Confirmed, verified, a client arrived (B7: confirmed is the ok kind).
  success,

  /// Waiting.
  warning,

  /// Cancelled, a no-show, unavailable.
  error,

  /// Made by the salon; the journal's « confirmé » (its own language).
  info,

  /// Done, new, a plain role.
  neutral,

  /// A role above the others (Manager), an open slot: the tint and a
  /// brand-black line, since black's tint alone is neutral's grey.
  strong,

  /// The owner. Gold is a state, never a text: its label is ink (B7.1).
  gold,
}
