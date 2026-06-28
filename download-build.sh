#!/usr/bin/env bash
#
# Download the latest CI build artifact (winhttp.dll + mod_config.ini) from the
# GitHub Actions "build" workflow.
#
#   ./download-build.sh [branch]
#
# Defaults to the current git branch. GitHub's own artifact downloads require
# auth even on public repos, so we go through nightly.link, which proxies the
# latest successful run's artifact without a token. Unzips into ./built; from
# there run ./install-mod.sh built/winhttp.dll to deploy.
set -euo pipefail

REPO="ekhadley/hzdr-gameplay-tweaks"
ARTIFACT="hzdr-gameplay-tweaks"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BRANCH="${1:-$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)}"
URL="https://nightly.link/$REPO/workflows/build/$BRANCH/$ARTIFACT.zip"
OUT="$REPO_DIR/built"

echo "Downloading latest build for branch '$BRANCH'..."
echo "  $URL"

rm -rf "$OUT"
mkdir -p "$OUT"
curl -fL "$URL" -o "$OUT/$ARTIFACT.zip"
unzip -o "$OUT/$ARTIFACT.zip" -d "$OUT"

echo "Done. Unzipped to:"
echo "  $OUT"
echo "Install with:"
echo "  ./install-mod.sh \"$OUT/winhttp.dll\""
