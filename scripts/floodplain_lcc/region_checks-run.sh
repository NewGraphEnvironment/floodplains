#!/usr/bin/env bash
# region_checks-run.sh — run #125's per-group acceptance checks over one region and tabulate them.
#
# For each watershed group in config/regions/<region>.yml:
#   provenance-check.R <wsg>
#   composition-check.R <wsg> all_ff04
#   bridge-check.R <wsg> all_ff04
#   disturbance-check.R <wsg>
#   wsg_split-check.R <wsg> all_ff04   (the group-line split, #53; FP_SPLIT_BACKUP=<dir> is passed
#                                       through as <dir>/<wsg> when set, for the before/after totals)
# plus dem_cache-check.R once (offline; it is not per area). Each check's full output goes to
# data/logs/region_checks_<region>_<stamp>/<wsg>_<check>.log (gitignored).
#
# The verdict is the check's own exit status, never a grep of its output. disturbance-check.R also
# gets a second column: the verdict of its transition_<primary> section alone, because the retired
# species layers beside it predate the context and lookback overlays (#95, #103) and fail by design.
# Every assertion FAIL line (indented two spaces in every check; their summary lines are not) is
# printed under the table, so an expected failure (composition's 1% change-vs-patch
# bound, #53) can be told from a new one by reading its label.
#
# usage: bash scripts/floodplain_lcc/region_checks-run.sh <region> [scenario]
#   scenario default: all_ff04
set -u

region="${1:?usage: region_checks-run.sh <region> [scenario]}"
scen="${2:-all_ff04}"
root="$(cd "$(dirname "$0")/../.." && pwd -P)" || exit 1
cd "$root" || exit 1

yml="config/regions/${region}.yml"
[ -f "$yml" ] || { echo "no region file: $yml" >&2; exit 1; }
groups=$(awk -F'[][]' '/^watershed_groups:/ { print $2; exit }' "$yml" | tr -d ' ' | tr ',' ' ' | tr '[:upper:]' '[:lower:]')
[ -n "$groups" ] || { echo "no watershed_groups in $yml" >&2; exit 1; }

stamp=$(date -u +%Y%m%d_%H%M%S)
out="data/logs/region_checks_${region}_${stamp}"
mkdir -p "$out" || exit 1
chk="scripts/floodplain_lcc"

# run <logname> <script> [args...] -> prints PASS or FAIL(<n>), from the exit status
run() {
  local log="$out/$1.log"; shift
  if Rscript "$@" > "$log" 2>&1; then
    echo "PASS"
  else
    local n
    n=$(grep -c '^  FAIL ' "$log") || n=0
    echo "FAIL($n)"
  fi
}

# The transition_<scen> section of a disturbance-check log: from its "  -- <layer>" header to the
# next layer header or the summary line. Absent counts as FAIL: a check that never reached the
# layer has not passed it. A section that never reaches either end is INCOMPLETE: the check died
# inside it (an error prints no summary line), and the layer is last in every log, so without this
# a crash there would read as PASS.
dst_section() {
  local log="$out/$1_disturbance.log"
  awk -v hdr="  -- transition_${scen}_" '
    index($0, hdr) == 1                   { on = 1; seen = 1; closed = 0; next }
    on && /^  -- /                        { on = 0; closed = 1 }
    on && /^(ALL PASS|[0-9]+ FAIL)$/      { on = 0; closed = 1 }
    on && /^  FAIL /                      { n++ }
    END {
      if (!seen) print "ABSENT"
      else if (!closed) print "INCOMPLETE"
      else if (n) print "FAIL(" n ")"
      else print "PASS"
    }
  ' "$log"
}

echo "Region: $region | scenario: $scen | groups: $groups"
echo "Logs: $out"
echo
dem=$(run dem_cache "$chk/dem_cache-check.R")
echo "dem_cache-check.R (offline): $dem"
echo
printf '%-6s %-12s %-12s %-12s %-12s %-14s %-12s\n' wsg provenance composition bridge disturbance "dist:$scen" wsg_split
for g in $groups; do
  p=$(run "${g}_provenance"  "$chk/provenance-check.R"  "$g")
  c=$(run "${g}_composition" "$chk/composition-check.R" "$g" "$scen")
  b=$(run "${g}_bridge"      "$chk/bridge-check.R"      "$g" "$scen")
  d=$(run "${g}_disturbance" "$chk/disturbance-check.R" "$g")
  ds=$(dst_section "$g")
  if [ -n "${FP_SPLIT_BACKUP:-}" ]; then
    w=$(FP_SPLIT_BACKUP="$FP_SPLIT_BACKUP/$g" run "${g}_wsg_split" "$chk/wsg_split-check.R" "$g" "$scen")
  else
    w=$(run "${g}_wsg_split" "$chk/wsg_split-check.R" "$g" "$scen")
  fi
  printf '%-6s %-12s %-12s %-12s %-12s %-14s %-12s\n' "$g" "$p" "$c" "$b" "$d" "$ds" "$w"
done

echo
echo "FAIL lines (file: line):"
fl=$(grep -H '^  FAIL ' "$out"/*.log) || fl=""
if [ -n "$fl" ]; then printf '%s\n' "$fl" | sed "s#^$out/##"; else echo "  none"; fi
