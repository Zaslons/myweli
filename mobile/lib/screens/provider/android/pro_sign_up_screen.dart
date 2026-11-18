import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/failure_messages.dart';
import '../../../core/constants/unnamed_salon.dart';
import '../../../core/forms/field_errors.dart';
import '../../../core/forms/sign_in_refusal.dart';
import '../../../core/router/pro_landing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../models/pro_sign_up_fields.dart';
import '../../../models/provider_login_result.dart';
import '../../../models/provider_sign_up_result.dart';
import '../../../models/provider_user.dart';
import '../../../providers/pro_auth_provider.dart';
import '../../../widgets/common/app_button.dart';
import '../../../widgets/common/app_chip.dart';
import '../../../widgets/common/app_snack_bar.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/commune_picker_sheet.dart';
import '../../../widgets/common/google_g_logo.dart';
import '../../../widgets/common/inline_feedback.dart';
import '../../../widgets/common/legal_consent_text.dart';
import '../../../widgets/common/phone_number_field.dart';
import '../../../widgets/common/screen_title.dart';
import '../../../widgets/team/invitation_card.dart';

/// The e-mail and code a sign-in verify used when it answered
/// `provider_not_found` (E3, docs/design/pro-android-signup.md §2.2): the
/// sign-up continues with that proof while it is valid. Crosses as GoRouter
/// `extra`, in memory — never in a URL (§6.4).
class ProSignUpCarry {
  const ProSignUpCarry(this.email, this.code);
  final String email;
  final String code;
}

// ---- The sign-up's own sentences (§2.4, §2.5, §2.6 a) -----------------------
// Every other refusal keeps the sign-in's sentence (SYSTEM §17: « a refusal
// whose code has its own sentence keeps it »).

/// S3 — the check found an account and signed it in.
const _kHadAccount =
    'Vous aviez déjà un compte MyWeli Pro : vous êtes connecté(e). '
    'Le salon saisi n’a pas été créé.';

/// S4 — the check found invitations.
const _kInvited =
    'Cette adresse a reçu une invitation. Rejoignez l’équipe, ou créez '
    'plutôt votre propre salon.';

/// E3's carried code, no longer usable (§2.3).
const _kCodeNoLongerValid =
    'Ce code n’est plus valable. Recevez-en un nouveau.';

/// S5 — the app's sentence for a refused number.
const _kInvalidPhone = 'Saisissez un numéro de téléphone valide.';

/// S6.
const _kInvalidArea = 'Choisissez une commune dans la liste.';

/// S7 — register's `invalid_input`: the salon's fields, not a code.
const _kCheckSalon = 'Vérifiez les informations du salon, puis réessayez.';

/// S8 — another device made the account between the check and register.
const _kAccountExists =
    'Un compte existe déjà pour cette identité. Connectez-vous.';

/// The server's cap, in code points as it counts them (`register.dart`).
const _kMaxNameCodePoints = 120;

/// The six types, in the website's order (§2.4 row 4).
const _kTypes = <(BusinessType, String)>[
  (BusinessType.salon, 'Salon de beauté'),
  (BusinessType.barber, 'Barbier'),
  (BusinessType.spa, 'Spa'),
  (BusinessType.nailSalon, 'Institut de manucure'),
  (BusinessType.massage, 'Massage'),
  (BusinessType.other, 'Autre'),
];

/// Android only: create a MyWeli Pro account and its draft salon
/// (docs/design/pro-android-signup.md §2.4, §2.5) — the salon first, the
/// identity last, and a sign-in check with that identity before anything is
/// created (§2.1).
///
/// **Behind the fence** (`lib/screens/provider/android/`): only
/// `lib/main_pro_android.dart` reaches it, so the iOS binary Apple reads has
/// none of it (App Store 3.1.1; `pro_android_fence_test.dart`).
///
/// Always **pushed** above `/pro/login`, never gone to: the salon gate and the
/// notification handler then read `/pro/login`, a launch page, while this
/// screen is on top (§5.2, P16).
class ProSignUpScreen extends StatefulWidget {
  const ProSignUpScreen({super.key, this.carried});

