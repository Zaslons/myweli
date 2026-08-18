import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/version/client_version_gate.dart';
import 'package:myweli/widgets/common/update_available_banner.dart';
import 'package:myweli/widgets/common/update_nudge_slot.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The gentle half of the version gate.
///
/// **A nudge that cannot be dismissed is a block with extra steps**, and it
/// would train people to ignore the one that matters — so most of these assert
/// that dismissal works and sticks for the right scope.
void main() {
  ClientVersionResult result({
    ClientVersionVerdict verdict = ClientVersionVerdict.updateAvailable,
    String? url = 'https://play.google.com/x',
    int build = 7,
  }) => (verdict: verdict, updateUrl: url, build: build);

  Widget host(ClientVersionResult r) => MaterialApp(
    home: Scaffold(body: UpdateNudgeSlot(result: r)),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows for update_available, with the action', (t) async {
    await t.pumpWidget(host(result()));
    await t.pumpAndSettle();
    expect(find.text('Une nouvelle version est disponible'), findsOneWidget);
    expect(find.text('Mettre à jour'), findsOneWidget);
  });

  testWidgets('renders NOTHING when there is nothing to say', (t) async {
    for (final r in [
      result(verdict: ClientVersionVerdict.ok),
      result(verdict: ClientVersionVerdict.updateRequired),
      // Recommended, but nowhere to send them — the same rule the backend
      // enforces, restated on the client so a dead CTA cannot appear.
      result(url: null),
    ]) {
      await t.pumpWidget(host(r));
      await t.pumpAndSettle();
      expect(find.text('Une nouvelle version est disponible'), findsNothing);
    }
  });

  testWidgets('dismissing hides it AND remembers, per recommended build', (
    t,
  ) async {
    await t.pumpWidget(host(result(build: 7)));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Masquer'));
    await t.pumpAndSettle();
    // Asserted on the VISIBLE text, not the widget type: the banner widget
    // stays mounted and collapses to a `SizedBox.shrink()`, so `byType` finds
    // it either way and would pass whether or not dismissal worked.
    expect(find.text('Une nouvelle version est disponible'), findsNothing);

    // A relaunch does not re-nag…
    await t.pumpWidget(host(result(build: 7)));
    await t.pumpAndSettle();
    expect(find.text('Une nouvelle version est disponible'), findsNothing);

    // …but the NEXT recommendation is a new fact and is shown again. Keying
    // dismissal on "ever dismissed" would silence every future nudge, which is
    // how a soft lever quietly becomes no lever.
    await t.pumpWidget(host(result(build: 9)));
    await t.pumpAndSettle();
    expect(find.text('Une nouvelle version est disponible'), findsOneWidget);
  });

  testWidgets('the dismiss control is labelled for a screen reader', (t) async {
    // Icon-only, so §13.4 requires a tooltip — and `IconButton` gives it the
    // 48-dp target for free.
    await t.pumpWidget(host(result()));
    await t.pumpAndSettle();
    expect(find.byTooltip('Masquer'), findsOneWidget);
  });

  testWidgets('the action opens the store URL', (t) async {
    String? opened;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateAvailableBanner(
            updateUrl: 'https://play.google.com/store/apps/details?id=x',
            recommendedBuild: 7,
            onOpen: (_, url) => opened = url,
          ),
        ),
      ),
    );
    await t.tap(find.text('Mettre à jour'));
    await t.pump();
    expect(opened, contains('play.google.com'));
  });
}
