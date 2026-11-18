#!/usr/bin/env bash
#
# Does the certificate chain Cloudflare serves for the app's hosts still end in
# a root the Android app trusts?
#
# Exit 0 = for every host, the chain served verifies against EXACTLY the roots
#          bundled in the Android app, and nothing else.
# Exit 1 = at least one did not, or could not be read. Each one is named.
#
# Design: docs/design/android-http3-transport.md §5.2
# Run daily by the `appchain` job of .github/workflows/production-checks.yml.
#
# ## Why this exists
#
# The Android app trusts only a list of roots for myweli.com and its
# subdomains (mobile/android/app/src/main/res/xml/network_security_config.xml),
# not the phone's own store: that closes the eMudhra path on Android 7 to 9.
# The other side: Cloudflare picks the CA of our Universal SSL certificate and
# can change it without notice. If it moves to a CA outside the list, every
# Android user fails to connect, with the whole test suite green. This is what
# notices.
#
# It cannot see Cloudflare's BACKUP certificate before Cloudflare deploys one:
# that certificate is not served until then. That is why the list holds every
# CA a backup can come from (spec §5.2, Q8).
#
# ## Green, exactly
#
# For each host: the chain it serves, read with `openssl s_client`, verified
# with `openssl verify` against the bundled files ONLY (no system store, no
# default paths). Green only if that says OK. Red if it does not, and red when
# the chain cannot be read at all: a check that measured nothing is not green.
# Every host is read before the exit, so one red line never hides a second.
#
# ## The rehearsal seam
#
# APP_CHAIN_HOSTS (host or host:port, separated by spaces or newlines) and
# APP_CHAIN_ANCHORS_DIR replace the hosts and the bundled roots, so that
# backend/test/infra/app_trust_chain_check_test.dart can run this very script
# against a local TLS server, both ways. The daily job sets neither, and that
# test fails if any workflow does.
#
# Read-only and anonymous: a TLS handshake, then nothing.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)

# The hosts the Android app reaches on our zone: the API and the photos.
HOSTS_DEFAULT='api.myweli.com cdn.myweli.com'
ANCHORS_DEFAULT="$repo/mobile/android/app/src/main/res/raw"

hosts=${APP_CHAIN_HOSTS-$HOSTS_DEFAULT}
anchors=${APP_CHAIN_ANCHORS_DIR-$ANCHORS_DEFAULT}

fix='Android users cannot connect until Cloudflare is back on a listed CA, or until a build that trusts the new root ships: add it to mobile/android/app/src/main/res/raw/ and network_security_config.xml (android_http_transport_guard_test.dart holds both). docs/design/android-http3-transport.md §5.2.'

# A variable set but empty is a broken rehearsal, never « check nothing ».
read -r -a targets <<<"$(printf '%s' "$hosts" | tr '\n' ' ')"
if [ ${#targets[@]} -eq 0 ]; then
  echo "::error::no host to check — nothing measured."
  exit 1
fi
shopt -s nullglob
roots=("$anchors"/*.pem)
if [ ${#roots[@]} -eq 0 ]; then
  echo "::error::no bundled root in ${anchors:-<empty>} — nothing to verify against."
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat "${roots[@]}" >"$work/anchors.pem"
echo "against ${#roots[@]} bundled roots from ${anchors#"$repo"/}"

# `timeout` where there is one (the runner); the Mac running the test has none.
with_timeout() {
  if command -v timeout >/dev/null 2>&1; then timeout 30 "$@"; else "$@"; fi
}

is_ip() { [[ $1 =~ ^[0-9.]+$ || $1 == *:* ]]; }

red=0
for target in "${targets[@]}"; do
  host=${target%:*}
  port=${target##*:}
  [ "$host" = "$target" ] && port=443
  out="$work/$host.$port"

  sni=()
  is_ip "$host" || sni=(-servername "$host")
  # `${a[@]+"${a[@]}"}`: an empty array is « unbound » to bash 3.2 under set -u.
  with_timeout openssl s_client -connect "$host:$port" ${sni[@]+"${sni[@]}"} \
    -showcerts </dev/null >"$out.txt" 2>/dev/null
  # Each certificate the server sent, in order: the leaf first.
  awk -v dir="$out" '
    /-----BEGIN CERTIFICATE-----/ { n++; f = dir ".c" n ".pem" }
    f { print > f }
    /-----END CERTIFICATE-----/ { close(f); f = "" }
  ' "$out.txt"
  certs=("$out".c*.pem)
  if [ ${#certs[@]} -eq 0 ]; then
    echo "::error::${target}: could not read the chain it serves — nothing measured; re-run the job."
    red=1
    continue
  fi

  leaf="$out.c1.pem"
  : >"$out.rest.pem"
  for ((i = 2; i <= ${#certs[@]}; i++)); do cat "$out.c$i.pem" >>"$out.rest.pem"; done
  untrusted=()
  [ -s "$out.rest.pem" ] && untrusted=(-untrusted "$out.rest.pem")

  served=$(openssl x509 -in "$leaf" -noout -issuer 2>/dev/null | sed 's/^issuer=//')
  if verdict=$(openssl verify -no-CApath -no-CAstore -CAfile "$work/anchors.pem" \
    ${untrusted[@]+"${untrusted[@]}"} -show_chain "$leaf" 2>&1); then
    root=$(printf '%s\n' "$verdict" | grep '^depth=' | tail -n 1 | sed 's/^depth=[0-9]*: //')
    echo "${target}: OK — issued by ${served}, ends in ${root}"
  else
    echo "::error::${target}: the chain it serves (issued by ${served}) ends in NO root the Android app trusts for myweli.com."
    echo "::error::$(printf '%s\n' "$verdict" | grep -m1 -E 'error|unable' || echo 'openssl verify failed')"
    echo "::error::${fix}"
    red=1
  fi
done

exit "$red"
