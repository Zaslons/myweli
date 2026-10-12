import 'package:myweli_backend/src/observability/refresh_log.dart';
import 'package:test/test.dart';

/// The refresh outcome line carries a request id the client may supply, so it
/// must not be able to inject fields (backend-refresh-rotation-atomic.md §6).
void main() {
  test('a plain id passes through (uuid, the middleware default)', () {
    const uuid = '3f1c2a9e-7b4d-4c1e-9a2f-0d6b8e5c4a11';
    expect(logSafeRequestId(uuid), uuid);
  });

  test('an id that could forge or hide a field is replaced, never echoed', () {
    for (final forged in [
      'x outcome=reused principal=admin',
      'abc\nINFO: auth_refresh outcome=reused',
      'a=b',
      '',
      'a' * 65,
    ]) {
      expect(logSafeRequestId(forged), 'invalid', reason: forged);
    }
  });
}
