# Main simulation: implementation handoff

This snapshot is used by `../start_or_resume.ps1` for the 2026-09-02 six-method
run (R=10, all four settings, no implementation 1). See `../README_CN.md` and
`../run_profile.json`. The generic config below still describes all nine
methods; use the dedicated launcher to pass the six-method scope explicitly.
Compared with v5, this snapshot uses load-balanced worker scheduling with a
worker log and adapts the figure panel-row count to the number of methods.

This directory starts the four-setting main study. The scientific source of
truth is `SimulationDesign.tex` / `SimulationDesign.pdf` from
`MultiStepStability.zip`. The files preserved from `StartingCode/` are pilot
scaffolding and must not be launched as the main study.

## What is implemented

- `config.json` records all prespecified scientific values, ten explicit and
  distinct replicate-block seeds, one coefficient seed, and the nine reporting
  procedures.
- `R/main_config.R` validates the main-study schema. It rejects changed forest,
  soft-screening, setting, and method values rather than silently accepting a
  pilot configuration.
- `R/main_randomization.R` implements all four DGPs, the one fixed dense
  coefficient vector, exact sharing of Settings 1/4 covariates, independent
  responses, setting-specific shared mask uniforms, and learner component
  seeds generated before fitting.
- `prepare_main.R` atomically saves resolved configuration, the fixed theta,
  and one complete randomization/data schedule per replicate.
- `tests/test_main_design.R` checks dimensions, deterministic replay,
  Settings-1/4 sharing, the uniform support, AR(1) covariance construction,
  mask/seed counts, and the fast LOO variance update.
- `preflight.R` reports R/platform/package readiness.
- `run_with_r460.ps1` invokes the requested R 4.6.0 and uses locale `C` to
  avoid the machine's invalid `C.UTF-8` startup setting.
- `R/main_models.R` connects the nine procedures to `ranger` while reusing the
  saved learner seeds in every full/LOO comparison.
- `R/main_storage.R` uses setting-aware atomic schedules, screening audits,
  and checkpoints.
- `R/main_runner.R` runs the full/LOO fits, resumes from existing checkpoints,
  and supports deterministic Windows PSOCK parallel workers.
- `R/main_results.R` and `summarize_main.R` create the deletion data,
  dataset-level estimates, 36-cell table, four histogram figures, four tail
  figures, plot data, manifest, and validation report.
- `BEGINNER_GUIDE_CN.md` explains the two implementation stages and the
  statistical workflow in Chinese without assuming prior simulation knowledge.

## Provenance from the pilot

The following pilot ideas are intended for direct reuse after adapting their
interfaces to `(setting, replicate)` and the saved schedules:

| Main-study need | Pilot source |
|---|---|
| unbiased variance and fast LOO update | `pilot_reference/R/dgp.R` |
| strict hard screen and soft probability | `pilot_reference/R/dgp.R` |
| fixed ranger settings and empty-mask fallback | `pilot_reference/R/models.R` |
| soft implementation 1 (25 forests x 250 trees) | `pilot_reference/R/models.R` |
| soft implementation 2 (250 masks, one active tree each) | `pilot_reference/R/models.R` |
| atomic checkpoints and configuration fingerprint | `pilot_reference/R/storage.R` |
| pause/resume boundaries | `pilot_reference/R/pause_control.R` |

The pilot's `R/seeds.R`, single Gaussian DGP, setting-free checkpoint keys,
screening-record regeneration, and pilot summaries must be replaced, as its
own README explicitly requires.

## Experiment outline

For each of 10 replicate blocks, create four datasets with `n=500`, `p=200`
and one matched `N_test=5000` sample per setting. Fit the nine methods on the
full data and all 500 leave-one-out datasets. Reuse each setting's saved mask
uniforms and learner seeds for every full/deleted pair. Save the 180,000
deletion perturbations, aggregate to 360 dataset-method estimates and 36
setting-method mean-(SD) cells, then create the prescribed replicate-1
histograms and empirical tail curves.

## Current commands

From this directory in PowerShell:

```powershell
.\run_with_r460.ps1 preflight.R
.\run_with_r460.ps1 tests\test_main_design.R
.\run_with_r460.ps1 run_main.R --smoke --workers 2 --output-dir outputs\main_smoke
```

## Add more Monte Carlo repetitions without recomputing old ones

The execution scope can be enlarged after a run. For example, a completed
`--replicates 1-4` run can be continued through replicate 10 by passing
`--replicates 1-10 --extend-scope` and keeping the same output folder.

`--extend-scope` is deliberately append-only. Existing settings, replicates,
and methods must all remain in the new scope. Valid checkpoints are skipped,
so only newly added work is fitted and the summaries are rebuilt afterward.
Do not use this option while another process is writing to the same output
folder. Changing the scientific configuration (for example `n`, `p`, tree
counts, seeds, or the DGP) changes its fingerprint and requires a new output
folder.

Repeating the same command resumes from existing checkpoints. To regenerate
only tables and plots, use:

```powershell
.\run_with_r460.ps1 summarize_main.R outputs\main_smoke
```

For a bounded formal work session, add `--max-hours 4`. Workers request a
shared pause at the deadline and exit before the next full or deletion fit;
the current single fit is allowed to finish so no checkpoint is corrupted.

Do not start the full command merely to test the code. The full design entails
roughly 405.8 million fitted tree components across all full and LOO fits. Read
`BEGINNER_GUIDE_CN.md` and run a staged timing study before choosing the final
worker count and launching all 40 setting-replicate tasks.
