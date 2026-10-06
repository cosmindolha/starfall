#!/usr/bin/env bash
# Install Starfall without launching it or changing gamepad service enablement.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
prefix=''
love_app=''
cartridge=''
stage_dir=''

usage() {
    cat <<'HELP'
Usage: ./tools/install.sh [--prefix PATH] [--love-app PATH] [--cartridge PATH]

macOS: installs Starfall.app into ~/Applications. --prefix selects another
Applications directory. Downloads and verifies official LÖVE 11.5 unless
--love-app supplies an existing official love.app. No Homebrew, Python or
Xcode is required on macOS.

Omarchy / Arch Linux: installs the game, command and desktop menu entry below
your home directory. --prefix selects another home-like installation root.
Missing love/python packages are installed with sudo pacman -S --needed.
The normal home install uses guarded launching on Wayland with user systemd.

--cartridge selects an already built starfall.love. Otherwise an existing
dist/starfall.love is used, or the checked-out runtime source is packaged.
The installer never starts the game or plays audio.
HELP
}

fail() { printf 'Starfall install: %s\n' "$*" >&2; exit 1; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix|--love-app|--cartridge)
            [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a path."
            case "$1" in
                --prefix) prefix="$2" ;;
                --love-app) love_app="$2" ;;
                --cartridge) cartridge="$2" ;;
            esac
            shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown option: $1. Run with --help." ;;
    esac
done

platform="$(uname -s)"
case "$platform" in
    Darwin) prefix="${prefix:-$HOME/Applications}" ;;
    Linux)
        [[ -z "$love_app" ]] || fail '--love-app is a macOS option.'
        prefix="${prefix:-$HOME}"
        missing=()
        command -v love >/dev/null 2>&1 || missing+=(love)
        command -v python3 >/dev/null 2>&1 || missing+=(python)
        if [[ ${#missing[@]} -gt 0 ]]; then
            command -v pacman >/dev/null 2>&1 || fail 'Install LÖVE 11.5 and Python 3 first. Automatic dependencies require Arch Linux / Omarchy and pacman.'
            command -v sudo >/dev/null 2>&1 || fail 'Install the missing packages with pacman, or install sudo and rerun.'
            sudo pacman -S --needed "${missing[@]}"
        fi
        command -v love >/dev/null 2>&1 || fail 'LÖVE is still missing after dependency installation.'
        command -v python3 >/dev/null 2>&1 || fail 'Python 3 is still missing after dependency installation.' ;;
    *) fail "Unsupported platform: $platform. Use LÖVE 11.5 to open starfall.love directly." ;;
esac

[[ "$prefix" != *$'\n'* && "$prefix" != *$'\r'* && "$prefix" != *$'\t'* ]] || fail 'Installation paths cannot contain control characters.'
mkdir -p "$prefix"
prefix="$(cd "$prefix" && pwd -P)"

cleanup() {
    # Only remove the private staging directory returned by mktemp.
    if [[ -n "$stage_dir" && -d "$stage_dir" && ! -L "$stage_dir" ]]; then
        case "$(basename "$stage_dir")" in
            .starfall-install.*) find "$stage_dir" -depth -delete ;;
        esac
    fi
}
trap cleanup EXIT

owned_directory() {
    [[ ! -L "$1" && -f "$1/.starfall-installer" ]] &&
        [[ "$(cat "$1/.starfall-installer")" == starfall-installer-v1 ]]
}

replace_directory() {
    local candidate="$1" target="$2"
    if [[ -e "$target" ]]; then
        mv "$target" "$stage_dir/previous-install"
    fi
    if ! mv "$candidate" "$target"; then
        [[ ! -d "$stage_dir/previous-install" ]] || mv "$stage_dir/previous-install" "$target"
        fail "Could not install $target; the prior installation was restored."
    fi
}

prepare_cartridge() {
    if [[ -n "$cartridge" ]]; then
        [[ -f "$cartridge" ]] || fail "Cartridge not found: $cartridge"
    elif [[ -f "$project_dir/dist/starfall.love" ]]; then
        cartridge="$project_dir/dist/starfall.love"
    elif [[ "$platform" == Linux ]]; then
        python3 "$project_dir/tools/package_game.py"
        cartridge="$project_dir/dist/starfall.love"
    else
        local runtime="$stage_dir/runtime"
        [[ -f "$project_dir/main.lua" && -f "$project_dir/conf.lua" ]] || fail 'Runtime source is missing. Supply --cartridge /path/to/starfall.love.'
        [[ -z "$(find "$project_dir/game" "$project_dir/assets" -type l -print -quit)" ]] || fail 'Runtime source contains a symlink; use a verified cartridge instead.'
        mkdir -p "$runtime/game" "$runtime/assets"
        cp "$project_dir/main.lua" "$project_dir/conf.lua" "$runtime/"
        for notice in ASSETS.md LICENSE; do
            [[ ! -f "$project_dir/$notice" ]] || cp "$project_dir/$notice" "$runtime/"
        done
        cp "$project_dir/game/"*.lua "$runtime/game/"
        for asset_group in audio fonts images; do
            [[ -d "$project_dir/assets/$asset_group" ]] || fail "Missing runtime assets: assets/$asset_group"
            mkdir -p "$runtime/assets/$asset_group"
            case "$asset_group" in
                audio) find "$project_dir/assets/$asset_group" -maxdepth 1 -type f \( -name '*.wav' -o -name '*.ogg' \) -exec cp {} "$runtime/assets/$asset_group/" \; ;;
                fonts) find "$project_dir/assets/$asset_group" -maxdepth 1 -type f \( -name '*.ttf' -o -name '*-LICENSE.txt' \) -exec cp {} "$runtime/assets/$asset_group/" \; ;;
                images) find "$project_dir/assets/$asset_group" -maxdepth 1 -type f \( -name '*.png' -o -name '*.lua' \) -exec cp {} "$runtime/assets/$asset_group/" \; ;;
            esac
        done
        cartridge="$stage_dir/starfall.love"
        # Exclude Finder/resource-fork metadata from the portable cartridge.
        /usr/bin/ditto -c -k --norsrc --noextattr --noqtn "$runtime" "$cartridge"
    fi
    [[ -s "$cartridge" ]] || fail 'The cartridge is empty or packaging failed.'
}

