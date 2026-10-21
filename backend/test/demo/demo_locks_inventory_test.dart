import 'dart:io';

import 'package:test/test.dart';

/// The demo account's locks, counted (T69).
///
/// The header of `lib/src/auth/demo_seam.dart` said « exactly two
/// capabilities subtracted » for six weeks after there were four. A sentence
/// in a file nobody opens when adding a lock is not a mechanism — so the
/// list is derived from the code here, and the header is checked against it.
///
/// It counts lock SITES and names the method that holds each one. The first
/// version compared the set of FILES: a sixth lock added inside a service
/// already listed left it green, with the header still saying five.
///
/// What this file cannot see, said plainly:
///
/// - a lock answered under another code, or returned in another shape than
///   the record `error: 'demo_account_locked'` — the third test below is the
///   guard on that class: it pins the files that read the demo identity at
///   all;
/// - a destructive action that has NO lock yet. It counts the locks that
///   exist; it does not find the ones that are missing;
/// - an identity delete that is neither a call to `deleteAccount(` nor the
///   SQL `DELETE FROM provider_users` — the in-memory repository's own
///   `Map.remove`, a table name built by interpolation, an operator working
///   in the database.
///
/// Design: docs/design/demo-account-deletion-lock.md §9.
void main() {
  /// `//` to end of line and `/* … */`. The sentences ABOUT a lock live in
  /// comments, and two guards in this repo have already matched a string
  /// that existed only there.
  String stripComments(String source) => source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  List<File> dartFilesUnder(String dir) =>
      Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  /// Everything the server is built from, and everything an operator can
  /// run against its database: `tool/` is where a purge or cleanup script
  /// would be written, and `main.dart` is the entry point.
  List<File> serverSources() => [
    for (final dir in const ['lib', 'routes', 'tool']) ...dartFilesUnder(dir),
    File('main.dart'),
  ];

  /// Service file → the method that holds its lock, and the route the seam
  /// header names for it.
  const locks = <String, ({String holder, String route})>{
    'lib/src/salon_provisioning_service.dart': (
      holder: 'SalonProvisioningService.publish',
      route: 'POST /providers/{id}/publish',
    ),
    'lib/src/access/team_service.dart': (
      holder: 'TeamService.invite',
      route: 'POST /me/provider/members',
    ),
    'lib/src/subscription/salon_subscription_service.dart': (
      holder: 'SalonSubscriptionService.chooseOffer',
      route: 'PUT /providers/{id}/subscription',
    ),
    'lib/src/access/salon_directory_service.dart': (
      holder: 'SalonDirectoryService.addSalon',
      route: 'POST /me/salons',
    ),
    'lib/src/provider_account_service.dart': (
      holder: 'ProviderAccountService.deleteAccount',
      route: 'DELETE /me/provider',
    ),
  };

  final answering = RegExp(r'''error:\s*'demo_account_locked'\s*[,)]''');
  final classDeclaration = RegExp(
    r'^(?:(?:abstract|final|base|sealed|interface) )*class (\w+)',
    multiLine: true,
  );

  /// A class member's declaration. `dart format` puts members at exactly two
  /// spaces and every statement deeper, so a two-space line that reaches an
  /// identifier followed by `(` opens a member, and the identifier is its
  /// name. (A member with no parenthesis — a getter — is not seen, and a
  /// site inside one would be attributed to the member above it.)
  final memberDeclaration = RegExp(
    r'^  (?:[A-Za-z_][^\n]*?)?\b(\w+)\(',
    multiLine: true,
  );

  /// `Class.member` enclosing [offset] in comment-stripped [source].
  String holderAt(String source, int offset) {
    final before = source.substring(0, offset);
    final cls = classDeclaration.allMatches(before).lastOrNull?.group(1);
    final member = memberDeclaration.allMatches(before).lastOrNull?.group(1);
    return '${cls ?? '?'}.${member ?? '?'}';
  }

  test('every lock SITE is listed here — one per service, in the method the '
      'list names', () {
    final found = <String, List<String>>{};
    for (final f in dartFilesUnder('lib/src')) {
      final source = stripComments(f.readAsStringSync());
      final sites = [
        for (final m in answering.allMatches(source)) holderAt(source, m.start),
      ];
      if (sites.isNotEmpty) found[f.path] = sites;
    }
    expect(
      found,
      {
        for (final lock in locks.entries) lock.key: [lock.value.holder],
      },
      reason:
          'a demo lock was added, removed or moved — a new file, a second '
          'site in a listed service, or another method. Update `locks` '
          'above, the header of lib/src/auth/demo_seam.dart, BACKEND.md T69 '
          'and the store review notes (docs/design/app-store-forms.md §8) '
          'together.',
    );
  });

  test('the seam header names every one of them — route and method — and '
      'says how many', () {
    // The header IS a comment — here the comment is the thing under test.
    final source = File('lib/src/auth/demo_seam.dart').readAsStringSync();
    final header = source.substring(0, source.indexOf('library;'));
    final prose = header
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^///\s?'), ''))
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    for (final lock in locks.values) {
      expect(
        prose,
        contains('`${lock.route}`'),
        reason: 'the header omits ${lock.route}',
      );
      // The name the first test READ in the code: a method the header
      // invents (it said `SalonDirectoryService.createSalon`, which does
      // not exist) is not in this list.
      expect(
        prose,
        contains('`${lock.holder}`'),
        reason: 'the header does not name ${lock.holder}',
      );
    }
    final named = RegExp(r'\(`(\w+\.\w+)`\)').allMatches(prose);
    expect(
      named.map((m) => m.group(1)).toSet(),
      locks.values.map((l) => l.holder).toSet(),
      reason: 'the header names a method that holds no lock',
    );
    const words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six'];
    expect(
      prose,
      contains('exactly ${words[locks.length]} capabilities subtracted'),
    );
  });

  test('the demo identity is read in a known set of files — a lock built in '
      'another shape shows up here', () {
    // The first test recognises a lock by the record it returns. A refusal
    // written in a route (`jsonError(…, 'demo_account_locked')`), or under
    // another code, has a different shape — but it still has to ask whether
    // the caller is the demo identity, and there are two ways to ask.
    final reads = RegExp(r'\bisDemoIdentity\(|\bkDemoProviderEmail\b');
    final found = [
      for (final f in serverSources())
        if (reads.hasMatch(stripComments(f.readAsStringSync()))) f.path,
    ];
    expect(
      found.toSet(),
      {
        // The five locks.
        ...locks.keys,
        // The identity itself, and the sign-in seam.
        'lib/src/auth/demo_seam.dart',
        // The weekly reset: finds its target, and refuses a salon that is
        // not demo-owned.
        'lib/src/demo/demo_reset_service.dart',
        // The boot warning when the seam is active in production.
        'lib/src/dependencies.dart',
        // The OTP request: no code is minted or mailed for the demo address.
        'routes/auth/provider/email/otp/request.dart',
      },
      reason:
          'a new file distinguishes the demo identity. If it refuses an '
          'action, it is a lock: it belongs in the SERVICE, in `locks` '
          'above and in the seam header. If it does not, list it here with '
          'what it does.',
    );
  });

  test('the identity delete has ONE caller — the service that holds the '
      'lock — and ONE statement', () {
    // `ProviderAuthRepository.deleteAccount` erases the account and every
    // session. A second caller — an admin route, a cleanup job, a script
    // under tool/ — would delete the demo identity without ever meeting
    // the lock.
    final mentions = [
      for (final f in serverSources())
        if (stripComments(f.readAsStringSync()).contains('deleteAccount('))
          f.path,
    ];
    expect(
      mentions.toSet(),
      {
        // The interface and its in-memory twin, then the Postgres twin.
        'lib/src/auth/provider_auth_repository.dart',
        'lib/src/db/postgres_provider_auth_repository.dart',
        // The service: its own method, and the one call to the repository.
        'lib/src/provider_account_service.dart',
        // The routes: they call the SERVICE — « Supprimer mon compte », and
        // the public accept discarding the account it made when the
        // invitation died in between (docs/design/backend-integrity-batch6.md
        // §2.2).
        'routes/me/provider/index.dart',
        'routes/auth/provider/invitations/accept.dart',
      },
      reason:
          'a new caller of deleteAccount( — it must go through '
          'ProviderAccountService, or apply the demo lock itself '
          '(docs/design/demo-account-deletion-lock.md §5).',
    );
    final service = stripComments(
      File('lib/src/provider_account_service.dart').readAsStringSync(),
    );
    expect(
      RegExp(r'_auth\s*\.deleteAccount\(').allMatches(service),
      hasLength(1),
      reason: 'one identity delete in the service',
    );
    // The route's only mention is the call to the SERVICE — whether the
    // lock then answers first is what the service tests observe.
    final route = stripComments(
      File('routes/me/provider/index.dart').readAsStringSync(),
    );
    expect(
      RegExp(r'deleteAccount\(').allMatches(route),
      hasLength(1),
      reason: 'one deletion call in the route',
    );
    expect(
      route,
      matches(RegExp(r'read<ProviderAccountService>\(\)\s*\.deleteAccount\(')),
    );

    // And the statement itself. A method under another name — a
    // `purgeAccount` in any repository — is not a caller of
    // `deleteAccount(`, and deletes the same row. Quotes are allowed
    // between the words: adjacent string literals concatenate.
    final rowDelete = RegExp(
      r'''delete\s+from[\s'"]+provider_users\b''',
      caseSensitive: false,
    );
    final statements = <String, int>{};
    for (final f in serverSources()) {
      final n = rowDelete
          .allMatches(stripComments(f.readAsStringSync()))
          .length;
      if (n > 0) statements[f.path] = n;
    }
    expect(
      statements,
      {'lib/src/db/postgres_provider_auth_repository.dart': 1},
      reason:
          'a second `DELETE FROM provider_users` — the demo identity can be '
          'erased without meeting the lock in ProviderAccountService.',
    );
  });
}
