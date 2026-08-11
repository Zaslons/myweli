/// Boot-time configuration resolution, as **pure functions** (G1).
///
/// `Platform.environment` is process-wide and immutable in Dart — a test cannot
/// flip `ENV` and re-enter the composition root, and a spawned isolate shares
/// the same environment. So the only way to test a production fail-fast in
/// process is to take the raw value as an argument. That is the shape
/// `AuthMethods.parse(String?)` already uses (`auth/auth_methods.dart:9`), and
/// this file follows it.
///
/// **Why this exists at all.** Before G1 there was no test for ANY of the
/// composition root's prod fail-fasts — `dependencies.dart` had five importers
/// and not one was a test file. The guards were real and entirely unproven.
library;

/// Which deployment this process is.
///
/// **Three values, because two cannot express staging.** `ENV` used to be read
/// as `(ENV ?? 'dev') == 'prod'` — one boolean answering two different
/// questions: *is this the real thing?* and *should the production guards be
/// on?* For `dev` and `prod` those answers coincide, so the conflation was
/// invisible. Staging is where they diverge, and it diverges in **both**
/// directions:
///
///   · it needs production's fail-fast on missing configuration ([guardsOn]),
///     because an environment whose guards are off is not rehearsing anything;
///   · it needs dev's OTP dev-code echo (`!`[isProd]), because staging runs
///     with no SMS channel and there would otherwise be no way to sign in.
///
/// A single flag cannot supply both, which is why `ENV=staging` against the old
/// expression produced an environment that was neither. Design:
/// docs/design/infra-staging.md §1.1.
enum Env {
  dev,
  staging,
  prod;

  /// Parses `ENV`. Unset, empty or whitespace → [dev].
  ///
  /// **An unrecognised value throws rather than falling back.** The old
  /// expression treated every typo as dev, so `ENV=production`, `ENV=Prod` or a
  /// stray character on the production service would silently disable every
  /// guard in this file — the exact failure the guards exist to prevent,
  /// reached by spelling. Failing at boot is loud, immediate and fixable;
  /// `main.dart` awaits this path before `serve()`, so the port never binds.
  static Env parse(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == null || v.isEmpty) return Env.dev;
    return switch (v) {
      'dev' || 'development' || 'local' => Env.dev,
      'staging' || 'stage' => Env.staging,
      'prod' || 'production' => Env.prod,
      _ => throw StateError(
        'ENV="$raw" is not a known environment — use dev, staging or prod. '
        'An unrecognised value was previously treated as dev, which silently '
        'disabled every production guard.',
      ),
    };
  }

  /// Run the production guards: fail fast on missing configuration.
  ///
  /// True for **staging and prod**.
  bool get guardsOn => this != Env.dev;

  /// This is the real thing — real users, real data, real money.
  ///
  /// True for **prod only**. Reserved for what must differ even from a
  /// production-shaped staging: echoing OTP dev-codes in API responses, and the
  /// smoke-seam disclosure warning.
  bool get isProd => this == Env.prod;
}

/// The Postgres URL, or null when the app should run on in-memory repositories.
///
/// **Throws in production when unset — and that guard is the whole point.**
/// `JWT_SECRET` has always failed fast; `DATABASE_URL` never did. It was
/// nullable, and every repository silently fell back to its `InMemory` variant,
/// so a production deploy missing this one variable would serve a **green,
/// healthy-looking API in which every booking is lost the moment the instance
/// recycles** — `/health` reporting `ok` throughout, because `/health` never
/// touches the database.
///
/// On Render that was theoretical: the value arrived through a service
/// reference (`fromDatabase`) that cannot be forgotten. On Cloud Run it is a
/// one-line omission in a deploy command, which is exactly why G1 closes it
/// before the cutover rather than after.
///
/// Trimmed, so a platform that injects an unset reference as `"  "` is treated
/// as unset rather than handed to `createPool` as whitespace. Every other env
/// read in `dependencies.dart` already trims (`_envOrNull`); this one did not.
String? resolveDatabaseUrl(String? raw, {required bool guardsOn}) {
  final url = raw?.trim();
  if (url != null && url.isNotEmpty) return url;
  if (guardsOn) {
    throw StateError(
      'DATABASE_URL must be set in staging and production — refusing to start '
      'on in-memory repositories, which would serve a healthy-looking API and '
      'lose every booking on the next restart.',
    );
  }
  return null;
}

/// The HS256 signing key for access tokens.
///
/// The guard itself is unchanged from `dependencies.dart`; it moved here so it
/// can be tested, and so [assertProductionBootConfig] can force it to fire at
/// **boot** rather than on the first request (see that function).
String resolveJwtSecret(String? raw, {required bool guardsOn}) {
  final secret = raw?.trim();
  if (secret != null && secret.isNotEmpty) return secret;
  if (guardsOn) {
    throw StateError('JWT_SECRET must be set in staging and production');
  }
  // Dev-only fallback so local runs work without setup; never used in prod.
  return 'dev-insecure-secret-change-me';
}

/// Resolve every production-required value **now**, so a misconfigured
/// deployment dies before the port is bound.
///
/// **This is not redundant with the individual guards — it is what makes them
/// boot-time.** `tokenService` is a lazy `final`, and at boot it is only
/// touched when `ADMIN_EMAIL`/`ADMIN_PASSWORD` happen to be set. Without them
/// the `JWT_SECRET` guard first runs on the **first request**, long after the
/// port is bound and `/health` has gone green — so an orchestrator's health
/// check passes, the revision is marked live, traffic shifts to it, and only
/// then does every request start failing.
///
/// A guard that fires after the health check is not a guard against a bad
/// deploy. Called from `initializeDatabase()`, which `main.dart` awaits before
/// `serve()`.
void assertProductionBootConfig({
  required String? databaseUrl,
  required String? jwtSecret,
  required bool guardsOn,
}) {
  resolveDatabaseUrl(databaseUrl, guardsOn: guardsOn);
  resolveJwtSecret(jwtSecret, guardsOn: guardsOn);
}
