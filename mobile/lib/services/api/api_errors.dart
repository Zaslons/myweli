import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/failure_messages.dart';
import '../../models/api_response.dart';

/// The two shared helpers every API service words its failures through
/// (docs/design/app-failure-messages.md §2.1). Before them, eleven services
/// each had their own `_errorFrom` and `_networkError` — which is how the app
/// came to say « Erreur » alone, the server's own `message`, and two different
/// sentences for one fact.

/// Nothing answered (`RefreshingHttpClient.send` returned `null`): the one
/// sentence for it, and the code `network` — the code a screen uses to say
/// « Pas de connexion » rather than « une erreur ». Before, only one service
/// set it, and « Accueil » relied on it from another that did not.
ApiResponse<T> networkError<T>() =>
    ApiResponse.error(kNoConnectionMessage, code: 'network');

/// An answer the app cannot read: a captive portal's HTML in a 200, a body
/// cut off, JSON of the wrong shape.
ApiResponse<T> unreadable<T>() =>
    ApiResponse.error(kGenericErrorMessage, code: 'unreadable');

/// Reads [res]'s body and hands the decoded JSON to [parse]. A
/// `FormatException` (not JSON) or a `TypeError` (JSON of the wrong shape —
/// an `as String` on a number) is [unreadable], never an exception that
/// climbs to a screen. #630's guard in `listClients`, generalised.
ApiResponse<T> readOrUnreadable<T>(
  http.Response res,
  T Function(Object? json) parse,
) {
  try {
    return ApiResponse.success(parse(jsonDecode(res.body)));
  } on FormatException {
    return unreadable();
  } on TypeError {
    return unreadable();
  }
}

/// A refusal, worded. The machine code is read from `{error}` when the body
/// is JSON; [messageFor] gives that code's own sentence (each service keeps
/// its table — a known code keeps the words it had), and anything else is the
/// generic sentence. **The server's own `message` is never shown**: these
/// routes send none, and the one that does (the origin gate) sends English.
///
/// A body that is not JSON is a page — a proxy's 500, a gateway's 502 — and
/// says the generic sentence: something answered, so it is not « Pas de
/// connexion » (the owner's words, §8; the web keeps that one for status 0
/// too). A 401 without a code asks to sign in again.
ApiResponse<T> errorFromResponse<T>(
  http.Response res, {
  String? Function(String? code)? messageFor,
}) {
  String? code;
  try {
    final body = jsonDecode(res.body);
    if (body is Map && body['error'] is String) code = body['error'] as String;
  } catch (_) {
    code = null;
  }
  if (code == null && res.statusCode == 401) {
    return ApiResponse.error(
      'Veuillez vous reconnecter.',
      code: 'unauthorized',
    );
  }
  return ApiResponse.error(
    messageFor?.call(code) ?? kGenericErrorMessage,
    code: code,
  );
}
