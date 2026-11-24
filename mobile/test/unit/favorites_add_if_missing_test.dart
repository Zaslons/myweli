import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/failure_messages.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/services/interfaces/favorites_service_interface.dart';
import 'package:myweli/services/mock/mock_data.dart';

/// consumer-signin-push.md §2.8, decision 205: a heart tapped before
/// signing in is applied after — read fresh, never a toggle — and §2.3: two
/// reads of the same account are one.
void main() {
  final service = _Favorites();
  setUpAll(() => serviceLocator.favoritesService = service);
  setUp(service.reset);

  final a = MockData.providers[0];
  final b = MockData.providers[1];

  test('not a favourite yet → added, once', () async {
    service.stored = [a];
    final fav = FavoritesProvider();
    expect(
      await fav.addIfMissing('u1', b.id),
      FavoriteAddOutcome.added,
    );
    expect(service.adds, [b.id]);
    expect(fav.isFavorite(b.id), isTrue);
    expect(fav.isFavorite(a.id), isTrue);
  });

  test('already one (saved on another phone) → nothing sent; a toggle would '
      'have REMOVED it', () async {
    service.stored = [a, b];
    final fav = FavoritesProvider();
    expect(
      await fav.addIfMissing('u1', b.id),
      FavoriteAddOutcome.alreadyThere,
    );
    expect(service.adds, isEmpty);
    expect(service.removes, isEmpty);
    expect(fav.isFavorite(b.id), isTrue);
  });

  test('read fresh even when this account\'s list is in memory', () async {
    service.stored = [a];
    final fav = FavoritesProvider();
    await fav.loadFavorites('u1');
    service.stored = [a, b]; // added on the website meanwhile
    expect(
      await fav.addIfMissing('u1', b.id),
      FavoriteAddOutcome.alreadyThere,
    );
    expect(service.adds, isEmpty);
  });

  test('the read fails → failed, nothing sent, the failure sentence kept', () async {
    service.failRead = true;
    final fav = FavoritesProvider();
    expect(await fav.addIfMissing('u1', b.id), FavoriteAddOutcome.failed);
    expect(service.adds, isEmpty);
    expect(fav.error, isNotNull);
  });

  test('the add fails → failed, the heart stays empty', () async {
    service.stored = [a];
    service.failAdd = true;
    final fav = FavoritesProvider();
    expect(await fav.addIfMissing('u1', b.id), FavoriteAddOutcome.failed);
    expect(fav.isFavorite(b.id), isFalse);
    expect(fav.error, kGenericErrorMessage);
  });

  test('no account → failed, nothing asked', () async {
    final fav = FavoritesProvider();
    expect(await fav.addIfMissing('', b.id), FavoriteAddOutcome.failed);
    expect(service.reads, 0);
  });

  test('two reads of the same account are one: the root\'s reload after a '
      'sign-in cannot land after the add and erase it (§2.3)', () async {
    service.stored = [a];
    final gate = Completer<void>();
    service.readGate = gate.future;
    final fav = FavoritesProvider();
    final rootReload = fav.loadFavorites('u1', force: true);
    final heart = fav.addIfMissing('u1', b.id);
    gate.complete();
    await rootReload;
    expect(await heart, FavoriteAddOutcome.added);
    expect(service.reads, 1, reason: 'one read, shared');
    expect(fav.isFavorite(b.id), isTrue, reason: 'the add survives');
  });
}

class _Favorites implements FavoritesServiceInterface {
  List<Provider> stored = [];
  bool failRead = false;
  bool failAdd = false;
  Future<void>? readGate;
  int reads = 0;
  final adds = <SalonId>[];
  final removes = <SalonId>[];

  void reset() {
    stored = [];
    failRead = false;
    failAdd = false;
    readGate = null;
    reads = 0;
    adds.clear();
    removes.clear();
  }

  @override
  Future<ApiResponse<List<Provider>>> getFavoriteProviders(
    String userId,
  ) async {
    reads++;
    // What the server holds when the read STARTS.
    final snapshot = List.of(stored);
    final gate = readGate;
    if (gate != null) await gate;
    if (failRead) return ApiResponse.error('Lecture impossible');
    return ApiResponse.success(snapshot);
  }

  @override
  Future<ApiResponse<bool>> addFavorite(String userId, SalonId id) async {
    if (failAdd) throw StateError('offline');
    adds.add(id);
    stored = [...stored, MockData.providers.firstWhere((p) => p.id == id)];
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> removeFavorite(String userId, SalonId id) async {
    removes.add(id);
    stored = stored.where((p) => p.id != id).toList();
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<List<SalonId>>> getFavoriteProviderIds(String userId) async =>
      ApiResponse.success([for (final p in stored) p.id]);

  @override
  Future<ApiResponse<bool>> isFavorite(String userId, SalonId id) async =>
      ApiResponse.success(stored.any((p) => p.id == id));
}
