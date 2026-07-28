import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// The six-box verification-code row, once (A11 C3).
///
/// ## Why this is shared, when there were only two copies
///
/// §11's rule of thumb is that a *third* inline copy is a review failure, and
/// this row had two — `otp_verify_screen` and `pro_otp_verify_screen`. The count
/// is not what decided it. **The two copies had already diverged, in the
/// direction that hurts**: the geometry was character-for-character identical
/// while the behaviour was not, and everything the pro screen was missing was
/// something the consumer screen had:
///
/// | | consumer | pro, before this |
/// |---|---|---|
/// | SMS autofill (`AutofillGroup` + `oneTimeCode`) | yes | **no** |
/// | paste of a 6-digit code | distributes across the boxes | fills box 0, drops five digits |
/// | backspace from an empty box | steps back and clears | **nothing** |
/// | auto-submit on the sixth digit | yes | **no** |
///
/// So a salon owner typing a code got a measurably worse screen than a client,
/// and nobody chose that — it is what two copies do while nothing measures them.
/// The same argument C1 wrote about `_fixtures.dart`, whose four copies had
/// drifted apart on a string no assertion read. Divergence is the trigger; the
/// copy count is only a proxy for it.
///
/// **Both screens are unrouted today** (`app_router.dart:32-34`,
/// `pro_router.dart:61-63` — dormant, kept for the phone-OTP revival), so this is
/// not urgent. It is the opposite: it is cheap now and expensive later, when
/// there are two live screens and one of them quietly lacks autofill.
///
/// ## What lives here and what does not
///
/// Here: the geometry, the `AutofillGroup`, focus advance, paste distribution,
/// backspace. All of it is identical for any caller, and all of it is fiddly —
/// which is exactly the code that gets pasted rather than shared.
///
/// Not here: the state machines. The screens keep their own controllers and
/// focus nodes (and dispose them), their own lockout/expiry rules, their own
/// error copy and their own destinations. This widget holds no state, and
/// [onChanged] hands the caller the whole code and lets it decide.
class OtpCodeRow extends StatelessWidget {
  const OtpCodeRow({
    super.key,
    required this.controllers,
    required this.focusNodes,
    required this.onChanged,
    this.enabled = true,
    this.hasError = false,
  })  : assert(controllers.length == length, 'OtpCodeRow needs $length boxes'),
        assert(focusNodes.length == length, 'OtpCodeRow needs $length nodes');

  /// The number of digits. Not a parameter: `Validators.otp` and every mock and
  /// backend agree on six, and a row that could be five would need a caller to
  /// say so in two places.
  static const int length = 6;

  /// Owned and disposed by the caller — this widget is stateless on purpose, so
  /// a screen can clear the boxes from its own failure path.
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;

  /// Called after every edit with the WHOLE code, already joined.
  ///
  /// The caller decides what a complete code means: the consumer screen
  /// auto-submits on six digits, both clear their inline error on any keystroke.
  /// Handing over the joined string rather than `(index, value)` is what lets
  /// the paste branch below live here instead of in each screen.
  final ValueChanged<String> onChanged;

  /// False while the code is locked or expired — the boxes grey out and refuse
  /// input until the caller sends a new code.
  final bool enabled;

  /// Paints the borders and the digits in `AppColors.error`.
  final bool hasError;

  String get _code => controllers.map((c) => c.text).join();

