import 'dart:convert';

import 'package:uuid/uuid.dart';

/// One `Idempotency-Key` per SUBMISSION of a form
/// (docs/design/write-idempotency.md §4): the same while the form is
/// unchanged — « Réessayer » is the same request, which the server may already
/// have done — a new one as soon as anything in it changed (another slot,
/// another text), and a new one after a success, so that sending the same
/// words again on purpose is a second note, not a replay of the first.
///
/// The web's twin is `SubmissionKey` in `web/lib/api/network.ts`.
class SubmissionKey {
  SubmissionKey({String Function()? newKey})
    : _newKey = newKey ?? (() => const Uuid().v4());

  final String Function() _newKey;
  String? _form;
  String? _key;

  /// The key for [form] — a JSON-encodable value (strings, not `DateTime`s).
  String forForm(Object? form) {
    final sig = jsonEncode(form);
    if (sig != _form || _key == null) {
      _form = sig;
      _key = _newKey();
    }
    return _key!;
  }

  /// The submission succeeded: the next one is a new request.
  void settle() {
    _form = null;
    _key = null;
  }
}
