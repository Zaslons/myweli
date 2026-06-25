import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../providers_repository.dart';

/// One migration: an id and its ordered statements (each `execute` runs a
/// single statement in extended mode).
typedef _Migration = ({String id, List<String> statements});

/// Schema migrations, applied in order and recorded in `schema_migrations` so
/// each runs at most once. Embedded as Dart (not loose `.sql` files) so they
/// ship with `dart_frog build` and are unit-testable. (docs/BACKEND.md §1)
const List<_Migration> _migrations = [
  (
    id: '0001_init',
    statements: [
      '''
CREATE TABLE IF NOT EXISTS users (
  id          text PRIMARY KEY,
  phone_number text UNIQUE NOT NULL,
  name        text,
  email       text,
  avatar_url  text,
  created_at  timestamptz NOT NULL DEFAULT now()
)''',
      '''
CREATE TABLE IF NOT EXISTS otp_codes (
  phone_number text PRIMARY KEY,
  code_hash    text NOT NULL,
  expires_at   timestamptz NOT NULL,
  attempts_left int NOT NULL,
  resends_left  int NOT NULL
)''',
      '''
CREATE TABLE IF NOT EXISTS refresh_tokens (
  token_hash text PRIMARY KEY,
  user_id    text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role       text NOT NULL,
  family_id  text NOT NULL,
  rotated    boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX IF NOT EXISTS refresh_tokens_family_idx ON refresh_tokens(family_id)',
      '''
CREATE TABLE IF NOT EXISTS providers (
  id          text PRIMARY KEY,
  category    text,
  commune     text,
  rating      double precision NOT NULL DEFAULT 0,
  name        text,
  description text,
  address     text,
  data        jsonb NOT NULL
)''',
      'CREATE INDEX IF NOT EXISTS providers_category_idx ON providers(category)',
      'CREATE INDEX IF NOT EXISTS providers_commune_idx ON providers(commune)',
      'CREATE INDEX IF NOT EXISTS providers_rating_idx ON providers(rating DESC)',
    ],
  ),
  (
    id: '0002_appointments',
    statements: [
      '''
CREATE TABLE IF NOT EXISTS appointments (
  id                        text PRIMARY KEY,
  user_id                   text NOT NULL,
  provider_id               text NOT NULL,
  service_ids               jsonb NOT NULL,
  artist_id                 text,
  appointment_date          timestamptz NOT NULL,
  status                    text NOT NULL,
  total_price               double precision NOT NULL,
  deposit_amount            double precision NOT NULL DEFAULT 0,
  balance_due               double precision NOT NULL DEFAULT 0,
  cancellation_window_hours int NOT NULL DEFAULT 24,
  client_name               text,
  client_phone              text,
  notes                     text,
  deposit_screenshot_url    text,
  created_at                timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX IF NOT EXISTS appointments_user_idx ON appointments(user_id)',
      'CREATE INDEX IF NOT EXISTS appointments_provider_date_idx '
          'ON appointments(provider_id, appointment_date)',
      // Atomic double-booking guard: at most one non-cancelled booking per
      // (provider, exact start). Duration-overlap exclusion is a follow-up.
      'CREATE UNIQUE INDEX IF NOT EXISTS appointments_slot_unique '
          "ON appointments(provider_id, appointment_date) "
          "WHERE status IN ('pending', 'confirmed')",
    ],
  ),
  (
    id: '0003_provider_accounts',
    statements: [
      '''
CREATE TABLE IF NOT EXISTS provider_users (
  id                  text PRIMARY KEY,
  phone_number        text UNIQUE NOT NULL,
  name                text,
  business_name       text NOT NULL,
  business_type       text NOT NULL,
  email               text,
  address             text,
  verification_status text NOT NULL DEFAULT 'pending',
  rejection_reason    text,
  provider_id         text,
  created_at          timestamptz NOT NULL DEFAULT now()
)''',
      // Separate from the consumer `otp_codes` (both phone-keyed) so a phone
      // used as both consumer and provider doesn't collide.
      '''
CREATE TABLE IF NOT EXISTS provider_otp_codes (
  phone_number  text PRIMARY KEY,
  code_hash     text NOT NULL,
  expires_at    timestamptz NOT NULL,
  attempts_left int NOT NULL,
  resends_left  int NOT NULL
)''',
    ],
  ),
  (
    id: '0004_provider_refresh_tokens',
    statements: [
      // Provider refresh-token families (hashed, rotating, reuse → family
      // revoke). `account_id` is the provider_users row (the JWT `sub`) —
      // separate from the consumer `refresh_tokens` table, which FKs to users.
      '''
CREATE TABLE IF NOT EXISTS provider_refresh_tokens (
  token_hash text PRIMARY KEY,
  account_id text NOT NULL REFERENCES provider_users(id) ON DELETE CASCADE,
  family_id  text NOT NULL,
  rotated    boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX IF NOT EXISTS provider_refresh_tokens_family_idx '
          'ON provider_refresh_tokens(family_id)',
    ],
  ),
];

/// Applies any not-yet-applied migrations. Idempotent.
Future<void> runMigrations(Pool<void> pool) async {
  await pool.execute(
    'CREATE TABLE IF NOT EXISTS schema_migrations '
    '(id text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())',
  );
  for (final migration in _migrations) {
    final applied = await pool.execute(
      Sql.named('SELECT 1 FROM schema_migrations WHERE id = @id'),
      parameters: {'id': migration.id},
    );
    if (applied.isNotEmpty) continue;
    await pool.runTx((tx) async {
      for (final statement in migration.statements) {
        await tx.execute(statement);
      }
      await tx.execute(
        Sql.named('INSERT INTO schema_migrations (id) VALUES (@id)'),
        parameters: {'id': migration.id},
      );
    });
  }
}

/// Seeds the `providers` table from [seedProviders] when it is empty, so the
/// read slice has data (mirrors the in-memory seed).
Future<void> seedProvidersIfEmpty(Pool<void> pool) async {
  final count = await pool.execute('SELECT count(*) AS n FROM providers');
  if ((count.first.toColumnMap()['n'] as int) > 0) return;
  for (final p in seedProviders) {
    await pool.execute(
      Sql.named(
        'INSERT INTO providers '
        '(id, category, commune, rating, name, description, address, data) '
        'VALUES (@id, @category, @commune, @rating, @name, @description, '
        '@address, @data:jsonb)',
      ),
      parameters: {
        'id': p['id'],
        'category': p['category'],
        'commune': p['commune'],
        'rating': p['rating'],
        'name': p['name'],
        'description': p['description'],
        'address': p['address'],
        'data': jsonEncode(p),
      },
    );
  }
}
