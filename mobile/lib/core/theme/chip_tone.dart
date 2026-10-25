/// The tones of a status chip (`AppChip.status`, SYSTEM.md §11.3) — here,
/// beside the colours, so a status's tone is said where its colour is
/// (`core/utils/status_colors.dart`) without the core importing a widget.
library;

/// What a status chip says by its colour — always with its words too.
enum AppChipTone {
  /// Done, verified.
  success,

  /// Waiting, a no-show.
  warning,

  /// Cancelled, refused, blocked.
  error,

  /// Confirmed, made by the salon.
  info,

  /// New, a plain role.
  neutral,

  /// A role above the others (Manager).
  strong,

  /// The owner. Gold is a state, never a text: its label is ink (B7.1).
  gold,
}
