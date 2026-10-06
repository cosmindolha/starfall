#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Optional machine-local path; .starfall-love is ignored by Git.
if [[ -z "${STARFALL_LOVE:-}" && -f .starfall-love ]]; then
    IFS= read -r STARFALL_LOVE < .starfall-love
fi
if [[ -n "${STARFALL_LOVE:-}" ]]; then
    [[ -x "$STARFALL_LOVE" ]] || { echo 'STARFALL_LOVE must point to the LÖVE executable.' >&2; exit 1; }
    exec "$STARFALL_LOVE" . "$@"
elif command -v love >/dev/null 2>&1; then
    exec love . "$@"
elif [[ -x /Applications/love.app/Contents/MacOS/love ]]; then
    exec /Applications/love.app/Contents/MacOS/love . "$@"
elif [[ -x "$HOME/Applications/love.app/Contents/MacOS/love" ]]; then
    exec "$HOME/Applications/love.app/Contents/MacOS/love" . "$@"
else
    echo 'LÖVE 11.5 is missing. Install the official macOS build from love2d.org.' >&2
    exit 1
fi
