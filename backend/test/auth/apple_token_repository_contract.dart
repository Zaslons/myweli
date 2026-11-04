import 'package:myweli_backend/src/auth/apple_tokens.dart';
import 'package:test/test.dart';

/// The contract of [AppleTokenRepository] (B6.7), run against BOTH twins —
/// in memory (`apple_tokens_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself: each caller
/// runs it inside its own group.
///
/// [repo] builds the repository under test; [id] makes an account id unique
/// to this run (the Postgres database outlives it).
void appleTokenRepositoryContract({
  required AppleTokenRepository Function() repo,
  required String Function(String name) id,
}) {
  test('kept, then listed', () async {
    final r = repo();
    final a = id('kept');
    await r.keep(
      kind: 'user',
      accountId: a,
      clientId: 'ci.myweli.app',
      refreshToken: 'rt-1',
    );
    expect(await r.listFor(kind: 'user', accountId: a), [
      (clientId: 'ci.myweli.app', refreshToken: 'rt-1'),
    ]);
  });

  test('the same client again replaces — one token per client', () async {
    final r = repo();
    final a = id('replaced');
    for (final t in ['rt-1', 'rt-2']) {
      await r.keep(
        kind: 'user',
        accountId: a,
        clientId: 'ci.myweli.app',
        refreshToken: t,
      );
    }
    expect(await r.listFor(kind: 'user', accountId: a), [
      (clientId: 'ci.myweli.app', refreshToken: 'rt-2'),
    ]);
  });

  test('two clients (the app and the web) → two tokens', () async {
    final r = repo();
    final a = id('two');
    await r.keep(
      kind: 'user',
      accountId: a,
      clientId: 'ci.myweli.app',
      refreshToken: 'rt-app',
    );
    await r.keep(
      kind: 'user',
      accountId: a,
      clientId: 'com.myweli.web',
      refreshToken: 'rt-web',
    );
    expect(
      await r.listFor(kind: 'user', accountId: a),
      unorderedEquals([
        (clientId: 'ci.myweli.app', refreshToken: 'rt-app'),
        (clientId: 'com.myweli.web', refreshToken: 'rt-web'),
      ]),
    );
  });

  test(
    'the kinds never mix — the same id string as a user and a Pro',
    () async {
      final r = repo();
      final a = id('kinds');
      await r.keep(
        kind: 'user',
        accountId: a,
        clientId: 'ci.myweli.app',
        refreshToken: 'rt-user',
      );
      await r.keep(
        kind: 'provider',
        accountId: a,
        clientId: 'ci.myweli.app',
        refreshToken: 'rt-pro',
      );
      expect(await r.listFor(kind: 'user', accountId: a), [
        (clientId: 'ci.myweli.app', refreshToken: 'rt-user'),
      ]);
      await r.deleteFor(kind: 'provider', accountId: a);
      expect(await r.listFor(kind: 'provider', accountId: a), isEmpty);
      expect(await r.listFor(kind: 'user', accountId: a), hasLength(1));
    },
  );

  test('deleteFor erases that account only', () async {
    final r = repo();
    final a = id('gone');
    final b = id('stays');
    for (final acc in [a, b]) {
      await r.keep(
        kind: 'user',
        accountId: acc,
        clientId: 'ci.myweli.app',
        refreshToken: 'rt-$acc',
      );
    }
    await r.deleteFor(kind: 'user', accountId: a);
    expect(await r.listFor(kind: 'user', accountId: a), isEmpty);
    expect(await r.listFor(kind: 'user', accountId: b), hasLength(1));
  });

  test('nothing kept → an empty list; deleting nothing is fine', () async {
    final r = repo();
    final a = id('none');
    expect(await r.listFor(kind: 'user', accountId: a), isEmpty);
    await r.deleteFor(kind: 'user', accountId: a);
  });
}
