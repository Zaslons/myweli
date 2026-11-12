import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/access/salon_directory_service.dart';
import 'package:myweli_backend/src/admin/admin_provider_service.dart';
import 'package:myweli_backend/src/admin/analytics_service.dart';
import 'package:myweli_backend/src/admin/disputes_repository.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/salon_provisioning_service.dart';
import 'package:myweli_backend/src/validation/salon_validation_service.dart';

import '../../routes/admin/_middleware.dart' as admin_mw;
import '../../routes/admin/analytics/overview.dart' as overview_route;
import '../../routes/admin/providers/[id]/restore.dart' as restore_route;
import '../../routes/admin/salon-validations/index.dart' as queue_route;
import '../../routes/admin/salons/[id]/validation/approve.dart'
    as approve_route;
import '../../routes/admin/salons/[id]/validation/index.dart' as detail_route;
import '../../routes/admin/salons/[id]/validation/refuse.dart' as refuse_route;
import '../../routes/me/provider/index.dart' as me_provider_route;
import '../../routes/me/salons/index.dart' as me_salons_route;
import '../../routes/providers/[id]/publish.dart' as publish_route;
import 'validation_world.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// B0.18 stage 3 — the routes over [ValidationWorld], wired as
/// `routes/_middleware.dart` provides them, and the `/admin` ones behind the
/// REAL admin middleware (`routes/admin/_middleware.dart`): a handler test
/// of an admin route that skipped it would prove nothing about who may call
/// it. Shared by the handler tests and the contract tests, so both observe
/// the same answers.
class ValidationRoutes {
  ValidationRoutes(this.world);

  final ValidationWorld world;

  /// The admin's token, as `/admin/auth/login` issues it.
  String get adminToken =>
      world.tokens.issueAccessToken(subject: 'admin_1', role: 'admin').token;

  /// A token for [subject] in [role] (`provider`, `user`, …).
  String token(String subject, String role) =>
      world.tokens.issueAccessToken(subject: subject, role: role).token;

  AnalyticsService get analytics => AnalyticsService(
    InMemoryAppointmentRepository(),
    world.providers,
    InMemoryAuthRepository(tokens: world.tokens, echoDevCode: true),
    world.auth,
    InMemoryDisputesRepository(),
    InMemoryReviewsRepository(),
    validations: world.validations,
  );

  SalonDirectoryService get directory => SalonDirectoryService(
    world.members,
    MembershipService(world.members, world.auth),
    world.providers,
    world.subscriptions,
    world.auth,
    validations: world.validations,
  );

  RequestContext _ctx(Request request) {
    final c = _MockRequestContext();
    when(() => c.request).thenReturn(request);
    when(() => c.read<TokenService>()).thenReturn(world.tokens);
    when(() => c.read<ProviderAuthRepository>()).thenReturn(world.auth);
    when(() => c.read<ProvidersRepository>()).thenReturn(world.providers);
    when(
      () => c.read<MembershipService>(),
    ).thenReturn(MembershipService(world.members, world.auth));
    when(
      () => c.read<SalonProvisioningService>(),
    ).thenReturn(world.provisioning);
    when(() => c.read<SalonValidationService>()).thenReturn(world.service);
    when(() => c.read<AdminProviderService>()).thenReturn(world.admin);
    when(() => c.read<AnalyticsService>()).thenReturn(analytics);
    when(() => c.read<SalonDirectoryService>()).thenReturn(directory);
    return c;
  }

  Request _request(
    String method,
    String path, {
    String? bearer,
    Object? json,
    String? rawBody,
  }) => Request(
    method,
    Uri.parse('http://localhost$path'),
    headers: {
      if (bearer != null) 'Authorization': 'Bearer $bearer',
      if (json != null || rawBody != null) 'content-type': 'application/json',
    },
    body: rawBody ?? (json == null ? null : jsonEncode(json)),
  );

