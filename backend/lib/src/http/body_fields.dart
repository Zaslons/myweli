/// Typed reads of a JSON request body's fields
/// (docs/design/phone-leftovers.md §3).
///
/// **Why not `body['x'] as String?`.** That cast throws a `TypeError` on
/// `{"x": 5}`, and a `TypeError` is exactly what `observabilityMiddleware`
/// answers as a server fault: a 500 and an error report, for a request that
/// was simply malformed. Sixty-six such reads lived in twenty-seven routes —
/// every text field of the API. A reader instead throws a
/// [BodyFieldTypeError], which the middleware answers `400 invalid_body`
/// without reporting it; any OTHER `TypeError` stays a reported 500, so a
/// real bug never passes for a bad request.
///
/// Absent and JSON `null` both read as `null` — the readers say nothing about
/// whether a field is required, or what a valid value is. Each route keeps
/// its own rules and codes for those; these answer only "is it the JSON type
/// the contract says".
///
/// No `dart_frog` here, deliberately: a service handed the body map may read
/// through these too, and services do not depend on the framework.
library;

/// A request body field arrived as a JSON type other than the contract's.
///
/// The caller's fault, not ours — hence an [Exception], answered `400
/// invalid_body` by the middleware and never reported. Carries the field's
/// NAME only: the value is the client's, and may be personal data.
class BodyFieldTypeError implements Exception {
  const BodyFieldTypeError(this.key);

  /// The body key whose value had the wrong type.
  final String key;

  @override
  String toString() => 'BodyFieldTypeError($key)';
}

/// [key] as text: `null` when absent or JSON `null`, the string as sent
/// (untrimmed) when it is one; any other JSON type throws
/// [BodyFieldTypeError].
String? optionalString(Map<String, Object?> body, String key) =>
    switch (body[key]) {
      null => null,
      final String value => value,
      _ => throw BodyFieldTypeError(key),
    };

/// [key] as a JSON array: `null` when absent or JSON `null`, the list as sent
/// when it is one — its ELEMENTS are not checked (a route filters or
/// validates them); any other JSON type throws [BodyFieldTypeError].
List<Object?>? optionalList(Map<String, Object?> body, String key) =>
    switch (body[key]) {
      null => null,
      final List<Object?> value => value,
      _ => throw BodyFieldTypeError(key),
    };
