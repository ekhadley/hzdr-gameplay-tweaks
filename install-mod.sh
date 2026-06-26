#!/usr/bin/env bash
#
# Install the HZDR Gameplay Tweaks mod into the local Steam (Proton) game folder.
#
#   ./install-mod.sh [path/to/winhttp.dll]
#
# Copies the built winhttp.dll (the mod, renamed by the build) and the default
# mod_config.ini into the game root. If no dll path is given, it searches ./bin.
#
set -euo pipefail

GAME_DIR="/home/ek/.local/share/Steam/steamapps/common/Horizon Zero Dawn Remastered"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DLL="${1:-}"
if [[ -z "$DLL" ]]; then
    DLL="$(find "$REPO_DIR/bin" -name winhttp.dll -type f 2>/dev/null | head -n1)"
fi

if [[ -z "$DLL" || ! -f "$DLL" ]]; then
    echo "error: winhttp.dll not found." >&2
    echo "  Build the mod first, or pass the path explicitly:" >&2
    echo "    ./install-mod.sh path/to/winhttp.dll" >&2
    exit 1
fi

if [[ ! -d "$GAME_DIR" ]]; then
    echo "error: game directory not found:" >&2
    echo "  $GAME_DIR" >&2
    exit 1
fi

# Back up a pre-existing winhttp.dll once, so we never clobber a real proxy or an earlier backup.
if [[ -f "$GAME_DIR/winhttp.dll" && ! -f "$GAME_DIR/winhttp.dll.bak" ]]; then
    cp -v "$GAME_DIR/winhttp.dll" "$GAME_DIR/winhttp.dll.bak"
fi

cp -v "$DLL" "$GAME_DIR/winhttp.dll"

# Always install the config, backing up an existing one once so tuned settings aren't lost outright.
if [[ -f "$GAME_DIR/mod_config.ini" && ! -f "$GAME_DIR/mod_config.ini.bak" ]]; then
    cp -v "$GAME_DIR/mod_config.ini" "$GAME_DIR/mod_config.ini.bak"
fi
cp -v "$REPO_DIR/resources/mod_config.ini" "$GAME_DIR/mod_config.ini"
echo "Installed mod_config.ini (overwrote existing; previous saved as mod_config.ini.bak)."

echo "Done. Mod installed to:"
echo "  $GAME_DIR"
