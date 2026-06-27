import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/provider_discovery.dart';
import 'package:myweli_backend/src/providers_repository.dart';

/// `GET /providers` — search/list, paginated. Backs `getProviders` /
/// `getFeaturedProviders` in the app's `ProviderServiceInterface`. Supports
/// `sort` (relevance|rating|price) + `availableToday` (FR-DISC-007); commune /
/// category / q filter. Design: docs/design/discovery-sort-filter.md.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'method_not_allowed'},
    );
  }

  final params = context.request.uri.queryParameters;
  final page = (int.tryParse(params['page'] ?? '') ?? 1).clamp(1, 100000);
  final pageSize = (int.tryParse(params['pageSize'] ?? '') ?? 20).clamp(1, 50);

  var all = await context.read<ProvidersRepository>().query(
    q: params['q'],
    commune: params['commune'],
    category: params['category'],
  );

  // Keep only salons with ≥1 free slot today (filter before paging → total OK).
  if (params['availableToday'] == 'true') {
    final slots = context.read<SlotService>();
    final today = DateTime.now().toUtc();
    final open = <Map<String, dynamic>>[];
    for (final p in all) {
      final r = await slots.availableSlots(
        providerId: p['id'] as String,
        date: today,
      );
      if (r.slots != null && r.slots!.isNotEmpty) open.add(p);
    }
    all = open;
  }

  all = sortProviders(all, params['sort']);

  final start = (page - 1) * pageSize;
  final items = start >= all.length
      ? const <Map<String, dynamic>>[]
      : all.sublist(start, (start + pageSize).clamp(0, all.length));

  return Response.json(
    body: {
      'items': items,
      'page': page,
      'pageSize': pageSize,
      'total': all.length,
    },
  );
}
