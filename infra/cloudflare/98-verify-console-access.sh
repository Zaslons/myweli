#!/usr/bin/env bash
#
# Is the admin console still behind Cloudflare Access, at every address it is
# served from?
#
# Exit 0 = every address answered an anonymous GET with a redirect to the Access
#          sign-in for that very hostname.
# Exit 1 = at least one did not, or could not be read. Each one is named.
#
# Design: docs/design/infra-console-access-check.md
# Run daily by the `access` job of .github/workflows/production-checks.yml.
#
# ## Why this exists
#
# Access lives only in the Cloudflare dashboard: the application « Myweli
# Admin », policy « Admins ». No file in this repository describes it, so
# nothing noticed that until 2026-11-13 it covered admin.myweli.com alone while
# myweli-admin.pages.dev served the whole console (main.dart.js, 200, 5.17 MB)
# to anyone. Fixed by hand that day. This is what notices the next time.
#
# ## Green, exactly
#
# For each URL, ONE request, redirects NOT followed. Green only if:
#   - the status is 301, 302, 303, 307 or 308, AND
#   - the Location is https://<team host>/cdn-cgi/access/login/<requested host>,
#     its query ignored (kid, meta and redirect_url change on every request).
# Anything else is red, and says what it shows:
#   - a 2xx: the console is public there. The fix names the hostname to add
#     back, and for the probe that is the WILDCARD, never the probe's own name;
#   - a redirect elsewhere, or to the sign-in of ANOTHER hostname: Access did
#     not answer for this one;
#   - a 404 on the probe: Pages does not know the made-up alias, so Access no
#     longer answers before it: the wildcard is gone;
#   - any other status (a 403, a 5xx, a 404 elsewhere): neither the sign-in nor
#     the console. Red, but nothing shown public, so no fix to apply blind: a
#     look by hand, and a 403 Cloudflare marks cf-mitigated is named as a
#     challenge of the machine running the check.
# No answer at all (curl's 000) is red too: a check that measured nothing is
# not green. Every URL is read before the exit, so one red line never hides a
# second.
#
# ## The rehearsal seam
#
# CONSOLE_ACCESS_URLS (separated by spaces or newlines) and
# CONSOLE_ACCESS_TEAM_HOST replace the list and the team host, so that
# backend/test/infra/console_access_check_test.dart can run this very script
# against a local server, both ways. The daily job sets neither, and that test
# fails if any workflow does.
#
# Read-only and anonymous: a plain GET, nothing added to it. A request that
# carried a sign-in would pass through Access and hide the very thing asked.
set -uo pipefail

# The Zero Trust team domain every read named on 2026-11-13.
TEAM_HOST_DEFAULT=blue-base-1ad1.cloudflareaccess.com

# Three hostnames, each at / (the page) and /main.dart.js (the code, the exact
# request that answered 200 on 2026-11-13). The wildcard *.myweli-admin.pages.dev
# is read through a made-up preview label: preview hashes change with every
# deploy, and Access answers before Pages does. Spec §3.
URLS_DEFAULT='
https://admin.myweli.com/
https://admin.myweli.com/main.dart.js
https://myweli-admin.pages.dev/
https://myweli-admin.pages.dev/main.dart.js
https://zz-access-probe.myweli-admin.pages.dev/
https://zz-access-probe.myweli-admin.pages.dev/main.dart.js
'

# The made-up label above. It stands for every preview address, so its fix
# names the wildcard: the probe's own name in Access would turn this check
# green with every real preview still public.
PROBE_LABEL=zz-access-probe

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

if [ -n "${CONSOLE_ACCESS_URLS+set}" ]; then
  echo "REHEARSAL: the URL list comes from CONSOLE_ACCESS_URLS, not the production list."
fi
if [ -n "${CONSOLE_ACCESS_TEAM_HOST+set}" ]; then
  echo "REHEARSAL: the team host comes from CONSOLE_ACCESS_TEAM_HOST."
fi
# `-` and not `:-`: a list set but empty is refused below, never swapped for
# the defaults behind the caller's back.
URLS="${CONSOLE_ACCESS_URLS-$URLS_DEFAULT}"
TEAM_HOST=$(lower "${CONSOLE_ACCESS_TEAM_HOST-$TEAM_HOST_DEFAULT}")

set -f # a URL is a word, never a glob
# shellcheck disable=SC2206
urls=($(printf '%s' "$URLS" | tr '\n' ' '))
set +f

if [ "${#urls[@]}" -eq 0 ] || [ -z "$TEAM_HOST" ]; then
  echo "::error::no URL or no team host to check — refusing to report success"
  exit 1
fi

errfile=$(mktemp)
trap 'rm -f "$errfile"' EXIT

echo "Cloudflare Access in front of the admin console (team ${TEAM_HOST})"
echo

fails=0
red() { echo "::error::$*"; }

# The fix for $host, as Access names it: for the probe, the wildcard.
say_fix() {
  red "Fix: add ${access_host} back to the Access application « Myweli Admin » in the Cloudflare dashboard (Zero Trust → Access → Applications; the policy « Admins » stays as it is) — docs/DEPLOYMENT.md « Restrict »."
  if [ -n "$probe_parent" ]; then
    red "${host} is made up: it stands for every preview address (<hash>.${probe_parent}), and every preview address is public without ${access_host}. Do not put the probe's own name, ${host}, in the application: that would turn this check green with every preview still public."
  fi
}