if [[ "$platform" == Darwin ]]; then
    target="$prefix/Starfall.app"
    if [[ -e "$target" || -L "$target" ]]; then
        owned_directory "$target" || fail "Refusing to replace an unrelated application: $target"
    fi
    stage_dir="$(mktemp -d "$prefix/.starfall-install.XXXXXX")"
    prepare_cartridge
    if [[ -z "$love_app" ]]; then
        archive="$stage_dir/love-11.5-macos.zip"
        curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error \
            'https://github.com/love2d/love/releases/download/11.5/love-11.5-macos.zip' --output "$archive"
        checksum="$(shasum -a 256 "$archive")"
        [[ "${checksum%% *}" == 6795bb3a1656af6a2fdfe741e150787b481886d3a280327a261a3fdded586913 ]] || fail 'Official LÖVE download failed its SHA-256 check.'
        mkdir "$stage_dir/download"
        /usr/bin/ditto -x -k "$archive" "$stage_dir/download"
        love_app="$stage_dir/download/love.app"
    fi
    [[ -x "$love_app/Contents/MacOS/love" && -f "$love_app/Contents/Info.plist" ]] || fail "Not a usable official love.app: $love_app"
    runtime_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$love_app/Contents/Info.plist")"
    runtime_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$love_app/Contents/Info.plist")"
    [[ "$runtime_id" == org.love2d.love ]] || fail '--love-app must be the official LÖVE application.'
    case "$runtime_version" in 11.5|11.5a) ;; *) fail "Expected LÖVE 11.5; supplied runtime is $runtime_version." ;; esac
    app="$stage_dir/Starfall.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    /usr/bin/ditto "$love_app" "$app/Contents/Resources/love.app"
    cp "$cartridge" "$app/Contents/Resources/starfall.love"
    printf 'starfall-installer-v1\n' > "$app/.starfall-installer"
    cat > "$app/Contents/MacOS/starfall" <<'LAUNCHER'
#!/bin/bash
# Installed by Starfall
set -euo pipefail
contents_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
exec "$contents_dir/Resources/love.app/Contents/MacOS/love" "$contents_dir/Resources/starfall.love" "$@"
LAUNCHER
    chmod +x "$app/Contents/MacOS/starfall"
    cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.starfall.game</string>
