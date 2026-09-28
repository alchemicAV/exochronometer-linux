#!/usr/bin/env bash
# Install the freshly built package with pacman.
#
# sudo here is password-fed from ~/.hermes/.env because this box has no TTY for
# the agent; Arch's tty_tickets means a `sudo -v` in one shell does not carry to
# another, so the password is piped to each sudo call. It is never echoed and
# never appears in argv.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../packaging"

pkg=$(ls -1t exochronometer-*.pkg.tar.zst | head -1)
echo "installing $pkg"

pw=$(grep -E '^SUDO_PASSWORD=' "$HOME/.hermes/.env" | cut -d= -f2-)
pw=${pw%\"}; pw=${pw#\"}
pw=${pw%\'}; pw=${pw#\'}
if [ -z "$pw" ]; then
  echo "no SUDO_PASSWORD in ~/.hermes/.env" >&2
  exit 1
fi

printf '%s\n' "$pw" | sudo -S pacman -U --noconfirm "$pkg" 2>&1 | grep -vE '^\[sudo\]' | tail -12
echo "--- installed ---"
pacman -Q exochronometer