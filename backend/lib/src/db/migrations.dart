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
  (
    // Consumer favorites: saved providers per user. The PK doubles as the
    // list-by-user index and makes add idempotent (ON CONFLICT DO NOTHING).
    id: '0006_favorites',
    statements: [
      '''
CREATE TABLE IF NOT EXISTS favorites (
  user_id     text NOT NULL,
  provider_id text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, provider_id)
)''',
    ],
  ),
  (
    // Consumer reviews: one per completed appointment (UNIQUE appointment_id →
    // upsert), attributed to the artist who performed it. Provider/artist
    // ratings stay denormalized; this is the source of truth for recompute.
    id: '0007_reviews',
    statements: [
      '''
CREATE TABLE IF NOT EXISTS reviews (
  id             text PRIMARY KEY,
  appointment_id text NOT NULL UNIQUE,
  provider_id    text NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  user_id        text NOT NULL,
  user_name      text NOT NULL,
  rating         smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  text           text NOT NULL DEFAULT '',
  verified       boolean NOT NULL DEFAULT true,
  artist_id      text,
  artist_name    text,
  service_name   text NOT NULL DEFAULT '',
  photo_urls     jsonb NOT NULL DEFAULT '[]',
  created_at     timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX IF NOT EXISTS reviews_provider_idx '
          'ON reviews(provider_id, created_at DESC)',
    ],
  ),
  (
    // Provider KYC: the submitted documents' metadata + private storage keys
    // (the bytes live in a private bucket; only the key + metadata are here).
    id: '0008_kyc_docs',
    statements: [
      "ALTER TABLE provider_users "
          "ADD COLUMN IF NOT EXISTS kyc_docs jsonb NOT NULL DEFAULT '[]'",
    ],
  ),
  (
    // Booking duration-overlap exclusion (T11 follow-up). The exact-start
    // unique index only blocks identical starts; this rejects any time-range
    // overlap per provider atomically (concurrency-safe). Range is half-open
    // [start, start+duration) so back-to-back bookings are allowed. Buffer
    // stays an app-level slot-engine concern.
    id: '0009_booking_overlap_exclusion',
    statements: [
      'ALTER TABLE appointments '
          'ADD COLUMN IF NOT EXISTS duration_minutes int NOT NULL DEFAULT 30',
      // `ends_at` is stored (computed in Dart = start + duration) because
      // `timestamptz + interval` is STABLE, not IMMUTABLE, so it can't appear
      // in the constraint expression. Ranging over two plain columns is
      // immutable. Empty table at migration time → the default is unused.
      'ALTER TABLE appointments '
          'ADD COLUMN IF NOT EXISTS ends_at timestamptz NOT NULL DEFAULT now()',
      'CREATE EXTENSION IF NOT EXISTS btree_gist',
      '''
ALTER TABLE appointments ADD CONSTRAINT appointments_no_overlap
  EXCLUDE USING gist (
    provider_id WITH =,
    tstzrange(appointment_date, ends_at) WITH &&
  ) WHERE (status IN ('pending', 'confirmed'))''',
    ],
  ),
  (
    id: '0010_admin',
    statements: [
      // Internal Myweli staff. Seeded super-admin; no self-signup.
      '''
CREATE TABLE admins (
  id text PRIMARY KEY,
  email text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now()
)''',
      '''
CREATE TABLE admin_refresh_tokens (
  token_hash text PRIMARY KEY,
  admin_id text NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
  family_id text NOT NULL,
  rotated boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX admin_refresh_family_idx '
          'ON admin_refresh_tokens(family_id)',
      // Append-only record of every privileged admin action.
      '''
CREATE TABLE audit_log (
  id text PRIMARY KEY,
  actor_admin_id text NOT NULL,
  action text NOT NULL,
  target_type text NOT NULL,
  target_id text,
  reason text,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX audit_log_created_idx ON audit_log(created_at DESC)',
      'CREATE INDEX audit_log_actor_idx ON audit_log(actor_admin_id)',
    ],
  ),
  (
    id: '0011_review_moderation',
    statements: [
      "ALTER TABLE reviews "
          "ADD COLUMN moderation_status text NOT NULL DEFAULT 'visible'",
      // Consumer reports (FR-REV-005). One report per (review, reporter).
      '''
CREATE TABLE review_reports (
  id text PRIMARY KEY,
  review_id text NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  reporter_user_id text NOT NULL,
  reason text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_by text,
  resolved_at timestamptz,
  UNIQUE (review_id, reporter_user_id)
)''',
      "CREATE INDEX review_reports_open_idx "
          "ON review_reports(review_id) WHERE status = 'open'",
    ],
  ),
  (
    id: '0012_provider_mgmt',
    statements: [
      // Admin marketplace management: suspend (hide from discovery + block new
      // bookings) and feature (homepage placement). Real columns so discovery
      // can filter/order on them (the rest of the provider lives in `data`).
      "ALTER TABLE providers ADD COLUMN status text NOT NULL DEFAULT 'active'",
      'ALTER TABLE providers '
          'ADD COLUMN featured boolean NOT NULL DEFAULT false',
    ],
  ),
  (
    id: '0013_user_status',
    statements: [
      // Admin can ban a consumer (blocks login + booking). active | banned.
      "ALTER TABLE users ADD COLUMN status text NOT NULL DEFAULT 'active'",
    ],
  ),
  (
    id: '0014_disputes',
    statements: [
      // Admin-recorded dispute cases on a booking (no money moves — no-custody).
      '''
CREATE TABLE disputes (
  id text PRIMARY KEY,
  appointment_id text NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  opened_by text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  reason text NOT NULL,
  resolution text,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_by text,
  resolved_at timestamptz
)''',
      "CREATE INDEX disputes_open_idx ON disputes(created_at DESC) "
          "WHERE status = 'open'",
      'CREATE INDEX disputes_appointment_idx ON disputes(appointment_id)',
    ],
  ),
  (
    id: '0015_messaging',
    statements: [
      // Outbound-message log (FR-NOTIF-001). OTP is NOT stored here (sent via
      // MessagingService.sendOtp). Design: docs/design/messaging-notifications.md.
      '''
CREATE TABLE outbound_messages (
  id text PRIMARY KEY,
  recipient_phone text NOT NULL,
  channel text NOT NULL,
  template text NOT NULL,
  params jsonb NOT NULL DEFAULT '{}',
  body text NOT NULL,
  status text NOT NULL DEFAULT 'queued',
  provider_message_id text,
  created_at timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX outbound_messages_recipient_idx '
          'ON outbound_messages(recipient_phone, created_at DESC)',
      'CREATE INDEX outbound_messages_provider_idx '
          'ON outbound_messages(provider_message_id)',
      // Promotional opt-out (transactional always sends).
      '''
CREATE TABLE messaging_opt_out (
  phone text PRIMARY KEY,
  opted_out boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
)''',
    ],
  ),
  (
    id: '0016_appointment_reminders',
    statements: [
      // Idempotency log for the 24h/2h reminder scheduler (one row per
      // appointment+kind). Design: docs/design/messaging-notifications.md.
      '''
CREATE TABLE appointment_reminders (
  appointment_id text NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  kind text NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (appointment_id, kind)
)''',
    ],
  ),
  (
    id: '0017_device_tokens',
    statements: [
      // FCM device-token registry (one token → one user). Design:
      // docs/design/push-notifications-fcm.md.
      '''
CREATE TABLE device_tokens (
  token text PRIMARY KEY,
  user_id text NOT NULL,
  role text NOT NULL,
  platform text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX device_tokens_user_idx ON device_tokens(user_id)',
    ],
  ),
  (
    id: '0018_notifications',
    statements: [
      // In-app notification feed (per consumer). Design:
      // docs/design/notification-center.md.
      '''
CREATE TABLE notifications (
  id text PRIMARY KEY,
  user_id text NOT NULL,
  type text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  route text,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX notifications_user_idx '
          'ON notifications(user_id, created_at DESC)',
    ],
  ),
  (
    id: '0019_notification_preferences',
    statements: [
      // Per-user notification opt-out prefs (default all on). Design:
      // docs/design/notification-preferences.md.
      '''
CREATE TABLE notification_preferences (
  user_id text PRIMARY KEY,
  reminders boolean NOT NULL DEFAULT true,
  marketing boolean NOT NULL DEFAULT true,
  push boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
)''',
    ],
  ),
  (
    id: '0020_appointments_client_phone_idx',
    statements: [
      // Index the manual-booking phone so the consumer list's auto-sync match
      // (FR-APPT-008) stays index-backed. Design: docs/design/appointment-auto-sync.md.
      'CREATE INDEX appointments_client_phone_idx '
          'ON appointments(client_phone) WHERE client_phone IS NOT NULL',
    ],
  ),
  (
    id: '0021_providers_slug',
    statements: [
      // Public web slug per provider (myweli.ci/<slug>). Backfill from the seed
      // data jsonb, then enforce uniqueness. Design: docs/design/web-m1-backend-glue.md.
      'ALTER TABLE providers ADD COLUMN IF NOT EXISTS slug text',
      "UPDATE providers SET slug = data->>'slug' WHERE slug IS NULL",
      'CREATE UNIQUE INDEX IF NOT EXISTS providers_slug_idx ON providers(slug)',
    ],
  ),
  (
    id: '0022_auth_social_email',
    statements: [
      // Auth overhaul (docs/design/auth-social-email.md): identity = verified
      // email (Google/Apple/email-OTP); phone becomes an optional, initially
      // unverified contact attribute (verified later via SMS/Termii).
      'ALTER TABLE users ALTER COLUMN phone_number DROP NOT NULL',
      // Phone is contact data now, not an identity → uniqueness is no longer
      // an invariant (the dormant phone-OTP path is disabled via AUTH_METHODS).
      'ALTER TABLE users DROP CONSTRAINT IF EXISTS users_phone_number_key',
      'ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified boolean NOT NULL DEFAULT false',
      // Existing accounts proved their number via SMS-OTP.
      'UPDATE users SET phone_verified = true WHERE phone_number IS NOT NULL',
      'ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified boolean NOT NULL DEFAULT false',
      'ALTER TABLE users ADD COLUMN IF NOT EXISTS google_sub text',
      'ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_sub text',
      'ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_provider text',
      'CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_key '
          'ON users (lower(email)) WHERE email IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS users_google_sub_key '
          'ON users (google_sub) WHERE google_sub IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS users_apple_sub_key '
          'ON users (apple_sub) WHERE apple_sub IS NOT NULL',
      'CREATE INDEX IF NOT EXISTS users_phone_number_idx '
          'ON users (phone_number) WHERE phone_number IS NOT NULL',
      '''
CREATE TABLE IF NOT EXISTS email_otp_codes (
  email        text PRIMARY KEY,
  code_hash    text NOT NULL,
  expires_at   timestamptz NOT NULL,
  attempts_left int NOT NULL,
  resends_left  int NOT NULL
)''',
    ],
  ),
  (
    id: '0023_provider_auth_social',
    statements: [
      // Pro auth overhaul (docs/design/pro-auth-social.md): salon identity =
      // verified email (Google/Apple/email-OTP); phone stays the REQUIRED
      // salon contact (uniqueness dropped — no longer an identity).
      'ALTER TABLE provider_users DROP CONSTRAINT IF EXISTS provider_users_phone_number_key',
      'ALTER TABLE provider_users ADD COLUMN IF NOT EXISTS email_verified boolean NOT NULL DEFAULT false',
      'ALTER TABLE provider_users ADD COLUMN IF NOT EXISTS google_sub text',
      'ALTER TABLE provider_users ADD COLUMN IF NOT EXISTS apple_sub text',
      'ALTER TABLE provider_users ADD COLUMN IF NOT EXISTS auth_provider text',
      'CREATE UNIQUE INDEX IF NOT EXISTS provider_users_email_lower_key '
          'ON provider_users (lower(email)) WHERE email IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS provider_users_google_sub_key '
          'ON provider_users (google_sub) WHERE google_sub IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS provider_users_apple_sub_key '
          'ON provider_users (apple_sub) WHERE apple_sub IS NOT NULL',
      'CREATE INDEX IF NOT EXISTS provider_users_phone_number_idx '
          'ON provider_users (phone_number)',
      '''
CREATE TABLE IF NOT EXISTS provider_email_otp_codes (
  email        text PRIMARY KEY,
  code_hash    text NOT NULL,
  expires_at   timestamptz NOT NULL,
  attempts_left int NOT NULL,
  resends_left  int NOT NULL
)''',
    ],
  ),
  (
    id: '0024_salon_clients',
    statements: [
      // Module `clients` C1 (docs/design/clients-c1.md): the salon client
      // base, DERIVED from bookings. One row per (salon, platform user) or
      // (salon, guest phone); tags jsonb (codebase idiom); stats stay
      // computed — only last_visit_at is denormalized (list sort).
      '''
CREATE TABLE IF NOT EXISTS salon_clients (
  id            text PRIMARY KEY,
  provider_id   text NOT NULL,
  user_id       text,
  display_name  text NOT NULL,
  phone         text,
  tags          jsonb NOT NULL DEFAULT '[]',
  last_visit_at timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE UNIQUE INDEX IF NOT EXISTS salon_clients_user_key '
          'ON salon_clients (provider_id, user_id) WHERE user_id IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS salon_clients_phone_key '
          'ON salon_clients (provider_id, phone) WHERE phone IS NOT NULL',
      'CREATE INDEX IF NOT EXISTS salon_clients_list_idx '
          'ON salon_clients (provider_id, last_visit_at DESC NULLS LAST)',
      '''
CREATE TABLE IF NOT EXISTS salon_client_notes (
  id                text PRIMARY KEY,
  client_id         text NOT NULL REFERENCES salon_clients(id)
                      ON DELETE CASCADE,
  author_account_id text NOT NULL,
  body              text NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX IF NOT EXISTS salon_client_notes_client_idx '
          'ON salon_client_notes (client_id, created_at DESC)',
      // Salon-scoped audit trail (T46/T39; `access` A2 reuses it).
      '''
CREATE TABLE IF NOT EXISTS provider_audit_log (
  id               text PRIMARY KEY,
  provider_id      text NOT NULL,
  actor_account_id text NOT NULL,
  action           text NOT NULL,
  target_id        text,
  meta             jsonb NOT NULL DEFAULT '{}',
  created_at       timestamptz NOT NULL DEFAULT now()
)''',
      'CREATE INDEX IF NOT EXISTS provider_audit_log_idx '
          'ON provider_audit_log (provider_id, created_at DESC)',
      // Stats resolve a client's bookings by user_id / guest phone.
      'CREATE INDEX IF NOT EXISTS appointments_provider_user_idx '
          'ON appointments (provider_id, user_id)',
      'CREATE INDEX IF NOT EXISTS appointments_provider_client_phone_idx '
          'ON appointments (provider_id, client_phone) '
          'WHERE client_phone IS NOT NULL',
      // Backfill 1/2 — platform users who ever booked. A linked client's
      // phone is stored only when VERIFIED (T33/T49 bar).
      '''
INSERT INTO salon_clients
  (id, provider_id, user_id, display_name, phone, last_visit_at)
SELECT gen_random_uuid()::text,
       a.provider_id,
       a.user_id,
       COALESCE(u.name, 'Client'),
       CASE WHEN u.phone_verified THEN u.phone_number END,
       MAX(a.appointment_date) FILTER (WHERE a.status = 'completed')
FROM appointments a
JOIN users u ON u.id = a.user_id
WHERE a.user_id <> 'manual'
GROUP BY a.provider_id, a.user_id, u.name, u.phone_number, u.phone_verified
ON CONFLICT DO NOTHING''',
      // Backfill 2/2 — walk-in guests (manual bookings keyed by phone). A
      // guest phone equal to a user's VERIFIED phone at the same salon merges
      // into that user row (skipped here — the user row already claims it).
      '''
INSERT INTO salon_clients
  (id, provider_id, user_id, display_name, phone, last_visit_at)
SELECT gen_random_uuid()::text,
       a.provider_id,
       NULL,
       COALESCE(MAX(a.client_name) FILTER (WHERE a.client_name IS NOT NULL),
                'Client'),
       a.client_phone,
       MAX(a.appointment_date) FILTER (WHERE a.status = 'completed')
FROM appointments a
WHERE a.user_id = 'manual' AND a.client_phone IS NOT NULL
GROUP BY a.provider_id, a.client_phone
ON CONFLICT DO NOTHING''',
    ],
  ),
  (
    id: '0025_appointment_arrived',
    statements: [
      // Journal J1/J2 (docs/design/journal-j1-grid.md): the in-day
      // « Client arrivé » flag — a timestamp on confirmed bookings.
      'ALTER TABLE appointments ADD COLUMN IF NOT EXISTS '
          'arrived_at timestamptz',
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
        '(id, slug, category, commune, rating, name, description, address, data) '
        'VALUES (@id, @slug, @category, @commune, @rating, @name, @description, '
        '@address, @data:jsonb)',
      ),
      parameters: {
        'id': p['id'],
        'slug': p['slug'],
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
      // Strip the now-normalized keys in Dart and write the cleaned document
      // back (the `data` column is stored as a JSON-string scalar, like the
      // rest of the codebase, so the jsonb `-` key-delete operator can't be
      // used). Single source of truth: services/availability now live in the
      // tables only.
      doc.remove('services');
      doc.remove('availability');
      await tx.execute(
        Sql.named('UPDATE providers SET data = @data:jsonb WHERE id = @id'),
        parameters: {'id': id, 'data': jsonEncode(doc)},
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
  if (availability != null) {
    await insertProviderAvailability(session, providerId, availability);
  }
}

/// Inserts a provider's [availability] (buffer + working hours + breaks +
/// blocked dates) into the normalized tables, within [session]. Assumes any
/// prior rows for [providerId] are already cleared (the caller replaces
/// wholesale or starts empty). Shared by the backfill and `replaceAvailability`.
Future<void> insertProviderAvailability(
  Session session,
  String providerId,
  Map<String, dynamic> availability,
) async {
  await session.execute(
    Sql.named(
      'INSERT INTO provider_availability (provider_id, buffer_minutes) '
      'VALUES (@pid, @buffer) ON CONFLICT (provider_id) DO UPDATE SET '
      'buffer_minutes = EXCLUDED.buffer_minutes',
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