for url in "${urls[@]}"; do
  case "$url" in
    http://*|https://*) ;;
    *)
      echo "  ✗ ${url}"
      red "${url} is not an http(s) URL — nothing measured"
      fails=$((fails + 1))
      continue
      ;;
  esac

  # The hostname as Access names it: no userinfo, no port, lower case.
  rest=${url#*://}
  host=${rest%%[/?#]*}
  host=${host##*@}
  host=$(lower "${host%%:*}")
  expected="https://${TEAM_HOST}/cdn-cgi/access/login/${host}"
  probe_parent=''
  access_host=$host
  case "$host" in
    "$PROBE_LABEL".*)
      probe_parent=${host#"$PROBE_LABEL".}
      access_host="*.${probe_parent}"
      ;;
  esac

  # --retry covers timeouts, a failed DNS lookup and 408, 429, 500, 502, 503,
  # 504; a refused connection is not retried. -w is written once, for the last
  # attempt. No -L: the redirect itself is what is being read. One field per
  # line: a header value never holds a newline, so none can bleed into another.
  # %header{} needs curl 7.84 (ubuntu-latest has 8.5).
  meta=$(curl -sS -o /dev/null --max-time 20 --retry 2 --retry-delay 5 \
           -w '%{http_code}\n%{redirect_url}\n%header{cf-mitigated}' \
           "$url" 2>"$errfile")
  code='' location='' mitigated=''
  { IFS= read -r code; IFS= read -r location; IFS= read -r mitigated; } <<<"$meta"
  case "$code" in ''|*[!0-9]*) code=000 ;; esac
  # Printed without its query: Access puts kid and meta there.
  shown=${location%%\?*}

  case "$code" in
    000)
      err=$(tr '\n' ' ' <"$errfile")
      echo "  ✗ ${url} → no answer"
      red "could not reach ${url} — nothing measured (${err% }). Re-run the job: a check that measured nothing is not green."
      fails=$((fails + 1))
      ;;
    2??)
      echo "  ✗ ${url} → ${code}"
      red "the console is PUBLIC at ${url}: it answered ${code} to an anonymous request, without the Access sign-in."
      say_fix
      fails=$((fails + 1))
      ;;
    301|302|303|307|308)
      loc_rest=${location#https://}
      loc_host=${loc_rest%%[/?#]*}
      loc_path=${loc_rest#"$loc_host"}
      loc_path=${loc_path%%[?#]*}
      loc_host=$(lower "$loc_host")
      loc_path=$(lower "$loc_path")
      if [ -z "$location" ]; then
        echo "  ✗ ${url} → ${code}, no Location"
        red "${url} answered ${code} with no Location, not a redirect to the Access sign-in for ${host} (${expected})."
        say_fix
        fails=$((fails + 1))
      elif [ "$loc_rest" != "$location" ] && [ "$loc_host" = "$TEAM_HOST" ] \
           && [ "$loc_path" = "/cdn-cgi/access/login/${host}" ]; then
        echo "  ✓ ${url} → ${code}, the Access sign-in for ${host}"
      else
        echo "  ✗ ${url} → ${code} to ${shown}"
        red "${url} answered ${code} to ${shown}, not to the Access sign-in for ${host} (${expected})."
        if [ "$loc_rest" != "$location" ] && [ "$loc_path" = "/cdn-cgi/access/login/${host}" ] \
           && [ "${loc_host%.cloudflareaccess.com}" != "$loc_host" ]; then
          # Another team's sign-in for the right hostname: Access does answer,
          # under a different team domain. Nothing is public; the default is old.
          red "Only the team domain differs: if it was renamed in Zero Trust, put the new one in TEAM_HOST_DEFAULT in infra/cloudflare/98-verify-console-access.sh, in a PR."
        else
          say_fix
        fi
        fails=$((fails + 1))
      fi
      ;;
    *)
      echo "  ✗ ${url} → ${code}"
      if [ -n "$probe_parent" ] && [ "$code" = 404 ]; then
        # What Pages answers an alias it does not know: Access no longer
        # answers first.
        red "${url} answered 404: Pages does not know this made-up address, so Access no longer answers before Pages there — the wildcard ${access_host} is gone, and every preview address is public."
        say_fix
      else
        red "${url} answered ${code}: neither the Access sign-in nor the console. Red, but it does not show the console is public: do not edit Access on this line alone."
        if [ -n "$mitigated" ]; then
          red "Cloudflare marked that answer « cf-mitigated: ${mitigated} »: it challenged the machine running this check (on the daily job, GitHub's runner), not the console's visitors. Re-run the job; if it stays, a Cloudflare security setting is challenging GitHub's network — docs/design/infra-console-access-check.md §8."
        fi
        red "Look by hand first: open ${url} in a private window, and read « Myweli Admin » in Zero Trust → Access → Applications. Only if ${access_host} is missing from it, add it back — docs/DEPLOYMENT.md « Restrict »."
      fi
      fails=$((fails + 1))
      ;;
  esac
done

echo
if [ "$fails" -gt 0 ]; then
  red "${fails} of ${#urls[@]} console addresses did not send an anonymous visitor to the Access sign-in, or could not be read — each is named above."
  exit 1
fi
echo "All ${#urls[@]} console addresses send an anonymous visitor to the Access sign-in."
