#!/usr/bin/env bash
# The ONE command of the MyWeli Pro promo reel (tool/promo_reel/README.md):
#
#   tool/promo_reel/build.sh                    build every cut × format, then verify them
#   tool/promo_reel/build.sh --set k=v …        the same, on a variant of the storyboard
#   tool/promo_reel/build.sh test               run the unit tests instead
#
# 1. Python 3.12 (/usr/local/bin/python3.12, else python3.12 on the PATH, or
#    PROMO_PYTHON) and a private venv, tool/promo_reel/.venv, with exactly the
#    pinned requirements.txt — rebuilt whenever requirements.txt changes.
# 2. ffmpeg and ffprobe (Homebrew); the command stops and says how to install
#    them when they are missing.
# 3. python -m promo build --all, then python -m promo verify --all: every
#    cut × format the storyboard lays out (today 30s/9x16) is rendered to
#    out/<cut>-<format>/reel.mp4 and verified (out/<cut>-<format>/verify/);
#    the others are named « NOT BUILT » with the reason. A failed check exits 1;
#    a film whose only open item is the owner's (the end card's reading speed)
#    exits 3, OWNER DECISION PENDING — never 0.
#
# Nothing outside tool/promo_reel/ is written. The recorded takes are read
# from the main checkout's build/ folder (or PROMO_MATERIAL).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HERE/.venv"
REQUIREMENTS="$HERE/requirements.txt"
STAMP="$VENV/.requirements.sha256"

say() { printf 'build.sh: %s\n' "$*"; }
die() { printf 'build.sh: %s\n' "$*" >&2; exit 1; }

# ---- 1. Python 3.12 + the pinned venv ---------------------------------------
PYTHON="${PROMO_PYTHON:-/usr/local/bin/python3.12}"
if [ ! -x "$PYTHON" ]; then
  PYTHON="$(command -v python3.12 || true)"
fi
if [ -z "$PYTHON" ] || [ ! -x "$PYTHON" ]; then
  die "Python 3.12 not found (looked at /usr/local/bin/python3.12 and the PATH). Install it from
  https://www.python.org/downloads/ or with 'brew install python@3.12', or set PROMO_PYTHON."
fi
"$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 12) else 1)' \
  || die "$PYTHON is not Python 3.12 ($("$PYTHON" --version 2>&1))"

WANT="$(shasum -a 256 "$REQUIREMENTS" | cut -d' ' -f1)"
HAVE="$(cat "$STAMP" 2>/dev/null || true)"
if [ ! -x "$VENV/bin/python" ] || [ "$HAVE" != "$WANT" ]; then
  say "creating $VENV (Python 3.12, pinned requirements.txt)"
  rm -rf "$VENV"
  "$PYTHON" -m venv "$VENV"
  "$VENV/bin/python" -m pip install --quiet --disable-pip-version-check --no-input -r "$REQUIREMENTS"
  printf '%s\n' "$WANT" > "$STAMP"
fi

# ---- 2. ffmpeg / ffprobe ------------------------------------------------------
find_tool() {  # $1 = name, $2 = override variable
  local override="${!2:-}"
  if [ -n "$override" ]; then
    [ -x "$override" ] && { printf '%s\n' "$override"; return 0; }
    return 1
  fi
  local found
  found="$(command -v "$1" || true)"
  [ -n "$found" ] && { printf '%s\n' "$found"; return 0; }
  for dir in /opt/homebrew/bin /usr/local/bin; do
    [ -x "$dir/$1" ] && { printf '%s\n' "$dir/$1"; return 0; }
  done
  return 1
}
FFMPEG="$(find_tool ffmpeg PROMO_FFMPEG || true)"
FFPROBE="$(find_tool ffprobe PROMO_FFPROBE || true)"
if [ -z "$FFMPEG" ] || [ -z "$FFPROBE" ]; then
  die "ffmpeg and ffprobe are needed (found: ffmpeg='${FFMPEG:-none}', ffprobe='${FFPROBE:-none}').
  Install them with Homebrew (https://brew.sh):   brew install ffmpeg
  or point PROMO_FFMPEG and PROMO_FFPROBE at the binaries."
fi
export PROMO_FFMPEG="$FFMPEG" PROMO_FFPROBE="$FFPROBE"
say "python $("$VENV/bin/python" --version 2>&1 | cut -d' ' -f2) · $("$FFMPEG" -version | head -1 | cut -d' ' -f1-3)"

# ---- 3. build + verify (or the tests) ----------------------------------------------
cd "$HERE"
if [ "${1:-}" = "test" ]; then
  shift
  exec "$VENV/bin/python" -m unittest discover -s tests "$@"
fi
"$VENV/bin/python" -m promo build --all "$@"
"$VENV/bin/python" -m promo verify --all "$@"
