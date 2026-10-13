import 'dart:io';

import 'package:test/test.dart';

/// The demo account's locks, counted (T69).
///
/// The header of `lib/src/auth/demo_seam.dart` said « exactly two
/// capabilities subtracted » for six weeks after there were four. A sentence
/// in a file nobody opens when adding a lock is not a mechanism — so the
/// list is derived from the code here, and the header is checked against it.
///
/// What this file cannot see, said plainly: a lock answered under another
/// code or built in another shape than `error: 'demo_account_locked'`, and
/// a destructive action that has NO lock yet. It counts the locks that
/// exist; it does not find the ones that are missing.
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

  /// Service file → the route the seam header names for it.
  const locks = <String, String>{
    'lib/src/salon_provisioning_service.dart': 'POST /providers/{id}/publish',
    'lib/src/access/team_service.dart': 'POST /me/provider/members',
    'lib/src/subscription/salon_subscription_service.dart':
        'PUT /providers/{id}/subscription',
    'lib/src/access/salon_directory_service.dart': 'POST /me/salons',
    'lib/src/provider_account_service.dart': 'DELETE /me/provider',
  };

  test('the services that answer demo_account_locked are exactly the ones '
      'listed here', () {
    final answering = RegExp(r'''error:\s*'demo_account_locked'\s*[,)]''');
    final found = [
      for (final f in dartFilesUnder('lib/src'))
        if (answering.hasMatch(stripComments(f.readAsStringSync()))) f.path,
    ];
    expect(
      found.toSet(),
      locks.keys.toSet(),
      reason:
          'a demo lock was added or removed. Update `locks` above, the '
          'header of lib/src/auth/demo_seam.dart, BACKEND.md T69 and the '
          'store review notes (docs/design/app-store-forms.md §8) together.',
    );
  });

  test('the seam header names every one of them, and says how many', () {
    // The header IS a comment — here the comment is the thing under test.
    final source = File('lib/src/auth/demo_seam.dart').readAsStringSync();
    final header = source.substring(0, source.indexOf('library;'));
    final prose = header
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^///\s?'), ''))
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    for (final route in locks.values) {
      expect(prose, contains('`$route`'), reason: 'the header omits $route');
    }
    const words = ['zero', 'one', 'two', 'three', 'four', 'five', 'six'];
    expect(
      prose,
      contains('exactly ${words[locks.length]} capabilities subtracted'),
    );
  });

  test('the identity delete has ONE caller: the service that holds the '
      'lock', () {
    // `ProviderAuthRepository.deleteAccount` erases the account and every
    // session. A second caller — an admin route, a cleanup job — would
    // delete the demo identity without ever meeting the lock.
    final mentions = [
      for (final dir in const ['lib', 'routes'])
        for (final f in dartFilesUnder(dir))
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
        // The route: calls the SERVICE.
        'routes/me/provider/index.dart',
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
  });
}