  /// E3's proof, or null from E1 and E2.
  final ProSignUpCarry? carried;

  @override
  State<ProSignUpScreen> createState() => _ProSignUpScreenState();
}

/// The identity section's three shapes (§2.4 rows 8–12).
enum _Identity {
  /// E3: « Compte : {e-mail} », the carried code.
  carried,

  /// Google, then the e-mail field.
  options,

  /// The code step, replacing the e-mail field.
  code,
}

/// What fills the screen: the form, S3's notice, or S4's invitations.
enum _Phase { form, hadAccount, invited }

/// Which button's request runs (S1: its spinner).
enum _Action { google, sendCode, create, own }

/// The Google identity in the own-salon choice (an e-mail address otherwise).
const _kGoogle = '#google';

class _ProSignUpScreenState extends State<ProSignUpScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _scroll = ScrollController();

  final _nameFocus = FocusNode();
  // The chips have no field to focus: the group takes focus for
  // `focusFirstError`, out of the traversal order (deposit_settings' way).
  final _typeFocus = FocusNode(skipTraversal: true);
  final _phoneFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _areaFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();

  // §14 — declaration order IS the reading order `focusFirstError` follows.
  late final _errors = FieldErrors({
    'businessName': (value) =>
        Validators.requiredField('le nom de l’entreprise')(value) ??
        (value.trim().runes.length > _kMaxNameCodePoints
            ? '120 caractères au plus.'
            : null),
    'businessType': (value) =>
        value.isEmpty ? 'Choisissez le type d’entreprise.' : null,
    'phone': Validators.phoneNumber,
    'address': Validators.requiredField('l’adresse de l’entreprise'),
    // Optional: only the server refuses it (S6).
    'area': (_) => null,
    'email': Validators.email,
    'code': Validators.otp,
  });
  late final _focusNodes = {
    'businessName': _nameFocus,
    'businessType': _typeFocus,
    'phone': _phoneFocus,
    'address': _addressFocus,
    'area': _areaFocus,
    'email': _emailFocus,
    'code': _codeFocus,
  };

  BusinessType? _type;
  String _phone = '';
  String? _areaId;
  String _communeName = '';

  late _Identity _identity;
  ProSignUpCarry? _carried;
  _Phase _phase = _Phase.form;
  _Action? _running;

  /// The outcome under the buttons (§2.4 row 13), when it is no field's.
  String? _formFault;

  /// S8: « Se connecter » under it.
  bool _offerSignIn = false;

  /// S4's accept and decline refusals, under the cards.
  String? _invitedFault;

  /// The identity whose check surfaced the invitations, and — once « Créer
  /// plutôt mon propre salon » is chosen — the one that registers directly,
  /// without the check, until the screen is left (S4).
  String? _invitedFor;
  String? _ownSalonFor;

  /// S12: a register went out and its answer was lost, so the salon may
  /// exist — a later check's 200 is then S2, not S3.
  bool _registerMayHaveLanded = false;

  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _carried = widget.carried;
    _identity = _carried != null ? _Identity.carried : _Identity.options;
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    for (final c in [
      _nameController,
      _addressController,
      _emailController,
      _codeController,
    ]) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  ProSignUpFields _fields() => ProSignUpFields(
    businessName: _nameController.text.trim(),
    businessType: _type!,
    phoneNumber: _phone,
    address: _addressController.text.trim(),
    areaId: _areaId,
  );

  /// Rows 3–7, plus [extra] (the e-mail, the code): checked on the action,
  /// the first fault focused and scrolled to (§14).
  bool _validate([Map<String, String> extra = const {}]) {
    final ok = _errors.validate({
      'businessName': _nameController.text,
      'businessType': _type?.name ?? '',
      'phone': _phone,
      'address': _addressController.text,
      ...extra,
    });
    setState(() {});
    if (!ok) focusFirstError(_errors, _focusNodes);
    return ok;
  }

  Future<void> _pickCommune() async {
    final choice = await showCommunePicker(
      context,
      selected: _communeName.isEmpty ? null : _communeName,
      allowAll: false,
    );
    if (choice == null || choice.areaId == null || !mounted) return;
    setState(() {
      _areaId = choice.areaId;
      _communeName = choice.commune ?? '';
      _errors.set('area', null);
    });
  }

  void _startCooldown() {
    _resendCooldown = AppConstants.otpResendCooldownSeconds;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  /// Where a signed-in Pro lands: the sign-in's rule (S2, S3).
  void _land() =>
      context.go(proLandingRoute(context.read<ProAuthProvider>(), null));

  /// A phase replaces what was on screen: back to its top.
  void _toTop() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  // ---- The actions ----------------------------------------------------------

  Future<void> _google() async {
    if (!_validate()) return;
    final auth = context.read<ProAuthProvider>();
    // S4's choice made with this identity: register with the held proof.
    final own = _ownSalonFor == _kGoogle;
    await _run(
      own ? _Action.own : _Action.google,
      own
          ? () => auth.createOwnSalonInstead(_fields())
          : () => auth.signUpSalonWithGoogle(_fields()),
      identity: _kGoogle,
    );
  }

  /// « Continuer avec e-mail » (and « Renvoyer le code »): a code for the
  /// address. [resend] checks only the address — the salon was checked
  /// before the first code.
  Future<void> _sendCode({bool resend = false}) async {
    final email = {'email': _emailController.text};
    if (resend) {
      if (!_errors.validate(email)) {
        setState(() {});
        focusFirstError(_errors, _focusNodes);
        return;
      }
    } else if (!_validate(email)) {
      return;
    }
    final auth = context.read<ProAuthProvider>();
    setState(() {
      _running = _Action.sendCode;
      _formFault = null;
      _offerSignIn = false;
    });
    final ok = await auth.requestEmailOtp(_emailController.text.trim());
    if (!mounted) return;
    setState(() => _running = null);
    if (ok) {
      setState(() {
        _codeController.clear();
        // A new code: the last one's fault is not this one's.
        _errors.set('code', null);
        _identity = _Identity.code;
      });
      _startCooldown();
      return;
    }
    // The e-mail's fault under the e-mail when it is on screen (S10); on the
    // code step, « Renvoyer le code »'s refusal is the form's.
    final fault = emailFieldFault(auth.errorCode);
    if (fault != null && _identity == _Identity.options) {
      setState(() => _errors.set('email', fault));
      focusFirstError(_errors, _focusNodes);
    } else {
      setState(() => _formFault = auth.error ?? kGenericErrorMessage);
    }
  }

  /// « Créer mon compte » on the code step.
  Future<void> _createWithCode() async {
    if (!_validate({'code': _codeController.text})) return;
    await _createWithEmail(
      _emailController.text.trim().toLowerCase(),
      _codeController.text.trim(),
    );
  }

  /// « Créer mon compte » from E3, with the carried pair.
  Future<void> _createWithCarried() async {
    final carried = _carried;
    if (carried == null || !_validate()) return;
    await _createWithEmail(
      carried.email.trim().toLowerCase(),
      carried.code,
      carried: true,
    );
  }

  Future<void> _createWithEmail(
    String email,
    String code, {
    bool carried = false,
  }) async {
    final auth = context.read<ProAuthProvider>();
    // S4's choice made with this address: register directly, with this code.
    final own = _ownSalonFor == email;
    await _run(
      own ? _Action.own : _Action.create,
      own
          ? () => auth.createOwnSalonInstead(
              _fields(),
              proof: EmailOtpInvitationProof(email, code),
            )
          : () => auth.signUpSalonWithEmail(email, code, _fields()),
      identity: email,
      carried: carried,
    );
  }

  /// S4's « Créer plutôt mon propre salon »: the account, with the proof the
  /// check left held, and the fields as they are now.
  Future<void> _createOwnInstead() async {
    final ok = _errors.validate({
      'businessName': _nameController.text,
      'businessType': _type?.name ?? '',
      'phone': _phone,
      'address': _addressController.text,
    });
    if (!ok) {
      // The fault is on the form, which the cards hide: bring it back, then
      // take the person to the field once it is built.
      setState(() => _phase = _Phase.form);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) focusFirstError(_errors, _focusNodes);
      });
      return;
    }
    final auth = context.read<ProAuthProvider>();
    _ownSalonFor = _invitedFor;
    await _run(
      _Action.own,
      () => auth.createOwnSalonInstead(_fields()),
      identity: _invitedFor ?? _kGoogle,
      carried: _identity == _Identity.carried,
    );
  }

  Future<void> _run(
    _Action action,
    Future<ProviderSignUpResult> Function() call, {
    required String identity,
    bool carried = false,
  }) async {
    setState(() {
      _running = action;
      _formFault = null;
      _offerSignIn = false;
    });
    final result = await call();
    // The provider may have gone elsewhere itself: the rejoin gate, or the
    // sign-in after an ended session (S3b).
    if (!mounted) return;
    setState(() => _running = null);
    switch (result) {
      case ProviderSignUpCreated():
        _land();
      case ProviderSignUpSignedIn():
        if (_registerMayHaveLanded) {
          _land(); // S12: that salon exists — S2.
        } else {
          setState(() => _phase = _Phase.hadAccount);
          _toTop();
        }
      case ProviderSignUpEnded():
        break; // S3b: the sign-in shows why.
      case ProviderSignUpInvited():
        setState(() {
          _phase = _Phase.invited;
          _invitedFor = identity;
          _invitedFault = null;
        });
        _toTop();
      case ProviderSignUpFailure():
        _refused(result, identity: identity, carried: carried);
    }
  }

  /// A lost answer: no network, a 5xx, or nothing the server said.
  bool _mayHaveLanded(String? code) =>
      code == null || code == 'network' || code == 'internal_error';

  /// S5–S13: each refusal where it belongs; the form comes back from S4.
  void _refused(
    ProviderSignUpFailure failure, {
    required String identity,
    required bool carried,
  }) {
    final code = failure.code;
    final atRegister = failure.stage == ProSignUpStage.register;
    if (atRegister && _mayHaveLanded(code)) _registerMayHaveLanded = true;
    if (code == 'cancelled') return; // S14: Google's sheet closed.
    var fieldFault = false;
    setState(() {
      _phase = _Phase.form;
      switch (code) {
        case 'invalid_phone' when atRegister:
          _errors.set('phone', _kInvalidPhone);
          fieldFault = true;
        case 'invalid_area':
          _errors.set('area', _kInvalidArea);
          fieldFault = true;
        case 'invalid_input' when atRegister:
          _formFault = _kCheckSalon;
        case 'provider_exists':
          _formFault = _kAccountExists;
          _offerSignIn = true;
        default:
          final codeFault = codeFieldFault(code);
          if (codeFault != null && identity != _kGoogle) {
            if (carried) {
              // The carried pair was proven, so only its expiry reaches
              // here: the e-mail path, the address filled in (§2.3).
              _carried = null;
              _identity = _Identity.options;
              _emailController.text = identity;
              _formFault = _kCodeNoLongerValid;
            } else {
              _identity = _Identity.code;
              _errors.set('code', codeFault);
              fieldFault = true;
            }
          } else {
            _formFault = failure.message.isEmpty
                ? kGenericErrorMessage
                : failure.message;
          }
      }
    });
    // After the frame: from S4, the field is not built until the form is back.
    if (fieldFault) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) focusFirstError(_errors, _focusNodes);
      });
    }
  }

  // ---- S4: the invitations --------------------------------------------------

  Future<void> _accept(String invitationId, String salonName) async {
    final auth = context.read<ProAuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _invitedFault = null);
    final ok = await auth.acceptPendingInvitation(invitationId);
    if (!mounted) return;
    if (ok) {
      // Exactly as on the sign-in.
      AppSnackBar.showOn(
        messenger,
        'Bienvenue dans l’équipe de $salonName !',
        kind: SnackKind.success,
      );
      _land();
    } else {
      setState(() => _invitedFault = auth.error);
    }
  }

  Future<void> _decline(String invitationId) async {
    final auth = context.read<ProAuthProvider>();
    setState(() => _invitedFault = null);
    final ok = await auth.declinePendingInvitation(invitationId);
    if (!mounted) return;
    if (!ok) {
      setState(() => _invitedFault = auth.error);
    } else if (!auth.hasPendingInvitations) {
      // None left: the form as it was, with no message.
      setState(() {
        _phase = _Phase.form;
        _invitedFor = null;
      });
      _toTop();
    }
  }

  // ---- Back -----------------------------------------------------------------

  /// Held while a request runs and on S3 (the session may be live: a
  /// signed-in person must never land on the sign-in). On S3, Back acts as
  /// « Continuer ».
  bool _canPop(ProAuthProvider auth) =>
      !auth.isLoading && _running == null && _phase != _Phase.hadAccount;

  void _onPop(bool didPop, ProAuthProvider auth) {
    if (didPop) {
      // What this screen's check surfaced goes with it — in the pop, never
      // in dispose, where a notify would hit a locked tree.
      if (auth.hasPendingInvitations) auth.clearPendingInvitations();
      return;
    }
    if (_phase == _Phase.hadAccount && _running == null) _land();
  }

  // ---- The screen -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ProAuthProvider>();
    final busy = auth.isLoading || _running != null;
    return PopScope(
      canPop: _canPop(auth),
      onPopInvokedWithResult: (didPop, _) => _onPop(didPop, auth),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const ScreenTitle('Créer mon compte')),
        body: SafeArea(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(AppTheme.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: switch (_phase) {
                _Phase.hadAccount => _hadAccount(),
                _Phase.invited => _invited(auth, busy),
                _Phase.form => _form(auth, busy),
              },
            ),
          ),
        ),
      ),
    );
  }

  /// S3, in place of the form.
  List<Widget> _hadAccount() => [
    const InlineFeedback(_kHadAccount, kind: SnackKind.info),
    const SizedBox(height: AppTheme.spacingL),
    AppButton(text: 'Continuer', onPressed: _land),
  ];

  /// S4, in place of the form; the fields are kept behind it.
  List<Widget> _invited(ProAuthProvider auth, bool busy) => [
    Semantics(
      headingLevel: 2,
      child: Text(
        'Vous êtes invité(e)',
        style: AppTextStyles.headlineSmall,
        textAlign: TextAlign.center,
      ),
    ),
    const SizedBox(height: AppTheme.spacingS),
    Text(
      _kInvited,
      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: AppTheme.spacingL),
    for (final invitation in auth.pendingInvitations) ...[
      InvitationCard(
        invitation: invitation,
        busy: busy,
        onAccept: () => _accept(
          invitation.id,
          salonNameOr(invitation.salonName, kUnnamedSalonInSentence),
        ),
        onDecline: () => _decline(invitation.id),
      ),
      const SizedBox(height: AppTheme.spacingM),
    ],
    InlineFeedback(_invitedFault),
    AppButton(
      text: 'Créer plutôt mon propre salon',
      type: AppButtonType.text,
      isLoading: _running == _Action.own,
      onPressed: busy ? null : _createOwnInstead,
    ),
  ];

  List<Widget> _form(ProAuthProvider auth, bool busy) => [
    _heading('Votre salon'),
    const SizedBox(height: AppTheme.spacingM),
    AppTextField(
      controller: _nameController,
      focusNode: _nameFocus,
      label: 'Nom de l’entreprise',
      hint: 'Ex : Salon de Beauté Marie',
      errorText: _errors['businessName'],
      onChanged: (v) => setState(() => _errors.revalidate('businessName', v)),
    ),
    const SizedBox(height: AppTheme.spacingM),
    Text(
      'Type d’entreprise',
      style: AppTextStyles.labelLarge.copyWith(color: AppColors.textPrimary),
    ),
    const SizedBox(height: AppTheme.spacingS),
    Focus(
      focusNode: _typeFocus,
      child: Wrap(
        spacing: AppTheme.spacingS,
        runSpacing: AppTheme.spacingS,
        children: [
          for (final (type, label) in _kTypes)
            AppChip.choice(
              label: label,
              selected: _type == type,
              onSelected: (_) => setState(() {
                _type = type;
                _errors.revalidate('businessType', type.name);
              }),
            ),
        ],
      ),
    ),
    // A selection has no decoration to carry its fault: it sits under the
    // chips, as deposit_settings' operator does.
    InlineFeedback(_errors['businessType']),
    const SizedBox(height: AppTheme.spacingM),
    PhoneNumberField(
      label: 'Téléphone du salon',
      focusNode: _phoneFocus,
      errorText: _errors['phone'],
      onChanged: (e164) {
        _phone = e164;
        setState(() => _errors.revalidate('phone', e164));
      },
    ),
    const SizedBox(height: AppTheme.spacingXS),
    Text(
      'Le numéro que vos clients appellent.',
      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
    ),
    const SizedBox(height: AppTheme.spacingM),
    AppTextField(
      controller: _addressController,
      focusNode: _addressFocus,
      label: 'Adresse',
      hint: 'Rue, quartier, repère',
      maxLines: 2,
      errorText: _errors['address'],
      onChanged: (v) => setState(() => _errors.revalidate('address', v)),
    ),
    const SizedBox(height: AppTheme.spacingM),
    InkWell(
      focusNode: _areaFocus,
      onTap: busy ? null : _pickCommune,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Commune (optionnel)',
          errorText: _errors['area'],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _communeName.isEmpty ? 'Choisir une commune' : _communeName,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: _communeName.isEmpty
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.expand_more, color: AppColors.textTertiary),
          ],
        ),
      ),
    ),
    const SizedBox(height: AppTheme.spacingXL),
    _heading('Votre identité de connexion'),
    const SizedBox(height: AppTheme.spacingXS),
    Text(
      'Elle vous servira à vous connecter à votre espace pro.',
      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
    ),
    const SizedBox(height: AppTheme.spacingM),
    // Above the first button that can create the account, on every path.
    const LegalConsentText(lead: 'En créant votre compte professionnel'),
    const SizedBox(height: AppTheme.spacingM),
    ...switch (_identity) {
      _Identity.carried => _carriedIdentity(busy),
      _Identity.options || _Identity.code => [
        AppButton(
          text: 'Continuer avec Google',
          type: AppButtonType.secondary,
          leading: const GoogleGLogo(),
          isLoading:
              _running == _Action.google ||
              (_running == _Action.own && _ownSalonFor == _kGoogle),
          onPressed: busy ? null : _google,
        ),
        const SizedBox(height: AppTheme.spacingL),
        _or(),
        const SizedBox(height: AppTheme.spacingL),
        ...(_identity == _Identity.code
            ? _codeStep(auth, busy)
            : _emailStep(busy)),
      ],
    },
    // §14 rule 3 + §15: an outcome that is no field's, in a live region.
    InlineFeedback(_formFault),
    if (_offerSignIn)
      AppButton(
        text: 'Se connecter',
        type: AppButtonType.text,
        onPressed: busy ? null : () => context.pop(),
      ),
  ];

  /// A section of the form: level 2 under the screen's title (§13.4).
  Widget _heading(String text) => Semantics(
    headingLevel: 2,
    child: Text(
      text,
      style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
    ),
  );

  Widget _or() => Row(
    children: [
      const Expanded(child: Divider(color: AppColors.divider)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingM),
        child: Text(
          'ou',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ),
      const Expanded(child: Divider(color: AppColors.divider)),
    ],
  );

  /// E3: the carried address, one button, and the way out of it.
  List<Widget> _carriedIdentity(bool busy) => [
    Text(
      'Compte : ${_carried?.email ?? ''}',
      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textPrimary),
    ),
    const SizedBox(height: AppTheme.spacingM),
    AppButton(
      text: 'Créer mon compte',
      isLoading: _running == _Action.create || _running == _Action.own,
      onPressed: busy ? null : _createWithCarried,
    ),
    const SizedBox(height: AppTheme.spacingS),
    AppButton(
      text: 'Utiliser une autre adresse',
      type: AppButtonType.text,
      onPressed: busy
          ? null
          : () => setState(() {
              _carried = null;
              _identity = _Identity.options;
              _formFault = null;
            }),
    ),
  ];

  List<Widget> _emailStep(bool busy) => [
    AppTextField(
      controller: _emailController,
      focusNode: _emailFocus,
      label: 'Votre e-mail',
      hint: 'exemple@email.com',
      keyboardType: TextInputType.emailAddress,
      errorText: _errors['email'],
      onChanged: (v) => setState(() => _errors.revalidate('email', v)),
    ),
    const SizedBox(height: AppTheme.spacingM),
    AppButton(
      text: 'Continuer avec e-mail',
      // §14 rule 5: disabled ONLY while a request runs.
      isLoading: _running == _Action.sendCode,
      onPressed: busy ? null : _sendCode,
    ),
  ];

  /// The sign-in's code step, cooldown included (§2.4 row 12).
  List<Widget> _codeStep(ProAuthProvider auth, bool busy) => [
    Text(
      'Entrez le code reçu par e-mail à ${_emailController.text.trim()}.',
      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: AppTheme.spacingL),
    AppTextField(
      controller: _codeController,
      focusNode: _codeFocus,
      label: 'Code à 6 chiffres',
      keyboardType: TextInputType.number,
      maxLength: 6,
      errorText: _errors['code'],
      onChanged: (v) => setState(() => _errors.revalidate('code', v)),
    ),
    if (auth.emailDevCode != null) ...[
      const SizedBox(height: AppTheme.spacingXS),
      Text(
        'Code (dev) : ${auth.emailDevCode}',
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
        textAlign: TextAlign.center,
      ),
    ],
    const SizedBox(height: AppTheme.spacingM),
    AppButton(
      text: 'Créer mon compte',
      isLoading:
          _running == _Action.create ||
          (_running == _Action.own && _ownSalonFor != _kGoogle),
      onPressed: busy ? null : _createWithCode,
    ),
    const SizedBox(height: AppTheme.spacingSM),
    AppButton(
      text: _resendCooldown > 0
          ? 'Renvoyer le code (${_resendCooldown}s)'
          : 'Renvoyer le code',
      type: AppButtonType.text,
      isLoading: _running == _Action.sendCode,
      onPressed: (busy || _resendCooldown > 0)
          ? null
          : () => _sendCode(resend: true),
    ),
    const SizedBox(height: AppTheme.spacingXS),
    AppButton(
      text: 'Changer d’e-mail',
      type: AppButtonType.text,
      onPressed: busy
          ? null
          : () => setState(() {
              _identity = _Identity.options;
              _errors.set('code', null);
              _formFault = null;
            }),
    ),
  ];
}
