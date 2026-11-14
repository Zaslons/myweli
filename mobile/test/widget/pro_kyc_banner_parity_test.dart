import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/app_constants.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/kyc_document.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/providers/pro_kyc_provider.dart';
import 'package:myweli/screens/provider/onboarding/pro_kyc_screen.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_kyc_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

/// The KYC answer the screen reads, scripted per test.
class _ScriptedKyc extends MockProKycService {
  KycStatus status = const KycStatus(status: VerificationStatus.pending);

  @override
  Future<ApiResponse<KycStatus>> getKycStatus(String providerUserId) async {
    await Future<void>.delayed(AppConstants.mockDelay);
    return ApiResponse.success(status);
  }
}

/// « Vérification »'s status banner, drawn exactly as it was before B0.18
/// moved it onto the shared `StatusBanner` (lib/widgets/common/
/// status_banner.dart — SYSTEM.md §11: the validation banner on
/// « Configuration » is the same pattern, and a second copy becomes a shared
/// widget). The KYC screen has no golden, so this is the instrument that
/// says the move cost KYC nothing: every box of the banner — its place and
/// size, its tint and corner, each text's words, colour, size and weight,
/// each icon's glyph, colour and size — and what a screen reader hears,
/// recorded on the code BEFORE the move (commit 76bf1154) and asserted
/// after it.
void main() {
  final kyc = _ScriptedKyc();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = MockProService();
    serviceLocator.proKycService = kyc;
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  setUp(MockData.resetTeam);

  String describeStyle(TextStyle? s) =>
      'color=${s?.color?.toARGB32().toRadixString(16)} '
      'size=${s?.fontSize} weight=${s?.fontWeight?.value} '
      'height=${s?.height} spacing=${s?.letterSpacing} '
      'family=${s?.fontFamily}';

  /// A glyph of the icon font (the Private Use Area) as its code point, so
  /// the recording holds no invisible character.
  String readable(String text) => text.runes
      .map(
        (r) => r >= 0xE000 && r <= 0xF8FF
            ? 'U+${r.toRadixString(16)}'
            : String.fromCharCode(r),
      )
      .join();

  /// Every render box of the banner, relative to the banner, in tree order.
  String fingerprint(WidgetTester tester, String title, String subtitle) {
    final banner = find
        .ancestor(
          of: find.text(title),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
        )
        .first;
    final root = tester.renderObject<RenderBox>(banner);
    final origin = root.localToGlobal(Offset.zero);
    final out = <String>[];
    void visit(RenderObject o, int depth) {
      if (o is RenderBox) {
        final at = o.localToGlobal(Offset.zero) - origin;
        final what = switch (o) {
          RenderParagraph p =>
            '«${readable(p.text.toPlainText())}» '
                '${describeStyle(p.text.style)} '
                'maxLines=${p.maxLines} overflow=${p.overflow.name}',
          RenderDecoratedBox d => '${d.decoration}',
          RenderPadding p => '${p.padding}',
          _ => '',
        };
        out.add(
          '${'  ' * depth}${o.runtimeType} '
          '(${at.dx.toStringAsFixed(1)}, ${at.dy.toStringAsFixed(1)}) '
          '${o.size.width.toStringAsFixed(1)}x'
          '${o.size.height.toStringAsFixed(1)} $what',
        );
      }
      o.visitChildren((child) => visit(child, depth + 1));
    }

    visit(root, 0);
    final heard = tester.getSemantics(find.text(title));
    final heardSub = tester.getSemantics(find.text(subtitle));
    out.add('semantics title «${heard.label}» ${heard.rect}');
    out.add('semantics subtitle «${heardSub.label}» ${heardSub.rect}');
    out.add('semantics one node: ${identical(heard, heardSub)}');
    return out.join('\n');
  }

  Future<void> pumpKyc(WidgetTester tester, KycStatus status) async {
    kyc.status = status;
    pinSurface(tester, size: const Size(360, 1600));
    final auth = await signInPro(tester);
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<ProAuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProKycProvider()),
        ],
        home: const ProKycScreen(),
      ),
    );
    await settleMocks(tester, rounds: 2);
  }

  for (final (name, status, title, subtitle) in [
    (
      'pending',
      const KycStatus(status: VerificationStatus.pending),
      'Vérification en attente',
      'Soumettez vos documents pour être vérifié.',
    ),
    (
      'verified',
      const KycStatus(status: VerificationStatus.verified),
      'Compte vérifié',
      'Vous pouvez activer les acomptes.',
    ),
    (
      'rejected, with the reason',
      const KycStatus(
        status: VerificationStatus.rejected,
        rejectionReason: 'La pièce d’identité est illisible.',
      ),
      'Vérification refusée',
      'La pièce d’identité est illisible.',
    ),
    (
      'rejected, no reason',
      const KycStatus(status: VerificationStatus.rejected),
      'Vérification refusée',
      'Veuillez renvoyer vos documents.',
    ),
  ]) {
    testWidgets('the KYC banner ($name) draws and reads as before the shared '
        'banner', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpKyc(tester, status);
        expect(fingerprint(tester, title, subtitle), _recorded[name]);
      } finally {
        handle.dispose();
      }
    });
  }
}

