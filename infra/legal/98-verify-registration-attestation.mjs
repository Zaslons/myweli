#!/usr/bin/env node
//
// Has anyone confirmed, recently, that the registration claim is still true?
//
// Exit 0 = the attestation in infra/legal/registration-manifest.json is fresh.
// Exit 1 = nobody has looked in `attestationMaxAgeDays`, and it is time.
//
// ## Why this exists
//
// web/app/mentions-legales/page.tsx tells the public MyWeli is « société en
// cours d'immatriculation ». Nothing in this repository can check that — no
// API answers it, and the only person who knows is the owner. So this does not
// verify the claim. It verifies that someone LOOKED, and fails when nobody has.
//
// A deadline in a document is a wish. This is the mechanism.
//
// ## Why Node and not bash
//
// Every other checker here is a shell script, and this one is not, on purpose:
// `date -d` is GNU-only. A bash version could not be rehearsed on the machine
// it was written on — it could only ever be watched fail on the runner, which
// is how a guard ships unproven. Node behaves identically in both places.
//
// ## Why this is not a unit test
//
// web/tests/stub-clock.test.ts: « a suite that is green at every hour except
// one fails a future PR at random and looks like that PR's fault. » Web unit
// tests block merges; this cannot. It runs on the production-checks cron and
// opens an issue. The CONSISTENCY half — that all seven surfaces agree — is
// clock-free and does live in the merge gate
// (web/tests/registration-claim.test.ts).
//
// ## Read-only
//
// It opens one file for reading and writes nothing but stdout.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
// Overridable so the failure paths can be rehearsed against a fixture, the way
// infra/gcp/97-verify-log-retention.sh takes LOGGING_MANIFEST. The CLOCK is
// deliberately NOT overridable: a seam that can silence a monitor is a seam
// someone silences.
const MANIFEST =
  process.env.REGISTRATION_MANIFEST ?? join(HERE, 'registration-manifest.json');

const fail = (msg) => {
  console.log(`  ✗ ${msg}`);
  console.log(`::error::${msg}`);
  process.exit(1);
};

let manifest;
try {
  manifest = JSON.parse(readFileSync(MANIFEST, 'utf8'));
} catch (e) {
  // Never swallow the error you are about to act on: an unreadable manifest is
  // indistinguishable from a fresh one if this returns quietly.
  fail(`cannot read ${MANIFEST}: ${e.message}`);
}

const { attestedOn, attestationMaxAgeDays, registered } = manifest;

if (typeof attestedOn !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(attestedOn)) {
  fail(`attestedOn must be YYYY-MM-DD, got ${JSON.stringify(attestedOn)}`);
}
// `new Date("2026-13-45")` is Invalid Date, and every comparison against it is
// false — so a typo would sail through a naive `days > max` as "fresh".
const attested = new Date(`${attestedOn}T00:00:00Z`);
if (Number.isNaN(attested.getTime())) {
  fail(`attestedOn is not a real date: ${attestedOn}`);
}
if (!Number.isFinite(attestationMaxAgeDays) || attestationMaxAgeDays <= 0) {
  fail(
    `attestationMaxAgeDays must be a positive number, got ${JSON.stringify(
      attestationMaxAgeDays,
    )}`,
  );
}

const days = Math.floor((Date.now() - attested.getTime()) / 86_400_000);
if (days < 0) {
  fail(`attestedOn is ${-days} day(s) in the future: ${attestedOn}`);
}

const claim = registered
  ? 'the published RCCM facts (numéro, siège, capital, représentant légal)'
  : '« société en cours d’immatriculation » in the mentions légales';

// The remediation has to match the world the manifest is in. Telling someone to
// flip a flag that is already flipped is the kind of instruction that gets a
// monitor ignored.
const remedy = registered
  ? 'Either one of those facts changed — correct every surface, and ' +
    'web/tests/registration-claim.test.ts will confirm none still reads as ' +
    'pending — or nothing changed, and `attestedOn` becomes today.'
  : 'Either registration completed — flip `registered` to true in ' +
    'infra/legal/registration-manifest.json and ' +
    'web/tests/registration-claim.test.ts will list every surface to rewrite ' +
    '— or it has not, and `attestedOn` becomes today.';

if (days > attestationMaxAgeDays) {
  console.log(`  ✗ last confirmed ${days} days ago, on ${attestedOn}`);
  console.log(
    `::error::Nobody has confirmed ${claim} in ${days} days ` +
      `(limit ${attestationMaxAgeDays}). ${remedy} Both are one edit in a PR.`,
  );
  process.exit(1);
}

console.log(`  ✓ ${claim}`);
console.log(
  `    confirmed ${days} day(s) ago (${attestedOn}); ` +
    `${attestationMaxAgeDays - days} day(s) before this asks again`,
);
