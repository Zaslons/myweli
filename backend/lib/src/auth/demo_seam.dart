/// The store-review demo account (T69).
///
/// **The credential is public by design** — it is printed into both stores'
/// review notes, read by Apple and Google staff. So this file is not a lock;
/// the security is the ROOM the credential opens: an ordinary provider
/// account owning one permanently-draft salon, with exactly two capabilities
/// subtracted (publish, team invitations) and everything else bounded by the
/// same ownership checks and rate limits as any account.
///
/// Design + threat model (T69): docs/design/backend-demo-review-account.md.
library;

import 'smoke_seam.dart' show constantTimeEquals;

/// The demo identity. `.test` is reserved by **RFC 2606 §2** and can never be
/// delegated in public DNS — the address can never receive mail and can never
/// be a real person's. A compile-time constant for the same reason the smoke
/// seam's suffix is one: there is nothing to misconfigure, and no value of
/// any environment variable can widen it to a real address.
const String kDemoProviderEmail = 'revue@myweli.test';

/// The app's OTP field demands exactly six digits (`Validators.otp`,
/// mobile-side), so the fixed code must be this shape or the reviewer cannot
/// type it. A configured code that is NOT this shape is treated as absent —
/// `DEMO_PROVIDER_CODE=test` cannot enable the seam.
final RegExp kDemoCodeShape = RegExp(r'^\d{6}$');

/// True only for the demo identity (trimmed, case-insensitive, EXACT match —
/// never a suffix test: the identity is one address, not a family).
bool isDemoIdentity(String email) =>
    email.trim().toLowerCase() == kDemoProviderEmail;

/// Whether this request signs in the demo account.
///
/// False means the seam is *absent*, not merely closed: with
/// `DEMO_PROVIDER_CODE` unset (or mis-shaped) the demo identity behaves
/// exactly like any unknown address, which is the off switch if the account
/// is ever abused between review cycles.
bool demoLoginAllowed({
  required String? configuredCode,
  required String email,
  required String code,
}) {
  final configured = configuredCode?.trim();
  if (configured == null || !kDemoCodeShape.hasMatch(configured)) return false;
  if (!isDemoIdentity(email)) return false;
  // Constant-time, though the code is public by design: the habit costs one
  // line and removes the timing question from every future audit.
  return constantTimeEquals(configured, code.trim());
}

/// Injectable wrapper, the [SmokeSeam] shape: a distinct type for
/// `provider<T>`, stubbable in handler tests.
class DemoSeam {
  const DemoSeam(this.code);

  /// `DEMO_PROVIDER_CODE`, or null when the seam is absent.
  final String? code;

  bool allows({required String email, required String otp}) =>
      demoLoginAllowed(configuredCode: code, email: email, code: otp);

  /// For the boot-time warning — a sign-in path quietly left enabled is the
  /// failure mode worth engineering against, so it announces itself in the
  /// deploy log exactly as the smoke seam does.
  bool get isActive => kDemoCodeShape.hasMatch(code?.trim() ?? '');
}
