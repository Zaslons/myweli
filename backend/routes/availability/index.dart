import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/appointments/slot_service.dart';
import 'package:myweli_backend/src/responses.dart';

/// `GET /availability?providerId=&date=YYYY-MM-DD[&serviceIds=a,b][&durationMinutes=N][&artistId=x]`
/// — bookable start times (UTC). Public: clients browse availability before
/// signing in.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) return methodNotAllowed();

  final params = context.request.uri.queryParameters;
  final providerId = params['providerId']?.trim() ?? '';
  final dateRaw = params['date'];
  final date = dateRaw == null ? null : DateTime.tryParse(dateRaw);
  if (providerId.isEmpty || date == null) {
    return jsonError(HttpStatus.badRequest, 'invalid_input');
  }

  final serviceIds = params['serviceIds']
      ?.split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final durationMinutes = int.tryParse(params['durationMinutes'] ?? '');
  final artistId = params['artistId']?.trim();

  final result = await context.read<SlotService>().availableSlots(
    providerId: providerId,
    date: date,
    serviceIds: serviceIds,
    durationMinutes: durationMinutes,
    artistId: (artistId == null || artistId.isEmpty) ? null : artistId,
  );
  if (!result.ok) {
    return result.error == 'invalid_artist'
        ? jsonError(HttpStatus.badRequest, 'invalid_artist')
        : jsonError(HttpStatus.notFound, result.error!);
  }

  return Response.json(
    body: {
      'providerId': providerId,
      'date': dateRaw,
      'slots': result.slots!.map((d) => d.toIso8601String()).toList(),
    },
  );
}
