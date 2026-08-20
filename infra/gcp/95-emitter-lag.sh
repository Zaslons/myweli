#!/usr/bin/env bash
#
# Can the code that is RUNNING produce the strings the alerts watch for?
#
# ## The hole this closes
#
# `alert_runbooks_test.dart` asserts every `textPayload` filter literal exists
# under `backend/lib/` — in the WORKING TREE. `93-sync-runbooks.sh` proves the
# live policies match the repo. Neither asks whether the artifact a service is
# actually RUNNING can emit the string.
#
# On 2026-08-20 #445 added the `rate_limited bucket=` emitter and merged AFTER
# the last production deploy. Production ran a commit without that string while
# the live policy filtered for it. The alert could not fire on the surface it was
# built for, and every outward sign — policy enabled, runbook correct, no
# incidents, tests green — said otherwise. An audit found it, not a check.
#
# ## Why it checks EVERY service, not the one just deployed
#
# The deploys that followed #445 were staging pushes, and staging DID have the
# string. A check scoped to the service being deployed would have passed on every
# one of them while production stayed blind. All five app-emitted filters name
# production as well as staging, so every filter is checked against every service
# it names, on every run.
#
# ## Where the filters come from
#
# The repo's rendered bodies, via `policy-bodies.sh` — the same renderer
# `93-sync-runbooks.sh` uses, so the two cannot disagree about what a filter
# says. Not the live policies: the deploy service account has `run.admin` and
# `artifactregistry.writer` and NO monitoring read, so a CI run cannot list
# policies. That live-vs-repo question is `93`'s job, and it is answered
# separately.
#
# ## Testing it
#
#   PIN_myweli_api=34d55c0 bash infra/gcp/95-emitter-lag.sh
#
# pins a service to a past commit without touching anything, and reproduces the
# historical defect above.
set -euo pipefail

PROJECT=${PROJECT:-myweli}
REGION=${REGION:-europe-west9}

if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
  echo "::error:: this is a SHALLOW clone - \`git grep <old-sha>\` cannot work here." >&2
  echo "          Check out with fetch-depth: 0, or fetch the deployed commit." >&2
  echo "          Failing rather than passing: a check that cannot look is not a check." >&2
  exit 1
fi

CHANNEL=${CHANNEL:-projects/placeholder/notificationChannels/0}
WORK=$(mktemp -d); trap 'rm -rf "${WORK}"' EXIT
# shellcheck source=infra/gcp/policy-bodies.sh
source "$(dirname "${BASH_SOURCE[0]}")/policy-bodies.sh"

python3 - "${PROJECT}" "${REGION}" "${INTENDED[@]}" <<'PY'
import json, os, re, subprocess, sys

project, region = sys.argv[1], sys.argv[2]
bodies = sys.argv[3:]

def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout.strip()

# --- what each service is really running ------------------------------------
# The `commit` label is self-reported by the deploy. A registry tag is mutable
# and can collide (`latest` shares a digest with a real SHA in this registry).
# Neither alone is sound. The tie that IS sound is the pair: take the label,
# resolve IMAGE:<label> back to a digest, and require it to equal the digest the
# revision is serving. That is the pattern deploy-backend.yml already uses.
_cache = {}
def running(service):
    if service in _cache:
        return _cache[service]
    pin = os.environ.get('PIN_' + service.replace('-', '_'))
    if pin:
        _cache[service] = (pin, 'PINNED (test override)')
        return _cache[service]
    image = sh('gcloud', 'run', 'services', 'describe', service, '--region', region,
               '--project', project,
               '--format=value(spec.template.spec.containers[0].image)')
    label = sh('gcloud', 'run', 'services', 'describe', service, '--region', region,
               '--project', project,
               '--format=value(spec.template.metadata.labels.commit)')
    if not image:
        _cache[service] = (None, 'service not found')
        return _cache[service]
    if not label:
        _cache[service] = (None, 'revision carries no commit label')
        return _cache[service]
    repo = image.split('@')[0]
    resolved = sh('gcloud', 'artifacts', 'docker', 'images', 'describe',
                  '%s:%s' % (repo, label), '--project', project,
                  '--format=value(image_summary.digest)')
    if resolved and image.endswith(resolved):
        _cache[service] = (label, 'label verified against the serving digest')
    else:
        _cache[service] = (None,
            'label %s resolves to %s, which is NOT what is serving - do not trust it'
            % (label, resolved or '<nothing>'))
    return _cache[service]

# --- the filters, from the same renderer 93 uses -----------------------------
checkable, skipped = [], []
for path in bodies:
    d = json.load(open(path))
    for c in d.get('conditions') or []:
        for k in c:
            if not k.startswith('condition'):
                continue
            f = (c[k] or {}).get('filter') or ''
            if not f:
                continue
            lits = re.findall(r'textPayload:"([^"]+)"', f)
            if not lits:
                why = ('a load-balancer or Cloud Run field, not a string our code prints'
                       if 'jsonPayload' in f or 'httpRequest' in f
                       else 'metric-based, no application code involved'
                       if 'metric.type' in f else 'no textPayload literal')
                skipped.append((d['displayName'], why))
                continue
            svcs = sorted(set(re.findall(r'service_name="([^"]+)"', f)))
            for lit in lits:
                checkable.append((d['displayName'], lit, svcs or ['myweli-api']))

print('CAN THE RUNNING CODE PRODUCE WHAT THE ALERTS WATCH FOR?')
print()
for s in sorted({s for _, _, sv in checkable for s in sv}):
    commit, how = running(s)
    print('  %-22s %-10s [%s]' % (s, commit or 'UNRESOLVED', how))
print()

lag = 0
for name, lit, svcs in checkable:
    marks = []
    for s in svcs:
        commit, _ = running(s)
        if not commit:
            marks.append('%s=UNRESOLVED' % s); lag += 1; continue
        ok = subprocess.run(['git', 'grep', '-q', lit, commit, '--', 'backend/lib'],
                            capture_output=True).returncode == 0
        marks.append('%s=%s' % (s, 'ok' if ok else 'CANNOT EMIT'))
        if not ok:
            lag += 1
    bad = any(('CANNOT EMIT' in m) or ('UNRESOLVED' in m) for m in marks)
    print('  %s  %-42s %r' % ('FAIL' if bad else 'ok  ', name[:42], lit))
    print('          %s' % '   '.join(marks))

if skipped:
    print()
    print('  Not checkable against source, and why - said rather than silently omitted:')
    for name, why in sorted(set(skipped)):
        print('    %-46s %s' % (name[:46], why))

print()
if lag:
    print('EMITTER LAG: %d filter/service pair(s) watch for a string the running' % lag)
    print('artifact cannot produce. Those alerts CANNOT FIRE there, and a blind')
    print('alert is indistinguishable from a quiet one.')
    print()
    print('If this ran after a deploy: THE DEPLOY SUCCEEDED and traffic is live.')
    print('This failure is about alert coverage, not the release. Deploy the')
    print('service that is behind, or correct the filter.')
    sys.exit(1)
print('No emitter lag: every alert can produce every string it watches for.')
PY
