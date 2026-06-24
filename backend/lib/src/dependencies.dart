import 'dart:io';

import 'package:postgres/postgres.dart';

import 'appointments/appointment_lifecycle_service.dart';
import 'appointments/appointment_repository.dart';
import 'appointments/booking_service.dart';
import 'appointments/pro_appointment_service.dart';
import 'appointments/slot_service.dart';
import 'auth/auth_repository.dart';
import 'auth/provider_auth_repository.dart';
import 'auth/tokens.dart';
import 'db/database.dart';
import 'db/migrations.dart';
import 'db/postgres_appointment_repository.dart';
import 'db/postgres_auth_repository.dart';
import 'db/postgres_providers_repository.dart';
import 'providers_repository.dart';

/// Composition root: process-wide singletons built from env
/// (docs/BACKEND.md §3.5), provided into request context by
/// `routes/_middleware.dart`. When `DATABASE_URL` is set the repositories are
/// Postgres-backed; otherwise they are in-memory — so local/dev/CI without a
/// database (and the app's tests) are unchanged.

bool get _isProd => (Platform.environment['ENV'] ?? 'dev') == 'prod';

String _resolveSecret() {
  final secret = Platform.environment['JWT_SECRET'];
  if (secret != null && secret.isNotEmpty) return secret;
  if (_isProd) {
    throw StateError('JWT_SECRET must be set in production');
  }
  // Dev-only fallback so local runs work without setup; never used in prod.
  return 'dev-insecure-secret-change-me';
}

final String? _databaseUrl = () {
  final url = Platform.environment['DATABASE_URL'];
  return (url == null || url.isEmpty) ? null : url;
}();

final Pool<void>? _pool = _databaseUrl == null
    ? null
    : createPool(_databaseUrl!);

final TokenService tokenService = TokenService(secret: _resolveSecret());

final AuthRepository authRepository = _pool == null
    ? InMemoryAuthRepository(tokens: tokenService, isProd: _isProd)
    : PostgresAuthRepository(_pool!, tokens: tokenService, isProd: _isProd);

final ProvidersRepository providersRepository = _pool == null
    ? InMemoryProvidersRepository()
    : PostgresProvidersRepository(_pool!);

// Provider auth is in-memory for now; a Postgres impl is a follow-up.
final ProviderAuthRepository providerAuthRepository =
    InMemoryProviderAuthRepository(tokens: tokenService, isProd: _isProd);

final AppointmentRepository appointmentRepository = _pool == null
    ? InMemoryAppointmentRepository()
    : PostgresAppointmentRepository(_pool!);

final SlotService slotService = SlotService(
  providersRepository,
  appointmentRepository,
);

final BookingService bookingService = BookingService(
  providersRepository,
  appointmentRepository,
  slotService,
);

final AppointmentLifecycleService appointmentLifecycleService =
    AppointmentLifecycleService(appointmentRepository, slotService);

final ProAppointmentService proAppointmentService = ProAppointmentService(
  providerAuthRepository,
  appointmentRepository,
);

/// Server-startup hook (called from the custom entrypoint `main.dart`): applies
/// migrations and seeds providers when a database is configured. No-op for
/// in-memory mode.
Future<void> initializeDatabase() async {
  final pool = _pool;
  if (pool == null) return;
  await runMigrations(pool);
  await seedProvidersIfEmpty(pool);
}
