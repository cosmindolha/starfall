#!/usr/bin/env bash
set -euo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if systemctl --user is-active --quiet starfall-game.service; then
    echo 'Starfall is already running.'
    exit 0
fi
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    for display in "$XDG_RUNTIME_DIR"/wayland-*; do
        [[ -S "$display" ]] && export WAYLAND_DISPLAY="$(basename "$display")" && break
    done
fi
[[ -n "${WAYLAND_DISPLAY:-}" ]] || { echo 'No active Wayland desktop found' >&2; exit 1; }
share_dir="$HOME/.local/share/starfall"
exec systemd-run --user --collect --unit=starfall-game --property=Type=exec \
    --property=OnFailure=starfall-controls-restore.service \
    --property=KillMode=control-group --property="ExecStopPost=$share_dir/uconsole-guard.sh restore" \
    --setenv="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" --setenv="WAYLAND_DISPLAY=$WAYLAND_DISPLAY" \
    --setenv="DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}" \
    "$share_dir/uconsole-guard.sh" run "$@"