  /// An `/admin/*` route behind the real admin middleware. [bearer] null →
  /// no `Authorization` header at all.
  Future<Response> _admin(
    Handler route,
    String method,
    String path, {
    required String? bearer,
    Object? json,
    String? rawBody,
  }) async => admin_mw.middleware(route)(
    _ctx(_request(method, path, bearer: bearer, json: json, rawBody: rawBody)),
  );

  // ---- The owner's side ----------------------------------------------------

  /// `POST /providers/{id}/publish` as [bearer] ([method] for the 405).
  Future<Response> publish(
    String id, {
    required String? bearer,
    String method = 'POST',
  }) => publish_route.onRequest(
    _ctx(_request(method, '/providers/$id/publish', bearer: bearer)),
    id,
  );

  /// `GET /me/provider` (`?salonId=` when [salonId] is set).
  Future<Response> meProvider({required String? bearer, String? salonId}) =>
      me_provider_route.onRequest(
        _ctx(
          _request(
            'GET',
            salonId == null ? '/me/provider' : '/me/provider?salonId=$salonId',
            bearer: bearer,
          ),
        ),
      );

  /// `GET /me/salons`.
  Future<Response> meSalons({required String? bearer}) => me_salons_route
      .onRequest(_ctx(_request('GET', '/me/salons', bearer: bearer)));

  // ---- MyWeli's side -------------------------------------------------------

  /// `GET /admin/salon-validations[?query]`.
  Future<Response> queue({
    String query = '',
    String? bearer,
    bool anonymous = false,
    String method = 'GET',
  }) => _admin(
    queue_route.onRequest,
    method,
    '/admin/salon-validations${query.isEmpty ? '' : '?$query'}',
    bearer: anonymous ? null : (bearer ?? adminToken),
  );

  /// `GET /admin/salons/{id}/validation`.
  Future<Response> detail(
    String id, {
    String? bearer,
    bool anonymous = false,
    String method = 'GET',
  }) => _admin(
    (c) => detail_route.onRequest(c, id),
    method,
    '/admin/salons/$id/validation',
    bearer: anonymous ? null : (bearer ?? adminToken),
  );

  /// `POST /admin/salons/{id}/validation/approve` with [json] (or the
  /// verbatim [rawBody]).
  Future<Response> approve(
    String id, {
    Object? json,
    String? rawBody,
    String? bearer,
    bool anonymous = false,
    String method = 'POST',
  }) => _admin(
    (c) => approve_route.onRequest(c, id),
    method,
    '/admin/salons/$id/validation/approve',
    bearer: anonymous ? null : (bearer ?? adminToken),
    json: json,
    rawBody: rawBody,
  );

  /// `POST /admin/salons/{id}/validation/refuse` with [json] (or the
  /// verbatim [rawBody]).
  Future<Response> refuse(
    String id, {
    Object? json,
    String? rawBody,
    String? bearer,
    bool anonymous = false,
    String method = 'POST',
  }) => _admin(
    (c) => refuse_route.onRequest(c, id),
    method,
    '/admin/salons/$id/validation/refuse',
    bearer: anonymous ? null : (bearer ?? adminToken),
    json: json,
    rawBody: rawBody,
  );

  /// `POST /admin/providers/{id}/restore` — « Lever la suspension ».
  Future<Response> restore(
    String id, {
    String? bearer,
    bool anonymous = false,
    String method = 'POST',
  }) => _admin(
    (c) => restore_route.onRequest(c, id),
    method,
    '/admin/providers/$id/restore',
    bearer: anonymous ? null : (bearer ?? adminToken),
  );

  /// `GET /admin/analytics/overview`.
  Future<Response> overview({
    String? bearer,
    bool anonymous = false,
    String method = 'GET',
  }) => _admin(
    overview_route.onRequest,
    method,
    '/admin/analytics/overview',
    bearer: anonymous ? null : (bearer ?? adminToken),
  );
}

/// The decoded JSON body of [res].
Future<Map<String, dynamic>> bodyOf(Response res) async =>
    (await res.json()) as Map<String, dynamic>;
