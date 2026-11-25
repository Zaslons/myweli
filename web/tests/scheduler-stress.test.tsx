import { cleanup, render, screen } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { useEffect, useState } from 'react';
import { afterEach, describe, expect, it } from 'vitest';

/// The guards ON the scheduler-stress mode (tests/support/scheduler-stress.ts).
/// That mode exists to make one race happen every run instead of at random; if a
/// React or Scheduler upgrade made it inert, its CI job would stay green and mean
/// nothing. So: the canary below must SEE the race under stress, and the npm
/// script and the CI job that switch it on are pinned.

const WEB = process.cwd();
const REPO = join(WEB, '..');
const flag = process.env.MYWELI_SCHEDULER_STRESS === '1';
const loaded = (globalThis as Record<string, unknown>).__myweliSchedulerStress === true;

afterEach(cleanup);

/// Drawn one effect after its parent appears — SalonTimeHint's shape.
function AfterTheEffect() {
  const [on, setOn] = useState(false);
  useEffect(() => {
    setOn(true);
  }, []);
  return on ? <p>dessiné après l’effet</p> : null;
}

/// Revealed by an update that lands OUTSIDE act — a fetch resolving while the
/// test waits — so React's real Scheduler runs it.
function Page() {
  const [ready, setReady] = useState(false);
  useEffect(() => {
    void Promise.resolve().then(() => setReady(true));
  }, []);
  return ready ? (
    <>
      <h1>La page</h1>
      <AfterTheEffect />
    </>
  ) : (
    <p>Chargement…</p>
  );
}

describe('scheduler stress', () => {
  // Without this, a config that stopped loading the setup would turn the stress
  // job into a second plain run — and skip the canary that would have said so.
  it('the flag and the setup travel together', () => {
    expect(loaded).toBe(flag);
  });

  describe.runIf(flag || loaded)('the canary (only under stress)', () => {
    it('a read right after the page appears misses what an effect draws; waiting finds it', async () => {
      render(<Page />);
      await screen.findByRole('heading', { level: 1, name: 'La page' });
      // The race, on purpose: the effect has not run yet. If this is ever found
      // here, the stress no longer bites and its job proves nothing.
      expect(screen.queryByText('dessiné après l’effet')).toBeNull();
      // Waiting is what makes the read right.
      expect(await screen.findByText('dessiné après l’effet')).toBeInTheDocument();
    });
  });

  it('`npm run test:stress` sets the flag', () => {
    const pkg = JSON.parse(readFileSync(join(WEB, 'package.json'), 'utf8')) as {
      scripts: Record<string, string>;
    };
    expect(pkg.scripts['test:stress']).toBe('MYWELI_SCHEDULER_STRESS=1 vitest run');
  });

  // In the `web` job — already a required check — after the plain run. A job of
  // its own would block nothing until branch protection listed it
  // (backend/test/infra/launch_doc_test.dart says why that matters).
  it('CI runs it in the required web job, from web/, after the plain run', () => {
    const job = yamlJob(readFileSync(join(REPO, '.github/workflows/ci.yml'), 'utf8'), 'web');
    expect(job, 'no web job in ci.yml').not.toBe('');
    expect(job).toMatch(/^\s+working-directory: web$/m);
    const plain = job.search(/^\s+run: npm test$/m);
    const stress = job.search(/^\s+run: npm run test:stress$/m);
    expect(plain, 'the plain unit-test step is gone').toBeGreaterThan(-1);
    expect(stress, 'the scheduler-stress step is gone').toBeGreaterThan(-1);
    expect(stress).toBeGreaterThan(plain);
  });
});

/// One job's block, comments stripped, so neither another job nor a sentence
/// about the command can satisfy the pin (the same helpers as
/// registration-claim.test.ts; importing a test file would re-run its suite).
function yamlJob(src: string, name: string): string {
  const stripped = src.replace(/(^|\s)#.*$/gm, (_m, before: string) => before);
  const m = stripped.match(new RegExp(`^  ${name}:$[\\s\\S]*?(?=^  \\S[^\\n]*:$|$(?![\\s\\S]))`, 'm'));
  return m ? m[0] : '';
}
