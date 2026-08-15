import 'dart:convert';
import 'dart:io';

import 'package:myweli_backend/src/upload_verification_service.dart';
import 'package:test/test.dart';

/// The offline half of the R2 configuration check.
///
/// `infra/cloudflare/95-verify-r2.sh` compares the **manifest to the live
/// account**. This compares the **manifest to the code**, and the two
/// directions are both needed: a manifest that has drifted from what the
/// backend actually does would let the script report a healthy account while
/// the application depends on something else entirely. Only this half can run
/// in CI — the other needs a Cloudflare identity CI must not have.
void main() {
  final root = Directory.current.path.endsWith('backend')
      ? '${Directory.current.path}/..'
      : Directory.current.path;

  final manifest =
      jsonDecode(
            File('$root/infra/cloudflare/r2-manifest.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  Map<String, dynamic> env(String name) =>
      (manifest['environments'] as Map<String, dynamic>)[name]
          as Map<String, dynamic>;
  List<String> buckets(String name) =>
      (env(name)['buckets'] as List).cast<String>();

  group('the manifest agrees with the code', () {
    test('the expiring prefix IS the one the backend writes under', () {
      // The single fact the whole promotion design rests on. If the signer's
      // prefix ever changed and the manifest did not, the checker would go on
      // confirming a rule that collects nothing, and `pending/` would grow
      // forever while every doc claimed otherwise.
      expect(manifest['lifecycle']['prefix'], kPendingPrefix);
    });

    test('the bucket names match the ones the scope test pins', () {
      // `r2_token_scope_test.dart` holds both lists as literals precisely so a
      // credential cannot supply its own idea of what it should reach. Two
      // literal lists in two files is two chances to disagree, so they are
      // compared rather than trusted.
      final scope = File(
        '$root/backend/test/storage/r2_token_scope_test.dart',
      ).readAsStringSync();
      for (final b in [...buckets('production'), ...buckets('staging')]) {
        expect(
          scope,
          contains("'$b'"),
          reason:
              '$b is in the R2 manifest but not in the token-scope test — one '
              'of the two has been edited alone',
        );
      }
    });

    test('the staging script provisions exactly the staging buckets', () {
      final script = File(
        '$root/infra/cloudflare/90-staging-r2.sh',
      ).readAsStringSync();
      for (final b in buckets('staging')) {
        expect(
          script,
          contains(b),
          reason: '$b is not provisioned by 90-staging-r2.sh',
        );
      }
      for (final b in buckets('production')) {
        expect(
          script,
          isNot(contains('"$b"')),
          reason:
              'the STAGING provisioning script names the production bucket $b. '
              'That script creates buckets and sets lifecycle rules.',
        );
      }
    });
  });

  group('the manifest is internally coherent', () {
    test('the public bucket belongs to its own environment', () {
      for (final name in ['production', 'staging']) {
        expect(
          buckets(name),
          contains(env(name)['publicBucket']),
          reason: "$name's publicBucket is not in its own bucket list",
        );
      }
    });

    test('the two environments share no bucket', () {
      // The failure that would not look like one: a production bucket listed
      // under staging reads as a copy-paste, and makes the checker bless a
      // staging deploy pointed at production objects.
      expect(
        buckets('production').toSet().intersection(buckets('staging').toSet()),
        isEmpty,
      );
    });

    test('every staging bucket is named as such, and no production one is', () {
      for (final b in buckets('staging')) {
        expect(b, endsWith('-staging'));
      }
      for (final b in buckets('production')) {
        expect(b, isNot(endsWith('-staging')));
      }
    });

    test('CORS requires the method the upload actually performs', () {
      // R2 does not implement presigned POST (501), so the browser uploads with
      // a raw PUT. A manifest that forgot PUT would pass against a bucket that
      // blocks every upload.
      expect(
        (manifest['cors']['requiredMethods'] as List).cast<String>(),
        contains('PUT'),
      );
      expect(manifest['cors']['requiredHeader'], 'content-type');
    });
  });

  group('the checker cannot write', () {
    final checker = File(
      '$root/infra/cloudflare/95-verify-r2.sh',
    ).readAsStringSync();

    test('it names no mutating wrangler verb', () {
      // The header promises read-only. This is what makes that a property
      // rather than a comment — and it matters because the thing being pointed
      // at is production, already configured by hand, where a provisioning run
      // would add a SECOND lifecycle rule for the same prefix (the staging
      // script decides idempotency by its own rule name, and production's is
      // called something else).
      //
      // The phrases are wrangler's ACTUAL subcommand paths, matched whole. The
      // first draft of this list checked for `r2 lifecycle add` and friends —
      // but wrangler spells it `r2 bucket lifecycle add`, so the guard could
      // not fire, and a mutation test that appended exactly that line watched
      // it pass. A read-only guarantee enforced by a check that cannot match
      // is worth less than no guarantee, because it is believed.
      //
      // Matched anywhere in the file, comments included: a commented-out
      // provisioning command is a line someone uncomments at 2am.
      const mutating = [
        'r2 bucket create',
        'r2 bucket delete',
        'r2 bucket cors set',
        'r2 bucket cors delete',
        'r2 bucket lifecycle add',
        'r2 bucket lifecycle set',
        'r2 bucket lifecycle remove',
        'r2 object put',
        'r2 object delete',
      ];
      for (final verb in mutating) {
        expect(
          checker,
          isNot(contains(verb)),
          reason:
              '95-verify-r2.sh contains `$verb`. It is the tool pointed at '
              'PRODUCTION on the strength of being unable to change anything.',
        );
      }

      // And the list itself is pinned against the provisioning script, so a
      // wrangler rename cannot quietly empty it: every verb 90-staging-r2.sh
      // actually uses must appear above.
      final provisioner = File(
        '$root/infra/cloudflare/90-staging-r2.sh',
      ).readAsStringSync();
      for (final verb in ['r2 bucket create', 'r2 bucket lifecycle add']) {
        expect(
          provisioner,
          contains(verb),
          reason:
              'the provisioning script no longer uses `$verb`, so the '
              'read-only guard above is matching a phrase wrangler has '
              'stopped using — re-derive the list from its --help',
        );
      }
    });

    test('it reads the manifest rather than hardcoding the answer', () {
      // A checker carrying its own copy of the expectations would pass while
      // the manifest — the thing the rest of this file verifies — said
      // something else entirely.
      expect(checker, contains(r'jq -r'));
      expect(checker, contains('r2-manifest.json'));
      for (final b in buckets('production')) {
        expect(
          checker,
          isNot(contains(b)),
          reason:
              '$b is hardcoded in the checker instead of read from the '
              'manifest, so the manifest is no longer the source of truth',
        );
      }
    });

    test('it fails loudly rather than skipping when it cannot check', () {
      // `set -euo pipefail` plus an explicit exit: a checker that swallows a
      // wrangler error and reports success is worse than none.
      expect(checker, contains('set -euo pipefail'));
      expect(checker, contains('exit 1'));
    });
  });
}
