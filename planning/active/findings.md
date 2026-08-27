# Findings — Add a columbia region (KOTL/LARL/SLOC) (#36)

## Species resolution — verified, not assumed

`fresh.streams_vw_bcfp`, `stream_order >= 3`:

| WSG | network km | `access_bt` km | `access_wct` km | group ha |
|---|---|---|---|---|
| KOTL | 2,829 | 1,920 | 2,037 | 936,950 |
| LARL | 2,277 | 1,093 | 959 | 661,226 |
| SLOC | 1,317 | 684 | 597 | 343,097 |

Reproduces the issue's table exactly (1,941,273 ha total).

**Correction to the issue:** `access_ch/co/st/salmon` are **`-9`**, not NULL — a sentinel meaning
"not modelled", not a missing value. Behaviour is identical (`IN (1,2)` excludes it either way),
but the NULL framing would send the next person looking for the wrong thing. `access_bt` and
`access_wct` take only `{0,1,2}` here, so the pre-pass's `IN (1,2)` and the issue's `> 0` agree.

**`wct` never fires.** `run_region.R`'s pre-pass takes the *first* species in the preference list
with any access, not the one with the most. `access_bt > 0` in all three groups, so bull trout
always wins — including KOTL, where wct has the longer accessible network (2,037 vs 1,920 km).
Listing `[bt, wct]` documents the fallback; it does not make wct a live second choice. Adding wct
later means a second region file with the same `region:` label (the `skeena_ch.yml` pattern) on
the #23 coexistence machinery.

link models both species in all three groups — `wsg_species_presence.csv` flags `bt` and `wct`
`t` for KOTL/LARL/SLOC; both are in `dimensions.csv`. `01_network_extract.R`'s `^[a-z]{2,4}$`
species guard passes `bt`.

## GRAB, not BUILD — and why the freshness guard needs `warn`

The plan assumed a BUILD: at exploration time `fresh_default` had **zero** rows for these groups.
That was a race — the link builds landed minutes later (link **0.45.1**, config `default`,
`date_end` 14:52–14:58 on 2026-08-27). `fresh_default` now carries all three, so step 1 can GRAB
and skip the pipeline entirely.

The catch: `fp_network`'s freshness guard compares grabbed km against the bcfp reference view and
stops at >2% divergence. Columbia sits at **LARL +1.8% / KOTL +2.5% / SLOC +6.6%** — two of three
would fail a strict guard.

Checked whether that signals a real problem, across **all 49 groups** present in both schemas
(`access_bt`, order >= 3):

| statistic | pct dev (fresh_default vs bcfp) |
|---|---|
| min | −15.5% (USKE) |
| 1st quartile | +0.1% |
| median | **+0.7%** |
| 3rd quartile | **+2.6%** |
| max | +161.2% (CHES) |

So the divergence is **systematic and expected** — the `default` bundle leaves `subsurfaceflow`
off as a natural barrier where `bcfishpass` opts it in, making default generally the more
permissive of the two — and the **2% strict tolerance is calibrated tighter than the observed
spread**: a quarter of all groups would trip it against a perfectly fresh source. Columbia is
unremarkable within that distribution. `network_guard: warn` is the documented setting for "the
divergence is expected and understood", and the override is recorded in the `lnk_stamp` sidecar.

`run_region.R` wrote neither `network_source` nor `network_guard` into the `area.yml` it
generates, so a region could only ever BUILD. Env vars (`FP_NETWORK_SOURCE`/`FP_NETWORK_GUARD`)
would work for one run but leave the choice unreproducible — and `run_region.R` rewrites
`area.yml` on every invocation, so a hand-edited value gets clobbered. Hence the pass-through.

## Disturbance overlays already cover the Columbia

No `config/disturbance.yml` change needed:

| source | KOTL | LARL | SLOC |
|---|---|---|---|
| fire (all years) | 69 / 82,323 ha | 68 / 52,360 ha | 51 / 51,633 ha |
| cutblocks (loaded >= 2017) | 1,727 / 23,826 ha | 2,066 / 24,322 ha | 333 / 3,043 ha |

The SLOC cutblock figure reads low against the issue's Slocan-valley number (1,262 blocks /
15,721 ha) because the fwapg load is filtered `HARVEST_START_YEAR_CALENDAR >= 2017` while the
issue's is all-time. Not a discrepancy.

## Publish side needs no code change

`stac_floodplains_bc/scripts/01_stage.R:39` globs `config/regions/*.yml` for its WSG→region
roster and has no hardcoded region names, and `05_stac_register.py:203` derives the collection's
spatial extent from the union of item bboxes. A new region file is picked up and the extent
extends south automatically.

## Provenance: strong on the producer side, absent from the STAC

link 0.45.1 writes a provenance record into the persist schema beside the data — `log` (one row
per run, keyed `watershed_group_code`, so it joins straight to `streams`), `log_parameters_fresh`
and `log_dimensions` (full CSV rows keyed `config_hash`, so N groups sharing a config store one
parameter set), and `log_input` (input vintages). Readable via `lnk_log_read()` or plain SQL with
no link install. Our three groups: `link_version` 0.45.1, `config_name` default; KOTL and SLOC
share `config_hash` `sha256:3cfde7b…` while LARL logged `sha256:44e452e…` (a mid-sequence working
tree edit under `LNK_LOAD=loadall`, proven input-identical by diffing the two hashes' snapshot
rows). Absence of a `log` row means pre-provenance vintage (before v0.45.0), not an error.

floodplains additionally writes an `aquatic_network_<sp><order>.stamp.md` sidecar per network.

