#!/usr/bin/env bash
#
# Print the roadmap log, newest first.
#
#   ./tool/roadmap-log.sh          everything since the entries directory began
#   ./tool/roadmap-log.sh 2026-08  only files whose name starts with that
#
# Entries live one-per-file in docs/roadmap/entries/ so that two branches can
# never conflict over the same line — see that directory's README for why.
# Anything older than 2026-08-24 is in docs/ROADMAP.md §1.8.
set -euo pipefail

DIR="$(dirname "${BASH_SOURCE[0]}")/../docs/roadmap/entries"
FILTER="${1:-}"

shopt -s nullglob
files=("$DIR"/[0-9]*"${FILTER}"*.md)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No entries${FILTER:+ matching \"$FILTER\"} in ${DIR}." >&2
  exit 1
fi

# Reverse lexicographic on an ISO date prefix IS newest-first, which is why the
# names start with one.
printf '%s\n' "${files[@]}" | sort -r | while read -r f; do
  cat "$f"
  echo
done
