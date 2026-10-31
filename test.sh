#!/usr/bin/env bash
# Every Foamy Tray test. Safe to run anywhere: the runtime test is offscreen,
# in temporary HOME/XDG directories and its own private D-Bus session, so it
# never touches the desktop, its bar or its tray. Extra arguments go to
# tests/runtime.py (e.g. --host 4.5, --shots DIR).
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
node tests/tray-model.test.js
node tests/i18n.test.js
bash tests/kit-check.sh
python3 -I tests/runtime.py "$@"
