/**
 * api.myweli.com → Cloud Run. The front door, without the load balancer.
 *
 * WHY THIS EXISTS. Cloud Run domain mappings are unimplemented in
 * europe-west9, so `api.myweli.com` needed a global load balancer — $26.5 a
 * month of flat charges (forwarding-rule minimum + Cloud Armor) at zero
 * traffic. This Worker replaces it (docs/design/infra-cloudflare-front-door.md
 * §0, §1). It does exactly two things:
 *
 *   1. Forwards the request to the Cloud Run `*.run.app` hostname. Cloud Run
 *      answers 404 to any Host it does not recognise, and the runtime derives
 *      Host from the URL — so changing the URL's hostname IS the « Host
 *      rewrite » infra-gcp-migration.md §7.2 asked for.
 *   2. Adds ONE header, `X-Myweli-Origin-Auth`, whose value only this Worker
 *      and the origin hold. Production ingress is `all` (nothing else can
 *      reach run.app), so that header is what closes the direct door: the
 *      backend's origin gate (lib/src/security/origin_front_door.dart) answers
 *      403 `origin_required` to anything without it, except `GET /health`.
 *      Only after that gate passes does the backend trust `CF-Connecting-IP`
 *      for the per-IP auth limiter — a header Cloudflare sets itself on every
 *      Worker subrequest and « the Worker cannot alter » (spec §3).
 *
 * WHAT IT MUST NEVER DO (spec §5.3, each one a documented runtime fact):
 *   - set a Host header — a cross-zone Host cannot be forced and the runtime
 *     derives it from the URL; a copied `Host: api.myweli.com` would be the
 *     404 of §7.2 all over again;
 *   - copy or force Content-Length — the runtime sets it from the body source
 *     and ignores a manual value;
 *   - read the body — streaming and Content-Encoding pass through untouched
 *     only while nobody touches the stream;
 *   - follow redirects — `redirect: 'manual'` returns a 3xx as-is; `follow`
 *     would forward Authorization (cron OIDC, user JWTs) to wherever the
 *     origin pointed;
 *   - add its own client-IP header — Cloudflare's `CF-Connecting-IP` is the
 *     one the backend reads, and one fewer thing to trust is the point.
 *
 * Everything else — Authorization, Origin, Content-Type, X-Request-Id,
 * X-Smoke-Secret, X-Twilio-Signature, X-Messaging-Secret — passes through
 * verbatim (spec §3). Cron OIDC checks `aud` against the configured
 * `https://api.myweli.com`, never the Host, so the run.app Host is invisible
 * to it.
 *
 * Bindings (wrangler.toml): ORIGIN_HOST is a plain var; ORIGIN_AUTH_SECRET is a
 * Worker secret set by `wrangler secret put` from Secret Manager over stdin
 * (infra/cloudflare/96-api-front-door.sh step 3) and is never in any file.
 *
 * Plain JavaScript, no build step: `wrangler deploy` ships this file as-is.
 * Free-plan budget: 10 ms CPU per request, time awaiting fetch() excluded — a
 * header-only proxy is well inside (spec §5.3).
 */

// The one header the origin gate reads. The name is pinned byte-for-byte
// against lib/src/security/origin_front_door.dart by a wiring test, because a
// rename on one side is a silent 403 on every request.
const ORIGIN_AUTH_HEADER = 'X-Myweli-Origin-Auth';

// Answered instead of forwarding when a binding is missing. Forwarding
// WITHOUT the header would be worse than an outage: in `enforce` mode every
// request is refused anyway, and in `log` mode it would quietly pass the
// gate unverified — the exact state the header exists to prevent. A missing
// binding means the secret was never put (step 3 of the script did not run or
// did not stick), so the loud answer is the useful one.
const MISCONFIGURED = 'front door misconfigured';

export default {
  async fetch(request, env) {
    if (!env.ORIGIN_AUTH_SECRET || !env.ORIGIN_HOST) {
      // Names only, never values: this line lands in `wrangler tail`.
      console.error(
        `front_door_misconfigured missing=${
          !env.ORIGIN_AUTH_SECRET ? 'ORIGIN_AUTH_SECRET' : 'ORIGIN_HOST'
        }`,
      );
      return new Response(MISCONFIGURED, {
        status: 500,
        headers: { 'content-type': 'text/plain; charset=utf-8' },
      });
    }

    const url = new URL(request.url);
    // The load balancer's redirect url-map sent http:// to https:// on the
    // PUBLIC hostname. Without this, an http:// client would be proxied to
    // the origin over http, Cloud Run would answer 301 with a Location naming
    // its own run.app hostname, and redirect: 'manual' would hand that to the
    // client — who would follow it to the direct door and be refused.
    if (url.protocol === 'http:') {
      url.protocol = 'https:';
      return Response.redirect(url.toString(), 301);
    }
    url.hostname = env.ORIGIN_HOST; // Host follows the URL — the rewrite
    const headers = new Headers(request.headers);
    headers.set(ORIGIN_AUTH_HEADER, env.ORIGIN_AUTH_SECRET);

    // Returned verbatim: the Response body streams to the client without
    // being read here, so compression and Content-Length pass through.
    return fetch(
      new Request(url, {
        method: request.method,
        headers,
        body: request.body, // streamed, not buffered
        redirect: 'manual', // 3xx returned as-is; never follows with Authorization
      }),
    );
  },
};