/// Recorded on commit 76bf1154 (the private `_StatusBanner` of
/// pro_kyc_screen.dart), 360dp, the test font.
const Map<String, String> _recorded = {
  'pending':
      'RenderDecoratedBox (0.0, 0.0) 328.0x124.0 BoxDecoration(color: Color(alpha: 0.1000, red: 0.4196, green: 0.3569, blue: 0.0000, colorSpace: ColorSpace.sRGB), borderRadius: BorderRadius.circular(12.0))\n'
      '  RenderPadding (0.0, 0.0) 328.0x124.0 EdgeInsets.all(16.0)\n'
      '    RenderFlex (16.0, 16.0) 296.0x92.0 \n'
      '      RenderSemanticsAnnotations (16.0, 16.0) 24.0x24.0 \n'
      '        RenderExcludeSemantics (16.0, 16.0) 24.0x24.0 \n'
      '          RenderConstrainedBox (16.0, 16.0) 24.0x24.0 \n'
      '            RenderPositionedBox (16.0, 16.0) 24.0x24.0 \n'
      '              RenderParagraph (16.0, 16.0) 24.0x24.0 «U+e556» color=ff6b5b00 size=24.0 weight=null height=1.0 spacing=null family=MaterialIcons maxLines=null overflow=visible\n'
      '      RenderConstrainedBox (40.0, 16.0) 12.0x0.0 \n'
      '      RenderFlex (52.0, 16.0) 260.0x92.0 \n'
      '        RenderParagraph (52.0, 16.0) 260.0x40.0 «Vérification en attente» color=ff6b5b00 size=14.0 weight=500 height=1.4285714285714286 spacing=0.1 family=Roboto maxLines=null overflow=clip\n'
      '        RenderConstrainedBox (52.0, 56.0) 0.0x4.0 \n'
      '        RenderParagraph (52.0, 60.0) 260.0x48.0 «Soumettez vos documents pour être vérifié.» color=ff6b5b00 size=12.0 weight=400 height=1.3333333333333333 spacing=0.4 family=Roboto maxLines=null overflow=clip\n'
      'semantics title «Vérification en attente\n'
      'Soumettez vos documents pour être vérifié.» Rect.fromLTRB(0.0, 0.0, 328.0, 124.0)\n'
      'semantics subtitle «Vérification en attente\n'
      'Soumettez vos documents pour être vérifié.» Rect.fromLTRB(0.0, 0.0, 328.0, 124.0)\n'
      'semantics one node: true',
  'verified':
      'RenderDecoratedBox (0.0, 0.0) 328.0x88.0 BoxDecoration(color: Color(alpha: 0.1000, red: 0.1765, green: 0.3137, blue: 0.0863, colorSpace: ColorSpace.sRGB), borderRadius: BorderRadius.circular(12.0))\n'
      '  RenderPadding (0.0, 0.0) 328.0x88.0 EdgeInsets.all(16.0)\n'
      '    RenderFlex (16.0, 16.0) 296.0x56.0 \n'
      '      RenderSemanticsAnnotations (16.0, 16.0) 24.0x24.0 \n'
      '        RenderExcludeSemantics (16.0, 16.0) 24.0x24.0 \n'
      '          RenderConstrainedBox (16.0, 16.0) 24.0x24.0 \n'
      '            RenderPositionedBox (16.0, 16.0) 24.0x24.0 \n'
      '              RenderParagraph (16.0, 16.0) 24.0x24.0 «U+e699» color=ff2d5016 size=24.0 weight=null height=1.0 spacing=null family=MaterialIcons maxLines=null overflow=visible\n'
      '      RenderConstrainedBox (40.0, 16.0) 12.0x0.0 \n'
      '      RenderFlex (52.0, 16.0) 260.0x56.0 \n'
      '        RenderParagraph (52.0, 16.0) 197.4x20.0 «Compte vérifié» color=ff2d5016 size=14.0 weight=500 height=1.4285714285714286 spacing=0.1 family=Roboto maxLines=null overflow=clip\n'
      '        RenderConstrainedBox (52.0, 36.0) 0.0x4.0 \n'
      '        RenderParagraph (52.0, 40.0) 260.0x32.0 «Vous pouvez activer les acomptes.» color=ff2d5016 size=12.0 weight=400 height=1.3333333333333333 spacing=0.4 family=Roboto maxLines=null overflow=clip\n'
      'semantics title «Compte vérifié\n'
      'Vous pouvez activer les acomptes.» Rect.fromLTRB(0.0, 0.0, 328.0, 88.0)\n'
      'semantics subtitle «Compte vérifié\n'
      'Vous pouvez activer les acomptes.» Rect.fromLTRB(0.0, 0.0, 328.0, 88.0)\n'
      'semantics one node: true',
  'rejected, with the reason':
      'RenderDecoratedBox (0.0, 0.0) 328.0x108.0 BoxDecoration(color: Color(alpha: 0.1000, red: 0.5451, green: 0.0000, blue: 0.0000, colorSpace: ColorSpace.sRGB), borderRadius: BorderRadius.circular(12.0))\n'
      '  RenderPadding (0.0, 0.0) 328.0x108.0 EdgeInsets.all(16.0)\n'
      '    RenderFlex (16.0, 16.0) 296.0x76.0 \n'
      '      RenderSemanticsAnnotations (16.0, 16.0) 24.0x24.0 \n'
      '        RenderExcludeSemantics (16.0, 16.0) 24.0x24.0 \n'
      '          RenderConstrainedBox (16.0, 16.0) 24.0x24.0 \n'
      '            RenderPositionedBox (16.0, 16.0) 24.0x24.0 \n'
      '              RenderParagraph (16.0, 16.0) 24.0x24.0 «U+e238» color=ff8b0000 size=24.0 weight=null height=1.0 spacing=null family=MaterialIcons maxLines=null overflow=visible\n'
      '      RenderConstrainedBox (40.0, 16.0) 12.0x0.0 \n'
      '      RenderFlex (52.0, 16.0) 260.0x76.0 \n'
      '        RenderParagraph (52.0, 16.0) 260.0x40.0 «Vérification refusée» color=ff8b0000 size=14.0 weight=500 height=1.4285714285714286 spacing=0.1 family=Roboto maxLines=null overflow=clip\n'
      '        RenderConstrainedBox (52.0, 56.0) 0.0x4.0 \n'
      '        RenderParagraph (52.0, 60.0) 260.0x32.0 «La pièce d’identité est illisible.» color=ff8b0000 size=12.0 weight=400 height=1.3333333333333333 spacing=0.4 family=Roboto maxLines=null overflow=clip\n'
      'semantics title «Vérification refusée\n'
      'La pièce d’identité est illisible.» Rect.fromLTRB(0.0, 0.0, 328.0, 108.0)\n'
      'semantics subtitle «Vérification refusée\n'
      'La pièce d’identité est illisible.» Rect.fromLTRB(0.0, 0.0, 328.0, 108.0)\n'
      'semantics one node: true',
  'rejected, no reason':
      'RenderDecoratedBox (0.0, 0.0) 328.0x108.0 BoxDecoration(color: Color(alpha: 0.1000, red: 0.5451, green: 0.0000, blue: 0.0000, colorSpace: ColorSpace.sRGB), borderRadius: BorderRadius.circular(12.0))\n'
      '  RenderPadding (0.0, 0.0) 328.0x108.0 EdgeInsets.all(16.0)\n'
      '    RenderFlex (16.0, 16.0) 296.0x76.0 \n'
      '      RenderSemanticsAnnotations (16.0, 16.0) 24.0x24.0 \n'
      '        RenderExcludeSemantics (16.0, 16.0) 24.0x24.0 \n'
      '          RenderConstrainedBox (16.0, 16.0) 24.0x24.0 \n'
      '            RenderPositionedBox (16.0, 16.0) 24.0x24.0 \n'
      '              RenderParagraph (16.0, 16.0) 24.0x24.0 «U+e238» color=ff8b0000 size=24.0 weight=null height=1.0 spacing=null family=MaterialIcons maxLines=null overflow=visible\n'
      '      RenderConstrainedBox (40.0, 16.0) 12.0x0.0 \n'
      '      RenderFlex (52.0, 16.0) 260.0x76.0 \n'
      '        RenderParagraph (52.0, 16.0) 260.0x40.0 «Vérification refusée» color=ff8b0000 size=14.0 weight=500 height=1.4285714285714286 spacing=0.1 family=Roboto maxLines=null overflow=clip\n'
      '        RenderConstrainedBox (52.0, 56.0) 0.0x4.0 \n'
      '        RenderParagraph (52.0, 60.0) 260.0x32.0 «Veuillez renvoyer vos documents.» color=ff8b0000 size=12.0 weight=400 height=1.3333333333333333 spacing=0.4 family=Roboto maxLines=null overflow=clip\n'
      'semantics title «Vérification refusée\n'
      'Veuillez renvoyer vos documents.» Rect.fromLTRB(0.0, 0.0, 328.0, 108.0)\n'
      'semantics subtitle «Vérification refusée\n'
      'Veuillez renvoyer vos documents.» Rect.fromLTRB(0.0, 0.0, 328.0, 108.0)\n'
      'semantics one node: true',
};
