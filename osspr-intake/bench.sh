#!/bin/bash
# Re-run the measurements behind the notes in this directory.
# Does not modify the checkout. upower, pactl and hyprctl are not required:
# battery-status is timed against the same instant upower stub the shell test uses.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runs=8

now_us() {
  local now="${EPOCHREALTIME//[!0-9]/}"
  printf '%s' "$now"
}

# Prints one line: median mean min max range
summarize() {
  python3 - "$@" <<'PY'
import statistics, sys
vals = [float(x) for x in sys.argv[1:]]
mean = statistics.mean(vals)
print(f"{statistics.median(vals):.2f} {mean:.2f} {min(vals):.2f} {max(vals):.2f} {max(vals)-min(vals):.2f} {((max(vals)-min(vals))/mean*100):.2f}")
PY
}

time_cmd() {
  local i start end us
  local -a samples=()
  "$@" >/dev/null 2>&1 || true
  for (( i = 1; i <= runs; i++ )); do
    start=$(now_us)
    "$@" >/dev/null 2>&1 || true
    end=$(now_us)
    us=$(( end - start ))
    samples+=("$(printf '%d.%03d' $(( us / 1000 )) $(( us % 1000 )))")
  done
  summarize "${samples[@]}"
}

echo "system-stats ($runs runs, real top)"
echo "  $(time_cmd "$ROOT/bin/omarchy-system-stats")"

if command -v strace >/dev/null; then
  strace -tt -o /tmp/osspr-top.strace top -bn1 >/dev/null
  python3 - <<'PY'
import re
lines=open("/tmp/osspr-top.strace").read().splitlines()
pat=re.compile(r'clock_nanosleep\([^)]*\{tv_sec=(\d+), tv_nsec=(\d+)\}')
for line in lines:
    m=pat.search(line)
    if m:
        print(f"  top nanosleep {int(m.group(1))*1000 + int(m.group(2))/1e6:.0f} ms")
PY
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/power/macsmc-battery" "$work/tree/bin"
printf '%s\n' '-10800000' >"$work/power/macsmc-battery/power_now"
printf '75\n' >"$work/power/macsmc-battery/charge_control_start_threshold"
printf '80\n' >"$work/power/macsmc-battery/charge_control_end_threshold"
printf '212\n' >"$work/power/macsmc-battery/cycle_count"
cat >"$work/bin/upower" <<'STUB'
#!/bin/bash
if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_hidpp_battery_0"
  echo "/org/freedesktop/UPower/devices/battery_macsmc_battery"
  exit 0
fi
if [[ $1 == "-i" && $2 == */battery_hidpp_battery_0 ]]; then
  printf '%s\n' "  power supply:         no" "  percentage:           5%"
  exit 0
fi
if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          macsmc-battery
  power supply:         yes
  state:                discharging
  energy:               28.3 Wh
  energy-full:          56.7 Wh
  energy-rate:          7.3 W
  time to empty:        2.5 hours
  percentage:           51%
INFO
  exit 0
fi
exit 1
STUB
chmod +x "$work/bin/upower"

cp "$ROOT/bin/omarchy-battery-status" "$work/tree/bin/omarchy-battery-status"
patch -p1 -d "$work/tree" <"$ROOT/osspr-intake/battery-status-single-parse.patch" >/dev/null

export OMARCHY_PATH=$ROOT
export OMARCHY_POWER_SUPPLY_PATH=$work/power
export PATH="$work/bin:$ROOT/bin:/usr/bin:/bin"

echo "battery-status --shell, stub upower, alternating ($runs pairs)"
python3 - "$ROOT" "$work" "$runs" <<'PY'
import os, statistics, subprocess, sys, time
root, work, runs = sys.argv[1], sys.argv[2], int(sys.argv[3])
env = os.environ.copy()
base = [f"{root}/bin/omarchy-battery-status", "--shell"]
fast = [f"{work}/tree/bin/omarchy-battery-status", "--shell"]
def once(cmd):
    start = time.perf_counter()
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    return (time.perf_counter() - start) * 1000, proc.returncode, proc.stdout, proc.stderr
once(base); once(fast)
base_ms, fast_ms, mismatches = [], [], 0
for _ in range(runs):
    b, rc1, out1, err1 = once(base)
    f, rc2, out2, err2 = once(fast)
    base_ms.append(b)
    fast_ms.append(f)
    if (rc1, out1, err1) != (rc2, out2, err2):
        mismatches += 1
def line(name, vals):
    mean = statistics.mean(vals)
    print(f"  {name}: median {statistics.median(vals):.2f} mean {mean:.2f} min {min(vals):.2f} max {max(vals):.2f} range {max(vals)-min(vals):.2f} noise {(max(vals)-min(vals))/mean*100:.2f}%")
line("baseline", base_ms)
line("patched", fast_ms)
print(f"  delta_median {statistics.median(base_ms)-statistics.median(fast_ms):.2f} overlap {max(fast_ms) >= min(base_ms)} mismatches {mismatches}")
PY
