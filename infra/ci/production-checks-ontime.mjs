#!/usr/bin/env node
//
// Did the morning run of production-checks.yml start on time?
// docs/design/infra-production-checks-on-time.md §3.4, §4.1, §13.2 (decision 269).
//
// ## Why this exists
//
// The workflow promises 06:00 UTC, « before the Abidjan working day ». From
// 2026-08-27 GitHub created that run 3.7 to 11.9 hours late, every day, for
// three months, and nothing said so: the dead-man check counts runs, and a run
// eleven hours late is a run. A check that tells you at 17:00 that the site has
// been broken since 06:00 has failed at the one thing a morning check is for.
//
// ## What it does
//
// It reads this run's own `created_at` from the API (no `github` field holds
// it, and the clock would say when the job started, not when GitHub created
// the run), decides, and opens or closes ONE issue, « The morning check starts
// late ». Never the production alarm: a late start is not production being
// wrong, and sharing the alarm would hold it open all week (spec §12.2).
//
// It exits 0 whatever it decides. It exits 1 only when it could not read or
// write GitHub, because then nothing was learned.
//
// ## The rules, two ways
//
// Until the trigger's GitHub App exists (`TRIGGER_BOT` is empty):
//   - a scheduled run created after 07:00 UTC opens the issue, one created by
//     07:00 closes it (spec §3.4). Since 2026-08-27 every scheduled run would
//     open it, which is true.
// Once the IDs PR (B19.3d) sets `TRIGGER_BOT`:
//   - the App's own run (a dispatch it started) closes the issue when created
//     by 06:30 UTC, and opens it when later;
//   - the scheduled run, now the backup, opens it when its UTC day has no run
//     of the App on `main` created between 06:00 and 06:30, and closes it when
//     it has one (spec §4.1).
// Always: a manual run, or a run not on `main`, passes with a line and touches
// nothing. Its start time says nothing about the morning.
//
// ## What it cannot see
//
// A day with no run at all — neither the App's nor the backup — leaves nothing
// to run this. The backup has arrived every single day since 2026-08-22 (96 of
// 96, spec §2.1), and three days without one fail every PR through
// infra/ci/99-verify-monitor-alive.mjs.

import { pathToFileURL } from 'node:url';

/// The GitHub App's bot login, e.g. `myweli-production-checks[bot]`. Read from
/// its first run, then set here by the IDs PR (B19.3d) together with the
/// Worker's client ID and installation ID and `clear`'s condition — one wiring
/// test holds all of them equal. Empty until the App exists.
export const TRIGGER_BOT = '';

export const ISSUE_TITLE = 'The morning check starts late';
export const OWNER_MENTION = '@Zaslons';

/// Minutes after 00:00 UTC. 07:00 is the line while only GitHub's schedule
/// starts the run (§3.4); 06:30 once the Worker starts it at 06:00 (§4.1).
export const SCHEDULE_DEADLINE = 7 * 60;
export const TRIGGER_FROM = 6 * 60;
export const TRIGGER_DEADLINE = 6 * 60 + 30;

const minutes = (d) => d.getUTCHours() * 60 + d.getUTCMinutes() + d.getUTCSeconds() / 60;
const day = (d) => d.toISOString().slice(0, 10);
const hhmm = (d) => d.toISOString().slice(11, 16);
const late = (d, deadline) => {
  const m = Math.round(minutes(d) - deadline);
  return `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')} min after ${String(
    Math.floor(deadline / 60),
  ).padStart(2, '0')}:${String(deadline % 60).padStart(2, '0')}`;
};

/// The whole decision, with no I/O. `dayRuns` are this workflow's runs created
/// on this run's UTC day, as the runs API returns them; only read for a
/// scheduled run once the App exists.
///
/// Returns `{ action: 'open' | 'close' | 'none', say }`: `say` is the line for
/// the log, and the reason in the issue when it opens.
export function decide({ event, ref, startedBy, createdAt, bot = TRIGGER_BOT, dayRuns = [] }) {
  const at = new Date(createdAt);
  if (Number.isNaN(at.getTime())) {
    throw new Error(`this run's created_at is unreadable: ${createdAt}`);
  }

  if (ref !== 'refs/heads/main') {
    return { action: 'none', say: `not on main (${ref}): only a run on main says when the morning starts` };
  }

  if (event === 'workflow_dispatch') {
    if (bot && startedBy === bot) {
      return minutes(at) <= TRIGGER_DEADLINE
        ? { action: 'close', say: `the 06:00 trigger's run was created at ${hhmm(at)} UTC, on time` }
        : {
            action: 'open',
            say: `the 06:00 trigger's run on ${day(at)} was created at ${hhmm(at)} UTC, ${late(at, TRIGGER_DEADLINE)}`,
          };
    }
    return {
      action: 'none',
      say: `a manual run, started by ${startedBy || 'someone unknown'}: its start says nothing about the morning`,
    };
  }

  if (event !== 'schedule') {
    return { action: 'none', say: `a ${event} run: only the morning run is judged` };
  }

  if (!bot) {
    return minutes(at) <= SCHEDULE_DEADLINE
      ? { action: 'close', say: `GitHub created the 06:00 scheduled run at ${hhmm(at)} UTC, on time` }
      : {
          action: 'open',
          say:
            `GitHub created the 06:00 scheduled run of ${day(at)} at ${hhmm(at)} UTC, ` +
            `${late(at, SCHEDULE_DEADLINE)}. The 06:00 trigger (B19.3) is not running yet`,
        };
  }

  const onTime = dayRuns.find((r) => {
    const created = new Date(r.created_at);
    return (
      r.event === 'workflow_dispatch' &&
      r.head_branch === 'main' &&
      r.triggering_actor?.login === bot &&
      day(created) === day(at) &&
      minutes(created) >= TRIGGER_FROM &&
      minutes(created) <= TRIGGER_DEADLINE
    );
  });
  return onTime
    ? {
        action: 'close',
        say: `the 06:00 trigger's run of ${day(at)} was created at ${hhmm(new Date(onTime.created_at))} UTC (this backup at ${hhmm(at)})`,
      }
    : {
        action: 'open',
        say:
          `the 06:00 trigger did not fire on ${day(at)}: no run of ${bot} on main was created ` +
          `between 06:00 and 06:30 UTC. This scheduled backup was created at ${hhmm(at)} UTC`,
      };
}

