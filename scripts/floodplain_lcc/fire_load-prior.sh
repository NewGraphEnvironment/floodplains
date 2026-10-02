#!/usr/bin/env bash
#
# fire_load-prior.sh — append the fires BEFORE 2017 to fwapg's fire table (#103).
#
# The fire table `whse_land_and_natural_resource.prot_historical_fire_polys_sp` (DataBC
# "Fire Perimeters - Historical") was loaded holding fire_year >= 2017 only -- the change interval and
# later -- so the `lookback:` entry in config/disturbance.yml (`fire_prior`, the 15 years before the
# change interval) would match nothing. This loads the rest of the layer, FIRE_YEAR < 2017.
#
# APPEND, never refresh: a refresh reloads the in-window rows from today's DataBC, and any perimeter
# edited upstream since the original load would move a published `in_fire` / `fire_year` value with
# no change here (fire_tag.R would then refuse every area until FORCE=1). Appending adds rows only
# outside the window the causes read, and the guard below proves it: an md5 over the in-window rows,
# taken before and after, must match or the script exits non-zero.
#
# Refuses to run twice: rows < 2017 already present means it has run (a second append duplicates).
# A load that died part-way leaves some of them, and is recovered by removing exactly what this adds,
# then re-running:  psql -c "DELETE FROM whse_land_and_natural_resource.prot_historical_fire_polys_sp
#                            WHERE fire_year < 2017"
#
# Connection: the libpq PG* variables. They live in ~/.Renviron, which bash does not read, so they are
# taken from there when PGHOST is unset (CLAUDE.md, "The database is a Docker container").
#
# usage: scripts/floodplain_lcc/fire_load-prior.sh            # load
#        DRY=1 scripts/floodplain_lcc/fire_load-prior.sh      # report counts and the in-window md5 only

set -euo pipefail

TABLE="whse_land_and_natural_resource.prot_historical_fire_polys_sp"
LAYER="WHSE_LAND_AND_NATURAL_RESOURCE.PROT_HISTORICAL_FIRE_POLYS_SP"
QUERY="FIRE_YEAR < 2017"

if [ -z "${PGHOST:-}" ]; then
  eval "$(grep -E '^PG(HOST|PORT|DATABASE|USER|PASSWORD)=' "$HOME/.Renviron" | sed 's/^/export /')"
fi
: "${PGHOST:?PGHOST unset and not in ~/.Renviron}" "${PGDATABASE:?PGDATABASE unset}" "${PGUSER:?PGUSER unset}"

q() { psql -X -A -t -v ON_ERROR_STOP=1 -c "$1"; }

# In-window rows, ordered on every column the causes read plus the geometry, so a reordered load
# cannot change the digest and a moved vertex must.
INWIN_MD5_SQL="SELECT md5(string_agg(concat_ws('|', fire_number, fire_year, encode(ST_AsBinary(geom), 'hex')), ',' ORDER BY fire_number, fire_year, encode(ST_AsBinary(geom), 'hex'))) FROM $TABLE WHERE fire_year >= 2017"

n_prior="$(q "SELECT count(*) FROM $TABLE WHERE fire_year < 2017")"
n_inwin="$(q "SELECT count(*) FROM $TABLE WHERE fire_year >= 2017")"
md5_before="$(q "$INWIN_MD5_SQL")"
echo "before: $n_inwin rows >= 2017 (md5 $md5_before), $n_prior rows < 2017"

if [ "${DRY:-0}" = "1" ]; then echo "DRY=1: nothing loaded"; exit 0; fi
if [ "$n_prior" -gt 0 ]; then
  echo "REFUSED: $n_prior rows < 2017 already present -- this has run; a second append duplicates them" >&2
  exit 1
fi

# bcdata takes a URL; percent-encode the parts so a password with special characters survives
DATABASE_URL="$(python3 - <<'PY'
import os, urllib.parse as u
q = lambda k, d="": u.quote(os.environ.get(k, d), safe="")
print("postgresql://%s:%s@%s:%s/%s" % (q("PGUSER"), q("PGPASSWORD"), q("PGHOST"), q("PGPORT", "5432"), q("PGDATABASE")))
PY
)"
export DATABASE_URL
# bcdata logs the URL it connected with, password included; never let that reach a committed log
bcdata bc2pg "$LAYER" --append --query "$QUERY" 2>&1 | sed -E 's#postgresql://[^@]*@#postgresql://<redacted>@#g'

n_prior="$(q "SELECT count(*) FROM $TABLE WHERE fire_year < 2017")"
n_after="$(q "SELECT count(*) FROM $TABLE WHERE fire_year >= 2017")"
md5_after="$(q "$INWIN_MD5_SQL")"
echo "after:  $n_after rows >= 2017 (md5 $md5_after), $n_prior rows < 2017"
if [ "$md5_after" != "$md5_before" ] || [ "$n_after" != "$n_inwin" ]; then
  echo "FAIL: the in-window rows changed -- the published causes would move" >&2
  exit 1
fi
if [ "$n_prior" -eq 0 ]; then echo "FAIL: nothing < 2017 was loaded" >&2; exit 1; fi
echo "OK: in-window rows unchanged; prior fires by decade:"
q "SELECT (floor(fire_year / 10) * 10)::int AS decade, count(*) FROM $TABLE WHERE fire_year < 2017 GROUP BY 1 ORDER BY 1" \
  | sed 's/|/: /'
