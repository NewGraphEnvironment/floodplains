## Outcome

Added a `columbia` region (KOTL, LARL, SLOC — 1,941,273 ha) with **bull trout** as the target
species, ran the full pipeline, and published: **20 items live**, with the STAC collection's
spatial extent moving from 52.71 N to **48.99 N**. The issue's real acceptance test — a Nelson-area
bbox search that previously returned nothing — now returns `larl_bt_ff04` + `kotl_bt_ff04`.
Results at `bt_ff04`: KOTL 707.8 km² / LARL 306.9 / SLOC 129.6; classified coverage 101–104% of
the delineated floodplain, so the large-AOI scaling failure class did not recur even on KOTL at
936,950 ha (the largest group run to date).

The premise held — this was a configuration gap, not a capability one — but four things were only
true because they were checked rather than assumed. (1) The issue described `access_ch/co/st/salmon`
as NULL; they are `-9`, a "not modelled" sentinel. Same behaviour, wrong mental model. (2) The
issue expected the `[bt, wct]` preference to let wct win in KOTL; the pre-pass resolves
**first-modelled, not best-modelled**, so wct can never fire there — documented in `columbia.yml`
rather than silently accepted. (3) `fresh_default` gained all three groups *during* exploration,
turning a multi-hour BUILD into a seconds-long GRAB — but the freshness guard then failed two of
three groups, and checking across all 49 groups in both schemas showed the 2% tolerance is simply
tighter than the real default-vs-bcfp spread (median +0.7%, IQR to +2.6%), i.e. it fires on config
difference rather than staleness → **#37**. (4) SLOC came back 99% unattributed, which looks like a
broken run until you check: only 4.6 ha of 2017–2023 cutblock falls inside its floodplain, because
Slocan valley-bottom harvest peaked in the 1980s. The attribution was correctly reporting a real
absence.

Two issues filed from the work: **#37** (guard calibration) and **#38** (loss needs a treed-area
denominator — the Columbia floodplains are 61–74% open water, so raw hectares are not comparable
across groups). One blocker recorded for **stac#6**: the same transition layer name now carries
three different schemas — retro-tagged groups (BULK/MORR) have `in_fire` only on the plain layer
with attribution in a `_disturbance` sibling, while natively-generated groups carry `in_fire` +
`in_harvest` on the plain layer and no sibling. Neither read rule works across the catalogue.

One code change, deliberately small: `run_region.R` now carries `network_source` / `network_guard`
from the region file into each generated `area.yml`, because it rewrites `area.yml` on every
invocation (so hand-edits don't survive) and the `FP_NETWORK_*` env overrides leave the choice
unreproducible. Verified backward-compatible — a DRY `peace` run regenerates its configs
byte-identically.

Also corrected long-standing README drift found along the way: "17 watershed groups" was counting
items rather than groups *and* omitting BOWR and MCGR, which had been publishing unnoticed.

Closed by: PR (branch `36-add-a-columbia-region-kotl-larl-sloc-bul`)
