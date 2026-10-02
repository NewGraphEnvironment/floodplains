## Outcome

#103 added the earlier of two things #93's accuracy review was missing: what happened before the
change interval. It also added dated, sharp imagery to judge against.

`config/disturbance.yml` gained a third list, `lookback:`. `fire_prior` is fires from the 15 years
before the interval. Patches are tagged with it and it is reported beside the unattributed share,
never counted as a cause, because measurement showed it overlaps tree **loss** more than regrowth.
That needed the pre-2017 fires appended to fwapg (`fire_load-prior.sh`, md5-guarded).

The NECR accuracy sample was redrawn, before any label existed, with stratum 19 "change in prior
fire", decided at cell level.

Per point, `imagery.csv` records which orthophoto (private catalogue) and air photo epochs cover it.
The review project gained a warped-VRT orthophoto layer, a 2012 digital air photo layer, and map
themes ("Review" plus one per imagery layer). Film epochs wait for fly#53. `windows.csv` is
unchanged, because its rule was pre-registered. The research verdicts live in
[`research/landcover_accuracy.md`](../../../research/landcover_accuracy.md): "Strata" and "Dated
reference imagery".

Follow-ups filed:
- floodplains#104: whole floodplains with habitat tags, a user request.
- stac_floodplains_bc#6, body extended: lookback columns are context, not attribution.

A floodplains issue on promoting the lookback to a cause is **drafted in `findings.md`, not filed**.
The user asked to file it "once we understand", meaning once stratum 19 is labelled.

## Measurement

- **Prior fires.**
  - 21,186 rows were appended. The 3,565 in-window rows were unchanged, with md5
    `893d6cc4…` before and after.
  - NECR re-tag: 314 patches (506.4 ha) are `in_fire_prior`.
  - **242.8 of 886.3 ha (27%) of unattributed tree loss lies in a 2002–2016 fire.**
  - Inside those fires: Trees→Rangeland 282.5 ha, Rangeland→Trees 176.8 ha (by patch).
  - BULK: 3.6 ha.
  - 10- and 15-year lookbacks are identical in both areas.
  - **9 of 23 areas have no 2002–2016 fire** on their floodplain.
- **Stratum 19.**
  - 453.4 ha, taken from 8 strata: wetland change −192, Trees→Rangeland −94, Rangeland→Trees −143,
    and less from the others.
  - Strata that lost no cells kept every point, across drift 0.19 → 0.20, and the redraw is
    byte-reproducible.
- **Imagery.**
  - Orthophoto 2021 covers **204 of 480** points (42.5%) at 0.15 m. It is read from pixels. The
    footprints claimed 229, but 25 points sit on a tile's zero collar, which the code-check round 3
    enumeration measured.
  - Air photo 2012 (digital, DEM-sized) covers 480 of 480 points, with 250 of 250 frames
    georeferenced, at 4.43 m.
- **Wrong turn, kept.** The first air photo build lost 87 of 250 frames. I diagnosed it as a fly
  defect and filed fly#88. It was my caller error: I passed `fly_georef` the fetched sample
  without its roll neighbours, so the frames had no bearing, and I hid fly's warning with
  `suppressWarnings()`. Code-check round 1 traced it. fly#88 was corrected and withdrawn, and the
  fix took the build to 250 of 250.
- **Review spend.** 1 plan review plus 6 code-check rounds, 7 agents in all. Each round past the
  second found a real defect, two of them inside the previous round's fix (redaction missing bare
  hosts; a content check unable to see missing rows). A URL-egress enumeration ended the loop.

## Evidence

- `scripts/fwapg/logs/20261002_*` (the prior-fire append)
- `scripts/floodplain_lcc/logs/20261002_*` (the NECR re-tag and the live check)
- `scripts/landcover_accuracy/logs/20261002_*` (the redraw)
- code-check reports: `review-*.md` in this directory

**Re-chip done after archiving.** It produced 1,920 chips with 0 missing in 282 min. The final
`review_build-qgis.R necr` run added the four S2 layers, so the project now carries "Review" plus 6
imagery themes. Log: `scripts/landcover_accuracy/logs/20261002_chip_build-composite_necr.md`.

Closed by: the PR for branch `103-dated-orthophotos-and-air-photos-as-revi`
