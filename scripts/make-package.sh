#!/bin/bash
# Compile the TypeScript core, assemble the QML app, and build the package.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

echo "==> compiling TypeScript core"
./node_modules/.bin/tsc

echo "==> assembling QML app"
node scripts/build-app.mjs

echo "==> building the real-time audio module"
bash scripts/build-audio.sh

echo "==> staging app package source"
tar czf packaging/exochronometer-app.tar.gz -C build app audio/ExoAudio
cp LICENSE packaging/LICENSE

echo "==> generating the Omarchy shell plugin"
node scripts/build-omarchy-plugin.mjs
tar czf packaging/omarchy/exochronometer-plugin.tar.gz -C build omarchy-plugin

echo "==> makepkg: app"
( cd packaging && makepkg -f "$@" )

# The helper is packaged as a local source, which makepkg reads from the PKGBUILD's
# own directory. Copy it in rather than keeping two hand-maintained files - they
# drifted once already, and the package shipped the stale one.
cp packaging/exochronometer-omarchy-plugin packaging/omarchy/

echo "==> makepkg: omarchy integration"
( cd packaging/omarchy && makepkg -f "$@" )

echo
echo "==> built:"
ls -la packaging/*.pkg.tar.zst packaging/omarchy/*.pkg.tar.zst
