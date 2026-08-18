import 'package:myweli_backend/src/security/client_ip.dart';
import 'package:test/test.dart';

/// The resolver a per-IP limiter stands on.
///
/// **The spoofing case is the point.** Trusting the leftmost `X-Forwarded-For`
/// entry is the classic bypass: the client controls it, so an attacker rotates
/// it and every per-IP limit evaporates while looking like it works.
void main() {
  group('counts from the right, by trusted-proxy depth', () {
    test('no proxy in front → the only entry is the peer', () {
      expect(clientIpFrom('1.2.3.4', trustedProxies: 0), '1.2.3.4');
    });

    test('one proxy appended its own address → ours is one left of it', () {
      // Production shape: <client>, <load balancer>
      expect(
        clientIpFrom('203.0.113.9, 35.191.0.1', trustedProxies: 1),
        '203.0.113.9',
      );
    });

    test('two proxies', () {
      expect(
        clientIpFrom('203.0.113.9, 10.0.0.1, 35.191.0.1', trustedProxies: 2),
        '203.0.113.9',
      );
    });
  });

  group('a client cannot move the resolved address', () {
    test('injected entries land to the LEFT and are ignored', () {
      // The attacker sends `X-Forwarded-For: 1.2.3.4`; the LB appends the real
      // client address and then its own. The forged value is now leftmost.
      const forged = '1.2.3.4, 203.0.113.9, 35.191.0.1';
      expect(clientIpFrom(forged, trustedProxies: 1), '203.0.113.9');
    });

    test('and no amount of them helps', () {
      final many =
          '${List.filled(50, '1.2.3.4').join(', ')}, 203.0.113.9, 35.191.0.1';
      expect(clientIpFrom(many, trustedProxies: 1), '203.0.113.9');
    });
  });

  group('refuses rather than guesses', () {
    test('absent header → null', () {
      expect(clientIpFrom(null, trustedProxies: 1), isNull);
    });

    test(
      'fewer entries than claimed proxies → null, never the proxy itself',
      () {
        // The misconfiguration that would key every caller into ONE bucket and
        // lock out the whole service at a 10/minute ceiling.
        expect(clientIpFrom('35.191.0.1', trustedProxies: 1), isNull);
        expect(clientIpFrom('', trustedProxies: 0), isNull);
        expect(clientIpFrom('   ', trustedProxies: 0), isNull);
      },
    );

    test('junk is not a key', () {
      expect(clientIpFrom('not an address', trustedProxies: 0), isNull);
      expect(clientIpFrom('a' * 60, trustedProxies: 0), isNull);
    });
  });

  test('IPv6, with and without brackets', () {
    expect(clientIpFrom('2001:db8::1', trustedProxies: 0), '2001:db8::1');
    expect(
      clientIpFrom('2001:db8::1, 35.191.0.1', trustedProxies: 1),
      '2001:db8::1',
    );
  });

  test('whitespace around entries is not part of the key', () {
    // Otherwise ` 1.2.3.4` and `1.2.3.4` are two buckets, and an attacker gets
    // a fresh budget by adding a space.
    expect(
      clientIpFrom('  203.0.113.9 ,  35.191.0.1  ', trustedProxies: 1),
      '203.0.113.9',
    );
  });
}
