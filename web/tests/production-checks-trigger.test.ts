// @vitest-environment node
import { execFileSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';

/// **The 06:00 trigger of the daily production check, and the fence that keeps
/// it away from the deploys** (docs/design/infra-production-checks-on-time.md
/// §4, §13.2; B19.3a).
///
/// GitHub created production-checks.yml's 06:00 run 4 to 12 hours late for three
/// months. A Cloudflare Worker now starts it as a GitHub App, whose token can
/// start ANY workflow: so this file holds the Worker's request shapes, `ontime`'s
/// rules, the read-back of the environment rules, and the wiring that keeps the
/// three agreeing. It lives under web/ because a file under backend/ starts
/// deploy-backend.yml on merge (web-swiss-cards.md §9).

const REPO = join(__dirname, '..', '..');
const read = (file: string) => readFileSync(join(REPO, file), 'utf8');

/// YAML `#` comments, blanked: a guard matched inside a comment is the footgun
/// this repository keeps finding (verification guardrails §2).
const stripYaml = (src: string) => src.replace(/(^|\s)#.*$/gm, '$1');
const job = (src: string, name: string) =>
  stripYaml(src).match(new RegExp(`^  ${name}:$[\\s\\S]*?(?=^  \\S[^\\n]*:$|$(?![\\s\\S]))`, 'm'))?.[0] ?? '';

// Loaded by absolute path: web/ type-checks without allowJs, and a specifier
// TypeScript cannot resolve stays out of `tsc`.
const load = (file: string) => import(/* @vite-ignore */ join(REPO, file));

type Log = string[];
type Call = { url: string; method: string; headers: Record<string, string>; body: string };
type Answer = { status: number; json?: unknown } | Error;

/// A stand-in `fetch` that records each call and answers from a queue.
function fakeFetch(answers: Answer[]) {
  const calls: Call[] = [];
  const fetchImpl = async (url: string, init: { method?: string; headers?: Record<string, string>; body?: string }) => {
    calls.push({ url, method: init.method ?? 'GET', headers: init.headers ?? {}, body: init.body ?? '' });
    const next = answers.shift();
    if (!next) throw new Error(`unexpected call: ${init.method ?? 'GET'} ${url}`);
    if (next instanceof Error) throw next;
    return new Response(next.json === undefined ? null : JSON.stringify(next.json), { status: next.status });
  };
  return { calls, fetchImpl };
}

const b64urlDecode = (s: string) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

describe('the Worker « myweli-production-checks-trigger »', () => {
  const W = 'infra/cloudflare/worker/production-checks-trigger/src/index.js';
  let worker: {
    signJwt: (o: { clientId: string; keyPem: string; now?: number }) => Promise<string>;
    pkcs8FromPem: (pem: string) => ArrayBuffer;
    trigger: (env: Record<string, string>, o: object) => Promise<{ runId: number | null }>;
    config: (env: Record<string, string>) => unknown;
    CONVERT: string;
    RETRY_DELAY_MS: number;
  };
  let keyPem = '';
  let publicKey: CryptoKey;

  beforeAll(async () => {
    worker = await load(W);
    const pair = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
      true,
      ['sign', 'verify'],
    );
    const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
    // Armour built from its label, as in the Worker: gitleaks scans every commit.
    const armour = (edge: string) => `-----${edge} ${'PRIVATE KEY'}-----`;
    keyPem = `${armour('BEGIN')}\n${der.match(/.{1,64}/g)!.join('\n')}\n${armour('END')}\n`;
    publicKey = pair.publicKey;
  });

  const NOW = Date.parse('2026-11-28T06:00:02Z');
  const env = () => ({
    GITHUB_APP_CLIENT_ID: 'Iv23liTESTCLIENT',
    GITHUB_APP_INSTALLATION_ID: '4242',
    GITHUB_APP_KEY: keyPem,
    GITHUB_REPOSITORY: 'Zaslons/myweli',
    GITHUB_WORKFLOW: 'production-checks.yml',
    GITHUB_REF: 'main',
  });
  const TOKEN = 'ghs_INSTALLATIONTOKENNEVERLOGGED';

  /// Runs the morning with a stand-in GitHub, recording logs and sleeps.
  async function morning(answers: Answer[], overrides: Record<string, string> = {}) {
    const { calls, fetchImpl } = fakeFetch(answers);
    const log: Log = [];
    const sleeps: number[] = [];
    let error: Error | null = null;
    let result: { runId: number | null } | null = null;
    try {
      result = await worker.trigger(
        { ...env(), ...overrides },
        { fetchImpl, now: NOW, log: (l: string) => log.push(l), sleep: async (ms: number) => void sleeps.push(ms) },
      );
    } catch (e) {
      error = e as Error;
    }
    return { calls, log, sleeps, error, result };
  }
  const minted = { status: 201, json: { token: TOKEN, expires_at: '2026-11-28T07:00:02Z' } };

  it('signs an RS256 JWT issued by the client ID, backdated 60 s, valid 9 minutes, that verifies', async () => {
    const jwt = await worker.signJwt({ clientId: 'Iv23liTESTCLIENT', keyPem, now: NOW });
    const [h, p, s] = jwt.split('.');
    expect(JSON.parse(b64urlDecode(h).toString())).toEqual({ alg: 'RS256', typ: 'JWT' });
    const claims = JSON.parse(b64urlDecode(p).toString());
    expect(claims).toEqual({ iat: NOW / 1000 - 60, exp: NOW / 1000 + 540, iss: 'Iv23liTESTCLIENT' });
    expect(claims.exp - claims.iat).toBeLessThanOrEqual(600);
    const ok = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      publicKey,
      new Uint8Array(b64urlDecode(s)),
      new TextEncoder().encode(`${h}.${p}`),
    );
    expect(ok).toBe(true);
  });

  it('refuses GitHub’s PKCS#1 download by name, with the command that converts it', () => {
    const pkcs1 = keyPem.replace('BEGIN PRIVATE KEY', 'BEGIN RSA PRIVATE KEY').replace('END PRIVATE KEY', 'END RSA PRIVATE KEY');
    expect(() => worker.pkcs8FromPem(pkcs1)).toThrow(worker.CONVERT);
    expect(worker.CONVERT).toContain('openssl pkcs8 -topk8 -nocrypt');
    expect(() => worker.pkcs8FromPem('not a key')).toThrow('not a PKCS#8 PEM');
  });

  it('asks for a token narrowed to myweli and Actions: write, then dispatches exactly {"ref":"main"}', async () => {
    const r = await morning([minted, { status: 200, json: { workflow_run_id: 987 } }]);
    expect(r.error).toBeNull();
    expect(r.result).toEqual({ runId: 987 });
    expect(r.calls).toHaveLength(2);

    const [token, dispatch] = r.calls;
    expect(token.method).toBe('POST');
    expect(token.url).toBe('https://api.github.com/app/installations/4242/access_tokens');
    expect(JSON.parse(token.body)).toEqual({ repositories: ['myweli'], permissions: { actions: 'write' } });
    expect(token.headers.authorization).toMatch(/^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);

    expect(dispatch.method).toBe('POST');
    expect(dispatch.url).toBe('https://api.github.com/repos/Zaslons/myweli/actions/workflows/production-checks.yml/dispatches');
    // No `inputs`: every input takes its declared default, so `target` is myweli.com.
    expect(dispatch.body).toBe('{"ref":"main"}');
    expect(dispatch.headers.authorization).toBe(`Bearer ${TOKEN}`);
  });

  it('accepts the older 204 to a dispatch, and nothing but 201 to the token', async () => {
    expect((await morning([minted, { status: 204 }])).result).toEqual({ runId: null });

    const ok200 = await morning([{ status: 200, json: { token: TOKEN } }]);
    expect(ok200.error?.message).toContain('GitHub answered 200');
    expect(ok200.calls).toHaveLength(1);

    const empty = await morning([{ status: 201, json: {} }]);
    expect(empty.error?.message).toContain('without a token');
  });

  it('retries a 5xx and a network error twice, 60 s apart, then throws', async () => {
    const recovered = await morning([{ status: 502 }, new TypeError('fetch failed'), minted, { status: 204 }]);
    expect(recovered.error).toBeNull();
    expect(recovered.calls).toHaveLength(4);
    expect(recovered.sleeps).toEqual([60_000, 60_000]);

    const down = await morning([minted, { status: 503 }, { status: 503 }, { status: 503 }]);
    expect(down.error?.message).toContain('3/3 dispatch: GitHub answered 503');
    expect(down.calls).toHaveLength(4);
    expect(down.sleeps).toEqual([60_000, 60_000]);
  });

  it('does not retry a refusal: a 4xx is a configuration fault, and says GitHub’s reason', async () => {
    const r = await morning([minted, { status: 422, json: { message: 'Workflow does not have workflow_dispatch trigger' } }]);
    expect(r.calls).toHaveLength(2);
    expect(r.sleeps).toEqual([]);
    expect(r.error?.message).toBe('3/3 dispatch: GitHub answered 422 — Workflow does not have workflow_dispatch trigger');
  });

  it('refuses to run with an ID missing, before signing or sending anything', async () => {
    for (const name of ['GITHUB_APP_CLIENT_ID', 'GITHUB_APP_INSTALLATION_ID', 'GITHUB_APP_KEY']) {
      const r = await morning([], { [name]: '' });
      expect(r.error?.message).toBe(`${name} is not set`);
      expect(r.calls).toHaveLength(0);
    }
  });

  it('never logs the key, the JWT or the token, on any path', async () => {
    const runs = [
      await morning([minted, { status: 200, json: { workflow_run_id: 1 } }]),
      await morning([{ status: 502 }, { status: 502 }, { status: 502 }]),
      await morning([minted, { status: 401, json: { message: 'Bad credentials' } }]),
      await morning([new TypeError('fetch failed'), new TypeError('fetch failed'), new TypeError('fetch failed')]),
    ];
    const keyBody = keyPem.split('\n')[1];
    for (const r of runs) {
      const jwt = r.calls[0]?.headers.authorization.slice('Bearer '.length) ?? '';
      const text = [...r.log, r.error?.message ?? ''].join('\n');
      expect(r.log.length).toBeGreaterThan(0);
      expect(text).not.toContain(TOKEN);
      expect(text).not.toContain(keyBody);
      expect(jwt.length).toBeGreaterThan(100);
      expect(text).not.toContain(jwt.split('.')[2]);
      expect(text).not.toContain('PRIVATE KEY');
    }
  });

  it('has no address, one cron at 06:00 UTC, and no secret in its vars', () => {
    const toml = read('infra/cloudflare/worker/production-checks-trigger/wrangler.toml');
    const code = toml.replace(/#.*$/gm, '');
    expect(code).toMatch(/^name = "myweli-production-checks-trigger"$/m);
    expect(code).toMatch(/^workers_dev = false$/m);
    expect(code).not.toMatch(/^\s*(\[\[routes\]\]|route\s*=|routes\s*=)/m);
    expect(code.match(/^crons = .*$/gm)).toEqual(['crons = ["0 6 * * *"]']);
    const vars = code.slice(code.indexOf('[vars]'));
    expect(vars).not.toMatch(/KEY|TOKEN|SECRET|PRIVATE|PASSWORD/);
    expect(vars).toMatch(/^GITHUB_REPOSITORY = "Zaslons\/myweli"$/m);
    expect(vars).toMatch(/^GITHUB_WORKFLOW = "production-checks.yml"$/m);
    expect(vars).toMatch(/^GITHUB_REF = "main"$/m);
  });
});

describe('ontime: did the morning run start on time? (decision 269)', () => {
  const O = 'infra/ci/production-checks-ontime.mjs';
  let ontime: {
    decide: (o: object) => { action: string; say: string };
    main: (o: object) => Promise<number>;
    TRIGGER_BOT: string;
    ISSUE_TITLE: string;
  };
  beforeAll(async () => {
    ontime = await load(O);
  });

  const BOT = 'myweli-production-checks[bot]';
  const at = (hhmm: string, day = '2026-11-28') => `${day}T${hhmm}Z`;
  const base = { ref: 'refs/heads/main', startedBy: 'Zaslons' };
  const botRun = (created: string, branch = 'main', login = BOT) => ({
    event: 'workflow_dispatch',
    head_branch: branch,
    triggering_actor: { login },
    created_at: created,
  });

  describe('before the App exists: GitHub’s schedule against 07:00 UTC', () => {
    it.each([
      ['06:40:00', 'close'],
      ['07:00:00', 'close'],
      ['07:00:59', 'open'],
      ['16:01:35', 'open'],
    ])('a scheduled run created at %s → %s', (time, action) => {
      expect(ontime.decide({ ...base, event: 'schedule', createdAt: at(time), bot: '' }).action).toBe(action);
    });

    it('says when, and how late', () => {
      const v = ontime.decide({ ...base, event: 'schedule', createdAt: at('16:01:35'), bot: '' });
      expect(v.say).toContain('16:01 UTC');
      expect(v.say).toContain('9 h 02 min after 07:00');
      expect(v.say).toContain('not running yet');
    });
  });

  describe('with the App: its own run against 06:30, the backup looks for it', () => {
    it.each([
      ['06:00:31', 'close'],
      ['06:30:00', 'close'],
      ['06:31:00', 'open'],
    ])('the App’s run created at %s → %s', (time, action) => {
      expect(ontime.decide({ ...base, event: 'workflow_dispatch', startedBy: BOT, createdAt: at(time), bot: BOT }).action).toBe(action);
    });

    it.each([
      ['the App’s run at 06:00:31 on main', [botRun(at('06:00:31'))], 'close'],
      ['the App’s run at 06:45', [botRun(at('06:45:00'))], 'open'],
      ['the App’s run on another branch', [botRun(at('06:00:31'), 'feature')], 'open'],
      ['a manual run at 06:05', [botRun(at('06:05:00'), 'main', 'Zaslons')], 'open'],
      ['yesterday’s App run', [botRun(at('06:00:31', '2026-11-27'))], 'open'],
      ['no run at all', [], 'open'],
    ])('the backup at 16:01, with %s → %s', (_label, dayRuns, action) => {
      const v = ontime.decide({ ...base, event: 'schedule', createdAt: at('16:01:35'), bot: BOT, dayRuns });
      expect(v.action).toBe(action);
      if (action === 'open') expect(v.say).toContain('did not fire on 2026-11-28');
    });
  });

  it.each([
    ['a manual run', { event: 'workflow_dispatch', startedBy: 'Zaslons', bot: BOT }],
    ['a manual run, before the App', { event: 'workflow_dispatch', startedBy: 'Zaslons', bot: '' }],
    ['a scheduled run not on main', { event: 'schedule', ref: 'refs/heads/feature', bot: '' }],
    ['the App’s run not on main', { event: 'workflow_dispatch', ref: 'refs/heads/feature', startedBy: BOT, bot: BOT }],
  ])('%s touches nothing', (_label, o) => {
    expect(ontime.decide({ ...base, createdAt: at('16:01:35'), ...o }).action).toBe('none');
  });

  it('refuses an unreadable created_at rather than guess', () => {
    expect(() => ontime.decide({ ...base, event: 'schedule', createdAt: 'yesterday', bot: '' })).toThrow('unreadable');
  });

  describe('main(), against a stand-in GitHub', () => {
    const ENV = {
      GH_REPO: 'Zaslons/myweli',
      GH_TOKEN: 'fixture',
      RUN_ID: '555',
      RUN_URL: 'https://github.com/Zaslons/myweli/actions/runs/555',
      EVENT: 'schedule',
      REF: 'refs/heads/main',
      STARTED_BY: 'Zaslons',
    };
    const theRun = (time: string) => ({ status: 200, json: { id: 555, workflow_id: 77, created_at: at(time) } });
    const search = (...items: object[]) => ({ status: 200, json: { items } });
    const issue = (number: number, state: string, title?: string) => ({ number, state, title: title ?? ontime.ISSUE_TITLE });

    async function check(answers: Answer[], env: Record<string, string> = {}, bot = '') {
      const { calls, fetchImpl } = fakeFetch(answers);
      const log: Log = [];
      const code = await ontime.main({ env: { ...ENV, ...env }, fetchImpl, log: (l: string) => log.push(l), sleep: async () => {}, bot });
      const writes = calls.filter((c) => c.method !== 'GET');
      return { code, calls, writes, log };
    }

    it('ships with no bot login: the IDs PR sets it (B19.3d)', () => {
      expect(ontime.TRIGGER_BOT).toBe('');
    });

    it('a late run and no issue yet: opens it, mentioning the owner, with the run', async () => {
      const r = await check([theRun('16:01:35'), search(), { status: 201, json: { number: 900 } }]);
      expect(r.code).toBe(0);
      expect(r.writes).toHaveLength(1);
      expect(r.writes[0].url).toBe('https://api.github.com/repos/Zaslons/myweli/issues');
      const body = JSON.parse(r.writes[0].body);
      expect(body.title).toBe('The morning check starts late');
      expect(body.body).toMatch(/^@Zaslons /);
      expect(body.body).toContain(ENV.RUN_URL);
      expect(body.body).toContain('Production checks are failing');
    });

    it('a late run and the issue already open: no write, no daily e-mail', async () => {
      const r = await check([theRun('16:01:35'), search(issue(900, 'open'))]);
      expect(r.code).toBe(0);
      expect(r.writes).toEqual([]);
    });

    it('a late run and the issue closed: reopens it, with a comment', async () => {
      const r = await check([theRun('16:01:35'), search(issue(900, 'closed')), { status: 200, json: {} }, { status: 201, json: {} }]);
      expect(r.code).toBe(0);
      expect(r.writes.map((w) => `${w.method} ${w.url.replace('https://api.github.com', '')}`)).toEqual([
        'PATCH /repos/Zaslons/myweli/issues/900',
        'POST /repos/Zaslons/myweli/issues/900/comments',
      ]);
      expect(JSON.parse(r.writes[0].body)).toEqual({ state: 'open' });
    });

    it('an on-time run and the issue open: closes it, saying why', async () => {
      const r = await check([theRun('06:40:00'), search(issue(900, 'open')), { status: 201, json: {} }, { status: 200, json: {} }]);
      expect(r.code).toBe(0);
      expect(r.writes[0].url).toContain('/issues/900/comments');
      expect(JSON.parse(r.writes[0].body).body).toMatch(/^@Zaslons /);
      expect(JSON.parse(r.writes[1].body)).toEqual({ state: 'closed', state_reason: 'completed' });
    });

    it('a similar title is not the issue', async () => {
      const r = await check([theRun('16:01:35'), search(issue(700, 'open', 'The morning check starts late on staging')), { status: 201, json: { number: 901 } }]);
      expect(r.writes).toHaveLength(1);
      expect(r.writes[0].url).toMatch(/\/issues$/);
    });

    it('a manual run reads its own run and nothing else', async () => {
      const r = await check([theRun('09:12:00')], { EVENT: 'workflow_dispatch' });
      expect(r.code).toBe(0);
      expect(r.calls).toHaveLength(1);
    });

    it('with the App, the backup lists that day’s dispatches on main', async () => {
      const r = await check(
        [theRun('16:01:35'), { status: 200, json: { workflow_runs: [botRun(at('06:00:40'))] } }, search()],
        {},
        BOT,
      );
      expect(r.code).toBe(0);
      expect(r.calls[1].url).toBe(
        'https://api.github.com/repos/Zaslons/myweli/actions/workflows/77/runs?event=workflow_dispatch&branch=main&created=2026-11-28&per_page=100',
      );
      expect(r.writes).toEqual([]);
    });

    it('retries a 5xx before deciding: a passing blip is not « nothing was learned »', async () => {
      const r = await check([{ status: 502 }, theRun('16:01:35'), search(issue(900, 'open'))]);
      expect(r.code).toBe(0);
      expect(r.calls[0].url).toBe(r.calls[1].url);
      expect(r.calls[1].url).toBe('https://api.github.com/repos/Zaslons/myweli/actions/runs/555');
    });

    it('does not retry a refusal', async () => {
      const r = await check([{ status: 404 }]);
      expect(r.code).toBe(1);
      expect(r.calls).toHaveLength(1);
    });

    it('cannot read GitHub: fails, says nothing was learned, and writes nothing', async () => {
      const r = await check([{ status: 502 }, { status: 502 }, { status: 502 }]);
      expect(r.code).toBe(1);
      expect(r.log.join('\n')).toContain('::error::');
      expect(r.log.join('\n')).toContain('nothing was learned');
      expect(r.writes).toEqual([]);
    });

    it('refuses to run without what the step passes', async () => {
      const r = await check([], { RUN_ID: '' });
      expect(r.code).toBe(1);
      expect(r.log.join('\n')).toContain('RUN_ID is not set');
    });
  });
});

describe('the deploy fence (decision 268)', () => {
  const WORKFLOWS = join(REPO, '.github', 'workflows');
  const workflows = readdirSync(WORKFLOWS).filter((f) => /\.ya?ml$/.test(f));

  /// The workflows a dispatch can start that deploy nothing, read 2026-11-27:
  /// goldens.yml cannot write, production-checks.yml is the one the App starts.
  const DEPLOYS_NOTHING = new Set(['goldens.yml', 'production-checks.yml']);
  const FENCED = /^ {4}environment: (admin-production|backend-\$\{\{ github\.event\.inputs\.environment \|\| 'staging' \}\})$/m;

  it('every workflow a dispatch can start deploys nothing, or declares a fenced environment in every job', () => {
    const dispatchable = workflows.filter((f) => /^\s+workflow_dispatch:/m.test(stripYaml(readFileSync(join(WORKFLOWS, f), 'utf8'))));
    expect(dispatchable).toEqual(expect.arrayContaining(['deploy-admin.yml', 'deploy-backend.yml']));
    for (const f of dispatchable.filter((f) => !DEPLOYS_NOTHING.has(f))) {
      const src = stripYaml(readFileSync(join(WORKFLOWS, f), 'utf8'));
      const jobs = [...src.slice(src.search(/^jobs:$/m)).matchAll(/^ {2}([A-Za-z_][\w-]*):$/gm)].map((m) => m[1]);
      expect(jobs.length, f).toBeGreaterThan(0);
      for (const name of jobs) {
        expect(job(src, name), `${f} job ${name} declares no fenced environment`).toMatch(FENCED);
      }
    }
  });

  it('deploy-admin.yml reads its Cloudflare secrets inside admin-production', () => {
    const src = read('.github/workflows/deploy-admin.yml');
    const admin = job(src, 'deploy-admin');
    expect(admin).toMatch(/^ {4}environment: admin-production$/m);
    // Every reference to a secret is in that job, so none is read outside the environment.
    const refs = stripYaml(src).match(/secrets\.[A-Z_]+/g) ?? [];
    expect(refs.length).toBeGreaterThan(0);
    expect(admin.match(/secrets\.[A-Z_]+/g)).toEqual(refs);
  });

  it.each([
    ['deploy-admin.yml', 'deploy-admin'],
    ['deploy-backend.yml', 'deploy'],
  ])('%s opens with the owner check, before anything else runs', (file, name) => {
    // Comments AND echo lines blanked: a guard text inside a message is not a guard.
    const body = job(read(`.github/workflows/${file}`), name).replace(/^\s*echo .*$/gm, '');
    const steps = body.slice(body.search(/^ {4}steps:$/m));
    const first = steps.match(/^ {6}- [\s\S]*?(?=^ {6}- |$(?![\s\S]))/m)?.[0] ?? '';
    expect(first).toMatch(/^ {6}- name: Guard — only the owner starts a deploy$/m);
    expect(first).toMatch(/^ {8}if: github\.triggering_actor != 'Zaslons'$/m);
    expect(first).toMatch(/^\s+exit 1$/m);
    expect(first).not.toMatch(/uses:/);
  });

  describe('infra/ci/98-verify-deploy-fence.sh, against a stand-in gh', () => {
    let dir = '';
    afterEach(() => dir && rmSync(dir, { recursive: true, force: true }));

    const env = (reviewers = ['Zaslons'], selfReview = false) => ({
      protection_rules: [
        { type: 'required_reviewers', prevent_self_review: selfReview, reviewers: reviewers.map((login) => ({ type: 'User', reviewer: { login } })) },
        { type: 'branch_policy' },
      ],
      deployment_branch_policy: { protected_branches: false, custom_branch_policies: true },
    });
    const branches = (...names: string[]) => ({ branch_policies: names.map((name) => ({ name, type: 'branch' })) });
    const GREEN: Record<string, unknown> = {
      'environments/backend-production': env(),
      'environments/backend-production/deployment-branch-policies': branches('main'),
      'environments/admin-production': env(),
      'environments/admin-production/deployment-branch-policies': branches('main'),
      'environments/admin-production/secrets': { secrets: [{ name: 'CLOUDFLARE_ACCOUNT_ID' }, { name: 'CLOUDFLARE_API_TOKEN' }] },
      'environments/backend-staging': { protection_rules: [], deployment_branch_policy: { protected_branches: false, custom_branch_policies: true } },
      'environments/backend-staging/deployment-branch-policies': branches('main'),
      'actions/secrets': { secrets: [] },
    };

    function fence(answers: Record<string, unknown>) {
      dir = mkdtempSync(join(tmpdir(), 'fence-'));
      for (const [path, json] of Object.entries(answers)) {
        if (json !== undefined) writeFileSync(join(dir, `${path.replace(/\//g, '__')}.json`), JSON.stringify(json));
      }
      // Answers `gh api repos/Zaslons/myweli/<path>` from a file, 404 otherwise.
      // Any other command fails, so the script cannot pass by calling something else.
      writeFileSync(
        join(dir, 'gh'),
        `#!/usr/bin/env bash
[ "$1" = api ] || { echo "unknown gh command: $*" >&2; exit 64; }
p=\${2#repos/Zaslons/myweli/}
f="${dir}/\${p//\\//__}.json"
[ -f "$f" ] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
cat "$f"
`,
      );
      chmodSync(join(dir, 'gh'), 0o755);
      try {
        const out = execFileSync('bash', [join(REPO, 'infra/ci/98-verify-deploy-fence.sh')], {
          env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, GH_REPO: 'Zaslons/myweli' },
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'pipe'],
        });
        return { code: 0, out };
      } catch (e) {
        const err = e as { status?: number; stdout?: string; stderr?: string };
        return { code: err.status ?? -1, out: `${err.stdout ?? ''}${err.stderr ?? ''}` };
      }
    }

    it('an environment that cannot be read fails both of its rules, each saying so', () => {
      const r = fence({ ...GREEN, 'environments/backend-production': undefined });
      expect(r.code).toBe(1);
      expect(r.out.match(/✗ cannot read the environment backend-production/g)).toHaveLength(2);
    });

    it('passes when every rule holds', () => {
      const r = fence(GREEN);
      expect(r.out).toContain('The fence is in place');
      expect(r.code).toBe(0);
    });

    it.each([
      ['no reviewer on backend-production', { 'environments/backend-production': { ...env(), protection_rules: [] } }, 'backend-production has no required reviewer'],
      ['a reviewer who is not the owner', { 'environments/admin-production': env(['someone']) }, 'admin-production requires a reviewer, but not Zaslons'],
      ['« Prevent self-review » on', { 'environments/backend-production': env(['Zaslons'], true) }, 'Prevent self-review'],
      ['any branch on admin-production', { 'environments/admin-production': { ...env(), deployment_branch_policy: null } }, 'admin-production accepts any branch'],
      ['main and another branch', { 'environments/backend-staging/deployment-branch-policies': branches('main', 'release') }, "backend-staging's branch rules are not exactly « main »"],
      ['admin-production without the API token', { 'environments/admin-production/secrets': { secrets: [{ name: 'CLOUDFLARE_ACCOUNT_ID' }] } }, 'admin-production lacks a Cloudflare secret'],
      ['the repository still holding the token', { 'actions/secrets': { secrets: [{ name: 'CLOUDFLARE_API_TOKEN' }] } }, 'repository-level secrets still hold ["CLOUDFLARE_API_TOKEN"]'],
      ['admin-production not created', { 'environments/admin-production': undefined }, 'cannot read the environment admin-production'],
      ['branch rules that cannot be read', { 'environments/backend-production/deployment-branch-policies': undefined }, "cannot read backend-production's branch rules"],
      ["admin-production's secret names that cannot be read", { 'environments/admin-production/secrets': undefined }, "cannot read admin-production's secret names"],
      ["the repository's secret names that cannot be read", { 'actions/secrets': undefined }, "cannot read the repository's secret names"],
    ])('fails on %s, naming it', (_label, change, expected) => {
      const r = fence({ ...GREEN, ...change });
      expect(r.code).toBe(1);
      expect(r.out).toContain(expected);
      expect(r.out).toContain('::error::');
      expect(r.out).toContain('Do not create the GitHub App yet');
    });
  });
});

