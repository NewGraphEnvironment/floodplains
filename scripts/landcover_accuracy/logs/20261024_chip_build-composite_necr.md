# Chip build on the `all_ff04` draw: NECR (#148)

**Run:** 2026-10-23 22:18 UTC to 2026-10-24 08:23 UTC · `chip_build-composite.R necr` · windows from
`reference/necr/windows.csv` (2017 `8-9`, 2018 / 2020 / 2023 `8`, scenario `all_ff04`)

The redraw moved every point, so every chip was a cold fetch.

- **One process, then four.** The single process ran at about 73 s a chip, against 31.5 s on 2026-09-30.
  It was stopped at 22:51 UTC with 27 chips cached. The build was then run as four processes, one window
  each, every one given a one-row copy of `windows.csv` through `WINDOWS=`, which goes through the same
  scenario guard as the committed file (`fp_acc_windows_read`).

  | window | chips | missing | min |
  |---|---:|---:|---:|
  | 2017 Aug–Sep | 479 | 1 | 174.7 |
  | 2018 Aug | 480 | 0 | 207.6 |
  | 2020 Aug | 480 | 0 | 174.6 |
  | 2023 Aug | 478 | 2 | 560.4 |

- **Three chips failed, each on a transient error,** and drift cached none of them:
  `16_00030` 2017 and `1_00025` 2023 on the STAC "HTTP content type response 'text/plain'" error, and
  `19_00001` 2023 refused by drift's chunk check ("gdalcubes could not read 1 of 1 chunk").
- **The full pass** (`chip_build-composite.R necr`, all four windows) fetched the three and wrote the
  manifest and the VRTs: **1,920 chips (0 missing) for 480 points x 4 windows in 6.0 min**. The manifest's
  points equal `sample.gpkg`'s, four windows each.
- **`grep -c repoprted`:** 0 in the 2017, 2018 and 2020 logs and in the full pass. **1 in the 2023 log**,
  for point `32_00004`, which drift did not refuse: its `chunk_status` recorded no failure, so the per-chunk check does not see every failed read (drift#87).
  The chip was moved aside and fetched again
  with no warning, and the two are identical (0 of 11,907 cells differ). The pass after that wrote
  1,920 chips, 0 missing, in 2.8 min.
- **NA share per chip** (bands x cells): the median is 0 in every window. The maximum is 1.0% (2017),
  8.1% (2018, the one chip over 5%), 1.1% (2020) and 0 (2023).

Review projects A (480 points) and B (75) were rebuilt on these chips. Both carry the four S2 layers, each
with its own map theme, and 0 labels.
