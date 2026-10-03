#!/usr/bin/env bash
#
# alr_load.sh — load the Agricultural Land Reserve into fwapg as a FROZEN, dated snapshot (#108).
#
# Source: ALC "Agricultural Land Reserve Polygons", BC Data Catalogue record
# 92e17599-ac8a-47c8-877c-107768cb373c, warehouse object WHSE_LEGAL_ADMIN_BOUNDARIES.OATS_ALR_POLYS,
# Open Government Licence - BC. DataBC refreshes it quarterly (end of Jan/Apr/Jul/Oct) as the ALC
# includes and excludes land, so a load is a snapshot of one date, not "the ALR".
#
# FREEZE, then refresh deliberately. The table feeds `in_alr` on published transition layers and the
# composition table, so a silent reload would move published numbers with no change in this repo.
# The script therefore refuses when the table exists; REFRESH=1 truncates and reloads.
#
# The snapshot is RECORDED ON THE TABLE: `COMMENT ON TABLE` carries the load time (UTC), the row count
# and the record id, as `key=value; ...`. Step 3 / composition_build.R copy that comment into
# provenance (`composition[<scenario>]$inputs`), so a reader of an output can tell which snapshot
# produced it. bcdata.log's `latest_download` is NOT used for this: it is per table and overwritten by
# every load, append or not.
#
# Checks, each fatal: rows loaded == the WFS count taken just before the load, and STATUS = 'ALR' on
# every row (measured 2026-10-02: all 3,226 rows 'ALR', FEATURE_CODE NULL on all -- if another status
# appears, the layer has started holding something other than the current reserve and a filter has to
# be decided, not assumed).
#
# Connection: the libpq PG* variables, taken from ~/.Renviron when PGHOST is unset (bash does not read
# it; CLAUDE.md, "The database is a Docker container").
#
# usage: scripts/fwapg/alr_load.sh                 # load (refuses if the table exists)
#        REFRESH=1 scripts/fwapg/alr_load.sh       # truncate + reload, re-stamp the comment
#        DRY=1 scripts/fwapg/alr_load.sh           # report the remote count and local state only

set -euo pipefail

LAYER="WHSE_LEGAL_ADMIN_BOUNDARIES.OATS_ALR_POLYS"
TABLE="whse_legal_admin_boundaries.oats_alr_polys"
RECORD="92e17599-ac8a-47c8-877c-107768cb373c"

if [ -z "${PGHOST:-}" ]; then
  eval "$(grep -E '^PG(HOST|PORT|DATABASE|USER|PASSWORD)=' "$HOME/.Renviron" | sed 's/^/export /')"
fi
: "${PGHOST:?PGHOST unset and not in ~/.Renviron}" "${PGDATABASE:?PGDATABASE unset}" "${PGUSER:?PGUSER unset}"

q() { psql -X -A -t -v ON_ERROR_STOP=1 -c "$1"; }

n_remote="$(bcdata info "$LAYER" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])')"
case "$n_remote" in ''|*[!0-9]*) echo "FAIL: could not read the remote count (got '$n_remote')" >&2; exit 1;; esac
exists="$(q "SELECT to_regclass('$TABLE') IS NOT NULL")"
echo "remote: $n_remote features in $LAYER"
if [ "$exists" = "t" ]; then
  echo "local:  $(q "SELECT count(*) FROM $TABLE") rows; comment: $(q "SELECT obj_description('$TABLE'::regclass)")"
else
  echo "local:  $TABLE absent"
fi

if [ "${DRY:-0}" = "1" ]; then echo "DRY=1: nothing loaded"; exit 0; fi
mode=()
if [ "$exists" = "t" ]; then
  if [ "${REFRESH:-0}" != "1" ]; then
    echo "REFUSED: $TABLE exists -- the snapshot is frozen; REFRESH=1 reloads it (and moves in_alr)" >&2
    exit 1
  fi
  mode=(--refresh)
fi

DATABASE_URL="$(python3 - <<'PY'
import os, urllib.parse as u
q = lambda k, d="": u.quote(os.environ.get(k, d), safe="")
print("postgresql://%s:%s@%s:%s/%s" % (q("PGUSER"), q("PGPASSWORD"), q("PGHOST"), q("PGPORT", "5432"), q("PGDATABASE")))
PY
)"
export DATABASE_URL
loaded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# bcdata logs the URL it connected with, password included; never let that reach a committed log.
# ${mode[@]+...}: an empty array under `set -u` is unbound on macOS bash 3.2.
bcdata bc2pg "$LAYER" ${mode[@]+"${mode[@]}"} 2>&1 | sed -E 's#postgresql://[^@]*@#postgresql://<redacted>@#g'

n_local="$(q "SELECT count(*) FROM $TABLE")"
if [ "$n_local" != "$n_remote" ]; then
  echo "FAIL: loaded $n_local rows, the WFS reported $n_remote" >&2
  exit 1
fi
other="$(q "SELECT string_agg(DISTINCT coalesce(status, '<NULL>'), ', ') FROM $TABLE WHERE status IS DISTINCT FROM 'ALR'")"
if [ -n "$other" ]; then
  echo "FAIL: STATUS values other than 'ALR' present ($other) -- decide a filter before using this table" >&2
  exit 1
fi
q "COMMENT ON TABLE $TABLE IS 'snapshot=$loaded_at; rows=$n_local; record=$RECORD; layer=$LAYER'" >/dev/null
echo "OK: $n_local rows, all STATUS = 'ALR'"
echo "comment: $(q "SELECT obj_description('$TABLE'::regclass)")"
