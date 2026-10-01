# chip_build-composite.R necr — 2026-09-30 to 2026-10-01

drift 0.20.0, `reference/necr/windows.csv`: 2017 `8-9`; 2018, 2020 and 2023 `8`. Chips are
true-colour (red/green/blue reflectance, FLT4S), 600 m squares around each of the 450 pilot points,
EPSG:3005, built with the default `cloud_cover_max = 20`. Run from a frozen copy of the script
under `caffeinate -s`, 18:31:01 UTC to 10:17:19 UTC.

- **1,800 chips, 0 missing**, in 946.2 min: 31.5 s a chip, against 44 s measured on 30 chips on
  2026-09-29.
- **drift#87 gate:** `grep -c repoprted` on the build log returned 0.
- **NA share per chip** (band 1):

  | year | chips | median | > 10% NA | > 50% NA | max |
  |---|---:|---:|---:|---:|---:|
  | 2017 | 450 | 0 | 0 | 0 | 0.010 |
  | 2018 | 450 | 0 | 0 | 0 | 0 |
  | 2020 | 450 | 0 | 0 | 0 | 0 |
  | 2023 | 450 | 0 | 0 | 0 | 0 |

- **One VRT per window-year** under `data/necr/accuracy/review/necr_lulc_review/chips/`, plus
  `manifest.csv`.
- **review_build-qgis.R** added the 4 "S2 same season_<year>" layers. Its first run aborted on
  `chip_rgb.qml`: a `--` inside the XML comment, invalid since that file was committed and never
  read until chips existed. It was fixed, and the abort left the `.qgs` byte-identical to before.
  A second build is byte-identical to the first, and `labels.gpkg` is unchanged (450 points).
  The layers were verified in the `.qgs` XML: `multibandcolor`, with a fixed 0–0.25 stretch.
