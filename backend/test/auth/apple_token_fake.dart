import 'package:myweli_backend/src/auth/apple_tokens.dart';

/// Records what the routes and the deletion paths ask of
/// [AppleTokenService] (B6.7) — the service itself is covered by
/// `apple_tokens_test.dart`.
class RecordingAppleTokens extends AppleTokenService {
  RecordingAppleTokens({this.onRevoke})
    : super(InMemoryAppleTokenRepository(), null, log: (_) {});

  /// Runs inside [revokeAll] — lets a test look at the world at that moment
  /// (is the identity still there?).
  final Future<void> Function(String kind, String accountId)? onRevoke;

  final kept = <Map<String, String?>>[];
  final revoked = <(String, String)>[];

  @override
  Future<void> keepFromCode({
    required String kind,
    required String accountId,
    required String clientId,
    required String sub,
    required String code,
    String? redirectUri,
  }) async {
    kept.add({
      'kind': kind,
      'accountId': accountId,
      'clientId': clientId,
      'sub': sub,
      'code': code,
      'redirectUri': redirectUri,
    });
  }

  @override
  Future<void> revokeAll({
    required String kind,
    required String accountId,
  }) async {
    await onRevoke?.call(kind, accountId);
    revoked.add((kind, accountId));
  }
}
