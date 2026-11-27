/**
 * 06:00 UTC → production-checks.yml, started on `main` as a GitHub App.
 *
 * WHY THIS EXISTS. production-checks.yml is the monitor of everything this
 * repository cannot check at merge time, and it promises 06:00 UTC, « before
 * the Abidjan working day ». From 2026-08-27 GitHub created its scheduled run
 * 3.7 to 11.9 hours late, every day, and an hourly schedule got one tick in
 * fifteen hours (docs/design/infra-production-checks-on-time.md §2.1, §13.1).
 * GitHub's advice, and everyone else's, is to start the workflow from outside
 * through the `workflow_dispatch` API. This Worker does exactly that, once a
 * day, and nothing else (§4.1):
 *
 *   1. signs a JWT with the GitHub App's private key (RS256, WebCrypto);
 *   2. exchanges it for an installation token narrowed to this one repository
 *      and to Actions: write, valid one hour (answer: 201);
 *   3. dispatches the workflow on `main` with no inputs, so every input takes
 *      its declared default — `target` is https://myweli.com (answer: 200 with
 *      `workflow_run_id`, or 204 before GitHub added that).
 *
 * WHAT KEEPS THE KEY AWAY FROM THE DEPLOYS is not this file. An installation
 * token with Actions: write can start ANY workflow, deploys included. GitHub's
 * environment rules hold them (§4.4): `backend-production` and
 * `admin-production` need the owner's approval and accept `main` only, and an
 * App can never approve. infra/ci/98-verify-deploy-fence.sh reads them back,
 * and the App is created only after it passes.
 *
 * WHAT IT MUST NEVER DO:
 *   - log the key, the JWT or the token — one line per step, statuses and ids
 *     only, and GitHub's own `message`, which never echoes a credential;
 *   - ask for more than Actions: write on `myweli` — the token request names
 *     both, so a wider App installation still yields a narrow token;
 *   - retry a refusal — a 4xx is a configuration fault, and repeating it
 *     changes nothing; a network error or a 5xx is retried twice, 60 s apart,
 *     then the handler throws so that Cloudflare records the event as failed.
 *
 * Bindings (wrangler.toml): the IDs, repository, workflow and ref are vars;
 * GITHUB_APP_KEY is a Worker secret (PKCS#8 PEM), set over stdin from Secret
 * Manager by infra/cloudflare/97-production-checks-trigger.sh.
 *
 * Plain JavaScript, no dependency, no build step. Free plan: 10 ms CPU per cron
 * invocation, time awaiting fetch() excluded; one RSA signature is INFERRED to
 * fit, and the first invocation's CPU time is read in the dashboard (§4.3).
 */

export const API = 'https://api.github.com';
export const RETRY_DELAY_MS = 60_000;
export const ATTEMPTS = 3;

// The PEM armour, built from its label: literal armour lines one after another
// have the shape of a key to gitleaks, which scans every commit.
const armour = (edge, label) => `-----${edge} ${label}-----`;
const PKCS8_BEGIN = armour('BEGIN', 'PRIVATE KEY');
const PKCS8_END = armour('END', 'PRIVATE KEY');
const PKCS1_BEGIN = armour('BEGIN', 'RSA PRIVATE KEY');

/// The command that turns GitHub's download (PKCS#1) into what WebCrypto
/// imports (PKCS#8). Run once, on the owner's machine (§4.6).
export const CONVERT =
  'openssl pkcs8 -topk8 -nocrypt -in <downloaded>.pem -out <converted>.pem';

