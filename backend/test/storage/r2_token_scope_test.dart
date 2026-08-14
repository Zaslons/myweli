@Tags(['r2'])
library;

import 'dart:io';

import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

/// **Is the staging R2 token actually scoped to the staging buckets?**
///
/// This is the single load-bearing security property of staging's object
/// storage, and until now it was an instruction in a runbook. Bucket *names*
/// isolate nothing: `R2_BUCKET` decides which bucket the code addresses, and an
/// account-scoped token reads and writes **every** bucket in the account
/// regardless. So a staging run of the user-erasure path — which deletes KYC
/// documents by key — would delete PRODUCTION objects, and every log line would
/// say it was operating on staging.
///
/// "Apply to all buckets" is the default in Cloudflare's token screen. That is
/// the whole reason this file exists: the failure is one radio button, it
/// produces no error, and nothing else in the system can tell.
///
/// ## How it proves it
///
/// A presigned GET for a key that does not exist distinguishes the two cases
/// without needing list permission or writing anything:
///
///   · a bucket the token MAY reach → **404**, `NoSuchKey` — the key is absent
///   · a bucket the token may NOT reach → **403**, `AccessDenied`
///
/// **Both halves are asserted**, and that pairing is the point: a revoked or
/// mistyped credential is denied everywhere, so checking only the production
/// half would pass with a token that cannot do anything at all.
///
/// Signed with `R2StorageService` — the production class, built as the
/// composition root builds it. A bespoke signer here would prove something
/// about the test rather than about what ships.
///
///   R2_ACCOUNT_ID=… \
///   R2_ACCESS_KEY_ID=<staging> R2_SECRET_ACCESS_KEY=<staging> \
///     dart test --tags r2 test/storage/r2_token_scope_test.dart
///
/// Design: docs/design/infra-staging.md §2 · infra/cloudflare/90-staging-r2.sh
void main() {
  final env = Platform.environment;
  final account = env['R2_ACCOUNT_ID'];
  final keyId = env['R2_ACCESS_KEY_ID'];
  final secret = env['R2_SECRET_ACCESS_KEY'];

  if ([account, keyId, secret].any((v) => v == null || v.isEmpty)) {
    group(
      'R2 token scope (skipped — set R2_ACCOUNT_ID/ACCESS_KEY_ID/SECRET_ACCESS_KEY)',
      () => test('needs the staging credentials', () {}),
      skip: 'requires the staging R2 token',
    );
    return;
  }

  /// The three staging buckets the token is supposed to reach.
  const staging = [
    'myweli-uploads-staging',
    'myweli-kyc-private-staging',
    'myweli-deposits-private-staging',
  ];

  /// The three production buckets it must not. Named here rather than read from
  /// env on purpose — this list is the *assertion*, and a list supplied by the
  /// same environment that supplies the credential could be emptied to make the
  /// test pass.
  const production = [
    'myweli-uploads',
    'myweli-kyc-private',
    'myweli-deposits-private',
  ];

  final client = HttpClient();
  tearDownAll(client.close);

  /// Signs a GET for a key that will not exist and returns what R2 answered.
  ///
  /// Read-only and side-effect-free by construction: the key is never created,
  /// so this cannot leave residue in a production bucket even in the case where
  /// it turns out the token *can* reach one.
  Future<({int status, String body})> probe(String bucket) async {
    final r2 = R2StorageService(
      endpoint: 'https://$account.r2.cloudflarestorage.com',
      bucket: bucket,
      accessKeyId: keyId!,
      secretAccessKey: secret!,
      publicBaseUrl: 'https://example.invalid',
    );
    final url = r2.presignGet(
      key:
          'scope-probe/does-not-exist-${DateTime.now().microsecondsSinceEpoch}',
      bucket: StorageBucket.public,
    );
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final body = await res.transform(const SystemEncoding().decoder).join();
    return (status: res.statusCode, body: body);
  }

  group('the staging token REACHES every staging bucket', () {
    for (final bucket in staging) {
      test(bucket, () async {
        final r = await probe(bucket);
        expect(
          r.body,
          isNot(contains('AccessDenied')),
          reason:
              '$bucket refused the staging token. Either the bucket is missing '
              '(run infra/cloudflare/90-staging-r2.sh) or the token was scoped '
              'to fewer buckets than the three staging needs. '
              'Got ${r.status}: ${r.body}',
        );
        expect(
          r.status,
          404,
          reason:
              'expected 404 NoSuchKey for a key that does not exist — anything '
              'else means this probe is not measuring what it thinks. '
              'Got ${r.status}: ${r.body}',
        );
      });
    }
  });

  group('and CANNOT reach any production bucket', () {
    for (final bucket in production) {
      test(bucket, () async {
        final r = await probe(bucket);
        expect(
          r.status,
          isNot(404),
          reason:
              '**$bucket answered as if the token may address it.** The staging '
              'R2 token is account-scoped, not bucket-scoped, so staging can '
              'read and delete production objects — a staging run of the '
              'user-erasure path would destroy real KYC documents. Re-create '
              'the token with "Specify bucket(s)" and only the three staging '
              'buckets. Got ${r.status}: ${r.body}',
        );
        expect(
          r.status,
          403,
          reason:
              'expected 403 AccessDenied. Got ${r.status}: ${r.body} — if this '
              'is some third status, read it before assuming it is a refusal.',
        );
      });
    }
  });

  test('the two halves disagree — the probe can tell them apart', () {
    // Guard against the test that passes for the wrong reason. If every bucket
    // answered identically, both groups above could still be green under some
    // future assertion edit while proving nothing about scoping. Stating the
    // lists are disjoint and non-empty is the cheap half of that; the paired
    // 404/403 assertions above are the real half.
    expect(staging, isNotEmpty);
    expect(production, isNotEmpty);
    expect(staging.toSet().intersection(production.toSet()), isEmpty);
  });
}
