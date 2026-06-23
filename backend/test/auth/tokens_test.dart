import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:test/test.dart';

void main() {
  final tokens = TokenService(secret: 'test-secret');

  test('issues an access token that verifies with sub + role', () {
    final issued = tokens.issueAccessToken(subject: 'user_1', role: 'user');
    final jwt = tokens.verifyAccessToken(issued.token);
    expect(jwt, isNotNull);
    expect(jwt!.subject, 'user_1');
    expect(jwt.payload['role'], 'user');
  });

  test('rejects garbage / tampered tokens', () {
    expect(tokens.verifyAccessToken('not.a.jwt'), isNull);
    final issued = tokens.issueAccessToken(subject: 'u', role: 'user');
    expect(tokens.verifyAccessToken('${issued.token}tampered'), isNull);
  });

  test('rejects a token signed with another secret', () {
    final other = TokenService(secret: 'different-secret');
    final issued = other.issueAccessToken(subject: 'u', role: 'user');
    expect(tokens.verifyAccessToken(issued.token), isNull);
  });

  test('rejects an expired token', () {
    final past =
        DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch ~/
        1000;
    final expired = JWT({
      'role': 'user',
      'exp': past,
    }, subject: 'u').sign(SecretKey('test-secret'));
    expect(tokens.verifyAccessToken(expired), isNull);
  });

  test('refresh tokens are unique + hashed deterministically', () {
    final r1 = tokens.generateRefreshToken();
    final r2 = tokens.generateRefreshToken();
    expect(r1, isNot(r2));
    expect(tokens.hashToken(r1), tokens.hashToken(r1));
    expect(tokens.hashToken(r1), isNot(tokens.hashToken(r2)));
  });
}
