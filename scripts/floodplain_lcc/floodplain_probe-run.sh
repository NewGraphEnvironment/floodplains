#!/usr/bin/env bash
#
# floodplain_probe-run.sh — run the whole-FWA floodplain probe's modes in order (#110).
#
# Each mode runs in its own process under `/usr/bin/time -l`, so every log carries that stage's
# peak RSS, and under `caffeinate -s` so idle sleep cannot kill a long arm. The run stops at the
# first mode that fails, judged by the probe's own `PROBE_DONE <mode>` line and an output newer than
# the mode's start -- never by the wrapper's exit code, which `time` and `caffeinate` both stand in
# front of. The anchor runs first: if it fails, the probe does not reproduce step 2 and nothing after
# it means anything. Then the common DEM, then the arms cheapest first, so a blow-up in arm 1 or the
# segment run leaves the cheap arms' results on disk.
#
# Usage:
#   scripts/floodplain_lcc/floodplain_probe-run.sh <area> [mode ...]
#   default modes: anchor dem 5 3 4 2 1 reach seg report
#
# Logs: data/<area>/probe_whole_fwa/logs/<mode>.log (gitignored; `report` reads RSS from them).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)" || exit 1
AREA="${1:?usage: floodplain_probe-run.sh <area> [mode ...]}"
shift
if [ "$#" -eq 0 ]; then set -- anchor dem 5 3 4 2 1 reach seg report; fi

OUT="$REPO_ROOT/data/$AREA/probe_whole_fwa"
LOGS="$OUT/logs"
mkdir -p "$LOGS"

for mode in "$@"; do
  log="$LOGS/$mode.log"
  stamp="$LOGS/.$mode.start"
  touch "$stamp"
  echo "=== $AREA / $mode -> $log ($(date -u +%FT%TZ))"
  caffeinate -s /usr/bin/time -l Rscript "$REPO_ROOT/scripts/floodplain_lcc/floodplain_probe-whole-fwa.R" \
    "$AREA" "$mode" > "$log" 2>&1 || true
  case "$mode" in
    anchor) out="$OUT/anchor.json" ;;
    dem)    out="$OUT/dem.json" ;;
    reach)  out="$OUT/reach.json" ;;
    seg)    out="$OUT/seg_timing.json" ;;
    report) out="$OUT/report.csv" ;;
    *)      out="$OUT/arm${mode}_timing.json" ;;
  esac
  done_n=$(grep -c "^PROBE_DONE $mode\$" "$log") || done_n=0
  if [ "$done_n" -ne 1 ] || [ ! -e "$out" ] || [ ! "$out" -nt "$stamp" ]; then
    echo "[FAIL] $mode: no PROBE_DONE line or no fresh $(basename "$out") -- see $log" >&2
    tail -n 25 "$log" >&2
    exit 1
  fi
  echo "[OK] $mode ($(grep 'maximum resident set size' "$log" | awk '{printf "%.1f GiB peak", $1/1024/1024/1024}'))"
done
echo "PROBE_RUN_DONE $AREA $*"
