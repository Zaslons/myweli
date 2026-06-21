import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/models/session.dart';
import 'package:myweli/models/user.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';

void main() {
  const phone = '+2250700000077';

  Future<void> login(MockAuthService service) async {
    await service.sendOtp(phone);
    await service.verifyOtp(phone, MockAuthService.demoOtp);
  }

  test('a logged-in session is restored by a new service instance', () async {
    final store = InMemorySessionStore();
    await login(MockAuthService(sessionStore: store));

    // Simulate an app restart: a fresh service over the same store.
    final restored =
        await MockAuthService(sessionStore: store).getCurrentUser();
    expect(restored, isNotNull);
    expect(restored!.phoneNumber, phone);
  });

  test('logout clears the persisted session', () async {
    final store = InMemorySessionStore();
    final service = MockAuthService(sessionStore: store);
    await login(service);
    await service.logout();

    expect(await MockAuthService(sessionStore: store).getCurrentUser(), isNull);
  });

  test('deleteAccount clears the persisted session', () async {
    final store = InMemorySessionStore();
    final service = MockAuthService(sessionStore: store);
    await login(service);
    await service.deleteAccount();

    expect(await MockAuthService(sessionStore: store).getCurrentUser(), isNull);
  });

  test('an expired session is discarded on restore', () async {
    final store = InMemorySessionStore();
    final expired = Session(
      token: 't',
      user: User(id: 'u1', phoneNumber: phone, createdAt: DateTime(2025)),
      expiresAt: DateTime(2025, 1, 1),
    );
    await store.save(jsonEncode(expired.toJson()));

    final service = MockAuthService(sessionStore: store);
    expect(await service.getCurrentUser(), isNull);
    expect(await store.read(), isNull); // store was cleared
  });
}
