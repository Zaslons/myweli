import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/// **The alarm's one line says how each check ended** (docs/design/production-alarm-close.md).
///
/// `backend/test/infra/production_alarm_test.dart` runs the report's script and holds who
/// it hears from, but a check dropped from the status line left all of it green (watched,
/// on the card photo job). The issue then names seven checks while the eighth is the red
/// one, and the reader goes looking in the wrong place. Derived from the file, not listed,
/// so a ninth check is held the day it arrives. It lives here because any file under
/// `backend/` starts `deploy-backend.yml` on merge (web-swiss-cards.md §9).
const workflow = readFileSync(join('..', '.github', 'workflows', 'production-checks.yml'), 'utf8').replace(
  /^\s*#.*$/gm,
  '',
);

const NOT_CHECKS = new Set(['report', 'clear']);

const jobs = workflow.slice(workflow.search(/^jobs:$/m));
const checks = [...jobs.matchAll(/^ {2}([a-z][a-z0-9_-]*):$/gm)].map((m) => m[1]).filter((name) => !NOT_CHECKS.has(name));

const report = jobs.match(/^ {2}report:$[\s\S]*?(?=^ {2}\S[^\n]*:$|$(?![\s\S]))/m)?.[0] ?? '';
/// The line that opens with the first check's row.
const statusLine = report.match(/^.*\bCWV: \$\{CWV\}.*$/m)?.[0] ?? '';

describe('production-checks.yml, the report’s status line', () => {
  it('reads a real file: a derived list that found nothing is green about nothing', () => {
    expect(checks.length).toBeGreaterThanOrEqual(8);
    expect(checks).toContain('cardphoto');
    expect(report, 'no report job').not.toBe('');
    expect(statusLine, 'no status line in the report').not.toBe('');
  });

  it('says how every check ended', () => {
    const missing = checks.filter((check) => {
      const row = report.match(new RegExp(`^\\s+([A-Z][A-Z0-9_]*): \\$\\{\\{ needs\\.${check}\\.result \\}\\}\\s*$`, 'm'));
      return !row || !statusLine.includes(`\${${row[1]}}`);
    });
    expect(missing, 'a check the issue does not mention can be the red one').toEqual([]);
  });
});
