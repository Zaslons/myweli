import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/team/pro_invitations_screen.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Team access R3 §2.3 — the authed « Invitations » screen: cards, accept
/// (« Vous avez rejoint {salon} », no navigation change — R6 brings the
/// switcher), decline, empty state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final team = MockProTeamService();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.proTeamService = team;
  });

  setUp(() {
    MockData.resetTeam();
    team.invitationEmail = 'invitee@myweli.test';
  });

  Widget app() => ChangeNotifierProvider(
        create: (_) => ProTeamProvider(),
        child: const MaterialApp(home: ProInvitationsScreen()),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets(
      'renders the pending card; accept shows « Vous avez rejoint » '
      'and empties the list', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.textContaining('Salon Excellence'), findsOneWidget);
    expect(find.textContaining('Collaborateur'), findsOneWidget);

    await tester.tap(find.text('Rejoindre'));
    await settle(tester);

    expect(
      find.textContaining('Vous avez rejoint Salon Excellence'),
      findsOneWidget,
    );
    await settle(tester);
    expect(find.text('Aucune invitation en attente'), findsOneWidget);
  });

  testWidgets('decline removes the card in place', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Refuser'));
    await settle(tester);

    expect(find.text('Aucune invitation en attente'), findsOneWidget);
    expect(MockData.teamMembers.any((m) => m.id == 'mem_staff1'), isFalse);
  });

  testWidgets('no invitations → the empty state', (tester) async {
    team.invitationEmail = 'personne@myweli.test';
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Aucune invitation en attente'), findsOneWidget);
  });
}
