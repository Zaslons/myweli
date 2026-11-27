#!/usr/bin/env node
//
// Is the daily monitor still firing?
//
// Exit 0 = production-checks.yml ran on its SCHEDULE recently.
// Exit 1 = it has not, and nobody would have noticed.
//
// ## Why this exists
//
// `production-checks.yml` is where every claim this repo cannot verify at merge
// time goes to be watched: Core Web Vitals, the privacy promises, the published
// registration status, the log-retention setting, and whether anyone has
// re-confirmed the registration claim in 90 days. All of it is a monitor, and a
// monitor that stops firing is **indistinguishable from a monitor with nothing
// to report**. Silence is the same shape as health.
//
// It stops for ordinary reasons: GitHub disables scheduled workflows after 60
// days of repository inactivity, someone disables the workflow in the UI, a
// rename breaks the schedule, a syntax error stops it parsing.
//
// ## Why it runs in CI, and blocks
//
// The only thing that reliably runs when a cron does not is CI. This is the one
// check in this repository that is allowed to fail a PR for something that is
// not in its diff, and that is deliberate: a dead monitor is a broken
// repository, not a date passing, and three days of silence on a daily job
// means it is actually broken. The fix is one click, and any PR author can do
// it — the message says which button.
//
// ## The way this would have passed for the wrong reason
//
// `workflow_dispatch` runs appear in the same list as scheduled ones. On the day
// this was written the workflow had four runs, three of them manual — so an
// unfiltered query would have reported a healthy schedule on the strength of
// someone clicking "Run workflow". `event=schedule` is the whole point.
//
// ## A run is not a check (2026-11-27, B19.3)
//
// It used to count runs CREATED. A run cancelled before it started, or one
// whose checks were all skipped, is created too, and checks nothing. Once a
// GitHub App can start and cancel this workflow (the 06:00 trigger,
// docs/design/infra-production-checks-on-time.md §4.7), a leaked key could
// cancel the scheduled backup every day and this would stay green (§3.5). So a
// scheduled run counts only when its Core Web Vitals job concluded `success`
// or `failure`: the checks ran, whatever they found. A run with jobs but none
// of that name fails this check rather than guess.

const REPO = process.env.GH_REPO;
const TOKEN = process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN;
const WORKFLOW = process.env.MONITOR_WORKFLOW ?? 'production-checks.yml';
const MAX_AGE_DAYS = Number(process.env.MONITOR_MAX_AGE_DAYS ?? 3);

const fail = (msg) => {
  console.log(`  ✗ ${msg}`);
  console.log(`::error::${msg}`);
  process.exit(1);
};

if (!Number.isFinite(MAX_AGE_DAYS) || MAX_AGE_DAYS <= 0) {
  fail(`MONITOR_MAX_AGE_DAYS must be a positive number, got ${process.env.MONITOR_MAX_AGE_DAYS}`);
}

// A rehearsal seam. It supplies the API's ANSWER, so it can make this check
// PASS as well as fail — an earlier version of this comment claimed otherwise,
// and the suite's own happy-path case disproves it by using this very variable
// to pass. What keeps it honest is not the seam: it announces itself in the
// log, and the CI-wiring test forbids it — and the other two MONITOR_* knobs —
// from appearing in ci.yml at all.
const fixture = process.env.MONITOR_RUNS_JSON;
// The jobs answer for each run, by run id, beside the runs answer. Same seam,
// same ban in ci.yml.
const jobsFixture = process.env.MONITOR_JOBS_JSON;

/// The job whose conclusion says the run's checks ran. Matched by its `name:`
/// in production-checks.yml, which is what the jobs API returns.
const CHECK_JOB = 'Real domain — Core Web Vitals (mobile)';
const CHECKED = new Set(['success', 'failure']);

async function runs() {
  if (fixture) {
    console.log('  ! reading fixture data from MONITOR_RUNS_JSON, not GitHub');
    try {
      return JSON.parse(fixture);
    } catch (e) {
      fail(`MONITOR_RUNS_JSON is not JSON: ${e.message}`);
    }
  }
  if (!REPO) fail('GH_REPO is not set — this job does not check out, so nothing else can supply it');
  if (!TOKEN) fail('GH_TOKEN is not set — the runs API needs `actions: read`');

  // 20 newest: three days of a daily schedule, with room for a burst.
  return get(`/repos/${REPO}/actions/workflows/${WORKFLOW}/runs?event=schedule&per_page=20`);
}

