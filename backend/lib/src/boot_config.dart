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

/// The OAuth audience allowlists, validated by SHAPE.
///
/// ## Why shape and not membership
///
/// `GOOGLE_CLIENT_IDS` and `APPLE_CLIENT_IDS` are the audiences the backend
/// will accept on an ID token. Until now the only check was `isEmpty`, so a
/// three-entry allowlist and a five-entry one were indistinguishable — while
/// `DEPLOYMENT.md` promised "a misconfigured revision never serves". That
/// promise was true for *absent* and false for *present and wrong*.
///
/// **It deliberately does not check which ids are there.** That belongs to the
/// merge gate, where the app configs are readable; a boot guard demanding a
/// particular set would have to be told the set, which is a second copy of it.
/// And the specific set is easy to get wrong in the dangerous direction: the
/// four per-flavour mobile client ids are NEVER presented as an audience —
/// `serverClientId` makes it the web client on both platforms — so a guard
/// requiring them would refuse a release that works perfectly. That mistake has
/// already been made once here and cost a day.
///
/// What is left is worth having, because every one of these is a real way to
/// break sign-in with a value that looks configured:
///
///   * an entry that is not an audience at all (a secret name, a URL, a
///     truncated paste);
///   * the same CSV pasted into both variables — the likeliest operator error,
///     and the `MESSAGING_PROVIDER=log` shape: plausible and definitely wrong;
///   * a duplicate, which is the signature of a bad merge and costs nothing to
///     reject.
///
/// Unlike everything else in this file, the offending value IS named in the
/// error. These are published identifiers — one is committed in
/// `app_config.dart` and ships inside the app binary — so there is nothing to
/// leak, and a guard that says only "invalid" sends someone to read a secret
/// they otherwise never need to open. Capped so a pasted blob cannot flood
/// Cloud Logging.
List<String> resolveOauthAudiences(
  String? raw, {
  required String name,
  required bool required,
  required bool guardsOn,
  required RegExp shape,
  required String shapeHint,
  RegExp? forbid,
  String? forbidHint,
}) {
  // Identical to `_csvEnv` in dependencies.dart, so a good value behaves
  // exactly as it did before this function existed.
  final ids = (raw ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  if (ids.isEmpty) {
    // The original guard, preserved verbatim in meaning.
    if (guardsOn && required) {
      throw StateError(
        '$name must be set in staging and production while the matching auth '
        'method is enabled (AUTH_METHODS).',
      );
    }
    return ids;
  }

  if (!guardsOn) return ids;

  String show(String v) => v.length <= 80 ? v : '${v.substring(0, 77)}...';

  for (var i = 0; i < ids.length; i++) {
    if (!shape.hasMatch(ids[i])) {
      throw StateError(
        '$name entry $i is not a valid audience: "${show(ids[i])}". $shapeHint '
        'A value that is present and wrong reaches every request and rejects '
        'every sign-in, which is why this is fatal at boot rather than a log '
        'line.',
      );
    }
  }

  // **The likeliest operator error, and the regex above cannot catch it.** A
  // Google client id is valid reverse-DNS — `731308991240-dairlha8....apps.
  // googleusercontent.com` matches the Apple shape perfectly — so the same CSV
  // pasted into both variables passes every check made so far while making
  // Apple sign-in reject every real token. Same idea as the
  // `MESSAGING_PROVIDER=log` guard: a value that looks deliberate and is
  // definitely wrong.
  if (forbid != null) {
    for (var i = 0; i < ids.length; i++) {
      if (forbid.hasMatch(ids[i])) {
        throw StateError(
          '$name entry $i belongs to the other provider: "${show(ids[i])}". '
          '${forbidHint ?? ''}',
        );
      }
    }
  }

  final seen = <String>{};
  for (final id in ids) {
    if (!seen.add(id)) {
      throw StateError(
        '$name lists "${show(id)}" more than once. A duplicate is the '
        'signature of a bad paste or merge; it changes nothing about which '
        'tokens are accepted, so rejecting it costs nothing and catching the '
        'paste it came with may cost a great deal.',
      );
    }
  }

  return ids;
}

/// Google OAuth client ids: `<project-number>-<random>.apps.googleusercontent.com`.
///
/// The random half is optional because the legacy bare-project-number form is
/// still valid, and a guard that false-rejects a real console value on the day
/// someone pastes it is worse than no guard. `[a-z0-9]`, **not** `[a-z]`:
/// `service_files_test.dart` records the day a `[A-Z_]` class silently dropped
/// `R2_ACCOUNT_ID`, and the same slip here would reject every real id.
final RegExp kGoogleAudienceShape = RegExp(
  r'^\d{6,}(-[a-z0-9]{8,64})?\.apps\.googleusercontent\.com$',
);

/// Apple audiences: an iOS bundle id, or the web Services ID. Reverse-DNS.
///
/// Deliberately weak. Apple's Services ID is a name someone chooses, and
/// guessing its label count is how a guard false-rejects on the day it changes.
/// The one thing it must catch is a Google client id pasted in here, which the
/// cross-provider check below does far more reliably than a regex could.
final RegExp kAppleAudienceShape = RegExp(
  r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$',
);

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
