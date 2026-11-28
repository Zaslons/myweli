import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:test/test.dart';

/// Marks Pro account [accountId]'s address unproven: the state of a row older
/// than the auth overhaul (`email_verified` added with `DEFAULT false`,
/// `migrations.dart:556`). Each twin does it its own way: the in-memory twin
/// through a test seam, Postgres by SQL.
typedef PlantUnprovenPro =
    Future<void> Function(ProviderAuthRepository repo, String accountId);

/// A Pro account's Google or Apple link, run against BOTH twins: in memory
/// (`pro_auth_contracts_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself.
///
/// docs/design/auth-store-twins.md §5.1, §5.5 (B16.4, decisions 284, 287).
/// A link is set only where the account has none for that provider, or
/// already has this one; another identity asserting the address is refused
/// with `social_link_taken`, never relinked; an address reaches only an
/// account that proved it; the result is the row as written.
///
/// Each case says, in brackets, the rule it pins, so a red names its reason.
/// Addresses are unique per run, in the RFC 2606 `.test` TLD.
void proSocialLinkContract({
  required ProviderAuthRepository Function() repo,
  required PlantUnprovenPro plantUnproven,
}) {
  final run = DateTime.now().microsecondsSinceEpoch;
  var n = 0;
  String address(String who) => '$who.${run}_${n++}@b164.test';
  String sub(String who) => '$who-${run}_${n++}';

  Future<ProviderAccount> signUpWith(
    ProviderAuthRepository r,
    String provider,
    String email,
    String s,
  ) async {
    final v = await r.register(
      businessName: 'B16.4',
      businessType: 'salon',
      phoneNumber: '+2250700000001',
      email: email,
      authProvider: provider,
      googleSub: provider == 'google' ? s : null,
      appleSub: provider == 'apple' ? s : null,
    );
    expect(v.ok, isTrue, reason: 'the premise: the sign-up failed: ${v.error}');
    return v.provider!;
  }

  Future<ProviderAccount> signUpByCode(
    ProviderAuthRepository r,
    String email,
  ) async {
    final code = (await r.requestEmailOtp(email)).devCode!;
    final v = await r.register(
      businessName: 'B16.4',
      businessType: 'salon',
      phoneNumber: '+2250700000001',
      email: email,
      authProvider: 'email',
      emailCode: code,
    );
    expect(v.ok, isTrue, reason: 'the premise: the sign-up failed: ${v.error}');
    return v.provider!;
  }

  Future<ProviderVerifyResult> social(
    ProviderAuthRepository r,
    String provider,
    String s, {
    String? email,
    bool verified = true,
  }) => r.loginWithSocial(
    provider: provider,
    sub: s,
    email: email,
    emailVerified: verified,
  );

  String? linkOf(ProviderAccount a, String provider) =>
      provider == 'google' ? a.googleSub : a.appleSub;

  for (final provider in ['google', 'apple']) {
    test('[never relinked] $provider: another identity asserting X verified '
        'is refused, and A keeps its link', () async {
      final r = repo();
      final x = address('nr-$provider');
      final first = sub('first');
      final a = await signUpWith(r, provider, x, first);

      final second = await social(r, provider, sub('second'), email: x);
      expect(
        second.ok,
        isFalse,
        reason: '[never relinked] another $provider identity got into A',
      );
      expect(second.error, 'social_link_taken', reason: '[never relinked]');
      expect(second.tokens, isNull);
      expect(
        linkOf((await r.accountById(a.id))!, provider),
        first,
        reason: "[never relinked] A's link must stay the first",
      );

      final old = await social(r, provider, first, email: address('moved'));
      expect(
        old.ok,
        isTrue,
        reason:
            '[never relinked] the first identity still signs in, '
            'even asserting another address',
      );
      expect(old.provider!.id, a.id);
    });
  }

  test('[links an empty column] an e-mail account, then Google with X '
      'verified: linked, and the result shows it (B-P1-d)', () async {
    final r = repo();
    final x = address('empty');
    final g = sub('g');
    final a = await signUpByCode(r, x);

    final v = await social(r, 'google', g, email: x);
    expect(v.ok, isTrue, reason: '[links an empty column] ${v.error}');
    expect(v.provider!.id, a.id);
    expect(
      v.provider!.googleSub,
      g,
      reason: '[links an empty column] the result is the row as written',
    );
    expect((await r.accountById(a.id))!.googleSub, g);
    final bySub = await social(r, 'google', g);
    expect(bySub.provider!.id, a.id, reason: 'the link signs in by its sub');
  });

  test('[same sub again] a link, then the same sub asserting X: signed in, '
      'not refused (a control)', () async {
    final r = repo();
    final x = address('same');
    final g = sub('g');
    final a = await signUpWith(r, 'google', x, g);
    final v = await social(r, 'google', g, email: x);
    expect(v.ok, isTrue, reason: '[same sub again] ${v.error}');
    expect(v.provider!.id, a.id);
  });

  test('[unverified] an address the provider does not vouch for links '
      'nothing (T35, a control)', () async {
    final r = repo();
    final x = address('unv');
    final a = await signUpByCode(r, x);
    final v = await social(r, 'apple', sub('ap'), email: x, verified: false);
    expect(v.error, 'provider_not_found');
    expect((await r.accountById(a.id))!.appleSub, isNull);
  });

  test('[unproven holder] an account holding X unproven is reached by X '
      'neither with Google nor with a code (decision 287)', () async {
    final r = repo();
    final x = address('unproven');
    final a = await signUpByCode(r, x);
    await plantUnproven(r, a.id);

    final v = await social(r, 'google', sub('g'), email: x);
    expect(
      v.error,
      'provider_not_found',
      reason:
          '[unproven holder] a verified Google X reached an account '
          'that never proved X',
    );
    expect((await r.accountById(a.id))!.googleSub, isNull);

    final code = (await r.requestEmailOtp(x)).devCode!;
    final c = await r.verifyEmailOtp(x, code);
    expect(
      c.error,
      'provider_not_found',
      reason:
          '[unproven holder] a code on X reached an account that '
          'never proved X',
    );
    // The dead end, pinned so it stays visible: the sign-up refuses X too.
    // B16.4a deploys only once decision 287's read counts no such account
    // (docs/design/auth-store-twins.md §9).
    final up = await r.register(
      businessName: 'B16.4',
      businessType: 'salon',
      phoneNumber: '+2250700000001',
      email: x,
      authProvider: 'email',
      emailCode: code,
    );
    expect(
      up.error,
      'provider_exists',
      reason: '[unproven holder] the dead end',
    );
  });
}