describe('the wiring between the Worker, ontime and the alarm', () => {
  const wf = read('.github/workflows/production-checks.yml');

  it('the bot login, the IDs and clear’s App clause land together, or not at all (the IDs PR, B19.3d)', async () => {
    const { TRIGGER_BOT } = await load('infra/ci/production-checks-ontime.mjs');
    const toml = read('infra/cloudflare/worker/production-checks-trigger/wrangler.toml').replace(/#.*$/gm, '');
    const client = toml.match(/^GITHUB_APP_CLIENT_ID = "(.*)"$/m)?.[1];
    const installation = toml.match(/^GITHUB_APP_INSTALLATION_ID = "(.*)"$/m)?.[1];
    expect(client, 'no GITHUB_APP_CLIENT_ID line').toBeDefined();
    expect(installation, 'no GITHUB_APP_INSTALLATION_ID line').toBeDefined();
    const clear = job(wf, 'clear');
    if (TRIGGER_BOT === '') {
      expect([client, installation]).toEqual(['', '']);
      expect(clear).not.toContain('triggering_actor');
    } else {
      expect(client).not.toBe('');
      expect(installation).toMatch(/^\d+$/);
      expect(clear).toContain(`github.triggering_actor == '${TRIGGER_BOT}'`);
    }
  });

  it('ontime runs the script on every run, with its own issue’s rights and nothing more', () => {
    const ontime = job(wf, 'ontime');
    expect(ontime, 'no ontime job').not.toBe('');
    expect(ontime).toContain('run: node infra/ci/production-checks-ontime.mjs');
    expect(ontime).toMatch(/^ {4}permissions:\n {6}contents: read\n {6}actions: read\n {6}issues: write\n {4}\S/m);
    expect(ontime).not.toMatch(/^ {4}if:/m);
    expect(ontime).not.toContain('continue-on-error');
  });

  it.each(['privacy', 'legal'])('%s holds contents: read and nothing else (spec §2.6)', (name) => {
    expect(job(wf, name)).toMatch(/^ {4}permissions:\n {6}contents: read\n {4}\S/m);
  });

  it('the deploy script runs the fence read-back before it deploys, and never shows the key or the token', () => {
    const script = read('infra/cloudflare/97-production-checks-trigger.sh');
    const code = script.replace(/^\s*#.*$/gm, '');
    const fenceAt = code.indexOf('98-verify-deploy-fence.sh');
    expect(fenceAt).toBeGreaterThan(0);
    expect(code.indexOf('$WRANGLER deploy')).toBeGreaterThan(fenceAt);
    expect(code).toContain('--secret="$KEY_SECRET"');
    expect(code).toMatch(/^KEY_SECRET=GITHUB_APP_PRODUCTION_CHECKS_KEY$/m);
    expect(code).toContain('secret put GITHUB_APP_KEY');
    // Over stdin: the line that puts the secret holds no variable to expand onto argv.
    for (const line of code.split('\n').filter((l) => l.includes('secret put'))) {
      expect(line.replace('$WORKER_DIR', '').replace('$WRANGLER', ''), line).not.toMatch(/\$/);
    }
    for (const line of code.split('\n').filter((l) => /^\s*echo /.test(l))) {
      expect(line, 'a credential on an echo line').not.toMatch(/CLOUDFLARE_API_TOKEN|KEY_HEAD|\$\(gcloud/);
    }
    expect(code).toContain('GITHUB_APP_CLIENT_ID or GITHUB_APP_INSTALLATION_ID is empty');
  });

  it('the probe is gone: no workflow ticks on its own besides the backup', () => {
    const scheduled = readdirSync(join(REPO, '.github', 'workflows')).filter((f) =>
      /^\s+schedule:/m.test(stripYaml(read(`.github/workflows/${f}`))),
    );
    expect(scheduled).toEqual(['production-checks.yml']);
  });
});
