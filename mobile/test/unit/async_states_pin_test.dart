import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/hygiene-batch9.md §2.7.2 (B9.8) — an async section is
/// `AppAsyncView`, its loading shape a skeleton where the shape is known, and
/// its load error the shared one. Pinned on the WHOLE tree, as
/// `failure_messages_pin_test.dart` does: the screen written tomorrow with
/// its own spinner and its own « Réessayer » fails here the day it is
/// written.
void main() {
  /// Every Dart file under `lib`, with its code lines only — the comments may
  /// say what was retired, and should.
  Map<String, List<(int, String)>> codeLines() {
    final out = <String, List<(int, String)>>{};
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      out[f.path] = [
        for (var i = 0; i < lines.length; i++)
          if (!lines[i].trimLeft().startsWith('//')) (i + 1, lines[i]),
      ];
    }
    return out;
  }

  Map<String, int> counts(bool Function(String line) bad) {
    final out = <String, int>{};
    for (final MapEntry(key: path, value: lines) in codeLines().entries) {
      final n = lines.where((l) => bad(l.$2)).length;
      if (n > 0) out[path] = n;
    }
    return out;
  }

  test('the spinner only where the shape is not known (SYSTEM §12)', () {
    expect(
      counts((l) => l.contains('LoadingIndicator(')),
      {
        // The widget itself.
        'lib/widgets/common/loading_indicator.dart': 1,
        // The blocking dialog: it stands over any screen.
        'lib/core/utils/helpers.dart': 1,
        // « Déconnexion » under way, and the gate's way out under way: what
        // comes next is another screen.
        'lib/screens/provider/team/pro_invitations_screen.dart': 2,
        // The session gate: no page is known until the salon is.
        'lib/widgets/provider/pro_salon_gate.dart': 1,
      },
      reason:
          'a new spinner: if its content has a shape, it is a skeleton '
          '(app_skeleton.dart); if it truly has none, it joins this list '
          'with its reason',
    );
  });

  test('one load error: no hand-written « Réessayer » state', () {
    expect(
      counts((l) => l.contains("actionText: 'Réessayer'")),
      {
        // Not a page's failed read: it stands in for every page, and says
        // why they wait (pro-app-salon-not-loaded.md §4).
        'lib/widgets/provider/pro_salon_gate.dart': 1,
      },
      reason: 'a load error is AppAsyncView\'s, or AppErrorView',
    );
  });

  test('the retired error titles and sentence are gone', () {
    // « Chargement impossible » is the title now (Q9); these said the same
    // thing differently, or blamed the connection for everything.
    final retired = RegExp(
      r"title: '(Une erreur est survenue|Connexion impossible)'|"
      // As a state's whole description — the export's own sentence names
      // its sections first, and ends with these words.
      r"description: 'Vérifiez votre connexion et réessayez\.'",
    );
    expect(counts(retired.hasMatch), isEmpty);
  });
}
