import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/// The register row-number pin (docs/design/SYSTEM.md §21 · WEB-SYSTEM.md §15).
///
/// **Why this exists.** Both registers are cited *by number* — « §21 row 73 »,
/// « §15 row 30 (reopened) » — from design specs, from source comments, and from
/// PR bodies. A row number is therefore an identifier, and a duplicated one
/// silently repoints every citation written after it.
///
/// Not hypothetical: **B12 filed its axe-anchor row as 31**, directly under row
/// 30, which reads naturally because B12 reopened row 30 — and B11 had already
/// taken 31 *and* 32. The register carried two row 31s until the chore that
/// added this pin. Nothing failed, because nothing could: the registers are
/// prose, and no gate had ever read them.
///
/// Shaped like `time-pin.test.ts` and `tokens.theme-pin.test.ts` — read the file
/// from disk, assert on its text. It reaches across into `docs/` because the
/// registers are shared design documents, the same way `tokens.mirror.test.ts`
/// reaches across into the Flutter token source.

const REPO = join(process.cwd(), '..');

const REGISTERS = [
  { file: 'docs/design/SYSTEM.md', heading: '## 21. The known-violations register' },
  {
    file: 'docs/design/WEB-SYSTEM.md',
    heading: '## 15. The known-violations register',
  },
];

/// The row ids of a register table: the first cell of every `| <id> | …` line
/// between the register heading and the next `## ` heading.
///
/// **Scoped to the section rather than the whole file on purpose.** Today every
/// line of that shape in both files is already inside its register (measured:
/// 78 of 78 in SYSTEM.md, 44 of 44 in WEB-SYSTEM.md), so a whole-file scan would
/// agree right now. But the next numbered table added anywhere else in either
/// document would turn this pin into a source of false reds — and a gate that
/// cries wolf gets re-run and ignored rather than read.
function registerRowIds(markdown: string, heading: string): string[] {
  const lines = markdown.split('\n');
  const start = lines.indexOf(heading);
  if (start === -1) throw new Error(`register heading not found: ${heading}`);

  const ids: string[] = [];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith('## ')) break;
    const m = /^\| (\d+[a-z]?) \|/.exec(line);
    if (m) ids.push(m[1]);
  }
  return ids;
}

function duplicates(ids: string[]): string[] {
  const seen = new Set<string>();
  const dupes = new Set<string>();
  for (const id of ids) (seen.has(id) ? dupes : seen).add(id);
  return [...dupes];
}

describe('the known-violations registers', () => {
  for (const { file, heading } of REGISTERS) {
    it(`${file} numbers every row exactly once`, () => {
      const ids = registerRowIds(readFileSync(join(REPO, file), 'utf8'), heading);
      // Non-vacuity: a heading rename or a table reformat would otherwise leave
      // this asserting `[] === []` forever, which is §21 row 67's whole lesson.
      expect(ids.length).toBeGreaterThan(10);
      expect(duplicates(ids)).toEqual([]);
    });
  }

  /// **The falsifiability case.** The two assertions above are green from birth
  /// — the duplicate they describe is fixed in the same commit — so on their own
  /// they prove only that the files still parse. SYSTEM.md §21 row 67 records
  /// six helpers shipped unable to fail; this feeds the rule a table that does
  /// repeat a number, and one that does not.
  it('reports a repeat when there is one, and stays quiet when there is not', () => {
    const heading = '## 15. The known-violations register';
    const table = (ids: string[]) =>
      [heading, '', '| # | Rule |', '|---|---|', ...ids.map((i) => `| ${i} | x |`), '', '## 16. Next'].join('\n');

    // A lettered variant (`30h`, `7b`) is a distinct id, not a repeat of its stem.
    expect(registerRowIds(table(['1', '2', '2a', '3']), heading)).toEqual(['1', '2', '2a', '3']);
    expect(duplicates(registerRowIds(table(['1', '2', '2a', '3']), heading))).toEqual([]);

    // The shape B12 actually shipped.
    expect(duplicates(registerRowIds(table(['1', '2', '2', '3']), heading))).toEqual(['2']);

    // The section boundary is load-bearing: a numbered table AFTER the register
    // must not be read into it.
    expect(registerRowIds([table(['1']), '| 1 | elsewhere |'].join('\n'), heading)).toEqual(['1']);
  });
});