async function get(path) {
  let res;
  try {
    res = await fetch(`https://api.github.com${path}`, {
      headers: {
        authorization: `Bearer ${TOKEN}`,
        accept: 'application/vnd.github+json',
        'user-agent': 'myweli-monitor-alive',
      },
    });
  } catch (e) {
    // Never treat "I could not ask" as "the answer was yes".
    fail(`cannot reach the GitHub API: ${e.message}`);
  }
  if (!res.ok) {
    fail(
      `GitHub API answered ${res.status} for ${path} — a 404 usually means ` +
        `the workflow was renamed or deleted, a 403 that this job lacks ` +
        `\`actions: read\``,
    );
  }
  return res.json();
}

/// The run's jobs, latest attempt. A run cancelled before it started has none.
async function jobsOf(run) {
  if (fixture) {
    let all;
    try {
      all = JSON.parse(jobsFixture ?? '');
    } catch (e) {
      fail(`MONITOR_JOBS_JSON is not JSON: ${e.message}`);
    }
    if (!(String(run.id) in all)) fail(`MONITOR_JOBS_JSON has no entry for run ${run.id}`);
    return all[String(run.id)];
  }
  return get(`/repos/${REPO}/actions/runs/${run.id}/jobs?per_page=100`);
}

const body = await runs();
const list = body?.workflow_runs;
if (!Array.isArray(list)) {
  fail(`unexpected API shape: no workflow_runs array`);
}

if (list.length === 0) {
  fail(
    `${WORKFLOW} has NEVER run on its schedule. Either it was just added, or ` +
      `GitHub has disabled it — Actions → ${WORKFLOW} → "Enable workflow". ` +
      `Manual runs do not count here, on purpose.`,
  );
}

const latest = list[0];
const at = new Date(latest.created_at);
if (Number.isNaN(at.getTime())) {
  fail(`the newest scheduled run has an unreadable date: ${latest.created_at}`);
}

const days = Math.floor((Date.now() - at.getTime()) / 86_400_000);
if (days < 0) {
  fail(`the newest scheduled run is dated ${-days} day(s) in the future: ${latest.created_at}`);
}

if (days > MAX_AGE_DAYS) {
  fail(
    `${WORKFLOW} last ran on its schedule ${days} days ago ` +
      `(${latest.created_at}), and it runs daily. GitHub disables scheduled ` +
      `workflows after 60 days of repository inactivity — re-enable it at ` +
      `Actions → ${WORKFLOW} → "Enable workflow". Everything that watches ` +
      `production has been silent since then, and silence looks exactly like ` +
      `health.`,
  );
}

// The newest scheduled run in the window whose checks ran.
let seen = 0;
for (const run of list) {
  const created = new Date(run.created_at);
  if (Number.isNaN(created.getTime())) {
    fail(`a scheduled run has an unreadable date: ${run.created_at}`);
  }
  const age = Math.floor((Date.now() - created.getTime()) / 86_400_000);
  if (age > MAX_AGE_DAYS) break;
  seen += 1;

  const answer = await jobsOf(run);
  const jobs = answer?.jobs;
  if (!Array.isArray(jobs)) fail(`unexpected API shape for run ${run.id}: no jobs array`);
  // Cancelled before it started: no job at all. It checked nothing.
  if (jobs.length === 0) continue;
  const cwv = jobs.find((j) => j.name === CHECK_JOB);
  if (!cwv) {
    fail(
      `run ${run.id} of ${WORKFLOW} has jobs but none named « ${CHECK_JOB} ». ` +
        `That job is how this check tells a run that checked from one that did ` +
        `not; it was probably renamed. Rename it here too, rather than guess.`,
    );
  }
  if (CHECKED.has(cwv.conclusion)) {
    console.log(
      `  ✓ ${WORKFLOW} ran its checks on its schedule ${age} day(s) ago ` +
        `(${run.created_at}, Core Web Vitals: ${cwv.conclusion})`,
    );
    console.log(`    newest scheduled run: ${latest.created_at}, ${latest.conclusion ?? 'in progress'}`);
    process.exit(0);
  }
}

fail(
  `${WORKFLOW} was created on its schedule ${seen} time(s) in the last ` +
    `${MAX_AGE_DAYS} days, and none of those runs ran its checks: each was ` +
    `cancelled, had its checks skipped, or has not finished. « Enable workflow » ` +
    `is not the fix — the schedule fires. Open Actions → ${WORKFLOW}: a run ` +
    `cancelled every day is the sign of someone holding the 06:00 trigger's key ` +
    `(docs/design/infra-production-checks-on-time.md §4.7); checks skipped ` +
    `every time mean a job condition changed.`,
);
