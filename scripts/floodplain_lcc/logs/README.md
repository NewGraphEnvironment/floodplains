# logs

Committed **evidence logs** for the floodplain pipeline — dated benchmark/timing/coverage runs
that are R&D evidence (one per intentional run):

    yyyymmdd_noun_verb-detail_target.ext

e.g. `20260711_lulc_tile-benchmark_pcea.md`. Committed to the default branch so git carries the
provenance (the log sits next to the change that produced it) and it is discoverable cross-machine
via the GitHub API without cloning.

**Not** for bulk machine output — per-WSG region CSVs, aborted/offline reruns, and other
pipeline-emitted iteration dumps stay in the gitignored `data/logs/`. Rule of thumb: if you'd hand
it to an auditor as proof of an experiment, it lives here; if it's hundreds of files a pipeline
emitted, it stays under `data/`.
