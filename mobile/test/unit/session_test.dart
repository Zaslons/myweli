import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/session.dart';
import 'package:myweli/models/user.dart';

void main() {
  final user = User(
    id: 'u1',
    phoneNumber: '+2250700000012',
    name: 'Awa',
    createdAt: DateTime(2025, 5, 1),
  );

  test('round-trips through JSON without an expiry', () {
    final back = Session.fromJson(Session(token: 't1', user: user).toJson());
    expect(back.token, 't1');
    expect(back.user.phoneNumber, '+2250700000012');
    expect(back.expiresAt, isNull);
  });

  test('round-trips through JSON with an expiry', () {
    final exp = DateTime(2026, 7, 1);
    final back = Session.fromJson(
      Session(token: 't1', user: user, expiresAt: exp).toJson(),
    );
    expect(back.expiresAt, exp);
  });

  test('isExpired honours the expiry', () {
    final s = Session(token: 't', user: user, expiresAt: DateTime(2026, 1, 1));
    expect(s.isExpired(DateTime(2026, 2, 1)), isTrue);
    expect(s.isExpired(DateTime(2025, 12, 1)), isFalse);
  });

  test('a null expiry never expires', () {
    expect(Session(token: 't', user: user).isExpired(DateTime(2100)), isFalse);
  });
}
