#!/usr/bin/env bash
set -euo pipefail
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
state_file="$runtime_dir/starfall-ai-controls.state"

restore_controls() {
    if [[ -f "$state_file" ]]; then
        while IFS= read -r unit; do
            [[ -n "$unit" ]] && systemctl --user start "$unit"
        done < "$state_file"
        rm -f "$state_file"
        echo 'STARFALL restored prior AI gamepad handlers'
    fi
}

if [[ "${1:-}" == restore ]]; then
    exec 9>"$runtime_dir/starfall-controls.lock"
    flock 9
    restore_controls
    exit
fi
[[ "${1:-}" == run ]] || { echo 'Expected run or restore' >&2; exit 2; }
shift
exec 9>"$runtime_dir/starfall-controls.lock"
flock -n 9 || { echo 'Starfall is already running' >&2; exit 3; }
# Recover an interrupted older run before recording the new session's state.
restore_controls
: > "$state_file"
for unit in uconsole-dictation-button.service uconsole-approval-button.service; do
    if systemctl --user is-active --quiet "$unit"; then
        printf '%s\n' "$unit" >> "$state_file"
    fi
done
trap restore_controls EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
while IFS= read -r unit; do
    [[ -n "$unit" ]] && systemctl --user stop "$unit"
done < "$state_file"
echo 'STARFALL suspended active AI gamepad handlers'
love "$HOME/.local/share/starfall/starfall.love" --fullscreen "$@"
