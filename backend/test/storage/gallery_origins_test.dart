import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

/// The gallery's origin allowlist, derived from the storage service in use.
///
/// **Why this moved out of the composition root.** `R2_PUBLIC_BASE_URL` was read
/// three times: inside storage's all-or-nothing fail-fast, again for this
/// allowlist, and again as the key-derivation base. Only the first read
/// participated in the guard, so the other two could carry a wrong or absent
/// value while every route still returned 200 — an anti-hotlink control that is
/// off and looks on. Deriving it from the storage object makes disagreement
/// impossible and makes the rule testable without touching env.
void main() {
  R2StorageService r2({String publicBase = 'https://cdn.myweli.com'}) =>
      R2StorageService(
        endpoint: 'https://acct.r2.cloudflarestorage.com',
        bucket: 'uploads',
        accessKeyId: 'k',
        secretAccessKey: 's',
        publicBaseUrl: publicBase,
      );

  test('real storage → only our own delivery origin, plus seed assets', () {
    expect(galleryOriginsFor(r2(), guardsOn: true), [
      'https://cdn.myweli.com',
      'asset:',
    ]);
  });

  test('the allowlist follows the bucket, so staging cannot trust prod', () {
    // The drift this closes: staging pointed at its own bucket while the
    // allowlist still named cdn.myweli.com would accept production URLs and
    // reject its own.
    expect(
      galleryOriginsFor(r2(publicBase: 'https://stg.r2.dev'), guardsOn: true),
      ['https://stg.r2.dev', 'asset:'],
    );
  });

  test('dev keeps accepting anything — an empty list means no check', () {
    // Unchanged behaviour, asserted so it stays deliberate: local work pastes
    // arbitrary image URLs and always has. `ReviewsService` /
    // `ProviderCatalogService` skip the check entirely when this is empty.
    expect(galleryOriginsFor(FakeStorageService(), guardsOn: false), isEmpty);
  });

  test('storage switched OFF in a guarded env still fails closed', () {
    // The hole `STORAGE_PROVIDER=disabled` would otherwise open: no public
    // base, so the old code produced an empty list — silently disabling the
    // origin check in staging. Turning a subsystem off must not turn a
    // security check off with it. The Fake's own origin stays allowed so the
    // fake upload flow still round-trips.
    expect(galleryOriginsFor(FakeStorageService(), guardsOn: true), [
      FakeStorageService.origin,
      'asset:',
    ]);
  });
}