  void _onBoxChanged(int index, String value) {
    // Paste / SMS autofill of several digits at once: spread them across the
    // boxes rather than letting box 0 swallow the lot. This is why box 0 carries
    // `maxLength: length` below — the OS delivers the whole code to the field it
    // hinted on, and this is the branch that unpacks it.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i + index < length && i < digits.length; i++) {
        controllers[index + i].text = digits[i];
      }
      focusNodes[(index + digits.length).clamp(0, length - 1)].requestFocus();
    } else if (value.isNotEmpty && index < length - 1) {
      focusNodes[index + 1].requestFocus();
    }
    onChanged(_code);
  }

  /// Backspace on an empty box steps back, clears, and stays there.
  ///
  /// Without this, a user who mistypes digit 4 has to tap digit 3 to fix it —
  /// the keyboard's own backspace does nothing, because the box it is in is
  /// already empty. The pro screen shipped without it.
  KeyEventResult _onBoxKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        controllers[index].text.isEmpty &&
        index > 0) {
      controllers[index - 1].clear();
      focusNodes[index - 1].requestFocus();
      onChanged(_code);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      // **The gaps are OUTSIDE the flex division, and that is the whole fix.**
      //
      // The obvious change — keep the per-box `margin` and wrap each box in
      // `Expanded` — produces the wrong row, silently. `Expanded` divides the
      // WHOLE width, and a margin is then spent inside its own slot: at 360 each
      // slot is 328/6 = 54.67, so the four middle boxes (margin 4+4) come out at
      // **46.67dp — under §13.2's 48 floor** — while the two end boxes (margin 4)
      // come out at 50.67. Six boxes that are neither equal nor legal, and
      // nothing overflows, so the width gate would have said nothing.
      //
      // `Flex.spacing` puts the gaps between the slots instead:
      // `(W − 2×spacingM − 5×spacingS)/6` = **48.0 @360 · 50.5 @375 · 53.0 @390**,
      // all six equal, at every width, and it cannot overflow at any width.
      //
      // 8 is what the two 4dp margins already summed to between adjacent boxes,
      // so the rendered gap does not move — and it is §13.2's adjacency floor
      // ("targets that are adjacent need ≥8px between them"), which is why it is
      // `spacingS` and not something smaller when the arithmetic gets tight.
      //
      // `mainAxisAlignment: center` is gone with the fixed widths: it is
      // meaningless once the children fill the row. `pro_journal_screen` deleted
      // its `spaceAround` for the same reason when its 7 day pills adopted
      // `Expanded` — the precedent this shape is copied from.
      child: Row(
        spacing: AppTheme.spacingS,
        children: [
          for (var i = 0; i < length; i++) Expanded(child: _box(i)),
        ],
      ),
    );
  }

  Widget _box(int index) {
    final borderColor = hasError ? AppColors.error : AppColors.borderStrong;
    // No `width:` and no `height:` — both were fixed dimensions around text, and
    // §13.3 forbids the height in writing: "a box that contains text may not
    // have a fixed height. `SizedBox(height: 50)` around a `Text` is a clip
    // waiting to happen." It was not waiting. Measured at the moment it was
    // removed: the field wants **66.0dp** at 1× and got 64 — **clipping by 2dp
    // on every device, today** — and wants 99.0dp at 2×, clipping by 35.
    //
    // The width had no written rule to break, which is exactly why it survived
    // every gate; §13.3 now has the twin bullet it was missing.
    return Focus(
      onKeyEvent: (node, event) => _onBoxKey(index, event),
      child: TextField(
        controller: controllers[index],
        focusNode: focusNodes[index],
        enabled: enabled,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: TextInputType.number,
        maxLength: index == 0 ? length : 1,
        // The OS delivers the SMS code to the first box; `_onBoxChanged`'s
        // paste branch then fills the rest.
        autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
        style: AppTextStyles.headlineMedium.copyWith(
          color: hasError ? AppColors.error : AppColors.textPrimary,
          fontWeight: FontWeight.bold,
          letterSpacing: 0,
          height: 1.2,
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          contentPadding:
              const EdgeInsets.symmetric(vertical: AppTheme.spacingM),
          isDense: false,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            borderSide: BorderSide(color: borderColor, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            borderSide: BorderSide(color: borderColor, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            borderSide: const BorderSide(color: AppColors.border, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            borderSide: BorderSide(
              color: hasError ? AppColors.error : AppColors.primary,
              width: 2.5,
            ),
          ),
          filled: true,
          fillColor: enabled ? AppColors.secondary : AppColors.surface,
        ),
        onChanged: (value) => _onBoxChanged(index, value),
      ),
    );
  }
}
