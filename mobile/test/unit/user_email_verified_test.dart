import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/user.dart';

/// `User.emailVerified` (B16.3b — docs/design/account-email-change.md §3.3,
/// §5.4). The server sends it on every `User` since B16.3a; « Modifier le
/// profil » says « Non vérifiée » from it, and offers « Vérifier ».
///
/// Read through `toJson`, which is also what the stored session keeps: a
/// field `fromJson` drops never reaches the next launch either.
void main() {
  Map<String, dynamic> json({String? email, Object? emailVerified = _absent}) =>
      {
        'id': 'user_1',
        'email': email,
        if (!identical(emailVerified, _absent)) 'emailVerified': emailVerified,
        'createdAt': DateTime(2026).toIso8601String(),
      };

  test('the server\'s false survives the round trip', () {
    final user = User.fromJson(
      json(email: 'awa@exemple.ci', emailVerified: false),
    );
    expect(user.toJson()['emailVerified'], isFalse);
    expect(User.fromJson(user.toJson()).toJson()['emailVerified'], isFalse);
  });

  test('the server\'s true survives the round trip', () {
    final user = User.fromJson(
      json(email: 'awa@exemple.ci', emailVerified: true),
    );
    expect(user.toJson()['emailVerified'], isTrue);
  });

  // A session stored by a build before B16.3b holds a `User` without the
  // field. Every address in production is proven (§9.1's reads: none
  // unproven, before and after B16.3a's deploy) and no route has written an
  // unproven one since, so an address there is a proven one — read as
  // unproven, the row would say « Non vérifiée » to everyone who updates.
  test('absent, with an address: proven (a session stored before B16.3b)', () {
    expect(
      User.fromJson(json(email: 'awa@exemple.ci')).toJson()['emailVerified'],
      isTrue,
    );
  });

  test('absent, without an address: not proven', () {
    expect(User.fromJson(json()).toJson()['emailVerified'], isFalse);
  });
}

const _absent = Object();
