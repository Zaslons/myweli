# Android reaches Cloudflare over HTTP/3 — the « Pas de connexion » fix — design spec

| | |
|---|---|
| **Status** | **Draft 2026-11-18** — written on the owner's « Yes, write it ». Nothing is built from it: no code, no dependency change, no console action until the owner answers §10. |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-18 |
| **PRD ref / phase** | Reliability and security, cross-cutting · V1 (it blocks the Play release) |
| **Module** | `mobile/` networking on Android, both apps (Pro and consumer); the Android network security config; the API front-door Worker if §4.5's relay is chosen |
| **Found by** | Step 6 of [android-play-release.md](android-play-release.md) §4: build 785 from the internal track, on the owner's Galaxy, over the owner's Wi-Fi (Orange CI fibre), 2026-11-18 |
| **Builds on** | [android-play-release.md](android-play-release.md) · [android-tls-artifact-gate.md](android-tls-artifact-gate.md) (GHSA-frr6-h895-5pxp) · [mobile-flutter-3.47-upgrade.md](mobile-flutter-3.47-upgrade.md) · [backend-r2-presigned-put.md](backend-r2-presigned-put.md) (the upload path) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails · myweli-backend-guardrails (only for §4.5's relay) |

Every claim is **read** (observed, with how and when), **sourced** (a link),
or **inferred** (and from what). Times are UTC, which is also the owner's local
time.

## 1. Goal & scope

**What a salon sees today.** On Android, over an Orange CI fibre Wi-Fi, MyWeli
Pro opens and every action that needs the server fails. At sign-in,
« Continuer avec l'e-mail » answers « Pas de connexion. Réessayez. » after
about 15 seconds. Photos never load. On the same Wi-Fi the iPhone app works,
slowly, and Chrome on the same phone works.

**Goal.** Every network call of both Android apps succeeds on that network,
with TLS kept at least as strong as it is now. No change to the iPhone apps
beyond the Sentry upgrade (§4.6).

**In scope:**
- one HTTP transport for both Android apps (§4.1–§4.3);
- the one place on Android that bypasses it (§4.4);
- the upload path to R2 (§4.5), confirmed by a device read first;
- Sentry 9 → 10, which the transport needs (§4.6);
- telemetry and guards, so that a fallback or a bypass is seen (§4.7, §7);
- the certificate-trust gap that moving off `dart:io` opens on Android 7–9
  (§5).

**Out of scope, stated:**
- **The iPhone apps' transport.** They work today, slowly (R6). Moving them to
  `cupertino_http` (Apple's URLSession, which also speaks HTTP/3) is a
  follow-up with its own spec (§10, Q5).
- **The website's pages.** Browsers already use HTTP/3 to Cloudflare (R5). Its
  photo uploads share §4.5's exposure; the relay, if built, serves them too.

## 2. What was measured

All on 2026-11-18, the Galaxy (Android, Play Services present) on the owner's
Wi-Fi, unless stated. The probes were diagnostic copies of the app (never
committed) and a separate probe app; `adb logcat` was read live.

| # | Read | Result |
|---|------|--------|
| R1 | `dart:io` → `api.myweli.com` and `cdn.myweli.com`, IPv4 and IPv6, from the app (12:46) | `HandshakeException: Connection terminated during handshake` after 15.3 s, all four |
| R2 | `dart:io` → `www.google.com`, same app, same minute | TCP 26 ms, TLS OK 155 ms (IPv4); TLS OK 322 ms (IPv6) |
| R3 | Cronet over TCP (no QUIC hint) → the API | three timeouts at 30 s; the same engine → Google: 204 in 485 ms |
| R4 | Cronet with QUIC on and hints for the API and CDN hosts (13:28) | `http=http/3 tls=TLSv1.3 kex=X25519MLKEM768`, 115–217 ms. Then a full sign-in with `revue@myweli.test`: `otp/request` 202, `verify` 200, then `/me/provider`, the dashboard, `/me/salons`, notifications, invitations and `/me/devices`, all 200. The salon's photos were shown from the CDN |
| R5 | Chrome on the Galaxy, Cloudflare's trace page | « http/3 » (the owner read it) |
| R6 | The iPhone app (`dart:io`) and the Mac, same Wi-Fi | both succeed, slowly; macOS `curl` (LibreSSL, classic X25519 only) succeeds |
| R7 | The Mac, a 1,500-byte packet with « don't fragment » to Cloudflare (188.114.96.2, 1.1.1.1) and to 8.8.8.8 | the Orange box (192.168.1.1) answers « frag needed and DF set (MTU 1460) » for every destination; 1,460-byte packets pass. The phone's own probe had learned a path MTU of 1,460 to Cloudflare |
| R8 | The hosts the apps use (`curl -I`, `dig`, the code on `main` `1854bfc5`) | see the table below |
| R9 | The certificate chain served (`openssl s_client`) | `api.myweli.com` and `cdn.myweli.com`: leaf → Google Trust Services WE1 → GTS Root R4 → cross-signed by GlobalSign Root CA |

The hosts the apps use (R8):

| Host | What it carries | Read |
|------|-----------------|------|
| `api.myweli.com` | the API | Cloudflare; `alt-svc: h3` |
| `cdn.myweli.com` | photos (R2's public bucket) | Cloudflare; no `alt-svc`, but it answered HTTP/3 when hinted (R4) |
| `<account>.r2.cloudflarestorage.com` | uploads | Cloudflare; answers HTTP/1.1; no `alt-svc` |
| `basemaps.cartocdn.com` | map tiles (CARTO) | Varnish, not Cloudflare |
| `ingest.de.sentry.io` | crash reports | not Cloudflare |

**Why now** (sourced, from the research of 2026-11-18):
- Flutter 3.47.8 moved `dart:io` to a BoringSSL that offers **X25519MLKEM768
  first**, sending a post-quantum and a classical key share in every
  ClientHello. Flutter 3.47.7 offered X25519, P-256 and P-384 only
  ([DEPS 3.47.7](https://github.com/flutter/flutter/blob/3.47.7/DEPS),
  [DEPS 3.47.8](https://github.com/flutter/flutter/blob/3.47.8/DEPS),
  [BoringSSL `e748facb`](https://github.com/google/boringssl/commit/e748facbaa5ef6e53aa51c68328e2b2245325e72)).
- The change came inside the eMudhra security roll that
  [mobile-flutter-3.47-upgrade.md](mobile-flutter-3.47-upgrade.md) took for
  GHSA-frr6-h895-5pxp. Neither changelog mentions it. BoringSSL's own note
  warns of the larger ClientHello.
- So every build since that upgrade offers it. That includes AAB 785 and
  iPhone build 781 (inferred: both are on 3.47.9).

**Inferred mechanism** (from R1–R7; not proven, and the decision does not rest
on it):
- The post-quantum key share is 1,216 bytes against 32 for X25519
  ([Cloudflare](https://blog.cloudflare.com/pq-2024/)). It makes the
  ClientHello about 1.8 KB, so it is the first packet of the handshake larger
  than this link's 1,460-byte MTU. Split ClientHellos are a known failure
  class ([tldr.fail](https://tldr.fail/); Cloudflare Radar now flags « Split
  ClientHello »).
- Classic X25519 (R6, `curl`) never sends a packet that large during the
  handshake, and QUIC caps its packets well below 1,460 bytes. Both work.
- Apple's network stack recovers, slowly (R6). Android's does not, before
  Cloudflare gives up on the handshake (R1, R3).
- Why Google's servers work with the same ClientHello (R2) is **not
  established**.

**What does not depend on the mechanism:**
- QUIC works on this network (R4, R5), measured end to end in the real app.
- Any network that behaves like this box will show the same failure.
- Orange fibre boxes are common on salons' and homes' Wi-Fi in Abidjan. That
  is inferred from the owner's own connection; no market figure is claimed.

## 3. Options considered

| | Option | Verdict |
|---|--------|---------|
| A | Do nothing; tell salons to use mobile data | **Rejected.** Many salons only have Wi-Fi on the counter phone; the owner's test phone has no data SIM. |
| B | Disable TLS 1.3 on the Cloudflare zone | **Rejected: it would not even work.** The client sends its key share in the ClientHello before the server picks a version ([RFC 8446 §4.2.8](https://www.rfc-editor.org/rfc/rfc8446#section-4.2.8)), so the large packet still goes out. It would also downgrade every visitor. Cloudflare offers no setting for visitors' key-exchange groups ([PQC docs](https://developers.cloudflare.com/ssl/post-quantum-cryptography/)). |
| C | `ok_http` (OkHttp over TCP, the phone's own TLS, classic key exchange today) | **Rejected as the long-term fix.** It works only while Android's TLS offers no post-quantum key share; once it does, the failure returns. |
| D | Change the certificate chain | **Rejected.** What is lost is the client's ClientHello, not the server's certificates. |
| E | Make `dart:io` offer classic key exchange only | **Not available.** `SecurityContext` sets no groups; [dart-lang/sdk#63670](https://github.com/dart-lang/sdk/issues/63670) (open) proposes such an API. |
| F | Go back to Flutter 3.47.7 | **Rejected.** It removes the post-quantum key share but reopens GHSA-frr6-h895-5pxp (High). |
| G | A DNS-only (not proxied) API hostname, straight to Cloud Run | **Rejected.** It bypasses the Worker front door and its origin gate. |
| H | **Cronet, the Chrome network stack from Google Play Services, with HTTP/3 (QUIC) and hints for our Cloudflare hosts** | **Chosen.** Measured working end to end (R4). It keeps TLS 1.3 with post-quantum key exchange, Play Services updates it with Chrome's fixes, and it falls back to TCP where QUIC is blocked (§4.3). |
| I | Ask Orange, Cloudflare and Dart to fix it | **Reported, not relied on** (§9). |

## 4. Design

### 4.1 One transport, passed explicitly

A new file, `mobile/lib/core/net/app_http_transport.dart`, owns the choice and
holds **one shared client** for the process:

- **On Android, one `CronetEngine`.** It is built lazily on the first request,
  after the Flutter binding exists: release builds froze when the engine was
  built in `main()` before it
  ([dart-lang/http#1241](https://github.com/dart-lang/http/issues/1241)). It is
  never closed, and is built with:
  - `enableQuic: true`;
  - `quicHints` for every Cloudflare host the app calls (§4.2), on port 443;
  - `useBuiltInDnsResolver: false`: the system resolver, which honours
    Android's Private DNS. Cronet's built-in resolver fails on some cellular
    networks ([CHANGELOG 1.10.0](https://github.com/dart-lang/http/blob/master/pkgs/cronet_http/CHANGELOG.md));
  - `cacheMode: CacheMode.disabled`, with no `storagePath`. The app has its
    own image cache, and a disk cache would keep copies of API answers that
    hold personal data;
  - a user agent naming the app and its version, nothing personal.

  The client is `CronetClient.fromCronetEngine(engine, closeEngine: false)`.
- **If the engine cannot be built,** the client is `dart:io`'s `IOClient`,
  exactly today's behaviour, and the fallback is reported once (§4.7). Without
  Play Services, Cronet throws a Java `RuntimeException` (« Unable to find any
  Cronet provider »), which cronet_http rethrows as a `JThrowable`
  ([source](https://github.com/dart-lang/http/blob/23495b011f/pkgs/cronet_http/lib/src/cronet_client.dart)).
  This is seen in the field on /e/OS and on phones whose Cronet module fails to
  load, so the catch is broad.
- **On iOS and every other platform,** today's `dart:io` client, unchanged.

**How it reaches every call:**
1. **Passed explicitly** to each `Api*Service`, the admin service, the version
   gate and the image cache's file service (`TimeoutCacheManager`). All of them
   already take an optional `http.Client`. It is also given to flutter_map's
   `NetworkTileProvider(httpClient:)` in `carto_basemap.dart`. No service
   closes its client (read: no `.close()` under `mobile/lib`), so one shared
   client is safe.
2. **`http.runWithClient` as a backstop,** around the whole app in every entry
   (`main.dart`, and `runProApp` for both Pro entries). It catches any
   third-party `Client()` that was missed.

   It is only the backstop: package:http itself warns that Flutter does not
   guarantee which zone a callback runs in, and recommends passing the client
   ([client.dart](https://github.com/dart-lang/http/blob/master/pkgs/http/lib/src/client.dart)).
   R4 used the zone alone and worked, but the design does not rely on it.

### 4.2 The hinted hosts

- **The API host,** taken from `AppConfig.apiBaseUrl` at build time, so a
  staging build hints its own host.
- **`cdn.myweli.com`,** for the photos (R8, R4).

Hosts that are not on Cloudflare (CARTO, Google, Sentry) get no hint. They use
TCP through Cronet, which works on this network (R3: Cronet → Google). Each
hint installs a permanent QUIC alternative for that host
([cronet_context.cc](https://chromium.googlesource.com/chromium/src/+/refs/tags/143.0.7445.0/components/cronet/cronet_context.cc)).

### 4.3 When QUIC is blocked

Chromium races a QUIC attempt against a TCP one for a hinted host. If QUIC
fails, TCP carries on at once. QUIC is then marked broken for that host for
300 s, doubling on each repeat up to 2 days, but only if TCP succeeded
([job_controller.cc](https://chromium.googlesource.com/chromium/src/+/refs/tags/143.0.7445.0/net/http/http_stream_factory_job_controller.cc),
[broken_alternative_services.cc](https://chromium.googlesource.com/chromium/src/+/refs/tags/143.0.7445.0/net/http/broken_alternative_services.cc)).

So:
- **On a network that blocks UDP 443,** requests go over TCP, which works there
  as it does today.
- **On this fibre,** TCP fails too, so QUIC is never marked broken.
- **The edge case** (inferred): a phone that was just on a UDP-blocking network
  arrives on this fibre with QUIC still marked broken in memory. Requests fail
  until the mark expires (5 minutes the first time) or the app restarts, since
  nothing is persisted. The app's existing « Réessayer » covers it.
- **A network that is both MTU-limited and blocks QUIC** is not solved here.
  The telemetry of §4.7 would show it.

### 4.4 The bypass

Flutter's `NetworkImage` and `Image.network` use `dart:io`'s `HttpClient`
directly, so neither the explicit client nor the zone reaches them
([_network_image_io.dart](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/painting/_network_image_io.dart)).
On `main` `1854bfc5` there are two uses:

- **`screens/provider/artists/artist_list_screen.dart:131`** — `NetworkImage`
  for a team member's avatar, in the Pro app. It becomes the cached image
  provider on `TimeoutCacheManager.images`, like every other photo in the app.
- **`screens/admin/widgets/admin_remote_image.dart:77`** — `Image.network`, in
  the admin console only. No Android flavour builds it (read:
  `build.gradle.kts` has `consumer` and `pro` only). It stays, allowed by name
  in the guard of §7.

### 4.5 Uploads to R2 — HTTP/3 will not reach them

Gallery photos, KYC documents and deposit screenshots go up as a presigned
`PUT` straight to `<account>.r2.cloudflarestorage.com` (read:
`api_image_upload_service.dart`, `api_pro_kyc_service.dart`,
`api_appointment_service.dart:149`). What is known about that host:

- **No HTTP/3.** It answered HTTP/1.1 with no `alt-svc` (R8). A QUIC handshake
  to `r2.cloudflarestorage.com` did not complete, while `www.cloudflare.com`'s
  did (research probe).
- **Post-quantum over TCP.** It agreed to X25519MLKEM768 over TCP: the
  handshake that fails on this network.
- **No other host.** Presigned URLs work only on that S3 API host, not on a
  custom domain such as `cdn.myweli.com`
  ([R2 docs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/)).

So an upload from Android on this network is **expected to fail**, with Cronet
as with `dart:io`. The website's uploads from a phone on the same Wi-Fi may
fail too. This is inferred, not measured.

**First, the read (V-U):**
- A probe build on the Galaxy, on the owner's Wi-Fi, sends a `PUT` of about
  1 MB with a deliberately invalid signature to the real upload host. R2
  refuses it with a 403, so nothing is stored.
- It sends it twice: through Cronet and through `dart:io`.
- A 403 means the transport works. A timeout or handshake failure confirms the
  expectation.

**Then, if it fails, a relay on the API's front door (recommended):**

`PUT https://api.myweli.com/_upload/<bucket>/<key>?<signed query>` is served
by the existing Worker (`infra/cloudflare/worker/api-front-door`), which:
- forwards the request to the fixed R2 host, signature and signed headers
  unchanged;
- accepts only `PUT` and only our three buckets;
- adds no credentials, so R2's signature check stays the only authority;
- holds no R2 secret.

The app reaches the relay over HTTP/3 (§4.2: the API host is already hinted),
and the Worker reaches R2 inside Cloudflare. The backend's upload ticket gives
the relay URL. The cost and limits fit:
- the body streams through, so the Worker's 10 ms of CPU does not cover the
  wait;
- the request body limit is 100 MB on our plan
  ([limits](https://developers.cloudflare.com/workers/platform/limits/)).

The alternative is a Worker with an R2 binding (`env.BUCKET.put`). It needs an
upload token of our own, because a binding cannot check a presigned signature.
That means a new secret and new authorisation code, so it is not recommended.

**The relay is its own addendum** to this spec — backend, Worker and the
website's uploads with their CORS — built only on the owner's OK after V-U
(§10, Q7). Until it ships, uploads on this kind of network stay broken. The
rest of the app works.

Two upload details hold either way:
- **The whole body is held in memory.** cronet_http reads a request body fully
  before sending it ([source](https://github.com/dart-lang/http/blob/23495b011f/pkgs/cronet_http/lib/src/cronet_client.dart)).
  The upload services already hold the compressed bytes, so nothing changes.
- **The content type is set by us.** cronet_http adds
  `application/octet-stream` when a body has no `content-type`. Ours always
  sends the signed headers from the ticket, so the signature still matches.

### 4.6 Sentry 9 → 10.4 or later

`cronet_http` 1.10.1 needs `jni` ^1.1.0. `sentry_flutter` 9 pins `jni` 0.14.2,
10.0–10.1 allow only `>=1.0.0 <1.1.0`, and 10.2 onwards accept ^1.1.0
([pub.dev](https://pub.dev/api/packages/sentry_flutter)). Versions 10.0–10.3
also require Android minSdk 26; **10.4.0 lowers it to 24**, our floor. So the
floor is **`sentry_flutter` ≥ 10.4.0**. 10.5.0 is the latest (2026-11-17), and
R4 ran on it.

What 10 changes for us
([migration guide](https://docs.sentry.io/platforms/dart/guides/flutter/migration/v9-to-v10/),
[CHANGELOG](https://github.com/getsentry/sentry-dart/blob/main/CHANGELOG.md)):

- **Our options are unchanged:** `dsn`, `environment`, `release`,
  `attachScreenshot`, `attachViewHierarchy`, `enableAutoSessionTracking`,
  `enableAppHangTracking`, and `beforeSend(event, hint)`. The compiler is the
  check.
- **`_scrub` keeps working.** It sets fields to null rather than calling
  `copyWith`, which 10 removes. Under 10, `beforeSend` runs before sampling,
  and a `beforeSend` that throws drops the event.
- **iOS changes too.** Deployment target 15.0, which ours already is (read:
  `project.pbxproj`, `Podfile`). Sentry Cocoa moves to v9. **sentry_flutter
  ships through Swift Package Manager only.** Our iOS project uses CocoaPods
  for everything else, so PR 1 must prove an iOS release build, and its
  binary reads (app-store-forms §11.3), before it merges.
- **Crash reports do not use the Dart client.** On Android and iOS, events go
  to the native SDK (`FileSystemTransport`), not through `http.Client`
  ([source](https://github.com/getsentry/sentry-dart/blob/10.4.0/packages/flutter/lib/src/sentry_flutter.dart)).
  The transport change does not touch them. They go to `ingest.de.sentry.io`,
  which is not on Cloudflare.

Two build notes from 2026-11-18:
- **A clean build is needed.** Sentry 10 failed to compile on stale build files
  (« SentryFlutterReplayRecorder ») until `flutter clean`.
- **The R8 mapping upload** of [android-play-release.md](android-play-release.md)
  §6 is re-read on the next AAB.

### 4.7 Telemetry

- **A tag on every Sentry event:** `net.transport` is `cronet` or `dartio`.
  When the fallback is used, `net.fallback` gives the exception's type only.
  No URL, no personal data.
- **One Sentry message the first time a process falls back to `dart:io`.**
  This is how devices without Play Services, or with a broken provider, become
  visible. Crash reports travel through the native SDK, so they arrive even on
  a network where our own calls fail.
- **No per-request logging.** The diagnostic `MYWELI_NET_DIAG` prints never
  ship.

## 5. Security

### 5.1 What stays the same or improves

- **TLS stays TLS 1.3 with post-quantum key exchange.** R4 read
  `X25519MLKEM768`. Options C and F would have meant classic key exchange.
- **Cronet is Google's code, updated by Play Services.** Security fixes arrive
  without a release of ours. The other side is that its behaviour can change
  under us; §4.7's telemetry is the watch.
- **No disk cache, no stored cookies** (§4.1). Authentication is unchanged:
  bearer tokens in headers.
- **The TLS gate stays.** `dart:io` is still the fallback, so
  android-tls-artifact-gate.md's read of every AAB keeps its purpose.

### 5.2 The gap: certificate checks on Android 7–9

**Who checks certificates changes, for traffic through Cronet:**
- **Today:** the BoringSSL inside `libflutter.so`, which carries an explicit
  block of the eight compromised eMudhra intermediates. The TLS gate reads that
  block in every AAB.
- **With Cronet:** Android's own trust store, through `X509TrustManager`.
  Cronet on Android uses neither Chrome's root store nor Chrome's CRL set
  ([features.gni](https://chromium.googlesource.com/chromium/src/+/refs/tags/143.0.7445.0/net/features.gni),
  [crl_set.cc](https://chromium.googlesource.com/chromium/src/+/refs/tags/143.0.7445.0/net/cert/crl_set.cc)).
  This is sourced for open-source Cronet and inferred for the Play Services
  build.

**Why that matters on old Android:**
- The advisory's intermediates chain to emSign ECC Root CA - G3. Six of them
  are also cross-signed to Sectigo's « AAA Certificate Services »
  ([advisory](https://github.com/dart-lang/sdk/security/advisories/GHSA-frr6-h895-5pxp),
  [disclosure](https://emudhra.we-have-a-problem.com/)).
- That root is in the Android 7.0–9 system stores; emSign's roots arrive only
  in Android 11 (AOSP `system/ca-certificates`, per release tag).
- Google says Android received « an equivalent update through Google Play
  Services » ([Google](https://blog.google/security/protecting-chrome-and-android-users-from-compromised-emudhra-intermediate-ca-certificates/)).
  How that update was delivered, and which versions it reached, is **not
  confirmed**.

So on an Android 7–9 phone that did not get that update, a certificate forged
through one of those intermediates would pass Cronet's check for
`api.myweli.com`. The attacker also needs to sit on the network path. Every
app on that phone that relies on the system's checks is exposed the same
way. But it is
a step back from today's `dart:io`, and the advisory is rated High.

**Proposed fix: trust anchors for our own domains** (§10, Q6, recommended).
Add a `domain-config` to the Android network security config for `myweli.com`
and its subdomains:
- **Trust only** the roots that Cloudflare's Universal SSL issues from, bundled
  in the app:
  - Google Trust Services (GTS Root R1–R4, and GlobalSign Root CA for the
    cross-sign served today, R9);
  - Let's Encrypt (ISRG Root X1, X2);
  - SSL.com, with its Certum cross-sign
    ([Cloudflare's CA list](https://developers.cloudflare.com/ssl/reference/certificate-authorities/)).
- **Leave out** AAA Certificate Services and the emSign roots.
- **The platform applies it per hostname,** for Cronet as for the system
  (inferred: Cronet verifies through
  `X509TrustManagerExtensions.checkServerTrusted(chain, authType, host)`, which
  applies the domain's config on Android 7+). **To be proven on a device,
  red first:** a debug build whose config trusts an unrelated root for
  `myweli.com` must fail to connect through Cronet.

What it buys:
- **The eMudhra path is closed** for our domains on every Android version,
  whatever Play Services delivered.
- **Let's Encrypt works on Android 7.0,** whose store lacks ISRG Root X1. If
  Cloudflare switches our certificate to it, today's app would fail on 7.0.
  Universal SSL can switch CAs without notice
  ([limitations](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/)).

**Its risk is the reverse:** if Cloudflare issues from a CA outside the list,
Android users can no longer connect, and the `dart:io` fallback does not help.
Two guards cover it:
- **A daily CI check,** like the existing Access check, that the chain served
  for `api.myweli.com` and `cdn.myweli.com` ends in a bundled root. It goes red
  before a switch is likely to matter.
- **Optionally, a fixed CA.** An Advanced Certificate with a chosen CA (about
  $10 a month) makes the list one CA family. This is not recommended now; the
  daily check is enough to start.

## 6. Performance

- **Cold start:** the engine is built once, on the first request. The cost is
  measured on the Galaxy and the old Samsung at the device pass. The budget is
  under 50 ms on the Galaxy.
- **Latency:** on this network, from a 15-second failure to 115–217 ms (R4).
  Elsewhere HTTP/3 is expected to be equal or faster.
- **APK size:** Play Services Cronet adds no native Cronet library, only the
  Java glue and `jni`'s small library. CI's `apk-size` job (under 30 MB, arm64
  consumer) measures it, and the number goes in the PR. For Q4: embedding
  Cronet instead (`--dart-define=cronetHttpNoPlay=true`) is a build-time
  switch costing about 8 MB uncompressed by the only official figure; the
  all-ABI library is 13.7 MB
  ([README](https://github.com/dart-lang/http/blob/master/pkgs/cronet_http/README.md),
  [Maven](https://dl.google.com/android/maven2/org/chromium/net/cronet-embedded/143.7445.0/cronet-embedded-143.7445.0.aar)).

## 7. Testing plan

**Unit tests** (`test/core/net/`). The engine builder is injected so they run
on the Mac. They check that:
- on Android, with an engine that builds, the factory returns the Cronet
  client, and builds the engine once across many calls;
- when building throws, it returns `dart:io` and reports once;
- off Android, it never builds an engine;
- the hints are exactly the API host and `cdn.myweli.com`;
- the cache is disabled, no storage path is set, and the built-in DNS resolver
  is off.

**Guards** (`test/infra/`):
- No `http.Client()`, `NetworkImage(`, `Image.network(`, `HttpClient(` or
  `IOClient(` under `mobile/lib` outside `core/net/`. The admin file of §4.4
  is allowed by name.
- Every `Api*Service` construction in dependency injection passes the shared
  client.
- `main.dart` and `runProApp` install the backstop.
- `carto_basemap.dart` gives the shared client to its tile provider.
- The network security config's domain list and bundled roots match §5.2's
  list.

**Mutations on committed code.** Each must turn a test red:
- drop a hint;
- drop the backstop from one entry;
- construct one service without the shared client;
- restore `NetworkImage`;
- make the fallback silent;
- remove a bundled root or add AAA Certificate Services.

**Device reads.** [android-play-release.md](android-play-release.md) §5 gains
these rows. On the Galaxy, over Orange fibre, with the internal-track build:
1. the first screen loads;
2. sign-in with `revue@myweli.test`;
3. the dashboard and photos load;
4. the map shows tiles with the real key;
5. after the relay, one gallery upload on the review salon (a production
   write: asked first);
6. a Sentry test event arrives tagged `net.transport=cronet`.

Then the same on mobile data where a SIM exists, and on the old Samsung, whose
Android version also decides how much §5.2 matters there. An iPhone smoke pass
confirms only Sentry moved there.

**The red-first device read of §5.2:** a debug build that trusts the wrong root
fails, and the real config connects.

## 8. Rollout

1. **The owner answers §10.**
2. **The read V-U** (§4.5): a probe build on the Galaxy, on the owner's yes.
3. **PR 1 — Sentry ≥ 10.4.** Both platforms, a clean build of each, the iOS
   release build read (§4.6).
4. **PR 2 — the transport.** The image fix, the trust anchors (if Q6 is yes),
   the daily chain check and the guards.
5. **The relay addendum, then PR 3,** if V-U fails and Q7 is yes.
6. **The next AAB** (0.0.2, the next build number), built by
   `tool/release_build.sh android pro` from `main` with every read of step 5.
   Then the internal track on the owner's yes, and the device pass.
   - PR 3 can follow in a later build: the rest of the app works without it.
   - The closed test (step 7) waits for it. A salon that cannot add a photo is
     a failed test.
7. **The consumer app** gets the same transport through `main.dart`, and ships
   it with its own first Android build.

Each PR reverts on its own; reverting PR 2 restores today's behaviour.

## 9. Reports upstream

Each report is posted only on the owner's yes, with no personal data:
- **Dart SDK:** a comment on [dart-lang/sdk#63670](https://github.com/dart-lang/sdk/issues/63670).
  The roll for 3.13.7 turned the post-quantum key share on, unannounced, and a
  ClientHello split by a 1,460-byte link fails in 15 s on Android. It asks for
  a way to choose groups.
- **Cloudflare:** a support ticket with packet captures, as their TLS 1.3 page
  suggests
  ([TLS 1.3](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/tls-13/)).
  A post-quantum ClientHello over TCP fails from Orange CI fibre while QUIC
  works.
- **Orange CI:** only if the owner wants to. The box answers « frag needed »
  correctly (R7), so the fault is not established as theirs.

## 10. Questions for the owner

- **Q1.** Approve the design: Cronet with HTTP/3 for both Android apps, the
  client passed explicitly, `dart:io` as the fallback, Sentry ≥ 10.4 first.
- **Q2.** Run the upload read V-U: a probe build on the Galaxy, nothing
  stored.
- **Q3.** File the reports of §9: Dart and Cloudflare.
- **Q4.** Devices without Play Services: keep the `dart:io` fallback for now?
  Recommended: yes. It works wherever the network is healthy, and the telemetry
  counts such devices before anyone pays 8 MB or more for an embedded Cronet.
- **Q5.** iPhone: a later spec for `cupertino_http`, so the iPhone gets HTTP/3
  instead of today's slow success. Recommended: after the Play release.
- **Q6.** The trust anchors of §5.2 for our domains, with the daily chain
  check. Recommended: yes, in PR 2. The alternative is to accept the Android
  7–9 gap and say so in LAUNCH §6.3.
- **Q7.** If V-U fails, the upload relay on the API's front door (§4.5).
  Recommended: yes, as an addendum before PR 3.

## 11. Not confirmed

Each of these is either read in §7's device pass or stays stated here:
- That Play Services' Cronet uses the platform trust store, like open-source
  Cronet. Inferred from Chromium's build flags; §5.2's red-first read proves it
  for our case.
- How Google's eMudhra update reached Android 7–9, and whether Sectigo revoked
  the cross-signs.
- Whether the real `<account>.r2.cloudflarestorage.com` host behaves like the
  bare one probed. V-U reads it.
- That Workers can forward a presigned `PUT` to the S3 API host unchanged. The
  relay addendum's first test reads it.
- Why `www.google.com` succeeds over `dart:io` on this network while Cloudflare
  fails.
- Whether the native Sentry SDKs' own traffic is affected on this network.
  Inferred no (not Cloudflare); the device pass's test event reads it.
- Embedded Cronet's size per ABI at the current version.
