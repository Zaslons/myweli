#!/usr/bin/env node
//
// **Can this build actually sign in with Google?**
//
// Run from `tool/release_build.sh` immediately before a store artifact is
// produced, because that is the only moment both halves of the answer are
// visible at once: the repository knows which OAuth clients the app will
// present, and Secret Manager knows which ones the backend will accept. A test
// can see the first. A monitor can see the second. Neither can see both, and
// the defect lives exactly in the gap between them.
//
// Two real failures this exists to prevent, both silent, both discovered on
// 2026-08-22:
//
//   1. **The signing key.** Google matches an Android sign-in by (package,
//      certificate SHA-1). Only a development keystore is registered, so every
//      build the owner tests works and the store build — signed by Google with
//      a different key — fails for every real user, and shows them NOTHING:
//      Credential Manager reports a wrong SHA as `canceled`, which the app
//      cannot tell from a dismissal, so the button does nothing and logs
//      nothing.
//
//   2. **The audience.** The backend accepts only the ids in
//      GOOGLE_CLIENT_IDS and rejects everything else, so a build presenting
//      an audience outside that list fails AFTER Google succeeds: the user
//      picks an account and lands back on an error.
//
//      **This header used to call that a live defect, and it was wrong.** It
//      said the Pro ids were missing from the allowlist and Pro sign-in was
//      therefore broken. They are missing, and it is not broken:
//      `serverClientId` sets the audience to the WEB client on both
//      platforms, which IS allowed — the chain is in section 4 below. The
//      per-flavour ids are never presented as an audience at all, and a gate
//      requiring them would refuse a release that works perfectly. The
//      invariant is conditional, and section 4 evaluates it as one.
//
// Neither failure produces a crash, a log line, or a red test. Both are one
// comparison away from being impossible.
//
//   node infra/mobile/96-verify-google-identity.mjs --platform android --flavour pro
//
// The allowlist is read from `infra/gcp/service.yaml`, which is where it lives
// now — it is a set of public audiences, not a secret, so this script needs no
// gcloud and no credentials at all. It used to read the environment, which
// meant the release gate could only run somewhere Secret Manager was reachable.

import { readFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..')
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8')
const json = (p) => JSON.parse(read(p))

const argv = process.argv.slice(2)
const arg = (name) => {
  const i = argv.indexOf(`--${name}`)
  return i >= 0 ? argv[i + 1] : undefined
}

const platform = arg('platform')
const flavour = arg('flavour')

const problems = []
const checked = []
const fail = (what, how) => problems.push({ what, how })
const ok = (line) => checked.push(line)

if (!['ios', 'android'].includes(platform) || !['consumer', 'pro'].includes(flavour)) {
  console.error('usage: 96-verify-google-identity.mjs --platform <ios|android> --flavour <consumer|pro>')
  process.exit(2)
}

const manifest = json('infra/mobile/signing-manifest.json')
const pkg = Object.entries(manifest.packages).find(([, v]) => v.flavour === flavour)
if (!pkg) {
  console.error(`the manifest declares no package for flavour "${flavour}"`)
  process.exit(2)
}
const [packageName, packageEntry] = pkg

// ── 1. the manifest must not be able to lie about itself ────────────────────
const play = manifest.playAppSigning
const devHashes = manifest.developmentFingerprints.map((f) => f.sha1)
const SHA1 = /^[0-9a-f]{40}$/

for (const f of manifest.developmentFingerprints) {
  if (!SHA1.test(f.sha1)) {
    fail(
      `development fingerprint "${f.sha1}" is not 40 lowercase hex characters`,
      'google-services.json stores hashes lowercase with the colons stripped; the ' +
        'console shows AA:BB:CC… and that form compares unequal against every entry',
    )
  }
  if (f.releaseSafe !== false) {
    fail(
      `development fingerprint ${f.sha1.slice(0, 12)}… is marked releaseSafe`,
      'a development keystore is never release-safe. If this were allowed to be ' +
        'true, the gate below could be satisfied by the very key it exists to reject',
    )
  }
}

if (play.enrolled) {
  if (!SHA1.test(play.sha1 ?? '')) {
    fail(
      `playAppSigning.sha1 is ${JSON.stringify(play.sha1)}`,
      'enrolled without a well-formed SHA-1 — 40 lowercase hex, colons stripped',
    )
  } else if (devHashes.includes(play.sha1)) {
    // The shortcut somebody reaches for at 2am when the gate is in the way.
    fail(
      'playAppSigning.sha1 is one of the development fingerprints',
      'that is the debug keystore wearing the release label, and it makes every ' +
        'check below pass while changing nothing about what Google will accept',
    )
  }
} else if (play.sha1 !== null) {
  fail(
    'playAppSigning.sha1 is set while enrolled is false',
    'one of the two is wrong, and guessing which would be the whole defect again',
  )
}

// ── 2. the fingerprints Google will actually match on ───────────────────────
if (platform === 'android') {
  const cfg = json(packageEntry.config)
  const client = cfg.client.find(
    (c) => c.client_info?.android_client_info?.package_name === packageName,
  )

  if (!client) {
    fail(
      `${packageEntry.config} has no entry for ${packageName}`,
      'the app would build with a config that does not describe it',
    )
  } else {
    // One entry per registered fingerprint, so this IS the registered set.
    const registered = client.oauth_client
      .filter((c) => c.client_type === 1)
      .map((c) => c.android_info?.certificate_hash)
      .filter(Boolean)

    if (registered.length === 0) {
      fail(
        `${packageName} has no Android OAuth client at all`,
        'Google sign-in cannot work for this package on any build',
      )
    }

    const undeclared = registered.filter(
      (h) => !devHashes.includes(h) && h !== play.sha1,
    )
    if (undeclared.length) {
      fail(
        `${packageName} has fingerprints nobody declared: ${undeclared.join(', ')}`,
        'somebody registered a signing key against a production OAuth client and ' +
          'did not write down whose it is. Add it to the manifest, or remove it ' +
          'from the console',
      )
    }

    if (!play.enrolled) {
      // **The chicken-and-egg this gate did not model at first:** enrolment
      // HAPPENS at the first AAB upload, so refusing every unenrolled build
      // also refuses the one build that can end the unenrolled state. The
      // explicit escape: BOOTSTRAP_PLAY_ENROLMENT=1 accepts exactly this
      // case, loudly, for an artifact whose only job is to make Play
      // generate the App Signing key. It is inherently non-final — after
      // enrolment the SHA gets registered, google-services.json
      // re-downloaded, and a NEW build made, which this gate then holds to
      // the full bar.
      if (process.env.BOOTSTRAP_PLAY_ENROLMENT === '1') {
        console.log(
          `\n  ⚠ BOOTSTRAP BUILD — Play App Signing is NOT enrolled for ${packageName}.\n` +
            '  This artifact exists to be uploaded ONCE so Play generates the App\n' +
            '  Signing key. Google sign-in is DEAD in it (silently — the button\n' +
            '  does nothing). Upload it, read the SHA-1, register it, re-download\n' +
            '  google-services.json, rebuild WITHOUT this flag — and never hand\n' +
            '  this artifact to a tester.\n',
        )
      } else {
        fail(
          `Play App Signing is not enrolled, so ${packageName} is signed for release by a key Google does not know`,
          'the ONLY fingerprint registered is a development keystore. This build ' +
            'would install, launch, look perfect, and fail Google sign-in for every ' +
            'real user WITHOUT SHOWING THEM ANYTHING — Credential Manager reports a ' +
            'wrong signing SHA as a cancellation, so the button does nothing and ' +
            'logs nothing. See infra/mobile/signing-manifest.json → ' +
            'playAppSigning.howToGetIt. For the FIRST upload — the one that ' +
            'creates the enrolment — set BOOTSTRAP_PLAY_ENROLMENT=1.',
        )
      }
    } else if (!registered.includes(play.sha1)) {
      fail(
        `${packageEntry.config} does not carry the Play App Signing SHA-1`,
        'the fingerprint is recorded here but not in the config, which means the ' +
          'file was never re-downloaded after it was added — or it was never ' +
          'actually added to this package in the Firebase console',
      )
    } else {
      ok(`${packageName} is registered under the Play App Signing key`)
    }
  }
}

// ── 3. the manifest's client ids are the ones the app really carries ────────
const declared = manifest.audience.clients.find(
  (c) => c.platform === platform && c.flavour === flavour,
)
if (!declared) {
  fail(
    `the manifest declares no ${platform} client for ${flavour}`,
    'nothing to check, which is how a gate becomes decorative',
  )
}

let actual
if (platform === 'ios') {
  const body = read(`mobile/ios/config/${flavour}/GoogleService-Info.plist`)
  const i = body.indexOf('<key>CLIENT_ID</key>')
  actual = i < 0 ? null : /<string>([^<]*)<\/string>/.exec(body.slice(i))?.[1]
} else {
  const cfg = json(packageEntry.config)
  actual = cfg.client
    .find((c) => c.client_info?.android_client_info?.package_name === packageName)
    ?.oauth_client.find((c) => c.client_type === 1)?.client_id
}

if (declared && actual && declared.id !== actual) {
  fail(
    `the manifest says ${flavour}/${platform} uses ${declared.id} but the config says ${actual}`,
    'the manifest has drifted into being a second source of truth, and the checks ' +
      'below would then be verifying an id no build ever presents',
  )
} else if (declared && actual) {
  ok(`${flavour}/${platform} presents ${actual.slice(0, 24)}…`)
}

// ── 4. the backend will accept the audience the app actually presents ──────
//
// **Which id that is depends on one argument, so the check depends on it too.**
// `GoogleSignIn.instance.initialize(serverClientId: …)` sets the ID token's
// `aud` to the server (web) client on BOTH platforms — not only Android, which
// is what this file assumed on its first draft and got wrong. The chain, read
// from source: google_sign_in_ios-6.3.0 FLTGoogleSignInPlugin.m:344 forwards
// serverClientId into GIDConfiguration; GIDConfiguration.h:27 says of
// serverClientID "This will be returned as the `audience` property of the
// OpenID Connect ID token"; GIDSignIn.m:901 sets the audience parameter from it.
//
// So requiring each per-flavour client id to be allowlisted would refuse a
// release that signs in perfectly. What must be allowlisted is whatever the app
// will actually send — and if the argument is ever dropped, that flips to the
// per-flavour id for every build at once. Both branches are checked, so the
// gate stays correct through the refactor that would otherwise be silent.
const authService = read('mobile/lib/services/api/api_auth_service.dart')
const passesServerClientId = /serverClientId:\s*AppConfig\.googleServerClientId/.test(
  authService,
)

const audience = passesServerClientId
  ? { id: manifest.audience.server, what: 'the server (web) client id' }
  : {
      id: declared?.id,
      what: `the ${platform} ${flavour} client id (serverClientId is NOT passed)`,
    }

if (!passesServerClientId) {
  console.log(
    '  ! api_auth_service.dart no longer passes serverClientId — the audience is\n' +
      '    now each build\'s own client id. That is a real change in what the\n' +
      '    backend must allowlist, not a formatting difference.',
  )
}

// A single quoted-scalar `value:` under the env entry. Parsed rather than
// imported because this file deliberately has no dependencies.
const serviceYaml = read('infra/gcp/service.yaml')
const m = /- name: GOOGLE_CLIENT_IDS\s*\n\s*value:\s*(\S+)/.exec(serviceYaml)
const raw = m ? m[1] : undefined

if (raw === undefined || raw.trim() === '') {
  fail(
    'GOOGLE_CLIENT_IDS is not a plain value in infra/gcp/service.yaml',
    'the audience half cannot be checked, and skipping it would mean this script ' +
      'reports success having verified less than it says. If it went back to a ' +
      'secretKeyRef, this script and the merge gate both go blind',
  )
} else if (!audience.id) {
  fail(
    `no client id is declared for ${platform}/${flavour}`,
    'there is nothing to check against the allowlist, which is how a gate becomes ' +
      'decorative',
  )
} else {
  const allow = new Set(raw.split(',').map((s) => s.trim()).filter(Boolean))
  if (allow.has(audience.id)) {
    ok(`the backend accepts ${audience.what}`)
  } else {
    fail(
      `GOOGLE_CLIENT_IDS does not contain ${audience.what} (${audience.id})`,
      'Google would succeed and the BACKEND would reject the token: the user sees ' +
        'the Google sheet, picks an account, and lands back on an error. Fix: add ' +
        'it to GOOGLE_CLIENT_IDS in infra/gcp/service.yaml, then deploy',
    )
  }
}

// The audience is only the web client because the app is compiled with it. If
// AppConfig's default and the manifest ever disagree, the id being checked above
// is not the id the build will send.
if (!/731308991240-/.test(manifest.audience.server)) {
  fail('the manifest server id is not a project 731308991240 client', 'wrong project')
} else if (!read('mobile/lib/core/config/app_config.dart').includes(manifest.audience.server)) {
  fail(
    'app_config.dart does not name the manifest server client id',
    'the gate would verify an audience the build does not send',
  )
} else {
  ok('the app is compiled with the server client id the manifest names')
}

// ── report ─────────────────────────────────────────────────────────────────
for (const line of checked) console.log(`  ✓ ${line}`)

if (problems.length) {
  console.error('')
  console.error(`✗ ${platform}/${flavour} cannot sign in with Google:`)
  for (const p of problems) {
    console.error('')
    console.error(`  • ${p.what}`)
    console.error(`    ${p.how}`)
  }
  console.error('')
  process.exit(1)
}

console.log(`✓ ${platform}/${flavour}: Google sign-in is configured end to end.`)
