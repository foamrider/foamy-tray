#!/usr/bin/env bash
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
omarchy_dir=${OMARCHY_PATH:-/usr/share/omarchy}
export OMARCHY_PATH="$omarchy_dir"
probe_dir=$(mktemp -d)
trap 'rm -rf -- "$probe_dir"' EXIT
for module in Commons Ui; do ln -s "$omarchy_dir/shell/$module" "$probe_dir/$module"; done
ln -s "$omarchy_dir/shell/plugins/bar" "$probe_dir/hostbar"
ln -s "$plugin_dir" "$probe_dir/plugin"
cp "$plugin_dir/test-tray.qml" "$probe_dir/shell.qml"
printf 'Passive\n' > "$probe_dir/status"
export FOAMY_TRAY_TEST_STATUS="$probe_dir/status"
# Prevent the stock bar's startup glass synchronization from touching the host.
printf 'omarchy-bar() { :; }\n' > "$probe_dir/commands.sh"
export BASH_ENV="$probe_dir/commands.sh"
cat > "$probe_dir/bus.conf" <<'BUS'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen><policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>
BUS
# Only this bus sees the synthetic application icon, never the desktop's tray.
cat > "$probe_dir/run.sh" <<'RUN'
#!/usr/bin/env bash
set -euo pipefail
python "$1/test-status-notifier.py" "$FOAMY_TRAY_TEST_STATUS" &
fixture_pid=$!
# The fixture is intentionally long-lived; reap it when Quickshell finishes.
trap 'kill "$fixture_pid"; wait "$fixture_pid" 2>/dev/null || true' EXIT
timeout 35s quickshell -p "$2" --no-color
RUN
dbus-run-session --config-file="$probe_dir/bus.conf" -- bash "$probe_dir/run.sh" "$plugin_dir" "$probe_dir" 2>&1 | tee "$probe_dir/result.log"
rg -q 'RESULT: [0-9]+ tray integration checks passed' "$probe_dir/result.log"
if rg 'FAIL:|TypeError:|ReferenceError:|Binding loop|Unable to assign|Error: Failed to load' "$probe_dir/result.log"; then exit 1; fi
