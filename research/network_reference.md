# Network reference tables in fwapg

**Verified:** 2026-10-22 · **Issues:** #14, #37 (GRAB freshness guard), #65 (`link_config_name`), #76 ·
**Produced by:** `psql` against the local fwapg (queries below).

The pipeline checks link's networks against two tables it does not build. One is not what its name
says and carries no load date; the other names a different link config from the one 01 used to
record.

## `fresh.streams_vw_bcfp` is a table, not a view

Despite the `_vw_` in its name, `information_schema.tables` reports it as a `BASE TABLE`: a
separately loaded snapshot of upstream bcfishpass. It holds **4,272,394 rows over 188 watershed
groups**, against link's 98 in `fresh.streams` and 241 in `fresh_default.streams`.

It carries **no load date**: no table comment and no load column. `pg_stat_user_tables.last_autoanalyze`
is when Postgres last sampled the table, not when it was loaded. So when a group's network diverges
from it, the database alone cannot say whether link or the snapshot's vintage moved. That is why
#76's PINE shortfall (10.8% on the bull-trout accessible network) could not be diagnosed from the
database. In whole-network mode PINE matches it to the km (`config/regions/peace.yml`).

It is the reference for 01's GRAB freshness guard, `run_region.R`'s species pre-pass,
`floodplain_probe-report.R`'s habitat-by-order table, and the per-group km comparisons in
`config/regions/*.yml`.

## `fresh.log` says `bcfishpass` on every row

| schema | `config_name` | rows | groups | distinct `config_hash` |
|---|---|---:|---:|---:|
| `fresh` | `bcfishpass` | 65 | 39 | 1 |
| `fresh_default` | `default` | 246 | 241 | 4 |

So every area that GRABs from `fresh` ran under link's `bcfishpass` config, never `default`. Before
#65, 01 recorded the literal `default` on every GRAB, and the error was fleet-wide rather than one
area's. `link_config_name` is now read from the log row (the #65 bullet in `CLAUDE.md`).

## Queries

```sql
select table_type from information_schema.tables
 where table_schema = 'fresh' and table_name = 'streams_vw_bcfp';
select count(*), count(distinct watershed_group_code) from fresh.streams_vw_bcfp;
select obj_description('fresh.streams_vw_bcfp'::regclass);
select config_name, count(*), count(distinct config_hash), count(distinct watershed_group_code)
  from fresh.log group by 1;          -- and fresh_default.log
select count(distinct watershed_group_code) from fresh.streams;   -- and fresh_default.streams
```
