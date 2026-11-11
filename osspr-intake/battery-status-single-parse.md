# `omarchy-battery-status` parses one upower record with a dozen awks

`bin/omarchy-battery-status` is what the power panel runs, as `--shell`, from the same 5 second timer as the unused `top` probe, and on each open. This output is shown: percentage, state, rate, size, time, cycles, threshold.

The script splits one `upower -i` blob with a separate `awk` per field (`percentage`, `energy`, `energy-full`, time-to-empty, `energy-rate`, `native-path`, `state`, both charge thresholds), then another `awk` to round the wattage. A trace of `--shell` against an instant `upower` stub was 24 `execve`s, 14 of them `awk`.

## How often

Same panel timer as the other note: every 5 seconds while the power panel is open. The human-readable form (no `--shell`) is the status line, not the panel. Both forms pay the field parsers. This is not a bar tick or a keypress.

## Benchmark

`upower` is not installed here. The timer uses the bash stub from `test/shell.d/battery-status-test.sh`: a mouse battery that is not a power supply, then a `macsmc-battery` record, with `power_now` of `-10800000` so the rate comes from sysfs. `OMARCHY_PATH` points at this checkout so `omarchy-i18n` is the real one. Command:

```bash
OMARCHY_POWER_SUPPLY_PATH="$stub/power" PATH="$stub/bin:$PWD/bin:$PATH" bin/omarchy-battery-status --shell
```

Twelve pairs, alternating baseline and the patched copy so a busy stretch hits both. `osspr-intake/bench.sh` repeats eight pairs.

| | median ms | mean | min | max | range |
|---|---|---|---|---|---|
| baseline | 31.67 | 31.29 | 28.02 | 33.12 | 5.10 (16.3% of the mean) |
| patched | 19.39 | 19.54 | 18.54 | 20.60 | 2.06 |

Median saving 12.29 ms. The sets do not overlap: patched max 20.60 is under baseline min 28.02, so the saving is outside the 5.10 ms band. `execve` count goes from 24 to 14. Stdout and stderr matched on every pair for this fixture.

A second 12-pair run, same stub, came out the same way: baseline median 32.08 ms (range 4.59), patched median 19.48 ms (range 3.20), delta 12.60 ms, no overlap, no output mismatches. One 8-pair run of `bench.sh`, taken straight after eight `top` invocations, had a single patched sample at 46 ms and the sets overlapped. The median still moved by about 13 ms. The claim is the quiet paired runs, not that every sample is tight.

An earlier unpaired run on a busier machine sat near 64 ms for the baseline. The paired runs above are the ones the saving is taken from.

The stub returns instantly. A real `upower -i` adds D-Bus on top of these numbers; that part was not measured. The 12 ms is the script's own forks.

## Sketch

`osspr-intake/battery-status-single-parse.patch`

One `awk` prints the fields, joined with `|` so an empty field survives `read` (tab is IFS whitespace and collapses). The wattage rounding moves to bash `printf '%.1f'`, which is a builtin, and still drops a trailing `.0`. State and the upower charge thresholds come from that same record. The sysfs fallback, the charge-limit time math, and `omarchy-i18n` are unchanged.

The state pattern is the first `state:` line. The old pattern was the first line containing `state`. The shipped tests agree on upower's records.

## Behaviour

`bash test/shell.d/battery-status-test.sh` passed on the unmodified script.

The same test, pointed at the patched script, passed every case: Apple Silicon and `CMB0` paths, unreadable `current_now`, a hold that has not reached its threshold, holding at the threshold, time-to-full against the charge limit, the UPower fallback, per-battery limits, Danish copy, and a sparse record. The copy of the test lived in `/tmp` and sourced `test/shell.d/base-test.sh`, so `ROOT` stayed this checkout.

Quickshell is not installed, so the panel was not opened.

## Would dhh take it

Not likely, even though the number clears 10 ms. The panel only asks every 5 seconds, real `upower` will dwarf 12 ms of `awk`, and the diff rewrites a parser the tests are careful about. Worth keeping only if a profile on a laptop shows this script, rather than `upower`, on the refresh. The unread `top` probe is the change with a chance.
