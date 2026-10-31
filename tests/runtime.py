#!/usr/bin/env python3
"""Offscreen integration test of Foamy Tray in the host's real bar, on both
hosts: 4.0.6 (installed) and 4.5 (reference shell, QML only).

  tests/runtime.py [--host 4.0|4.5|both] [--shots DIR] [--theme dark|light] [--plugin DIR] [--shell QML]

Uses the foamy-kit harness (FOAMY_KIT, default ~/GitHub/Personal/foamy-kit):
temp HOME/XDG/runtime dirs, offscreen Qt, no Wayland/Hyprland variables. The
host's plugins/bar/Bar.qml is loaded with its PanelWindow swapped for
tests/qml/FakeBarWindow.qml; everything else is the host's code. Bar helper
commands (omarchy-bar …) resolve to no-op stubs, no host script or binary is
run. Each run gets the harness's private D-Bus session (foamy-kit 0.2.0):
two synthetic apps (tests/status_notifier.py) provide tray items and
DBusMenus there, and the desktop's tray is never seen or touched.

FOAMY_TRAY_KEEP=1 keeps the run directory (log, events) after a pass.
--shots DIR writes composed 1920x1080 screens (wallpaper, bar, open menu
where the card's anchor puts it) and tight menu cards for the PR.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

PLUGIN = Path(__file__).resolve().parents[1]
KIT = Path(os.environ.get("FOAMY_KIT", Path.home() / "GitHub/Personal/foamy-kit"))
STUBS = ("omarchy-bar", "omarchy-bar-text-color", "omarchy-shell", "omarchy", "hyprctl")


def transform_bar(text):
    """Bar.qml with each `component X: PanelWindow {` built on FakeBarWindow.

    Only the window components' own top-level lines change: WlrLayershell
    lines go, `anchors {` becomes `windowAnchors {`, implicit sizes become
    requested sizes (a layer surface anchored to opposite edges spans them)."""
    out, window_indent, replaced = [], None, 0
    for line in text.splitlines():
        match = re.match(r"^(\s*)component (\w+): PanelWindow \{\s*$", line)
        if match:
            window_indent = len(match.group(1)) + 2
            replaced += 1
            out.append(f"{match.group(1)}component {match.group(2)}: FakeBarWindow {{")
            continue
        if window_indent is not None:
            if re.match(r"^\s{%d}\}\s*$" % (window_indent - 2), line):
                window_indent = None
            elif line.startswith(" " * window_indent) and not line.startswith(" " * (window_indent + 1)):
                stripped = line.strip()
                if stripped.startswith("WlrLayershell."):
                    continue
                if stripped == "anchors {":
                    line = line.replace("anchors {", "windowAnchors {")
                line = re.sub(r"^(\s*)implicitWidth:", r"\1requestedWidth:", line)
                line = re.sub(r"^(\s*)implicitHeight:", r"\1requestedHeight:", line)
        out.append(line)
    if replaced == 0:
        raise SystemExit("host Bar.qml changed shape: no PanelWindow component to replace")
    return "\n".join(out) + "\n"


def build_hostbar(host, dest):
    dest.mkdir()
    source = host / "plugins/bar"
    for path in sorted(source.iterdir()):
        if path.name != "Bar.qml":
            (dest / path.name).symlink_to(path, target_is_directory=path.is_dir())
    (dest / "Bar.qml").write_text(transform_bar((source / "Bar.qml").read_text()))
    for name in ("FakeBarWindow.qml", "FakeBarEdges.qml"):
        shutil.copyfile(PLUGIN / "tests/qml" / name, dest / name)


def compose(shots, line, theme):
    """FOAMY SHOT <name> <bar.png> <card.png|-> <x> <y> <barX> <barY>: a
    1920x1080 screen with the bar window and the card at its anchor rect."""
    from PIL import Image, ImageDraw
    name, bar_path, card_path, x, y, bar_x, bar_y = line.split()
    x, y, bar_x, bar_y = int(x), int(y), int(bar_x), int(bar_y)
    screen = Image.new("RGBA", (1920, 1080))
    top, bottom = ((214, 220, 228), (176, 186, 200)) if theme == "light" else ((24, 28, 38), (52, 58, 74))
    draw = ImageDraw.Draw(screen)
    for row in range(1080):
        t = row / 1079
        draw.line([(0, row), (1919, row)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    bar = Image.open(bar_path).convert("RGBA")
    screen.alpha_composite(bar, (max(0, bar_x), max(0, bar_y)))
    if card_path != "-":
        card = Image.open(card_path).convert("RGBA")
        screen.alpha_composite(card, (max(0, x), max(0, y)))
        shutil.copyfile(card_path, shots / f"{name}.png")
    screen.convert("RGB").save(shots / f"{name}-screen.png")
    return name


def run_host(host_name, shots, theme, plugin, shell_path=PLUGIN / "tests/qml/Runtime.qml"):
    sys.path.insert(0, str(KIT / "preview"))
    import harness
    shell = Path(shell_path).read_text()
    run = harness.Run(host_name, shell, plugin=plugin, theme=theme, prefix=f"foamy-tray-runtime-{host_name}-")
    build_hostbar(run.host, run.root / "hostbar")
    stubs = run.base / "stubs"
    stubs.mkdir()
    for name in STUBS:
        (stubs / name).write_text("#!/bin/sh\nexit 0\n")
        (stubs / name).chmod(0o755)
    status = run.base / "status"
    events = run.base / "events"
    status.write_text("Passive\n")
    events.write_text("")
    raw = run.base / "raw-shots"
    raw.mkdir()
    run.env.update({
        "PATH": f"{stubs}:{os.environ.get('PATH', '/usr/bin')}",
        "FOAMY_TRAY_STATUS": str(status),
        "FOAMY_TRAY_EVENTS": str(events),
        "FOAMY_TRAY_THEME": theme,
    })
    if shots:
        run.env["FOAMY_TRAY_SHOTS"] = str(raw)
    # start() brings up the harness's private bus (and qs on it); the fixture
    # joins that bus and registers its items once qs's watcher is up.
    fixture = None
    run.start()
    try:
        bus = run.env["DBUS_SESSION_BUS_ADDRESS"]
        if not bus.startswith(f"unix:path={run.base}/bus"):
            raise SystemExit("foamy-kit harness did not start a private D-Bus session")
        fixture = subprocess.Popen([sys.executable, "-I", str(PLUGIN / "tests/status_notifier.py"), str(status), str(events)],
                                   env=dict(run.env, FOAMY_TRAY_PRIVATE_BUS=bus), start_new_session=True)
        run.wait(timeout=120)
    finally:
        run.stop()
        if fixture is not None:
            os.killpg(fixture.pid, signal.SIGTERM)
            fixture.wait(timeout=5)
    run.ok = "FOAMY DONE" in run.log and "FOAMY FAIL" not in run.log \
        and not any(marker in run.log for marker in harness.FAILURE_MARKERS)
    result = next((line.split("FOAMY RESULT ", 1)[1] for line in run.log.splitlines() if "FOAMY RESULT" in line), "no result")
    ok = run.ok
    print(f"{'PASS' if ok else 'FAIL'} runtime {host_name} ({theme}): {result}")
    if not ok:
        print("\n".join("    " + line for line in (run.failures() or run.log.splitlines()[-40:])))
        print(f"    log kept at {run.base}")
        return False
    if shots:
        out = Path(shots) / host_name
        out.mkdir(parents=True, exist_ok=True)
        time.sleep(0.2)
        for line in run.log.splitlines():
            if "FOAMY SHOT " in line:
                name = compose(out, line.split("FOAMY SHOT ", 1)[1], theme)
                print(f"    shot {out}/{name}-screen.png")
    if os.environ.get("FOAMY_TRAY_KEEP") == "1":
        print(f"    log kept at {run.base}")
    else:
        run.cleanup()
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="both", choices=["4.0", "4.5", "both"])
    parser.add_argument("--shots")
    parser.add_argument("--theme", default="dark", choices=["dark", "light"])
    parser.add_argument("--plugin", default=str(PLUGIN), help="plugin directory to load (default: this checkout)")
    parser.add_argument("--shell", default=str(PLUGIN / "tests/qml/Runtime.qml"),
                        help="test QML to run (default tests/qml/Runtime.qml), e.g. a capture script for an older checkout")
    args = parser.parse_args()
    if not (KIT / "preview/harness.py").exists():
        print(f"SKIP: foamy-kit harness not found at {KIT} (set FOAMY_KIT)")
        return 0
    hosts = ["4.0", "4.5"] if args.host == "both" else [args.host]
    results = [run_host(host, args.shots, args.theme, Path(args.plugin).resolve(), args.shell) for host in hosts]
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
