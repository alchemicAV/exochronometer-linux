#!/usr/bin/env bash
# Build the ExoAudio QML module and the kernel selftest.
#
# Deliberately not cmake: this is one shared object plus one standalone test
# binary, and the machine has g++/pkg-config/moc but no cmake. Keeping it to a
# script means the package build has no new build dependency.
#
#   scripts/build-audio.sh [outdir]      (default: build/audio)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/src/audio"
base="${1:-$root/build/audio}"
# The plugin must live in a directory NAMED after the module, or Qt will not
# resolve the import. The selftest sits beside it, not inside it.
out="$base/ExoAudio"
mkdir -p "$out"
[ -f "$src/exosynth.cpp" ] || { echo "kernel sources not found in $src" >&2; exit 1; }

MOC="${MOC:-/usr/lib/qt6/moc}"
[ -x "$MOC" ] || { echo "moc not found at $MOC (set MOC=)" >&2; exit 1; }

QT_PKGS="Qt6Core Qt6Qml Qt6Multimedia"
cflags=$(pkg-config --cflags $QT_PKGS)
libs=$(pkg-config --libs $QT_PKGS)

# The same hardening makepkg would apply, since this build does not go through it:
# FULL RELRO and no gratuitous DT_NEEDED entries (namcap flags both otherwise).
HARDENING="-Wl,-z,relro,-z,now -Wl,--as-needed"

# 1. The kernel selftest: no Qt at all, so it runs headless anywhere.
echo "==> kernel selftest"
g++ -std=c++17 -O2 -Wall -o "$base/exo-selftest" \
    "$src/exosynth.cpp" "$src/selftest.cpp"

# 2. The QML module. moc first: these classes carry Q_OBJECT.
echo "==> moc"
# moc output goes BESIDE the module, not into it: the module directory must hold
# only what ships (the .so and the qmldir).
"$MOC" "$src/realtimeaudio.h" -o "$base/moc_realtimeaudio.cpp"
"$MOC" "$src/plugin.h" -o "$base/moc_plugin.cpp"

echo "==> libexoaudio.so"
g++ -std=c++17 -O2 -Wall -fPIC -shared $HARDENING -o "$out/libexoaudio.so" \
    $cflags -I"$src" \
    "$src/exosynth.cpp" "$src/realtimeaudio.cpp" "$src/plugin.cpp" \
    "$base/moc_realtimeaudio.cpp" "$base/moc_plugin.cpp" \
    $libs

# 3. The module directory Qt loads it from.
cp "$src/qmldir" "$out/qmldir"

echo
echo "built:"
ls -la "$out/libexoaudio.so" "$base/exo-selftest" "$out/qmldir"