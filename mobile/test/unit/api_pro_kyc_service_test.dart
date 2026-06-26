import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/models/kyc_document.dart';
import 'package:myweli/models/provider_user.dart';
import 'package:myweli/services/api/api_pro_kyc_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

ApiProKycService _service(MockClient client, {String? token = 'tok'}) {
  final store = InMemorySessionStore();
  if (token != null) {
    store.save(jsonEncode({
      'token': token,
      'refreshToken': 'r1',
      'provider': {'id': 'acc1', 'providerId': 'provider1'},
    }));
  }
  return ApiProKycService(
    client: client,
    baseUrl: 'http://x',
    providerSessionStore: store,
  );
}

void main() {
  test('getKycStatus GETs /me/kyc and parses status + documents', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/me/kyc');
      return http.Response(
        jsonEncode({
          'status': 'pending',
          'documents': [
            {
              'type': 'idCard',
              'fileName': 'id.jpg',
              'key': 'kyc/acc1/a.jpg',
              'submittedAt': DateTime.utc(2030).toIso8601String(),
            },
          ],
          'rejectionReason': null,
        }),
        200,
      );
    });
    final res = await _service(client).getKycStatus('acc1');
    expect(res.success, isTrue);
    expect(res.data!.status, VerificationStatus.pending);
    expect(res.data!.documents.single.key, 'kyc/acc1/a.jpg');
  });

  test('uploadDocument signs (kyc) → POSTs to private storage → returns key',
      () async {
    // A real file to read bytes from.
    final tmp = File(
      '${Directory.systemTemp.path}/kyc_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync([1, 2, 3, 4]);
    addTearDown(() => tmp.existsSync() ? tmp.deleteSync() : null);

    final paths = <String>[];
    final client = MockClient((req) async {
      paths.add(req.url.path);
      if (req.url.path == '/uploads/sign') {
        expect((jsonDecode(req.body) as Map)['purpose'], 'kyc');
        return http.Response(
          jsonEncode({
            'method': 'POST',
            'uploadUrl': 'http://storage.local/kyc-bucket',
            'fields': {'key': 'kyc/acc1/x.jpg'},
            'key': 'kyc/acc1/x.jpg',
            'maxBytes': 5242880,
            'expiresInSeconds': 300,
          }),
          200,
        );
      }
      return http.Response('', 204); // the storage upload
    });

    final res = await _service(client).uploadDocument(
      source: tmp.path,
      contentType: 'image/jpeg',
    );
    expect(res.success, isTrue);
    expect(res.data, 'kyc/acc1/x.jpg');
    expect(paths, ['/uploads/sign', '/kyc-bucket']);
  });

  test('submitKyc POSTs the documents (type/fileName/key)', () async {
    Map<String, dynamic>? body;
    final client = MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/me/kyc');
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(
            {'status': 'pending', 'documents': [], 'rejectionReason': null}),
        200,
      );
    });
    final res = await _service(client).submitKyc(
      providerUserId: 'acc1',
      documents: [
        KycDocument(
          type: KycDocumentType.idCard,
          fileName: 'id.jpg',
          key: 'kyc/acc1/a.jpg',
          submittedAt: DateTime.utc(2030),
        ),
      ],
    );
    expect(res.success, isTrue);
    final docs = body!['documents'] as List;
    expect((docs.single as Map)['key'], 'kyc/acc1/a.jpg');
    expect((docs.single as Map)['type'], 'idCard');
  });

  test('no provider session → fails fast without HTTP', () async {
    final client =
        MockClient((req) async => throw Exception('should not be called'));
    final res = await _service(client, token: null).getKycStatus('acc1');
    expect(res.success, isFalse);
  });
}
