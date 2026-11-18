import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/failure_messages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/inline_feedback.dart';
import 'pro_sign_up_screen.dart';

/// The sign-up's path, Android only (docs/design/pro-android-signup.md §5.4).
const kProSignUpPath = '/pro/register';

/// The sign-in's block on Android (§2.2): one sentence and one button at the
/// bottom of the sign-in.
///
/// | | The sentence |
/// |---|---|
/// | E1 | « Pas encore de compte ? » |
/// | E2, E3 | `kNoProAccountMessage`, which the sign-in then does not repeat |
///
/// The sentence is an info `InlineFeedback`, a live region, so TalkBack
/// announces the change from E1 to E2. E2 lands below the fold at 200% text,
/// so the block scrolls itself into view when it appears.
///
/// The button **pushes** the sign-up — never `go`: the salon gate and the
/// notification handler then read `/pro/login` while it is on top (§5.2,
/// P16). When it comes back, the sign-in resets itself ([onReturned]).
class ProSignUpEntry extends StatefulWidget {
  const ProSignUpEntry({
    super.key,
    required this.noAccount,
    this.email,
    this.code,
    required this.onReturned,
  });

  final bool noAccount;

  /// E3's pair: the one the refused verify used.
  final String? email;
  final String? code;
  final VoidCallback onReturned;

  @override
  State<ProSignUpEntry> createState() => _ProSignUpEntryState();
}

class _ProSignUpEntryState extends State<ProSignUpEntry> {
  @override
  void initState() {
    super.initState();
    if (widget.noAccount) _reveal();
  }

  @override
  void didUpdateWidget(ProSignUpEntry old) {
    super.didUpdateWidget(old);
    if (widget.noAccount && !old.noAccount) _reveal();
  }

  void _reveal() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(Scrollable.ensureVisible(context));
    });
  }

  Future<void> _open() async {
    final email = widget.email;
    final code = widget.code;
    await context.push(
      '/pro/register',
      extra: email != null && code != null ? ProSignUpCarry(email, code) : null,
    );
    // Back, « Se connecter », or anything else that comes back here: the
    // sign-in shown fresh (E1). It guards its own `mounted`.
    widget.onReturned();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineFeedback(
          widget.noAccount ? kNoProAccountMessage : 'Pas encore de compte ?',
          kind: SnackKind.info,
        ),
        const SizedBox(height: AppTheme.spacingS),
        AppButton(
          text: 'Créer le compte de mon salon',
          type: AppButtonType.text,
          onPressed: _open,
        ),
      ],
    );
  }
}
