# Power panel runs `top` for a value nothing reads

`shell/plugins/panels/power/Panel.qml` `refresh()` starts `omarchy-system-stats` every 5 seconds while the power panel is open, and again on each open. The process writes `systemInfo`. Nothing in the shell reads `systemInfo`. The stats block on the panel is filled from `batteryInfo` only.

`omarchy-system-stats` (the no-argument form) gets its CPU figure from `top -bn1`. On this machine that is two `clock_nanosleep` calls of 100 ms inside `top`, then a short parse. Thirty-three processes were on the box, and `-d 0`, `-d 0.05` and `-d 1` all stayed at about 205 ms, so the cost is those sleeps, not the size of the process table. The panel pays that every refresh and throws the text away.

## How often

The panel's timer is `interval: 5000`, `running: root.opened`, `repeat: true`, and `refresh()` also runs when the panel opens. This is not a bar tick or a keypress. It is the whole time the power panel stays open. `omarchy-system-stats` has no other production caller. `test/shell.d/system-stats-test.sh` is the other caller, and it stubs `top`.

## Benchmark

```bash
OMARCHY_PATH=/workspace /workspace/bin/omarchy-system-stats
```

Eight runs after one warmup, timed with `EPOCHREALTIME`, output discarded. No stubs: `top` and `/proc` are real. Recorded by `osspr-intake/bench.sh`.

| | ms |
|---|---|
| median | 207.60 |
| mean | 207.73 |
| min | 207.33 |
| max | 208.40 |
| range (noise band) | 1.06 (0.51% of the mean) |

`top -bn1` alone, same method: median 204.46 ms, range 0.69 ms. `strace -tt` shows the two 100 ms sleeps. The command forks `top` and two `awk`s (four `execve`s including itself).

The patch deletes the process, the `systemInfo` property, the refresh line, and the unread branch of `updateKeyValue`. After that, this refresh does not start the command, so the measured saving is the whole 207.60 ms. That is well outside the 1.06 ms band.

`omarchy-system-stats --bar-widget` reads `/proc` in about 3.5 ms and prints counters, not `cpu\tN%`. It is not a drop-in replacement, and it is not what this patch does. The command itself stays as it is for anyone who runs it by hand, and it is still slow there.

## Sketch

`osspr-intake/power-panel-unused-system-stats.patch`

One deletion in `shell/plugins/panels/power/Panel.qml`. The battery and power-profile probes stay.

## Behaviour

`bash test/shell.d/system-stats-test.sh` passed. The locale parsing of `top` is unchanged because the command is unchanged. No test asserts that the panel spawns `omarchy-system-stats`. `systemInfo` is assigned in that one file and referenced nowhere else in the tree.

Quickshell is not installed here, so the patched panel was not opened on a running bar. Nothing on screen can change: the property was already unread. A session with a battery would still be the right place to open the panel once and confirm the battery rows and profile buttons still fill in.

## Would dhh take it

Reasonable chance. It is one deletion, the cost is a pair of 100 ms sleeps, and the result has been unread since `systemInfo` landed on 2026-05-18. The file is not in the last 7 days of `quattro` history. The open-PR check is incomplete: the first page of open `omacom/omarchy` titles on 2026-11-11 did not mention this panel, and a later API credential check failed before per-file diffs could be listed.

The way this misses is if he still means to draw CPU and memory there. Rendering them is a different change, and it should not call `top -bn1`.
