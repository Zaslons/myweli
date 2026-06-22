import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import 'empty_state.dart';

/// Placeholder shown in place of a feature that isn't available in this
/// release (used to gate the V2/V3 provider feature screens behind
/// `FeatureFlags`).
class ComingSoonScaffold extends StatelessWidget {
  final String title;

  const ComingSoonScaffold({super.key, this.title = 'Bientôt disponible'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      body: const EmptyState(
        icon: Icons.rocket_launch_outlined,
        title: 'Bientôt disponible',
        description: 'Cette fonctionnalité arrive dans une prochaine version.',
      ),
    );
  }
}
