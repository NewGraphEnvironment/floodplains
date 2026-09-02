# Findings — Verify #33's provenance block against a live database (#63)

## Issue context

#33 shipped the per-area provenance block (PR #62). Its first acceptance criterion had two halves;
the offline half was fully exercised (31 guard assertions each shown able to fail, a live-STAC A/B,
a producer/guard key-drift check verified red on a one-character typo). The half that needs a
database had never run.

#63 was filed on a **false premise** — "postgres is not running". It was running the whole time
(`fresh-db`, postgis, up 7 weeks, healthy on `0.0.0.0:5432`). The probe was wrong twice:
`pg_isready` with no `-h` tests the unix socket a containerised server never creates, and the `PG*`
vars live in `~/.Renviron`, which R reads and bash does not. Connecting properly closed most of the
issue and surfaced a genuine bug (`pq__text` aborting the provenance write, fixed in 2406548).

## Pre-flight, measured 2026-09-02 before any run

All read-only, from m1.

| fact | value |
|---|---|
| `fresh-db` | up 7 weeks (healthy), `0.0.0.0:5432`; `pg_isready -h localhost` = accepting connections |
| province-wide rebuild (the stated remaining blocker) | **finished** — 34 groups under `run_uid 20260901_234743-6628379d`, last `fresh.log` write 01:25:14Z, no R/link processes running |
| BULK log row | `run_uid 20260901_234743-6628379d`, `link_version 0.50.0`, `link_sha 689146867a5f00f94ec2e8085ddae36996e64379`, `link_dirty f`, 00:18:57Z → 00:27:25Z |
| freshness guard (BULK, access_co in (1,2), order ≥ 3) | grab **2205.70 km** vs `fresh.streams_vw_bcfp` **2205.57 km** = **0.006% dev** against a 2% tolerance |
| network stability across the rebuild | all **1915** `streams_co3` segments on disk are present in the rebuilt `fresh`; max `abs(length_metre)` diff = **0** |
| parity numbers off the pre-run outputs | **673.5 km / 142.8 km² / 770.0 ha** |
| `provenance.json` | **absent from every `data/<area>/`** — the A/B creates it from scratch, so this is a cold-path test |

### Parity measurement method (pins the three numbers)

```r
sum(as.numeric(st_length(streams_co3))) / 1000                        # 673.5 km
sum(as.numeric(st_area(co_ff04))) / 1e6                               # 142.8 km²
sum(area_ha[from_class == "Trees"])  # transition_co_ff04_2017_2023   # 770.0 ha
```

### m1 package state (pre-Phase-3)

| pkg | installed | RemoteSha | checkout | checkout SHA |
|---|---|---|---|---|
| link | 0.47.3 | – | 0.50.0 | 2b5a435 |
| flooded | 0.5.0 | – | 0.6.0 | 1eaaaa0 |
| drift | 0.8.0 | – | 0.10.0 | b61f002 |
| fresh | 0.33.0 | 7f12d99… | 0.33.0 | dc48ca4 |

All four checkouts clean (`--untracked-files=no`).

`fp_pkg_stamp` therefore reads `unresolved (checkout … is X, installed is Y)` for link, flooded and
drift, and resolves via `RemoteSha` for fresh. **Note the `fresh` row:** installed RemoteSha
7f12d99 ≠ checkout dc48ca4, but the *versions* match, so tier 2 (RemoteSha) answers first and the
mismatch is not visible in the stamp.

### m4 state (pre-Phase-4)

Reachable over tailscale (`100.66.235.69`), has `~/Projects/repo/floodplains`, and
`pg_isready -h 100.101.213.2` from m4 answers **accepting connections** — m1's `pg_hba.conf` ends
`host all all all scram-sha-256`, so a remote connection with credentials is allowed.

| item | m4 |
|---|---|
| floodplains | f0d6fb3 (issue #39 merge — pre-#33 entirely) |
| link / flooded / drift / fresh installed | 0.40.2 / **0.3.0** / 0.6.0 / 0.33.0 |
| checkouts | link 3ac4a24 (0.45.2), flooded 8d169ce (0.3.1), drift a34f0ea (0.7.0), fresh 7f12d99 (0.33.0) |
| `PG*` in `~/.Renviron` | **absent** |
| docker | daemon not running |

flooded **0.3.0** predates the 0.5.0 bankfull units fix, so an unaligned m4 run would differ by
~16% on the floodplain for a reason that has nothing to do with provenance determinism.

Two probe traps met on m4 and worth recording: a non-login `ssh` shell has neither `psql` nor
`pg_isready` on `PATH` (both are under `/opt/homebrew/bin`, added by the login profile), so the
first probe reported them missing when they are installed. `bash -lc` is the fix.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `psql: ERROR: function round(double precision, integer) does not exist` | `length_metre` is `double precision`; cast before rounding — `sum(length_metre)::numeric/1000.0` |
| `ssh m4 'pg_isready'` → `command not found` | Non-login shell has no `/opt/homebrew/bin`; use `ssh m4 'bash -lc "…"'` |
