import 'package:myweli_backend/src/auth/demo_seam.dart';
import 'package:test/test.dart';

/// The pure half of T69: when the fixed code signs the demo identity in, and
/// — more importantly — every way it must NOT.
void main() {
  const code = '123456';

  test('configured + right identity + right code → allowed', () {
    expect(
      demoLoginAllowed(
        configuredCode: code,
        email: 'revue@myweli.test',
        code: '123456',
      ),
      isTrue,
    );
    // Trim + case, like every identity comparison in the auth stack.
    expect(
      demoLoginAllowed(
        configuredCode: code,
        email: '  REVUE@MYWELI.TEST ',
        code: ' 123456 ',
      ),
      isTrue,
    );
  });

  test('unset or mis-shaped code → the seam is ABSENT', () {
    for (final bad in [null, '', '   ', 'test', '12345', '1234567', 'abcdef']) {
      expect(
        demoLoginAllowed(
          configuredCode: bad,
          email: 'revue@myweli.test',
          code: bad ?? '',
        ),
        isFalse,
        reason: 'DEMO_PROVIDER_CODE=$bad must not enable the seam',
      );
    }
  });

  test('the RIGHT code on any other identity → false (non-interference)', () {
    // The case that matters most: the seam must be one address, never a
    // family — a suffix test would hand the public code to every .test
    // identity, including the smoke harness's.
    for (final other in [
      'owner@gmail.com',
      'autre@myweli.test',
      'revue@myweli.test.evil.com',
      'revue@myweli.tes',
    ]) {
      expect(
        demoLoginAllowed(configuredCode: code, email: other, code: '123456'),
        isFalse,
        reason: other,
      );
    }
  });

  test('the wrong code on the demo identity → false', () {
    expect(
      demoLoginAllowed(
        configuredCode: code,
        email: 'revue@myweli.test',
        code: '654321',
      ),
      isFalse,
    );
  });

  test('isActive mirrors the shape rule', () {
    expect(const DemoSeam('123456').isActive, isTrue);
    expect(const DemoSeam(null).isActive, isFalse);
    expect(const DemoSeam('test').isActive, isFalse);
  });

  test(
    'the identity constant is inside RFC 2606 — structurally unmailable',
    () {
      expect(kDemoProviderEmail, endsWith('.test'));
      expect(isDemoIdentity(kDemoProviderEmail), isTrue);
    },
  );
}
