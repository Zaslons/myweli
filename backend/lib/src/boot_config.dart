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
///   · it needed dev's OTP dev-code echo, because staging ran with no SMS
///     channel and there would otherwise have been no way to sign in — see
///     [echoesOtpDevCode], which is where that reasoning stopped being true.
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
  /// production-shaped staging — today, the smoke-seam disclosure warning.
  ///
  /// **No longer covers the OTP dev-code echo**; that is [echoesOtpDevCode],
  /// and the split is the point of this enum. See below.
  bool get isProd => this == Env.prod;

  /// May an OTP be handed back in an HTTP response?
  ///
  /// **True for `dev` only** — the one environment that is not reachable from
  /// the internet.
  ///
  /// This is the third question hiding inside a boolean, and it is here for the
  /// same reason [guardsOn] is: a flag that answers two questions is right until
  /// the day the answers diverge, and then it is wrong silently. The comment at
  /// the top of this enum used to say staging *needed* the echo, "because
  /// staging runs with no SMS channel and there would otherwise be no way to
  /// sign in". True when written. Then staging got `RESEND_API_KEY` and
  /// `AUTH_METHODS=google,apple,email`, so email, Google and Apple all work —
  /// and nothing revisited this line.
  ///
  /// Meanwhile staging is `ingress: all` with `allUsers` as invoker, and its
  /// hostname is committed to a **public** repository
  /// (`infra/gcp/service-staging.yaml`). So `!isProd` meant: anyone on the
  /// internet could ask for a code for **any** address and read it from the
  /// response, i.e. hold a session as any identity in whatever database is
  /// attached.
  ///
  /// **No mail was ever delivered**, and that is worth stating because the
  /// first write-up of this got it wrong: staging's `RESEND_API_KEY` is the
  /// deliberate placeholder `re_staging_placeholder_delivery_is_disabled`
  /// (`infra/gcp/90-staging.sh:213`), which satisfies the non-empty boot guard
  /// and delivers nothing. The disclosure is the whole of the exposure.
  ///
  /// The trade this makes, stated plainly: that placeholder was chosen
  /// **because** of the echo — "sign-in still works, the OTP is echoed and
  /// nothing needs to arrive". With the echo gone, **email sign-in to staging
  /// cannot complete at all.** Google and Apple still work
  /// (`AUTH_METHODS=google,apple,email`), and automation uses the seam. Mount a
  /// deliverable key if a human ever needs the email path there.
  ///
  /// Deployed environments now keep exactly one disclosure path, the Q1b seam
  /// (`auth/smoke_seam.dart`): a constant-time secret match **and** an identity
  /// in the RFC 2606 `.test` TLD. Design:
  /// docs/design/backend-staging-otp-disclosure.md.
  bool get echoesOtpDevCode => this == Env.dev;
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

/// Resolve every [dependencies] entry now, and throw **one** error naming all
/// the ones that failed.
///
/// ## Why this exists
///
/// [assertProductionBootConfig] forces exactly two guards — `DATABASE_URL` and
/// `JWT_SECRET`. **Every other guard in the composition root is a lazy Dart
/// `final`**, resolved per-request through `provider<T>` lambdas, so it fires on
/// the first request that touches it rather than at boot. That produces the
/// failure this whole file was written against, one level up:
///
///   · `/health` reads nothing, so it is green;
///   · `/providers` reads only the repository and the slot service, so it is
///     green too;
///   · therefore the deploy workflow's verify step — which checks exactly those
///     two — **passes on a service missing every lazy secret**, and the
///     revision is marked live.
///
/// The breakage then arrives per-feature, in production, at whatever hour
/// someone first tries to upload a photo. A deploy check that a broken deploy
/// passes is not a check.
///
/// ## Why one error rather than the first
///
/// A misconfigured deployment is usually missing a *set* of things — a whole
/// secret group that was never twinned into the new environment. Failing on the
/// first one turns that into a fix-deploy-fail cycle, once per variable. The
/// point is to hand the operator the entire list in the first log line.
///
/// Takes callbacks rather than values so nothing is resolved before the guard
/// runs, and takes them as an argument — the same reason everything else here is
/// a pure function: `Platform.environment` cannot be flipped by a test.
void assertEveryDependencyResolves(
  Map<String, Object? Function()> dependencies,
) {
  final failures = <String>[];
  for (final entry in dependencies.entries) {
    try {
      entry.value();
    } catch (error) {
      // Flattened and capped so eleven failures stay one readable log entry
      // rather than eleven stack traces. 500 clears every guard message in
      // `dependencies.dart` with headroom — an earlier 300 silently cut the
      // `— or set STORAGE_PROVIDER=disabled` hint off the end of the longest
      // one, which is the half an operator actually needs.
      //
      // The cap is about noise, NOT secrecy: a prefix of a leaked credential is
      // still a leaked credential. What keeps this safe is that these are our
      // own `must be set` errors, which name env VARIABLES and never values.
      final message = '$error'.replaceAll('\n', ' ');
      failures.add(
        '  - ${entry.key}: '
        '${message.length > 500 ? '${message.substring(0, 500)}…' : message}',
      );
    }
  }
  if (failures.isEmpty) return;
  throw StateError(
    'Refusing to start: ${failures.length} of ${dependencies.length} '
    'configured dependencies could not be resolved.\n'
    '${failures.join('\n')}\n'
    'Each is a lazy singleton that would otherwise have thrown on the first '
    'request that touched it, long after /health went green.',
  );
}
