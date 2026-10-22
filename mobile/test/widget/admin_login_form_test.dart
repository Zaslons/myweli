import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/providers/admin/admin_auth_provider.dart';
import 'package:myweli/screens/admin/admin_login_screen.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/widgets/common/app_text_field.dart';
import 'package:myweli/widgets/common/inline_feedback.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

/// docs/design/hygiene-batch9.md §2.6 (B9.7) — the admin sign-in's faults,
/// each under its field (SYSTEM.md §14 rule 1). Before A7 a blank press made
/// a round trip to be told « Identifiants invalides »; the form answers for
/// itself now, and the server's refusal — no field's — stays under the form.
void main() {
  late _SpyAdmin admin;

  Future<void> open(WidgetTester tester) async {
    admin = _SpyAdmin();
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AdminAuthProvider(service: admin),
          ),
        ],
        home: const AdminLoginScreen(),
      ),
    );
    await tester.pump();
  }

  Finder field(String label) =>
      find.byWidgetPredicate((w) => w is AppTextField && w.label == label);
  Finder input(String label) =>
      find.descendant(of: field(label), matching: find.byType(TextField));
  Finder under(String label, String message) =>
      find.descendant(of: field(label), matching: find.text(message));
  bool focused(WidgetTester tester, String label) => tester
      .widget<EditableText>(
        find.descendant(of: field(label), matching: find.byType(EditableText)),
      )
      .focusNode
      .hasFocus;

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a blank press: each fault under its field, the first one '
      'focused, nothing sent', (tester) async {
    await open(tester);
    await submit(tester);

    expect(under('Email', 'Saisissez une adresse e-mail.'), findsOneWidget);
    expect(
      under('Mot de passe', 'Indiquez votre mot de passe.'),
      findsOneWidget,
    );
    expect(focused(tester, 'Email'), isTrue, reason: 'the reading order');
    expect(admin.logins, 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a malformed address: said under it alone; fixing it clears '
      'it without a second press', (tester) async {
    await open(tester);
    await tester.enterText(input('Email'), 'admin@');
    await tester.enterText(input('Mot de passe'), 'secret');
    await tester.pump();
    await submit(tester);

    expect(
      under('Email', 'Saisissez une adresse e-mail valide.'),
      findsOneWidget,
    );
    expect(find.text('Indiquez votre mot de passe.'), findsNothing);
    expect(admin.logins, 0);

    await tester.enterText(input('Email'), 'admin@myweli.com');
    await tester.pump();
    expect(find.text('Saisissez une adresse e-mail valide.'), findsNothing);
  });

  testWidgets('the server\'s refusal is the form\'s: under the form, under '
      'no field', (tester) async {
    await open(tester);
    await tester.enterText(input('Email'), 'admin@myweli.com');
    await tester.enterText(input('Mot de passe'), 'wrong');
    await tester.pump();
    await submit(tester);

    expect(admin.logins, 1);
    expect(
      find.descendant(
        of: find.byType(InlineFeedback),
        matching: find.text('Identifiants invalides.'),
      ),
      findsOneWidget,
    );
    expect(under('Email', 'Identifiants invalides.'), findsNothing);
    expect(under('Mot de passe', 'Identifiants invalides.'), findsNothing);
  });
}

/// No network: counts the sign-ins that reached it and refuses each one.
class _SpyAdmin extends AdminService {
  _SpyAdmin() : super(store: InMemorySessionStore());

  int logins = 0;

  @override
  Future<ApiResponse<bool>> login(String email, String password) async {
    logins++;
    return ApiResponse.error(
      'Identifiants invalides.',
      code: 'invalid_credentials',
    );
  }
}
