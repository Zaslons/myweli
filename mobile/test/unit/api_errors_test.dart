import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/services/api/api_errors.dart';

/// docs/design/app-failure-messages.md §2.1 — the two shared helpers. An
/// answer the app cannot read (a captive portal's HTML in a 200, a body cut
/// off, JSON of the wrong shape) is « Une erreur est survenue. Réessayez. »
/// with the code `unreadable`, never an exception whose English text reaches
/// the screen; a refusal says its code's sentence, or the generic one — never
/// « Erreur », never the server's own `message`.
void main() {
  http.Response res(int status, String body) => http.Response(body, status);

  group('the two sentences', () {
    test('as the owner approved them (§8)', () {
      expect(kNoConnectionMessage, 'Pas de connexion. Réessayez.');
      expect(kGenericErrorMessage, 'Une erreur est survenue. Réessayez.');
    });

    test('nothing answered → the no-connection sentence, code network', () {
      final r = networkError<int>();
      expect(r.success, isFalse);
      expect(r.error, kNoConnectionMessage);
      expect(r.code, 'network');
    });

    test('an unreadable answer → the generic sentence, code unreadable', () {
      final r = unreadable<int>();
      expect(r.error, kGenericErrorMessage);
      expect(r.code, 'unreadable');
    });
  });

  group('readOrUnreadable', () {
    Map<String, dynamic> obj(Object? j) => j! as Map<String, dynamic>;

    test('a body that reads → its value', () {
      final r = readOrUnreadable(res(200, '{"id":"a1"}'), (j) => obj(j)['id']);
      expect(r.success, isTrue);
      expect(r.data, 'a1');
    });

    test('a captive portal’s HTML in a 200 → unreadable, no throw', () {
      final r = readOrUnreadable(
        res(200, '<html><body>Connectez-vous au Wi-Fi</body></html>'),
        obj,
      );
      expect(r.success, isFalse);
      expect(r.code, 'unreadable');
      expect(r.error, kGenericErrorMessage);
    });

    test('a body cut off → unreadable', () {
      expect(readOrUnreadable(res(200, '{"id":'), obj).code, 'unreadable');
    });

    test('JSON of the wrong shape (a TypeError in the parse) → unreadable', () {
      final r = readOrUnreadable(
        res(200, '{"id":42}'),
        (j) => obj(j)['id'] as String,
      );
      expect(r.code, 'unreadable');
      expect(r.error, isNot(contains('subtype')));
    });
  });

  group('errorFromResponse', () {
    String? sentence(String? code) =>
        code == 'slot_unavailable' ? 'Ce créneau vient d’être pris.' : null;

    test('a known code → its own sentence, and the code', () {
      final r = errorFromResponse<int>(
        res(409, '{"error":"slot_unavailable"}'),
        messageFor: sentence,
      );
      expect(r.error, 'Ce créneau vient d’être pris.');
      expect(r.code, 'slot_unavailable');
    });

    test('an unknown code → the generic sentence — never « Erreur »', () {
      final r = errorFromResponse<int>(
        res(409, '{"error":"something_new"}'),
        messageFor: sentence,
      );
      expect(r.error, kGenericErrorMessage);
      expect(r.code, 'something_new');
    });

    test('the server’s own message is never shown', () {
      final r = errorFromResponse<int>(
        res(
          403,
          '{"error":"origin_required","message":"Requests must come through api.myweli.com."}',
        ),
      );
      expect(r.error, kGenericErrorMessage);
      expect(r.code, 'origin_required');
    });

    test('a page that is not JSON (a 500 from a proxy) → generic, no code', () {
      final r = errorFromResponse<int>(res(500, '<html>Bad gateway</html>'));
      expect(r.error, kGenericErrorMessage);
      expect(r.code, isNull);
    });

    test(
      'a gateway’s page (502/503/504) is a page, not « no connection »: generic',
      () {
        // The approved words (§8): « Pas de connexion » is for NOTHING answered
        // — the web's `writeFailureMessage` keeps it for status 0 too. A
        // gateway did answer; the person's connection is not what failed.
        for (final status in [502, 503, 504]) {
          final r = errorFromResponse<int>(res(status, '<html>'));
          expect(r.error, kGenericErrorMessage, reason: '$status');
        }
      },
    );

    test('a 401 without a code → « Veuillez vous reconnecter. »', () {
      final r = errorFromResponse<int>(res(401, ''));
      expect(r.error, 'Veuillez vous reconnecter.');
      expect(r.code, 'unauthorized');
    });
  });
}
