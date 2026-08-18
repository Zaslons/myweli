/// Resolving the caller's address from `X-Forwarded-For`.
///
/// ## Why this is a pure function with a depth argument
///
/// **The app had never seen a client address** — there was no XFF handling
/// anywhere in `backend/` before 2026-08-18. Adding one is not a one-liner,
/// because the header's shape depends on what sits in front of the service:
///
///   · **production** is behind an external Application Load Balancer. Google
///     APPENDS as the request passes, so the rightmost entries are
///     infrastructure and the LEFTMOST is whatever the client chose to send.
///   · **staging** is `ingress: all` and reached directly on `run.app`, so
///     there is one fewer hop.
///
/// Both plausible shortcuts are wrong, and they fail in opposite directions:
///
///   · trusting the **leftmost** entry is trivially bypassed — the client
///     controls it, so an attacker rotates it and every per-IP limit
///     evaporates while appearing to work;
///   · trusting the **rightmost** keys on the proxy's own address, which limits
///     *all* traffic together. A 10/minute ceiling then locks out every user at
///     once — a worse outage than the abuse it prevents.
///
/// So: count from the RIGHT by a configured number of trusted proxies. Entries
/// an attacker injects land to the left of the real one and can never reach the
/// chosen position.
///
/// Design: docs/design/backend-rate-limiting.md §3.
library;

/// The address [trustedProxies] hops in from the right, or null when the header
/// cannot support that claim.
///
/// Returning **null rather than a guess** is deliberate: the caller decides
/// what an unknown address means, and for a rate limiter "unknown" must never
/// silently collapse into one shared bucket.
String? clientIpFrom(String? forwardedFor, {required int trustedProxies}) {
  if (forwardedFor == null) return null;
  final parts = [
    for (final p in forwardedFor.split(','))
      if (p.trim().isNotEmpty) p.trim(),
  ];
  if (parts.isEmpty) return null;

  // depth 0 → the rightmost entry is the peer itself (no proxy in front).
  // depth 1 → one proxy appended its own address; ours is one to the left.
  final index = parts.length - 1 - trustedProxies;

  // Fewer entries than the deployment claims proxies. That is a
  // misconfiguration or a stripped header, and inventing an address here is how
  // every caller ends up sharing one bucket.
  if (index < 0 || index >= parts.length) return null;

  final candidate = parts[index];
  return _looksLikeAddress(candidate) ? candidate : null;
}

/// A deliberately loose shape check.
///
/// Not validation — the value is a bucket key, never a security decision on its
/// own — but a header full of junk should not become a key, and an attacker
/// should not be able to make the key enormous.
bool _looksLikeAddress(String v) {
  if (v.isEmpty || v.length > 45) return false; // 45 = max IPv6 text length
  return RegExp(r'^[0-9a-fA-F:.\[\]]+$').hasMatch(v);
}
