#!/bin/bash
# foamy-tray's own tests; tests/validate.sh runs this after the linters.
#   --ci    no Quickshell, no Omarchy host: the node tests only
#   --fast  skip the offscreen runtime test
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1
ci=0 fast=0
for arg in "$@"; do
  case $arg in
    --ci) ci=1 ;;
    --fast) fast=1 ;;
    *)
      echo "suite.sh: unknown argument $arg" >&2
      exit 2
      ;;
  esac
done
status=0
run() {
  echo "== $*"
  "$@" || status=1
}
skip() { echo "SKIP $*"; }
run node tests/tray-model.test.js
run node tests/i18n.test.js
if ((ci || fast)); then
  skip "tests/runtime.py: offscreen Quickshell with the host bar"
else
  run python3 -I tests/runtime.py
  run python3 -I tests/runtime.py --theme light
fi
exit $status
