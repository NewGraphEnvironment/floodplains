# Progress — #93 windows + chips

## Session 2026-09-30

- Plan-mode exploration — phases approved by user ("go all phases")
- Created branch `93-lulc-accuracy-windows-chips` off main
- Scaffolded PWF baseline
- Phase 1: drift 0.19.0 -> 0.20.0 (pak); window rule (fp_acc_window_*) + derive + validate (c) +
  FORCE; accuracy-check arms (3 mutations each red); rule pre-registered alone in 9847d35 before
  `run` started
- validate passed; `run` launched 18:0x UTC from a frozen copy
- /code-check: 3 rounds + enumeration
- Phase 2: run 18:02–18:29 UTC, 49/49, 0 failed, 0 chunk-error lines. derive: span August,
  2017 widened to Aug–Sep (direct count 1.000); windows.csv regenerates byte-identical
- Phase 3: chip build launched from a frozen copy (~1,800 chips, ~22 h estimate)
