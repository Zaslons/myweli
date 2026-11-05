// **Fail the stub's image host at once, in the Next process**
// (docs/design/web-swiss-cards.md §8), loaded with
// `NODE_OPTIONS=--require ./tests/e2e/_cdn-stub-dns.cjs` by playwright.config.ts's Next
// server and by the `npm run lhci` step of ci.yml's web-lighthouse.
//
// Salon cards put a photo on `/`, the landings, `/recherche` and the favourites, and
// each one makes the Next server fetch `https://cdn.stub/…`, a host that does not
// exist. `axe.spec.ts` records what that lookup does on CI's libuv pool: a 30 s stall,
// with `retries: 0`. A per-spec route would have to reach about 62 `goto`s, and the next
// spec would forget it. So the failure stays the same one the suite always saw, an image
// that does not load, and only gets fast: with this, a 500 in 26 ms; with a lookup made
// to hang, no answer in 6 s (both measured). `networkidle` settles again too.
//
// Only this host, and never in production: nothing outside tests/e2e loads this file.
// `net` reads `dns.lookup` when it connects, so replacing the property reaches `fetch`.
// Held by the « test server » case in site-look.spec.ts.
const dns = require('node:dns');

const realLookup = dns.lookup;

dns.lookup = function lookup(hostname, options, callback) {
  if (hostname !== 'cdn.stub') return realLookup.call(this, hostname, options, callback);
  const answer = typeof options === 'function' ? options : callback;
  const refusal = Object.assign(new Error('getaddrinfo ENOTFOUND cdn.stub'), {
    code: 'ENOTFOUND',
    syscall: 'getaddrinfo',
    hostname,
  });
  return process.nextTick(answer, refusal);
};
