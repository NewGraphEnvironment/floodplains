#!/usr/bin/env bash
#
# run_areas.sh  —  run the floodplain + LULC pipeline over several areas.
#
# Thin orchestration wrapper around scripts/run_area.R, modelled on link's
# data-raw/study_area_run.sh: per-area SOFT-FAIL (a failing area logs [WARN] and the
# loop continues) + timestamped per-area logs. All R logic lives in run_area.R; this
# script only loops and logs.
#
# Usage:
#   scripts/run_areas.sh <area> [<area> ...]                 # default steps 1,2,3
#   STEPS=1,2 scripts/run_areas.sh neexdzii morr             # override steps
#
# Example:
#   scripts/run_areas.sh neexdzii morr

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STEPS="${STEPS:-1,2,3}"

if [ "$#" -eq 0 ]; then
  echo "usage: scripts/run_areas.sh <area> [<area> ...]" >&2
  exit 1
fi

LOG_DIR="$REPO_ROOT/data/logs"
mkdir -p "$LOG_DIR"
TS="$(date -u +%Y%m%d_%H%M%S)"

rc=0
for area in "$@"; do
  log="$LOG_DIR/${TS}_${area}.log"
  echo "=== $area (steps $STEPS) -> $log ==="
  if Rscript "$REPO_ROOT/scripts/run_area.R" "$area" "$STEPS" 2>&1 | tee "$log"; then
    echo "[OK] $area"
  else
    echo "[WARN] area $area failed (continuing) — see $log" >&2
    rc=1
  fi
done

exit "$rc"
