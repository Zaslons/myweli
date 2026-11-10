#!/usr/bin/env bash
# Read the Dart SDK compiled into a backend image, and refuse it below the TLS
# floor. Read-only. It downloads one layer, writes nothing to disk, and changes
# nothing in the registry.
#
#   verify-image-dart-sdk.sh europe-west9-docker.pkg.dev/myweli/myweli/api@sha256:<digest>
#
# Exit 0 = the binary says `Dart X.Y.Z (stable)` with X.Y.Z >= FLOOR.
# Exit 1 = below the floor, not stable, unreadable, or not a digest reference.
# Every failure is closed: a check that cannot read the version does not pass.
#
# ## Why the bytes and not the Dockerfile
#
# dart_frog's `dart:io` verifies every outbound TLS chain with the BoringSSL
# compiled into /app/bin/server. Dart < 3.13.7 trusts eight compromised eMudhra
# intermediates (GHSA-frr6-h895-5pxp). backend/test/infra/dart_sdk_pin_test.dart
# checks what backend/Dockerfile SAYS, `dart:X.Y.Z@sha256:…`. But Docker builds
# what the DIGEST is, and the tag beside a digest is decoration: a 3.13.6 digest
# under a 3.13.7 tag passes that test. Only the built binary can say which
# SDK it carries. A promotion (`image_tag`) never builds at all, so it is also
# the one path where an old tag below the floor could reach production.
#
# ## How
#
# The image's LAST layer is the Dockerfile's last COPY, /app/bin/server. The
# manifest names it, and the blob is streamed through `tar -xzO` into grep.
# The Dart VM embeds `Dart <version> (<channel>) (<date>) on "<os_arch>"`.
#
# Design: docs/design/backend-dart-sdk-pin.md §8.
set -euo pipefail

# The lowest SDK that blocks the eMudhra intermediates. Raise it when a newer
# advisory lands; dart_sdk_pin_test fails if it ever goes below 3.13.7, and
# fails if backend/Dockerfile pins anything under it.
FLOOR="3.13.7"

REF="${1:-}"
if [[ ! "${REF}" =~ ^([^/]+)/(.+)@(sha256:[0-9a-f]{64})$ ]]; then
  echo "::error::expected <host>/<path>@sha256:<digest>, got '${REF}'"
  exit 1
fi
HOST="${BASH_REMATCH[1]}"
REPO="${BASH_REMATCH[2]}"
DIGEST="${BASH_REMATCH[3]}"

TOKEN="$(gcloud auth print-access-token)"
ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json'

manifest() {
  curl -fsS -H "Authorization: Bearer ${TOKEN}" -H "Accept: ${ACCEPT}" \
    "https://${HOST}/v2/${REPO}/manifests/$1"
}
if ! MANIFEST="$(manifest "${DIGEST}")"; then
  echo "::error::could not read the manifest of ${REF}"
  exit 1
fi
# An image built on ubuntu-26.04's Docker is an OCI INDEX — the linux/amd64
# image plus an attestation manifest — where the 24.04 builds were a plain
# image manifest (measured 2026-11-10: 45a5d0f vs 4e78e48). Cloud Run runs the
# linux/amd64 entry, so that is the one read here.
if ! PLATFORM="$(python3 -I -c '
import json, sys
d = json.load(sys.stdin)
if "layers" in d:
    print("")
else:
    m = [m["digest"] for m in d.get("manifests", [])
         if m.get("platform", {}).get("os") == "linux"
         and m.get("platform", {}).get("architecture") == "amd64"]
    if len(m) != 1:
        sys.exit("expected one linux/amd64 manifest in the index, found %d" % len(m))
    print(m[0])
' <<< "${MANIFEST}")"; then
  echo "::error::${REF} is an index without exactly one linux/amd64 image"
  exit 1
fi
if [ -n "${PLATFORM}" ]; then
  echo "  index → linux/amd64 ${PLATFORM}"
  if ! MANIFEST="$(manifest "${PLATFORM}")"; then
    echo "::error::could not read the linux/amd64 manifest ${PLATFORM} of ${REF}"
    exit 1
  fi
fi
if ! LAYER="$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["layers"][-1]["digest"])' \
                <<< "${MANIFEST}")"; then
  echo "::error::the image manifest of ${REF} has no layers"
  exit 1
fi

# The whole stream is read (no `grep -m1`, no `head`): closing the pipe early
# would SIGPIPE curl, and pipefail would turn a good read into a failure.
if ! FOUND="$(curl -fsSL -H "Authorization: Bearer ${TOKEN}" "https://${HOST}/v2/${REPO}/blobs/${LAYER}" \
                | tar -xzO -f - app/bin/server \
                | LC_ALL=C grep -a -o -E 'Dart [0-9]+\.[0-9]+\.[0-9]+[^ ]* \([a-z]+\) \([^)]*\) on "[a-z_0-9]+"' \
                | sort -u)"; then
  echo "::error::could not read a Dart version from app/bin/server in the last layer of ${REF}"
  echo "  (is the server binary still the Dockerfile's last COPY?)"
  exit 1
fi
if [ "$(printf '%s\n' "${FOUND}" | grep -c .)" -ne 1 ]; then
  echo "::error::expected exactly one Dart version string in app/bin/server, found:"
  printf '  %s\n' "${FOUND}"
  exit 1
fi
echo "  ${REF##*/}"
echo "  → ${FOUND}"

if [[ ! "${FOUND}" =~ ^Dart\ ([0-9]+)\.([0-9]+)\.([0-9]+)\ \(stable\)\  ]]; then
  echo "::error::not a stable SDK: ${FOUND}. Production builds from a stable X.Y.Z (backend/Dockerfile)."
  exit 1
fi
HAVE=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
IFS=. read -r -a WANT <<< "${FLOOR}"
for i in 0 1 2; do
  if (( HAVE[i] > WANT[i] )); then break; fi
  if (( HAVE[i] < WANT[i] )); then
    echo "::error::Dart ${HAVE[0]}.${HAVE[1]}.${HAVE[2]} is below the TLS floor ${FLOOR} (GHSA-frr6-h895-5pxp): its verifier trusts the compromised eMudhra intermediates. Do not deploy this image."
    exit 1
  fi
done
echo "  ✓ Dart ${HAVE[0]}.${HAVE[1]}.${HAVE[2]} ≥ ${FLOOR}"