<key>CFBundleName</key><string>Starfall</string>
<key>CFBundleDisplayName</key><string>Starfall</string>
<key>CFBundleExecutable</key><string>starfall</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSHighResolutionCapable</key><false/>
</dict></plist>
PLIST
    replace_directory "$app" "$target"
    printf 'Installed %s\nOpen Starfall from Finder when you want to play.\n' "$target"
else
    share_dir="$prefix/.local/share/starfall"
    bin_dir="$prefix/.local/bin"
    applications_dir="$prefix/.local/share/applications"
    units_dir="$prefix/.config/systemd/user"
    if [[ -e "$share_dir" || -L "$share_dir" ]]; then
        owned_directory "$share_dir" || fail "Refusing to replace unrelated game data: $share_dir"
    fi
    for managed_file in "$bin_dir/starfall" "$applications_dir/starfall.desktop" "$units_dir/starfall-controls-restore.service"; do
        if [[ -e "$managed_file" || -L "$managed_file" ]]; then
            [[ ! -L "$managed_file" ]] && grep -Fq '# Installed by Starfall' "$managed_file" || fail "Refusing to replace an unrelated file: $managed_file"
        fi
    done
    mkdir -p "$prefix/.local/share" "$bin_dir" "$applications_dir" "$units_dir"
    stage_dir="$(mktemp -d "$prefix/.local/share/.starfall-install.XXXXXX")"
    prepare_cartridge
    game_dir="$stage_dir/starfall"
    mkdir "$game_dir"
    cp "$cartridge" "$game_dir/starfall.love"
    cp "$project_dir/tools/uconsole-launch.sh" "$project_dir/tools/uconsole-guard.sh" "$game_dir/"
    chmod +x "$game_dir/"*.sh
    printf 'starfall-installer-v1\n' > "$game_dir/.starfall-installer"
    {
        printf '#!/usr/bin/env bash\n# Installed by Starfall\nset -euo pipefail\nshare_dir=%q\n' "$share_dir"
        cat <<'LINUX_LAUNCHER'
if [[ "$share_dir" == "$HOME/.local/share/starfall" ]] && command -v systemd-run >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    wayland="${WAYLAND_DISPLAY:-}"
    if [[ -z "$wayland" ]]; then
        for display in "$runtime_dir"/wayland-*; do
            [[ ! -S "$display" ]] || { wayland="$(basename "$display")"; break; }
        done
    fi
    if [[ -n "$wayland" ]]; then
        exec "$share_dir/uconsole-launch.sh" "$@"
    fi
fi
exec love "$share_dir/starfall.love" "$@"
LINUX_LAUNCHER
    } > "$stage_dir/starfall-command"
    chmod +x "$stage_dir/starfall-command"
    python3 - "$bin_dir/starfall" "$stage_dir/starfall.desktop" <<'DESKTOP'
import pathlib, sys
command = sys.argv[1]
# Desktop Exec quoting has its own grammar; it is not shell quoting.
escaped = ''.join('\\' + character if character in '\\"`$' else character for character in command)
pathlib.Path(sys.argv[2]).write_text(
    '# Installed by Starfall\n[Desktop Entry]\nType=Application\nName=Starfall\n'
    'Comment=Commander Whiskers — arcade space shooter\n'
    f'Exec="{escaped}"\nIcon=applications-games\nTerminal=false\n'
    'Categories=Game;ActionGame;\nStartupNotify=false\n', encoding='utf-8')
DESKTOP
    {
        printf '# Installed by Starfall\n'
        cat "$project_dir/tools/starfall-controls-restore.service"
    } > "$stage_dir/starfall-controls-restore.service"
    replace_directory "$game_dir" "$share_dir"
    mv "$stage_dir/starfall-command" "$bin_dir/starfall"
    mv "$stage_dir/starfall.desktop" "$applications_dir/starfall.desktop"
    mv "$stage_dir/starfall-controls-restore.service" "$units_dir/starfall-controls-restore.service"
    if [[ "$prefix" == "$HOME" ]] && command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload || printf 'Run systemctl --user daemon-reload in your desktop session before using the guarded launcher.\n' >&2
    fi
    printf 'Installed %s\nLaunch Starfall from your application menu or run %s\n' "$share_dir/starfall.love" "$bin_dir/starfall"
fi
