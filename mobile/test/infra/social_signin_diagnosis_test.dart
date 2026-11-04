import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every social sign-in failure says WHICH failure it was — and still says
/// nothing about who.
///
/// ## Why this file exists
///
/// `mobile-external-testing.md` §5.1 claimed an unregistered Play App Signing
/// SHA-1 made Google sign-in fail *silently*: that Credential Manager returns
/// `canceled`, that the app could not tell it from a dismissal, and that the
/// button did nothing. All three were false. `canceled` has one source,
/// `GetCredentialCancellationException` — a real user dismissal — and a missing
/// credential arrives as `NoCredentialException`, which `authenticate()`
/// (`throwForNoAuth: true`) maps to `unknownError`. The user has always seen
/// « Connexion Google impossible. »
///
/// What was actually missing is the other half: five distinct exception codes
/// collapsed into one opaque `google_failed` across **six** call sites — the
/// consumer login, the pro login and the pro email-OTP registration — so a
/// misconfigured SHA-1, a network blip and an unsupported device were
/// indistinguishable in telemetry.
///
/// **Four since 2026-10-26**: the Pro app no longer registers a business
/// (App Store 3.1.1 — docs/design/pro-app-login-only.md), so the two
/// registration paths (Google, Apple) left with it. The consumer and Pro
/// LOGINS remain, each with Google and Apple.
///
/// A grep rather than a call, because none of the four paths is reachable from a
/// test: they all enter the real `GoogleSignIn.instance` / `SignInWithApple`
/// plugin, which needs a platform channel. Same reasoning as
/// `ios_google_client_test.dart`.
void main() {
  final source = File(
    'lib/services/api/api_auth_service.dart',
  ).readAsStringSync();

  /// Comments stripped BEFORE matching. Four guards in this repo have gone
  /// green against their own explanatory comment, one of them written the same
  /// day the other three were fixed.
  final code = source
      .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

  int count(String needle) => needle.allMatches(code).length;

  test('the walk finds the sign-in paths at all', () {
    // Vacuity guard: every assertion below counts occurrences, so a source
    // file that failed to load, or a refactor that moved these elsewhere,
    // would satisfy all of them with zero.
    expect(
      count('.canceled)'),
      greaterThanOrEqualTo(4),
      reason:
          'expected the four social catch arms; the file or the '
          'comment-stripper is wrong',
    );
  });

  test('all eight failure paths report which failure it was', () {
    // Four typed arms + four bare `catch (_)`. One definition is not a call.
    expect(count('_reportSignInFailure('), 9);
  });

  test('the typed arms report the real code, not a hardcoded string', () {
    // The two-assertion pattern: that it reports at all, AND that what it
    // reports is the variable. `_reportSignInFailure('google', 'google')`
    // would satisfy the count above and carry no information.
    expect(
      count("_reportSignInFailure('google', e.code.name)") +
          count("_reportSignInFailure('apple', e.code.name)"),
      4,
    );
    expect(count("'non_plugin_error')"), 4);
  });

  test('a user closing the sheet is never reported', () {
    // A cancel is not a failure, and reporting it would bury the real ones.
    // Match the guard block itself: nothing may sit between the `.canceled`
    // test and its closing brace except the cancelled return.
    final cancelBlocks = RegExp(
      r'if \(e\.code == \w+\.canceled\) \{(.*?)\n      \}',
      dotAll: true,
    ).allMatches(code);
    expect(cancelBlocks.length, 4, reason: 'the four cancel guards');
    for (final b in cancelBlocks) {
      expect(b.group(1), isNot(contains('_reportSignInFailure')));
    }
  });

  test('nothing free-form is ever reported', () {
    // The decision this pins: only the enum name leaves the device. `_scrub`
    // nulls breadcrumbs and `extra` because free-form strings cannot be kept
    // PII-free as screens are added, and an exception description is exactly
    // such a string. A denial is worth nothing without a test that fails when
    // the denied thing appears.
    expect(code, isNot(contains('e.description')));
    expect(code, isNot(contains('e.details')));
  });
}