**None of this reaches the STAC.** Item properties are the item key (`wsg`/`species`/`scenario`),
`region`, `flood_factor`, the three floodplain areas, loss/gain/net, and the projection
extension — no `link_version`, no `config_hash`, no run date. That gap is floodplains#33
(producer) + stac#17 (publisher), both open. The new log tables make them substantially cheaper:
three scalar properties joinable from the DB at stage time on a key the items already carry.
Out of scope here — recorded so #33/stac#17 can be re-scoped against it.

## Related issues — what this run changes for each

| issue | relevance | what Columbia changes |
|---|---|---|
| **floodplains#36** | this work | closes it |
| **stac#6** — carry disturbance attribution into the STAC schema | **direct** | Its "current upstream state" says *"Only BULK and MORR have either; the other 15 groups have neither."* `config/disturbance.yml` is present, so KOTL/LARL/SLOC get `_disturbance` layers natively — coverage moves **2 of 17 → 5 of 20**. Still gated on uniformity (#35), but both numbers in the gate move. |
| **floodplains#35** — pest as a third source, re-run across all areas | **direct** | Title literally encodes *"(2 of 17 today)"* → becomes **5 of 20**, and the re-run scope grows by three groups. |
| **floodplains#33** ↔ **stac#17** — run provenance | **direct** | link 0.45.1's `log` / `log_parameters_fresh` / `log_dimensions` / `log_input` tables now exist, keyed `watershed_group_code`. Three scalar properties (`link_version`, `config_hash`, `date_end`) are joinable at stage time on a key the items already carry — no new producer plumbing. Also: `lnk_stamp` stamps the **working-tree** config, so on a GRAB run the sidecar is aspirational and the DB log is the only authoritative record. That is an accuracy bug in the stamp, not just a missing feature. |
| **stac#19** — versioned catalogue releases | **moderate** | This release changes the collection's **spatial extent** (north-only → statewide-south past 49.5 N). That is exactly the class of change a version stamp + NEWS entry exists to record for consumers with cached extent assumptions. |
| **floodplains#3** — scale to multi-WSG + publish (pilot: Fraser) | **closing** | Columbia is the fourth region; the umbrella is fully delivered at 20 items. Close-or-rescope. |
| **floodplains#20** — transition params as config | **weak but real** | KOTL's floodplain is **65.6% open water** (Kootenay Lake). Fixed `patch_area_min` / class handling tuned on river-dominated groups may not suit lake-dominated ones. |

### New issues filed from this work

1. **#37 — GRAB freshness tolerance is mis-calibrated.** `fp_network`'s guard defaults to 2% against the
   bcfp reference, but across all 49 groups in both schemas the `default` bundle runs a median
   **+0.7%** over bcfp with an IQR of +0.1–2.6% and a range of −15.5% to +161%. A quarter of all
   groups would trip a strict guard against a perfectly fresh source, so every region adopting
   GRAB will need `warn` — which blunts the guard everywhere rather than fixing it. Wants either a
   calibrated default, a per-group expected-divergence baseline, or comparison against the source
   schema's own log rather than bcfp.
2. **#38 — Loss figures need a treed-area denominator.** KOTL is 14.8% trees and 65.6% water; SLOC will
   be river-dominated. Raw `gross_loss_ha` compared across groups is misleading — loss as a share
   of treed floodplain is the honest cross-group statistic. Touches stac#6's property design.

## Blocker for stac#6: the same layer name carries three different schemas

stac#6 documents attribution as living in a sibling layer:
`transition_<sp>_<scenario>_2017_2023_disturbance`. That is the shape produced by the
**`fire_tag.R` CLI wrapper**, which retro-tags an existing gpkg. It is not what the pipeline
produces natively — `03_lulc_classify.R` writes the attribution columns **onto** the plain
transition layer. Verified across the corpus:

| group | how tagged | `transition_<sp>_<sc>_2017_2023` | siblings |
|---|---|---|---|
| BULK, MORR | retro-tagged via `fire_tag.R` | `in_fire` only — **no `in_harvest`** | `_fire` (prototype), `_disturbance` (fire + harvest) |
| KOTL, LARL, SLOC | native (`disturbance.yml` present at run time) | `in_fire` **and** `in_harvest` | none |

So the plain `transition_*` layer means **fire-only** in BULK/MORR and **fire + harvest** in
Columbia — a silent schema divergence under an identical layer name. Neither read rule works
across the catalogue:

- read `transition_*` → Columbia has harvest, BULK/MORR silently do not
- read `*_disturbance` → BULK/MORR resolve, Columbia has no such layer

This is a harder blocker for stac#6 than the coverage count it currently tracks: a consumer
joining across groups on the layer name gets a column that exists for some groups and is absent
for others, with no error. It also widens #35's cleanup — the problem is not just retiring the
`_fire` prototype, it is that three generations coexist and the newest one changed where the
attributes live without changing the layer name.

Cleanest resolution is for the retro-tag path to converge on the native shape (attributes on the
transition layer, no sibling) and for #35's re-run to regenerate BULK/MORR natively, leaving one
shape everywhere.

## Attribution, area-weighted on tree loss (the comparable statistic)

| group | tree loss ha | fire | harvest | residual |
|---|---|---|---|---|
| KOTL | 641.7 | 3.0% | 33.4% | 63.7% |
| LARL | 204.5 | 8.9% | 21.2% | 72.4% |
| BULK (baseline) | 2,073.3 | 5.0% | 35.6% | 62.0% |

KOTL tracks the BULK baseline closely; LARL is more fire-weighted and less harvest-driven. Neither
is anomalous, so the attribution is behaving on a region it has never seen.