/// The DER bytes of a PKCS#8 PEM. Refuses GitHub's PKCS#1 download by name,
/// with the one command that fixes it, rather than failing inside WebCrypto
/// with « invalid key data ».
export function pkcs8FromPem(pem) {
  const text = String(pem ?? '').trim();
  if (text.startsWith(PKCS1_BEGIN)) {
    throw new Error(
      `GITHUB_APP_KEY is a PKCS#1 key (« BEGIN RSA PRIVATE KEY »), as GitHub downloads it. ` +
        `WebCrypto imports PKCS#8: convert it once with \`${CONVERT}\`, store the result in ` +
        `Secret Manager, and redeploy.`,
    );
  }
  if (!text.startsWith(PKCS8_BEGIN) || !text.endsWith(PKCS8_END)) {
    throw new Error('GITHUB_APP_KEY is not a PKCS#8 PEM (« BEGIN PRIVATE KEY »)');
  }
  const b64 = text.slice(PKCS8_BEGIN.length, -PKCS8_END.length).replace(/\s+/g, '');
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

const b64url = (bytes) => {
  let bin = '';
  for (const b of new Uint8Array(bytes)) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const b64urlJson = (value) => b64url(new TextEncoder().encode(JSON.stringify(value)));

/// A GitHub App JWT: RS256, issued by the App's client ID, backdated 60 s for
/// clock drift, valid 9 minutes (GitHub allows 10).
export async function signJwt({ clientId, keyPem, now = Date.now() }) {
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pkcs8FromPem(keyPem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const iat = Math.floor(now / 1000) - 60;
  const input = `${b64urlJson({ alg: 'RS256', typ: 'JWT' })}.${b64urlJson({
    iat,
    exp: iat + 60 + 9 * 60,
    iss: clientId,
  })}`;
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(input));
  return `${input}.${b64url(sig)}`;
}

const headers = (bearer) => ({
  authorization: `Bearer ${bearer}`,
  accept: 'application/vnd.github+json',
  'content-type': 'application/json',
  'x-github-api-version': '2022-11-28',
  'user-agent': 'myweli-production-checks-trigger',
});

/// GitHub's own explanation of a refusal, never the request, so never a
/// credential. Cut short: a log line, not a page.
async function why(res) {
  try {
    const body = await res.json();
    return typeof body?.message === 'string' ? ` — ${body.message.slice(0, 200)}` : '';
  } catch {
    return '';
  }
}

/// One POST with the retry rule: a network error or a 5xx is retried, a 4xx is
/// not, and anything outside `ok` throws after the last attempt.
async function post({ fetchImpl, sleep, log }, step, url, bearer, body, ok) {
  let last = '';
  for (let attempt = 1; attempt <= ATTEMPTS; attempt += 1) {
    let res;
    try {
      res = await fetchImpl(url, { method: 'POST', headers: headers(bearer), body: JSON.stringify(body) });
    } catch (e) {
      last = `${step}: network error (${e?.name ?? 'Error'})`;
      log(`${last}, attempt ${attempt} of ${ATTEMPTS}`);
      if (attempt < ATTEMPTS) await sleep(RETRY_DELAY_MS);
      continue;
    }
    if (ok.includes(res.status)) return res;
    last = `${step}: GitHub answered ${res.status}${await why(res)}`;
    log(`${last}, attempt ${attempt} of ${ATTEMPTS}`);
    if (res.status < 500) break;
    if (attempt < ATTEMPTS) await sleep(RETRY_DELAY_MS);
  }
  throw new Error(last);
}

/// The bindings, checked before anything is signed or sent. An empty ID means
/// the IDs PR (B19.3d) has not landed; nothing is guessed.
export function config(env) {
  const need = (name, pattern) => {
    const value = env?.[name];
    if (typeof value !== 'string' || value === '') throw new Error(`${name} is not set`);
    if (pattern && !pattern.test(value)) throw new Error(`${name} has an unexpected shape`);
    return value;
  };
  const repository = need('GITHUB_REPOSITORY', /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/);
  return {
    clientId: need('GITHUB_APP_CLIENT_ID', /^Iv[0-9A-Za-z._-]+$/),
    installationId: need('GITHUB_APP_INSTALLATION_ID', /^[0-9]+$/),
    keyPem: need('GITHUB_APP_KEY'),
    repository,
    repoName: repository.split('/')[1],
    workflow: need('GITHUB_WORKFLOW', /^[A-Za-z0-9_.-]+\.ya?ml$/),
    ref: need('GITHUB_REF', /^[A-Za-z0-9_./-]+$/),
  };
}

/// The whole morning. Returns what it did; throws when it could not.
export async function trigger(
  env,
  {
    fetchImpl = (...args) => fetch(...args),
    now = Date.now(),
    sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
    log = (line) => console.log(line),
  } = {},
) {
  const io = { fetchImpl, sleep, log };
  const c = config(env);
  log(`start: dispatch ${c.workflow} on ${c.ref} in ${c.repository}`);

  const jwt = await signJwt({ clientId: c.clientId, keyPem: c.keyPem, now });
  log('1/3 JWT signed');

  const tokenRes = await post(
    io,
    '2/3 installation token',
    `${API}/app/installations/${c.installationId}/access_tokens`,
    jwt,
    { repositories: [c.repoName], permissions: { actions: 'write' } },
    [201],
  );
  const minted = await tokenRes.json();
  if (typeof minted?.token !== 'string' || minted.token === '') {
    throw new Error('2/3 installation token: GitHub answered 201 without a token');
  }
  log(`2/3 installation token minted (expires ${minted.expires_at ?? 'in 1 h'})`);

  const dispatchRes = await post(
    io,
    '3/3 dispatch',
    `${API}/repos/${c.repository}/actions/workflows/${c.workflow}/dispatches`,
    minted.token,
    { ref: c.ref },
    [200, 204],
  );
  let runId = null;
  if (dispatchRes.status === 200) {
    try {
      runId = (await dispatchRes.json())?.workflow_run_id ?? null;
    } catch {
      runId = null;
    }
  }
  log(`3/3 dispatched ${c.workflow} on ${c.ref}${runId ? `: run ${runId}` : ''}`);
  return { runId };
}

export default {
  // A throw here is what makes Cloudflare record the event as failed, in the
  // dashboard's « Trigger Events ». Awaited, not handed to waitUntil, so that
  // the failure is the handler's own.
  async scheduled(_controller, env) {
    await trigger(env);
  },
};
