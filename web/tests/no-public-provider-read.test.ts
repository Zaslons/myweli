import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

/// No web surface fetches a salon by id from the PUBLIC route (Decision C).
///
/// **Why a source pin.** Nothing is user-visible while `GET /providers/{id}`
/// still serves every salon, so no behavioural test can see the difference
/// today. The property is about WHICH DOOR the code knocks on, and the only
/// artifact that records a door is the source. The behavioural half lives in
/// the e2e suite, whose stub already models the CLOSED backend — `p3` and `p4`
/// 404 there — so the two halves cover different failure modes: this one
/// catches a new fetch being added, that one catches a surface that would
/// break if the fetch stopped working.
///
/// **What was here.** Three call sites, each degrading in silence: `bff.ts`
/// fanned out one request per distinct salon to print a booking's name and
/// returned `{}` on failure; `/api/me/favorites` fetched each favorite and
/// filtered the failures away; and `fetchBookingWindow` fell back to a
/// year-wide window through a proxy route whose only caller it was. The server
/// hydrates all three now.
///
/// **Two things are deliberately NOT forbidden**, and the pin went red on the
/// second before it said so.
///
/// By-SLUG: `app/[slug]/page.tsx` IS the public salon page, and asking the
/// public route for a public page is correct.
///
/// And `callApiPro` / `callApi`: those attach the caller's session, so
/// `app/api/pro/profil/route.ts`'s `PATCH /providers/{id}` is an authenticated,
/// ownership-gated write — the opposite of the defect. The property is not
/// « never name this path », it is « never ask the ANONYMOUS door », so the pin
/// looks for the unauthenticated shapes: a server-side `fetch` against
/// `apiBase`, or a browser fetch of the deleted `/api/providers/` proxy.
const ROOTS = ['lib', 'app', 'components'];

function walk(dir: string, out: string[] = []): string[] {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      if (entry === 'node_modules' || entry.startsWith('.')) continue;
      walk(full, out);
    } else if (/\.(ts|tsx)$/.test(entry)) {
      out.push(full);
    }
  }
  return out;
}

/// Comments are not code — the same hole `french_test.dart:51` closes, and the
/// reason this file's own docstring does not fail the pin it describes.
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '')
    .replace(/^\s*\/\/\/.*$/gm, '');
}

describe('the public salon read has no web caller left', () => {
  const files = walk(ROOTS[0])
    .concat(walk(ROOTS[1]))
    .concat(walk(ROOTS[2]))
    // Generated from the contract; it describes the API, it does not call it.
    .filter((f) => !f.endsWith('lib/api/schema.ts'));

  it('scans a real tree — a pin whose glob matches nothing is green about nothing', () => {
    // §21 row 70. If this fails the paths moved, not the property.
    expect(files.length).toBeGreaterThan(100);
  });

  it('nothing asks the anonymous door for a salon by id', () => {
    const offenders: string[] = [];
    for (const f of files) {
      const src = stripComments(readFileSync(f, 'utf8'));
      for (const line of src.split('\n')) {
        if (!/providers\//.test(line)) continue;
        if (/providers\/by-slug/.test(line)) continue;
        // A further path segment means a sub-resource, not the document.
        if (/providers\/\$\{[^}]+\}\//.test(line)) continue;
        const unauthenticated =
          /\$\{apiBase\}\/providers\//.test(line) ||
          /\/api\/providers\//.test(line);
        if (unauthenticated) offenders.push(`${f} → ${line.trim()}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('and the pin can still SEE such a call — it is not green about nothing', () => {
    // The falsifiability check that matters for a regex pin: prove the matcher
    // fires on the exact line that was deleted from `bff.ts`, so a green run
    // means « no such call » rather than « the pattern never matches anything ».
    const wasThere = 'const r = await fetch(`${apiBase}/providers/${id}`);';
    expect(/\$\{apiBase\}\/providers\//.test(wasThere)).toBe(true);
  });

  it('and the BFF proxy that existed only to serve one of them is gone', () => {
    // `app/api/providers/[id]/route.ts` forwarded the public read so
    // `fetchBookingWindow` could ask for a salon's booking window. The window
    // rides the appointment now, so both the caller and the route are deleted.
    expect(existsSync('app/api/providers')).toBe(false);
  });
});
