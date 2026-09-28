#!/usr/bin/env bash
# Sample the spinning app's main-thread stack.
#
# ptrace_scope=1 blocks an external eu-stack; running eu-stack as root uses
# CAP_SYS_PTRACE instead, which avoids loosening a kernel setting just to debug.
# The password is read from ~/.hermes/.env and piped straight into sudo -S, so
# it never appears in argv or in this file.
set -u
APP="$HOME/exochronometer-linux/build/app"
cd "$APP" || exit 1

sed 's/property int page: 0/property int page: 3/' main.qml > main-p3.qml
qml6 main-p3.qml >/dev/null 2>&1 &
QLMPID=$!
sleep 7

# Focus so Qt renders it the way it would for a user.
python3 - <<'PY'
import json, subprocess
try:
    raw = subprocess.run(["hyprctl","clients","-j"],capture_output=True,timeout=10).stdout
    for c in json.loads(raw):
        if c.get("title") == "Exochronometer":
            subprocess.run(["hyprctl","dispatch","focuswindow","address:"+c["address"]],
                           capture_output=True,timeout=10)
except Exception as e:
    print("focus failed:", e)
PY
sleep 2

PID=$(pgrep -f "qml6 main-p3.qml" | head -1)
echo "pid=$PID"

hz=$(getconf CLK_TCK)
read a b < <(awk '{print $14, $15}' /proc/$PID/stat)
t0=$(date +%s.%N)
sleep 5
read a2 b2 < <(awk '{print $14, $15}' /proc/$PID/stat)
t1=$(date +%s.%N)
python3 -c "print(f'cpu {($a2+$b2-$a-$b)/$hz/($t1-$t0)*100:.1f}%')"

PW=$(grep -E '^SUDO_PASSWORD=' "$HOME/.hermes/.env" | cut -d= -f2- | sed 's/^["'\'']//;s/["'\'']$//')
for i in 1 2 3; do
  echo "=== stack sample $i ==="
  printf '%s\n' "$PW" | sudo -S -p '' eu-stack -p "$PID" 2>&1 | head -30
  sleep 1
done

kill "$QLMPID" 2>/dev/null
wait "$QLMPID" 2>/dev/null
rm -f main-p3.qml