/// One GitHub API call. A network error or a 5xx is retried twice; anything
/// else that is not 2xx throws. Never « I could not ask » read as an answer.
async function api({ fetchImpl, token, sleep }, method, path, body) {
  let last;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    let res;
    try {
      res = await fetchImpl(`https://api.github.com${path}`, {
        method,
        headers: {
          authorization: `Bearer ${token}`,
          accept: 'application/vnd.github+json',
          'x-github-api-version': '2022-11-28',
          'user-agent': 'myweli-production-checks-ontime',
          ...(body ? { 'content-type': 'application/json' } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
    } catch (e) {
      last = `cannot reach the GitHub API: ${e.message}`;
      if (attempt < 3) await sleep(attempt * 2000);
      continue;
    }
    if (res.ok) return res.status === 204 ? null : res.json();
    last = `GitHub answered ${res.status} to ${method} ${path}`;
    if (res.status < 500) break;
    if (attempt < 3) await sleep(attempt * 2000);
  }
  throw new Error(last);
}

/// Runs the check. Returns the exit code; never calls process.exit, so the
/// tests can run it with a stand-in `fetch`.
export async function main({
  env = process.env,
  fetchImpl = globalThis.fetch,
  log = console.log,
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
  bot = TRIGGER_BOT,
} = {}) {
  const fail = (msg) => {
    log(`  ✗ ${msg}`);
    log(`::error::${msg}`);
    return 1;
  };
  for (const name of ['GH_REPO', 'GH_TOKEN', 'RUN_ID', 'EVENT', 'REF']) {
    if (!env[name]) return fail(`${name} is not set — the workflow step passes it`);
  }
  const repo = env.GH_REPO;
  const ctx = { fetchImpl, token: env.GH_TOKEN, sleep };

  try {
    const run = await api(ctx, 'GET', `/repos/${repo}/actions/runs/${env.RUN_ID}`);
    let dayRuns = [];
    if (bot && env.EVENT === 'schedule') {
      const d = day(new Date(run.created_at));
      const listed = await api(
        ctx,
        'GET',
        `/repos/${repo}/actions/workflows/${run.workflow_id}/runs?event=workflow_dispatch&branch=main&created=${d}&per_page=100`,
      );
      dayRuns = listed.workflow_runs ?? [];
    }

    const verdict = decide({
      event: env.EVENT,
      ref: env.REF,
      startedBy: env.STARTED_BY,
      createdAt: run.created_at,
      bot,
      dayRuns,
    });
    log(`  ${verdict.action === 'open' ? '!' : '✓'} ${verdict.say}`);
    if (verdict.action === 'none') return 0;

    // Exact title, like the alarm's lookup: a title that merely contains it
    // is someone else's issue.
    const q = encodeURIComponent(`repo:${repo} is:issue in:title "${ISSUE_TITLE}"`);
    const found = await api(ctx, 'GET', `/search/issues?q=${q}&per_page=20`);
    const issue = (found.items ?? [])
      .filter((i) => i.title === ISSUE_TITLE && !i.pull_request)
      .sort((a, b) => a.number - b.number)[0];

    const runUrl = env.RUN_URL ?? '';
    if (verdict.action === 'open') {
      const body = [
        `${OWNER_MENTION} ${verdict.say}.`,
        '',
        runUrl,
        '',
        'This issue is about **when** the morning check starts, not what it finds:',
        'production failures open « Production checks are failing ». It closes on the',
        'next morning run that starts on time.',
        '(docs/design/infra-production-checks-on-time.md §13.2)',
      ].join('\n');
      if (!issue) {
        const made = await api(ctx, 'POST', `/repos/${repo}/issues`, { title: ISSUE_TITLE, body });
        log(`    opened #${made.number}`);
      } else if (issue.state === 'closed') {
        await api(ctx, 'PATCH', `/repos/${repo}/issues/${issue.number}`, { state: 'open' });
        await api(ctx, 'POST', `/repos/${repo}/issues/${issue.number}/comments`, { body });
        log(`    reopened #${issue.number}`);
      } else {
        // No comment: a daily e-mail about a lateness already open is noise.
        log(`    #${issue.number} is already open, left as it is`);
      }
      return 0;
    }

    if (issue && issue.state === 'open') {
      await api(ctx, 'POST', `/repos/${repo}/issues/${issue.number}/comments`, {
        body: `${OWNER_MENTION} ${verdict.say}, so this is closed. The next late morning reopens it.\n\n${runUrl}`,
      });
      await api(ctx, 'PATCH', `/repos/${repo}/issues/${issue.number}`, {
        state: 'closed',
        state_reason: 'completed',
      });
      log(`    closed #${issue.number}`);
    } else {
      log(issue ? `    #${issue.number} is already closed` : '    no lateness issue, nothing to close');
    }
    return 0;
  } catch (e) {
    return fail(`${e.message} — nothing was learned about this run's start; re-run the job`);
  }
}

// `pathToFileURL`, not a hand-built `file://${argv[1]}`: the repository lives
// under a path with a space, and the hand-built URL never matched there.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exit(await main());
}
