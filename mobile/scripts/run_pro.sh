#!/bin/bash
# Run MyWeli Pro on a device, with the entry that device's app ships.
#
#   mobile/scripts/run_pro.sh <device-id> [entry] [flutter run arguments…]
#
# The Pro app has two entries (docs/design/pro-android-signup.md §5.6):
#   lib/main_pro_android.dart — Android, the one with the salon sign-up;
#   lib/main_pro.dart         — iOS (and anything else): sign-in only.
# A plain `flutter run --flavor pro` on Android compiles neither the right
# entry nor the sign-up, so without an entry this script asks
# `flutter devices --machine` for the device's platform and picks. An entry
# given as the second argument (lib/….dart) wins. Anything after is passed to
# `flutter run` (for example --dart-define=…).
set -euo pipefail

usage='usage: run_pro.sh <device-id> [lib/entry.dart] [flutter run arguments…]'
device="${1:?$usage}"
shift

entry=""
if [[ $# -gt 0 && "$1" == lib/*.dart ]]; then
  entry="$1"
  shift
fi

cd "$(dirname "$0")/.."

if [[ -z "$entry" ]]; then
  platform="$(flutter devices --machine | python3 -c '
import json, sys
text = sys.stdin.read()
devices = json.loads(text[text.find("["):] or "[]")
wanted = sys.argv[1]
for d in devices:
    if wanted in (d.get("id"), d.get("name")):
        print(d.get("targetPlatform", ""))
        break
' "$device")"
  case "$platform" in
    android*) entry=lib/main_pro_android.dart ;;
    "")
      echo "run_pro.sh: no device « $device » in \`flutter devices\`." >&2
      exit 2
      ;;
    *) entry=lib/main_pro.dart ;;
  esac
fi

echo "→ flutter run --flavor pro -t $entry -d $device $*"
exec flutter run --flavor pro -t "$entry" -d "$device" "$@"
