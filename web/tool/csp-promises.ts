/// **What the policy must still allow, as one rule that two checks read.**
///
/// `check-privacy-promise.spec.ts` reads it against the header myweli.com sends;
/// `tests/csp.test.ts` reads it against the policy a PR is about to ship. It used to
/// live only in the daily check, as text matches on the whole header, and nothing
/// runs that check on a PR. When 9f320d4c correctly wrote « worker-src 'self' blob: »,
/// `toContain('worker-src blob:')` went red the next morning and stayed red for 13
/// days, while the line after it never ran.

type ResponseHeaders = Record<string, string | undefined>;

/// A directive's sources, in whatever order they are written.
function sourcesOf(csp: string, directive: string): string[] {
  for (const part of csp.split(';')) {
    const [name, ...sources] = part.trim().split(/\s+/);
    if (name === directive) return sources;
  }
  return [];
}

/// The omissions that break production with nothing else noticing (next.config.mjs
/// says why each is there). Each names its directive: R2 is in `img-src` too, so a
/// match on the whole policy stayed green with uploads refused.
const REQUIRED = [
  { directive: 'worker-src', source: 'blob:', why: 'maplibre builds its worker from a Blob URL' },
  { directive: 'worker-src', source: "'self'", why: 'the Pro area registers /pro/push-sw.js' },
  { directive: 'connect-src', source: '*.cartocdn.com', why: 'the map reads its style and tiles there' },
  { directive: 'connect-src', source: '*.r2.cloudflarestorage.com', why: 'uploads PUT straight at R2' },
];

/// Every way the response's policy falls short, so one failure cannot hide the next.
/// Read enforcing first: moving off Report-Only is a repair, and must not turn this red.
export function cspProblems(headers: ResponseHeaders): string[] {
  const csp = headers['content-security-policy'] ?? headers['content-security-policy-report-only'];
  if (!csp) return ['the response carries no CSP at all'];

  const problems = REQUIRED.filter(({ directive, source }) =>
    !sourcesOf(csp, directive).some((s) => s.replace(/^https:\/\//, '') === source),
  ).map(({ directive, source, why }) => `${directive} lacks ${source}: ${why}`);

  // Violations must reach a person, or Report-Only is a policy nobody reads.
  if (sourcesOf(csp, 'report-uri').length === 0) {
    problems.push('no report-uri: violations would go nowhere');
  }
  return problems;
}
