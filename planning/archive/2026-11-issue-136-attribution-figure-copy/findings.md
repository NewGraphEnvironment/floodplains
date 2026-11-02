# Findings — fig/attribution.png: the subtitle is written for the analyst, not the reader (#136)

## Issue context

`fig/attribution.png` carries the subtitle "fire and harvest are the causes config/disturbance.yml
lists today — it takes any layer". The company site shows this figure on its Open Source page, where
the caption already says what the figure is ("Floodplain tree loss 2017–2023 in the Bulkley watershed
group, by attributed cause"), so the in-plot subtitle reads as config notes to a visitor.

Suggest the figure carry a plain title only (or none) and leave the explanation to whatever text sits
beside it. Found 2026-10-17 while reviewing the site's figures.

## Exploration (2026-11-02)

- `fp_fig_attribution()` (`scripts/readme_functions.R`) sets two subtitles: the map's "every patch
  the model found, coloured by what it can be attributed to today" and the bar's derived
  "<sources> are the causes config/disturbance.yml lists today — it takes any layer".
- `fig/attribution.png` was last committed in 7023066 (#95, 2026-09-28); #53's backfill (17df5e0)
  did not rebuild it. The committed bar reads fire 66 ha 4% / harvest 474 ha 30% / not yet
  attributed 1025 ha 66%.
- `index.html` is `self_contained` and embeds the PNG as base64, so it must be re-rendered.
- m4 holds no `data/bulk/` gpkgs; m1 does (floodplain.gpkg and floodplain_landcover.gpkg dated
  2026-10-18, subbasins.gpkg 2026-10-14).

## Errors Encountered

| Error | Resolution |
|-------|------------|
