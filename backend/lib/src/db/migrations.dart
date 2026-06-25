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
  (
    // Normalize the salon catalogue + working hours out of the providers JSONB
    // document into first-class tables (design: docs/design/
    // provider-services-availability-backend.md). The provider DTO is
    // reassembled from these by the repository, so reads / slot engine /
    // booking are unchanged. Backfilled from `data` at startup (see
    // backfillCatalogueIfNeeded), which then strips them from `data`.
    id: '0005_provider_catalogue',
    statements: [
      '''
CREATE TABLE IF NOT EXISTS provider_services (
  id                text PRIMARY KEY,
  provider_id       text NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  name              text NOT NULL,
  description       text NOT NULL DEFAULT '',
  price             double precision NOT NULL,
  price_max         double precision,
  duration_minutes  int NOT NULL,
  duration_variants jsonb NOT NULL DEFAULT '{}',
  artist_ids        jsonb NOT NULL DEFAULT '[]',
  active            boolean NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX IF NOT EXISTS provider_services_provider_idx '
          'ON provider_services(provider_id)',
      // One config row per provider (the scalar buffer + an anchor row).
      '''
CREATE TABLE IF NOT EXISTS provider_availability (
  provider_id    text PRIMARY KEY REFERENCES providers(id) ON DELETE CASCADE,
  buffer_minutes int NOT NULL DEFAULT 0
)''',
      '''
CREATE TABLE IF NOT EXISTS provider_working_hours (
  id           text PRIMARY KEY,
  provider_id  text NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  weekday      smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time   time NOT NULL,
  end_time     time NOT NULL,
  is_available boolean NOT NULL DEFAULT true
)''',
      'CREATE INDEX IF NOT EXISTS provider_working_hours_provider_idx '
          'ON provider_working_hours(provider_id)',
      '''
CREATE TABLE IF NOT EXISTS provider_breaks (
  id          text PRIMARY KEY,
  provider_id text NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  weekday     smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time  time NOT NULL,
  end_time    time NOT NULL
)''',
      'CREATE INDEX IF NOT EXISTS provider_breaks_provider_idx '
          'ON provider_breaks(provider_id)',
      '''
CREATE TABLE IF NOT EXISTS provider_blocked_dates (
  provider_id  text NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  blocked_date date NOT NULL,
  PRIMARY KEY (provider_id, blocked_date)
)''',
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

/// Moves embedded `services` + `availability` out of each provider's `data`
/// JSONB into the normalized tables (migration `0005`), then strips them from
/// `data` so there is a single source of truth. Runs once — a no-op when
/// `provider_services` already holds rows. (Design:
/// docs/design/provider-services-availability-backend.md.)
Future<void> backfillCatalogueIfNeeded(Pool<void> pool) async {
  final existing = await pool.execute(
    'SELECT count(*) AS n FROM provider_services',
  );
  if ((existing.first.toColumnMap()['n'] as int) > 0) return;

  final providers = await pool.execute('SELECT id, data FROM providers');
  if (providers.isEmpty) return;

  await pool.runTx((tx) async {
    for (final row in providers) {
      final m = row.toColumnMap();
      final id = m['id'] as String;
      final raw = m['data'];
      final doc = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : Map<String, dynamic>.from(raw as Map);
      await insertProviderCatalogue(tx, id, doc);
      await tx.execute(
        Sql.named(
          "UPDATE providers SET data = data - 'services' - 'availability' "
          'WHERE id = @id',
        ),
        parameters: {'id': id},
      );
    }
  });
}

/// Inserts the `services` + `availability` embedded in a provider [doc] into the
/// normalized tables, within [session]. Shared by the backfill and the seed.
Future<void> insertProviderCatalogue(
  Session session,
  String providerId,
  Map<String, dynamic> doc,
) async {
  for (final s in (doc['services'] as List? ?? const [])) {
    final svc = (s as Map).cast<String, dynamic>();
    await session.execute(
      Sql.named(
        'INSERT INTO provider_services '
        '(id, provider_id, name, description, price, price_max, '
        'duration_minutes, duration_variants, artist_ids, active) '
        'VALUES (@id, @pid, @name, @desc, @price, @price_max, @dur, '
        '@variants:jsonb, @artists:jsonb, @active) ON CONFLICT (id) DO NOTHING',
      ),
      parameters: {
        'id': svc['id'],
        'pid': providerId,
        'name': svc['name'],
        'desc': svc['description'] ?? '',
        'price': (svc['price'] as num).toDouble(),
        'price_max': (svc['priceMax'] as num?)?.toDouble(),
        'dur': (svc['durationMinutes'] as num).toInt(),
        'variants': jsonEncode(svc['durationVariants'] ?? const {}),
        'artists': jsonEncode(svc['artistIds'] ?? const []),
        'active': svc['active'] as bool? ?? true,
      },
    );
  }

  final availability = (doc['availability'] as Map?)?.cast<String, dynamic>();
  if (availability == null) return;

  await session.execute(
    Sql.named(
      'INSERT INTO provider_availability (provider_id, buffer_minutes) '
      'VALUES (@pid, @buffer) ON CONFLICT (provider_id) DO NOTHING',
    ),
    parameters: {
      'pid': providerId,
      'buffer': (availability['bufferMinutes'] as num?)?.toInt() ?? 0,
    },
  );

  await _insertWindows(
    session,
    providerId,
    availability['weeklySchedule'],
    table: 'provider_working_hours',
    withAvailable: true,
  );
  await _insertWindows(
    session,
    providerId,
    availability['breaks'],
    table: 'provider_breaks',
    withAvailable: false,
  );

  for (final d in (availability['blockedDates'] as List? ?? const [])) {
    await session.execute(
      Sql.named(
        'INSERT INTO provider_blocked_dates (provider_id, blocked_date) '
        'VALUES (@pid, CAST(@d AS date)) ON CONFLICT DO NOTHING',
      ),
      parameters: {'pid': providerId, 'd': (d as String).split('T').first},
    );
  }
}

/// Inserts the per-weekday `{ "0".."6": [TimeSlot] }` [schedule] into [table]
/// (working hours or breaks), one row per window.
Future<void> _insertWindows(
  Session session,
  String providerId,
  Object? schedule, {
  required String table,
  required bool withAvailable,
}) async {
  final byWeekday = (schedule as Map?)?.cast<String, dynamic>() ?? const {};
  var i = 0;
  for (final entry in byWeekday.entries) {
    final weekday = int.parse(entry.key);
    for (final slot in (entry.value as List? ?? const [])) {
      final s = (slot as Map).cast<String, dynamic>();
      final id =
          '${providerId}_${table == 'provider_breaks' ? 'br' : 'wh'}_'
          '${weekday}_${i++}';
      final cols = withAvailable
          ? '(id, provider_id, weekday, start_time, end_time, is_available)'
          : '(id, provider_id, weekday, start_time, end_time)';
      final vals = withAvailable
          ? '(@id, @pid, @wd, CAST(@start AS time), CAST(@end AS time), @avail)'
          : '(@id, @pid, @wd, CAST(@start AS time), CAST(@end AS time))';
      await session.execute(
        Sql.named('INSERT INTO $table $cols VALUES $vals'),
        parameters: {
          'id': id,
          'pid': providerId,
          'wd': weekday,
          'start': _timeOfDay(s['startTime'] as String),
          'end': _timeOfDay(s['endTime'] as String),
          if (withAvailable) 'avail': s['isAvailable'] as bool? ?? true,
        },
      );
    }
  }
}

/// `HH:mm:ss` time-of-day from an ISO timestamp (Abidjan is UTC+0, and the slot
/// engine only uses the time component).
String _timeOfDay(String iso) {
  final t = DateTime.parse(iso).toUtc();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$hh:$mm:00';
}
