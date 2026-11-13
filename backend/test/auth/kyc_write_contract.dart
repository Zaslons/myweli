import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:test/test.dart';

/// The contract of [ProviderAuthRepository.submitKyc] — a compare under the
/// row lock (B0.22 — docs/design/pro-deletion-erase-gaps.md §3.2) — run
/// against BOTH twins: the in-memory one (`kyc_test.dart`) and Postgres
/// (`db/postgres_repositories_test.dart`). Not a test file itself: each
/// caller runs it inside its own group.
///
/// [repo] builds the repository under test; [account] registers a fresh
/// provider account in it and returns its id.
void kycWriteContract({
  required ProviderAuthRepository Function() repo,
  required Future<String> Function(ProviderAuthRepository r) account,
}) {
  Map<String, dynamic> doc(String key) => {
    'type': 'idCard',
    'key': key,
    'submittedAt': '2030-06-26T09:00:00.000Z',
  };

  Future<List<String>> rowKeys(ProviderAuthRepository r, String id) async =>
      kycKeysOf((await r.accountById(id))!.kycDocs);

  test('a write returns the PREVIOUS keys — none the first time', () async {
    final r = repo();
    final id = await account(r);
    final a = 'kyc/$id/a.jpg';
    final b = 'kyc/$id/b.jpg';
    final c = 'kyc/$id/c.jpg';

    final first = await r.submitKyc(id, [doc(a), doc(b)]);
    expect(first.refused, isFalse);
    expect(first.lockedKeys, isEmpty);
    expect(kycKeysOf(first.account!.kycDocs), [a, b]);

    final second = await r.submitKyc(id, [doc(a), doc(c)], passThrough: {a});
    expect(second.refused, isFalse);
    expect(second.lockedKeys, [a, b], reason: 'the list before the write');
    expect(kycKeysOf(second.account!.kycDocs), [a, c]);
    expect(await rowKeys(r, id), [a, c]);
  });

  test('a pass-through key no longer stored: refused, NOTHING written, the '
      'locked list returned', () async {
    final r = repo();
    final id = await account(r);
    final a = 'kyc/$id/a.jpg';
    final b = 'kyc/$id/b.jpg';
    final c = 'kyc/$id/c.jpg';
    final d = 'kyc/$id/d.jpg';
    await r.submitKyc(id, [doc(a), doc(c)]);
    await r.setVerification(id, status: 'rejected', rejectionReason: 'Floue');

    // `b` was replaced since this request read the row.
    final lost = await r.submitKyc(id, [doc(b), doc(d)], passThrough: {b});
    expect(lost.refused, isTrue);
    expect(lost.account, isNull);
    expect(lost.lockedKeys, [a, c], reason: 'the current list');

    final row = (await r.accountById(id))!;
    expect(kycKeysOf(row.kycDocs), [a, c]);
    expect(
      row.verificationStatus,
      'rejected',
      reason: 'nothing written — not even the status',
    );
    expect(row.rejectionReason, 'Floue');
  });

  test('an empty passThrough is never refused; an unknown account writes '
      'nothing and holds nothing', () async {
    final r = repo();
    final id = await account(r);
    final a = 'kyc/$id/a.jpg';
    await r.submitKyc(id, [doc(a)]);

    final reset = await r.submitKyc(id, const []);
    expect(reset.refused, isFalse);
    expect(reset.lockedKeys, [a]);
    expect(await rowKeys(r, id), isEmpty);

    final unknown = await r.submitKyc('nope', [doc(a)], passThrough: {a});
    expect(unknown.account, isNull);
    expect(unknown.refused, isFalse);
    expect(unknown.lockedKeys, isEmpty);
  });
}
