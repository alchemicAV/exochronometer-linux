#!/usr/bin/env bash
# Install the generated Omarchy shell plugin into the user's shell config.
#
# Copied rather than symlinked: QML resolves a component's relative imports
# against the file's own directory, so the plugin directory must really contain
# AppShell.qml, the other components and core/. A symlink to build/ would work
# only while the build tree exists.
#
# Re-run after scripts/build-omarchy-plugin.mjs to update. The shell only picks
# up bar-widget code changes on a restart, so this does that too.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ID="alchemicav.exochronometer"
SRC="build/omarchy-plugin"
DST="$HOME/.config/omarchy/plugins/$ID"

[ -d "$SRC" ] || { echo "$SRC missing - run scripts/build-omarchy-plugin.mjs first" >&2; exit 1; }

rm -rf "$DST"
mkdir -p "$DST"
cp -r "$SRC"/. "$DST"/

echo "installed $(find "$DST" -type f | wc -l) files to $DST"
omarchy plugin validate "$DST" && echo "validate: ok"

# A failed compile is cached in the shell's QML cache and will keep being
# reported after the file is fixed; clear it so the next start compiles fresh.
rm -rf "$HOME/.cache/quickshell/qmlcache"

echo "restarting shell..."
omarchy restart shell
sleep 8
echo
echo "--- shell log for this plugin (empty is good) ---"
journalctl --user --since "-2 min" --no-pager 2>/dev/null \
  | grep -i "$ID" | grep -iE "failed|error" | tail -5 || true
echo "--- done ---"