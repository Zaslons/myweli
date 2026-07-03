import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'jwks_cache.dart';

/// Verified identity-provider claims, or a typed failure.
/// Errors: `invalid_token` (malformed / wrong alg → 400) and `token_rejected`
/// (signature/aud/iss/exp/nonce/unverified-email → 401).
typedef IdTokenResult = ({
  bool ok,
  String? error,
  String? sub,
  String? email,
  bool emailVerified,
  String? name,
  String? avatarUrl,
});

IdTokenResult _fail(String error) => (
  ok: false,
  error: error,
  sub: null,
  email: null,
  emailVerified: false,
  name: null,
  avatarUrl: null,
);

/// Verifies an OIDC ID token against a provider's JWKS: RS256 signature,
/// `iss` and `aud` allowlists, `exp` (via the JWT library), plus per-provider
/// rules ([requireVerifiedEmail] for Google, `nonce` for Apple). The token is
/// **never trusted before verification** — this is the trust boundary (threat
/// model T31). Design: docs/design/auth-social-email.md §7–8.
class IdTokenVerifier {
  IdTokenVerifier({
    required this.jwks,
    required this.issuers,
    required this.audiences,
    this.requireVerifiedEmail = false,
    this.rejectUnsolicitedNonce = true,
  });

  final JwksCache jwks;
  final List<String> issuers;
  final List<String> audiences;
  final bool requireVerifiedEmail;

  /// Reject a token carrying a `nonce` claim when the caller presented none.
  /// Strict for Apple (WE issue that nonce — its absence would disable the
  /// replay defence). Relaxed for Google: the iOS Google Sign-In SDK
  /// (AppAuth) mints and validates its OWN nonce client-side, so iOS tokens
  /// legitimately arrive with a nonce we never asked for.
  final bool rejectUnsolicitedNonce;

  Future<IdTokenResult> verify(String token, {String? nonce}) async {
    if (audiences.isEmpty) return _fail('verifier_not_configured');

    // 1. Header: well-formed JWT with RS256 + a kid.
    final parts = token.split('.');
    if (parts.length != 3) return _fail('invalid_token');
    final Map<String, dynamic> header;
    try {
      header =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
              )
              as Map<String, dynamic>;
    } catch (_) {
      return _fail('invalid_token');
    }
    if (header['alg'] != 'RS256') return _fail('invalid_token');
    final kid = header['kid'] as String?;
    if (kid == null) return _fail('invalid_token');

    // 2. Signature + exp against the provider's published key (fail closed).
    final key = await jwks.keyFor(kid);
    if (key == null) return _fail('token_rejected');
    final JWT jwt;
    try {
      jwt = JWT.verify(token, RSAPublicKey.raw(key), checkHeaderType: false);
    } on JWTException {
      return _fail('token_rejected');
    } catch (_) {
      return _fail('token_rejected');
    }

    final payload = jwt.payload as Map<String, dynamic>;

    // 3. iss / aud allowlists (aud may be a string or a list).
    if (!issuers.contains(payload['iss'])) return _fail('token_rejected');
    final aud = payload['aud'];
    final audOk = aud is String
        ? audiences.contains(aud)
        : aud is List && aud.any(audiences.contains);
    if (!audOk) return _fail('token_rejected');

    final sub = payload['sub'] as String?;
    if (sub == null || sub.isEmpty) return _fail('token_rejected');

    // 4. Email verification (Google asserts it; Apple emails are verified).
    final email = (payload['email'] as String?)?.trim().toLowerCase();
    final rawVerified = payload['email_verified'];
    final emailVerified = rawVerified == true || rawVerified == 'true';
    if (requireVerifiedEmail && !(emailVerified && email != null)) {
      return _fail('token_rejected');
    }

    // 5. Nonce (replay defence — Apple). The claim holds either the raw nonce
    //    or its SHA-256 (the iOS convention); accept either. A token carrying
    //    a nonce claim requires the caller to present one — unless the
    //    provider's own SDK is known to mint one ([rejectUnsolicitedNonce]).
    final claimNonce = payload['nonce'] as String?;
    if (nonce != null && nonce.isNotEmpty) {
      final hashed = sha256.convert(utf8.encode(nonce)).toString();
      if (claimNonce != nonce && claimNonce != hashed) {
        return _fail('token_rejected');
      }
    } else if (claimNonce != null && rejectUnsolicitedNonce) {
      return _fail('token_rejected');
    }

    return (
      ok: true,
      error: null,
      sub: sub,
      email: email,
      emailVerified: emailVerified || (email != null && !requireVerifiedEmail),
      name: payload['name'] as String?,
      avatarUrl: payload['picture'] as String?,
    );
  }
}

/// Google Sign-In ID tokens (`accounts.google.com`). [clientIds] = the OAuth
/// client-ID allowlist (web + Android + iOS audiences).
class GoogleIdTokenVerifier extends IdTokenVerifier {
  GoogleIdTokenVerifier({
    required List<String> clientIds,
    http.Client? client,
    JwksCache? jwks,
  }) : super(
         jwks:
             jwks ??
             JwksCache(
               'https://www.googleapis.com/oauth2/v3/certs',
               client: client,
             ),
         issuers: const ['https://accounts.google.com', 'accounts.google.com'],
         audiences: clientIds,
         requireVerifiedEmail: true,
         // The iOS Google Sign-In SDK adds + self-validates a nonce; web GIS
         // and Android tokens carry none. We never issue a Google nonce.
         rejectUnsolicitedNonce: false,
       );
}

/// Sign in with Apple identity tokens (`appleid.apple.com`). [clientIds] =
/// the iOS bundle id + the web Service ID. Apple emails count as verified.
class AppleIdTokenVerifier extends IdTokenVerifier {
  AppleIdTokenVerifier({
    required List<String> clientIds,
    http.Client? client,
    JwksCache? jwks,
  }) : super(
         jwks:
             jwks ??
             JwksCache('https://appleid.apple.com/auth/keys', client: client),
         issuers: const ['https://appleid.apple.com'],
         audiences: clientIds,
       );
}
