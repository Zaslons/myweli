import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/team_invitation.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/providers/pro_team_provider.dart';
import 'package:myweli/screens/provider/team/pro_invitations_screen.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/widgets/common/app_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// Team access R3 §2.3 — the authed « Invitations » screen: cards, accept
/// (« Vous avez rejoint {salon} », no navigation change — R6 brings the
/// switcher), decline, empty state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final team = _HeldTeam();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    SharedPreferences.setMockInitialValues({});
    serviceLocator.proTeamService = team;
  });

  setUp(() {
    MockData.resetTeam();
    team
      ..invitationEmail = 'invitee@myweli.test'
      ..holdAccept = null;
  });

  Widget app() => wrapApp(
    providers: [ChangeNotifierProvider(create: (_) => ProTeamProvider())],
    home: const ProInvitationsScreen(),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('renders the pending card; accept shows « Vous avez rejoint » '
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

  // docs/design/pro-app-batch7.md §2.6 (B7.6): one answer at a time, and
  // it shows — the other cards wait too, as on the web.
  testWidgets('while one answer is out, every card’s buttons wait', (
    tester,
  ) async {
    MockData.teamInvitations['invitee@myweli.test']!.add(
      TeamInvitation(
        id: 'mem_other',
        providerId: 'provider2',
        salonName: 'Beauté Divine',
        role: TeamRole.staff,
        roleLabel: 'Collaborateur',
        expiresAt: DateTime.utc(2026, 11, 5),
      ),
    );
    final held = team.holdAccept = Completer<void>();
    await tester.pumpWidget(app());
    await settle(tester);

    await tester.tap(find.text('Rejoindre').first);
    await settle(tester);

    for (final label in ['Rejoindre', 'Refuser']) {
      final other = tester.widget<AppButton>(
        find.widgetWithText(AppButton, label).last,
      );
      expect(other.onPressed, isNull, reason: 'the other « $label » waits');
    }
    held.complete();
    await settle(tester);
  });

  testWidgets('no invitations → the empty state', (tester) async {
    team.invitationEmail = 'personne@myweli.test';
    await tester.pumpWidget(app());
    await settle(tester);

    expect(find.text('Aucune invitation en attente'), findsOneWidget);
  });
}

/// The mock, with an accept a test can hold after the mock answered it.
class _HeldTeam extends MockProTeamService {
  Completer<void>? holdAccept;

  @override
  Future<ApiResponse<TeamMember>> acceptInvitation(String invitationId) async {
    final served = await super.acceptInvitation(invitationId);
    final hold = holdAccept;
    if (hold != null) await hold.future;
    return served;
  }
}
