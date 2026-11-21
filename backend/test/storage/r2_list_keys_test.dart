import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:test/test.dart';

/// `StorageService.listKeys` (B0.24, deleted-owner-salon-purge.md §4.4): an
/// S3 `ListObjectsV2` on the bucket itself, every page, the signature over
/// the operation's query; a failure throws, never « nothing there ».
void main() {
  R2StorageService r2(http.Client client) => R2StorageService(
    endpoint: 'https://acct.r2.cloudflarestorage.com',
    bucket: 'pub',
    depositBucket: 'dep',
    accessKeyId: 'AK',
    secretAccessKey: 'SK',
    publicBaseUrl: 'https://cdn.example',
    clock: () => DateTime.utc(2026, 11, 21, 3, 30),
    client: client,
  );

  String page(List<String> keys, {String? next}) =>
      '<?xml version="1.0" encoding="UTF-8"?><ListBucketResult>'
      '${keys.map((k) => '<Contents><Key>$k</Key><Size>1</Size></Contents>').join()}'
      '<IsTruncated>${next != null}</IsTruncated>'
      '${next == null ? '' : '<NextContinuationToken>$next</NextContinuationToken>'}'
      '</ListBucketResult>';

  test('GET on the bucket root, the operation signed in the query', () async {
    final seen = <Uri>[];
    final keys = await r2(
      MockClient((req) async {
        seen.add(req.url);
        expect(req.method, 'GET');
        return http.Response(page(['gallery/s1/a.jpg']), 200);
      }),
    ).listKeys(prefix: 'gallery/s1/', bucket: StorageBucket.public);
    expect(keys, ['gallery/s1/a.jpg']);
    final u = seen.single;
    expect(u.path, '/pub', reason: 'the bucket, not an object');
    expect(u.queryParameters['list-type'], '2');
    expect(u.queryParameters['prefix'], 'gallery/s1/');
    expect(u.queryParameters['X-Amz-Signature'], isNotEmpty);
    // The query's parameters are sorted, as SigV4's canonical query is.
    final names = u.query.split('&').map((p) => p.split('=').first).toList();
    final unsigned = names.where((n) => n != 'X-Amz-Signature').toList();
    expect(unsigned, [...unsigned]..sort());
  });

  test('the prefix is part of the signature: another prefix, another '
      'signature', () async {
    final sigs = <String>{};
    final client = MockClient((req) async {
      sigs.add(req.url.queryParameters['X-Amz-Signature']!);
      return http.Response(page([]), 200);
    });
    await r2(
      client,
    ).listKeys(prefix: 'gallery/a/', bucket: StorageBucket.public);
    await r2(
      client,
    ).listKeys(prefix: 'gallery/b/', bucket: StorageBucket.public);
    expect(sigs, hasLength(2));
  });

  test('every page, following the continuation token', () async {
    var calls = 0;
    final keys = await r2(
      MockClient((req) async {
        calls++;
        final token = req.url.queryParameters['continuation-token'];
        return http.Response(
          token == null
              ? page(['logo/s1/a.jpg'], next: 't&amp;2')
              : page(['logo/s1/b.jpg']),
          200,
        );
      }),
    ).listKeys(prefix: 'logo/s1/', bucket: StorageBucket.public);
    expect(calls, 2);
    expect(keys, ['logo/s1/a.jpg', 'logo/s1/b.jpg']);
  });

  test('keys are XML-unescaped', () async {
    final keys = await r2(
      MockClient(
        (req) async => http.Response(page(['gallery/s1/a&amp;b.jpg']), 200),
      ),
    ).listKeys(prefix: 'gallery/s1/', bucket: StorageBucket.public);
    expect(keys, ['gallery/s1/a&b.jpg']);
  });

  test('the deposit bucket is its own bucket', () async {
    final paths = <String>[];
    await r2(
      MockClient((req) async {
        paths.add(req.url.path);
        return http.Response(page([]), 200);
      }),
    ).listKeys(prefix: 'deposit/u1/', bucket: StorageBucket.deposit);
    expect(paths, ['/dep']);
  });

  test('an error answer throws — never an empty listing', () {
    expect(
      r2(
        MockClient((req) async => http.Response('denied', 403)),
      ).listKeys(prefix: 'gallery/s1/', bucket: StorageBucket.public),
      throwsStateError,
    );
  });

  test('the fake lists what it holds under the prefix, and forgets a deleted '
      'key', () async {
    final fake = FakeStorageService();
    fake.listable[StorageBucket.public] = {
      'gallery/s1/a.jpg',
      'gallery/s10/b.jpg',
    };
    expect(
      await fake.listKeys(prefix: 'gallery/s1/', bucket: StorageBucket.public),
      ['gallery/s1/a.jpg'],
    );
    await fake.deleteObject(
      key: 'gallery/s1/a.jpg',
      bucket: StorageBucket.public,
    );
    expect(
      await fake.listKeys(prefix: 'gallery/s1/', bucket: StorageBucket.public),
      isEmpty,
    );
  });
}
