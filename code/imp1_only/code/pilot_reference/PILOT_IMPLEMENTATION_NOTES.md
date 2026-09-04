# Historical pilot implementation notes

This file documents the preserved pilot code. For the current folder map and
the changes required by the main study, read `README.md` first. The completed
pilot outputs remain in `../outputs/`; commands below use paths relative to
`StartingCode` and will create new local outputs unless another output path is
given explicitly.

# Mean-square stability pilot

This directory contains the reproducible pilot for comparing:

1. a random forest using all features;
2. hard variance screening followed by a random forest;
3. frozen hard screening (the full-data selected set is reused after deletion);
4. soft screening implementation 1: each soft mask receives a 250-tree forest;
5. soft screening implementation 2: every one of the 250 randomized trees receives its own soft mask.

The default configuration is the agreed reduced pilot: `R=10`, `n=200`, `p=50`, 5,000 independent test covariate vectors, threshold 1, 250 trees, every one of the 200 deletions, and `nu=0.005,0.025,0.1`. The code never tunes `M` or the tree count. Implementation 1 uses `M=25`; implementation 2 always has exactly one mask per tree, so `M=T=250`.

The configuration records `algorithm_version=soft2_padded_v1`, so checkpoints
from a different implementation cannot be silently reused.

## Pilot design

Each dataset has independent features `X_j ~ N(0,1)`, so the population
variance of every feature equals the screening threshold. The response is the
nonlinear regression function

```text
sqrt(2 / (1 - exp(-2))) sin(X1) + X2 X3
  + (X4^2 - 1) / sqrt(2) + 2 I(X5 > 0) - 1
```

plus independent Gaussian noise with variance 2. The first five features are
signal features and the other 45 are noise features. Screening uses the
unbiased sample variance. The soft inclusion probability is
`q_j = expit((sample_variance_j - 1) / nu)`. An empty sampled mask uses the
training-response mean.

Every forest uses bootstrap samples, variance (squared-error) splitting,
unrestricted depth, minimum node size 5, and
`mtry(d) = max(1, floor(d / 3))`, where `d` is the number of screened features.
These settings are fixed and are not retuned for any leave-one-out dataset.
Implementation 1 fits 250 trees *per mask*, so its `M=25` ensemble contains
6,250 fitted trees in total.

Implementation 2 has 250 active trees and one independently sampled global
feature mask for each tree. To avoid 250 separate `ranger` calls, trees are
batched by their mask-specific `mtry` value. Every batch retains all 250 tree
slots: an active slot uses that tree's global mask, while inactive slots use
constant dummy features and their predictions are discarded. Consequently,
tree `b` remains slot `b` even if deleting an observation changes its mask size
and moves it to another `mtry` batch. These dummy root-only trees are an
implementation device and are not part of the reported 250-tree ensemble.

## Setup

From this directory:

```sh
Rscript install_dependencies.R
```

The installer puts `ranger` and any missing supporting packages in the local `Rlib/` directory. It does not modify a system R library.

## Quick verification

Run the small smoke configuration before attempting the pilot:

```sh
Rscript run_pilot.R --smoke --output-dir outputs/smoke
```

Smoke mode uses one `n=20`, `p=6` dataset, 50 test samples, three trees, two mask counts, one value of `nu`, and still evaluates every deletion. It is only an implementation check; it is not a scientific result.

Run the agreed pilot with:

```sh
Rscript run_pilot.R --config config.json --output-dir outputs/pilot --workers 10
```

The earlier six-value, `M=25,50,100` run was paused and preserved under
`outputs/pilot_original_grid_paused/`. Its incomplete soft-screening rows are
retained for provenance and are not part of the reduced pilot.

The `--workers` option parallelizes independent replicates. Each random forest
still uses one thread, avoiding nested parallelism. On macOS/Linux, ten workers
run the ten pilot replicates concurrently; use a smaller value if other work
needs the machine.

The run resumes automatically. Each full-data fit and each method/deletion contribution is saved atomically below `outputs/pilot/checkpoints/`. Repeating the command skips completed work. Prefer the single-command `--workers` interface for parallel runs. Do not run multiple independent commands against the same output directory concurrently, because their reporting-table aggregation can race even though replicate checkpoints are disjoint.

Use `--force` only to recompute the requested tasks. It does not delete other checkpoints. Use `--aggregate-only` to rebuild tables from completed checkpoints without fitting models.

### Cooperative pause and resume

Keep the `run_pilot.R` process running and request a checkpoint-safe pause from
another terminal:

```sh
Rscript pilot_control.R pause --output-dir outputs/pilot
Rscript pilot_control.R status --output-dir outputs/pilot
Rscript pilot_control.R resume --output-dir outputs/pilot
```

A pause request does not interrupt a forest fit. Each replicate worker finishes
the full-data or deletion checkpoint currently in progress, then writes a
per-replicate safe-point marker and waits. Waiting workers check the flag every
two seconds, so they consume negligible CPU. `status` reports whether a pause
has been requested, which replicate workers have reached a safe point, the
numbers of full-fit and deletion checkpoints, and the most recent checkpoint
time. After `resume`, the existing workers continue automatically; no pilot
command needs to be restarted.

The request flag and worker markers live under the chosen output directory and
are execution-control files only. They are not part of `config.json`, the
configuration fingerprint, model seeds, or reported results. Workers remove
their marker on resume and normal exit; `resume` also clears any stale marker.
If a pilot process was terminated rather than cooperatively paused, rerun the
same `run_pilot.R` command and it will continue from its atomic checkpoints.

The pause-control tests do not fit models or wait in real time:

```sh
Rscript tests/test_pause_control.R
```

## Outputs

- `config.resolved.json`: exact validated configuration for the run.
- `run_manifest.json`: configuration fingerprint, completion counts, package versions, and timestamps.
- `deletion_results.csv`: one row per replicate, deletion, method, and reported ensemble size.
- `dataset_results.csv`: the all-deletion mean-square stability for each replicate and method.
- `summary.csv`: mean and between-dataset standard deviation across completed replicates.
- `feature_hard_screening.csv`: feature-level full-data and leave-one-out
  unbiased variances, hard inclusion/exclusion, the frozen full-data decision,
  and whether the ordinary hard decision flipped. The full dataset uses
  `variant="full"` and `deletion_id=0`; deletion rows use
  `variant="delete"` and IDs 1 through `n`.
- `feature_soft_probabilities.csv`: feature-level inclusion probability `q`,
  masking probability `1-q`, and signed change from the full-data `q`, for
  every configured `nu`, full dataset, and deletion.
- `shared_mask_uniforms.csv`: the shared uniform `U` for every replicate,
  mask, and feature, with flags showing which masks are used by soft
  implementations 1 and 2.
- `checkpoints/`: resumable RDS records; these are implementation artifacts rather than reported results.

For the reduced pilot these three screening tables contain 100,500, 301,500,
and 125,000 rows, respectively. They are regenerated deterministically and
written atomically during aggregation; their filenames, row counts, and
reconstruction rule are recorded in `run_manifest.json`.

The binary mask for any soft procedure is reconstructed by joining the soft
probability and uniform tables on `replicate` and `feature_id`, selecting the
desired deletion, `nu`, and `mask_id`, and applying

```text
delta = as.integer(uniform_u <= inclusion_probability_q).
```

Implementation 1 uses rows whose `used_by_soft_implementation_1` flag is true;
implementation 2 uses rows whose `used_by_soft_implementation_2` flag is true.
If a future configuration reports several implementation-1 ensemble sizes,
the flag identifies masks used by at least one of them; additionally restrict
to `mask_id <= M` for a particular ensemble size. Per-deletion binary mask
matrices are deliberately not stored.

The hard rule is `hard_selected = (unbiased_variance > threshold)` and
`hard_screened_out = !hard_selected`; equality with the threshold is screened
out. `frozen_hard_selected` repeats the full-data hard decision for that
feature in every deletion row, while `flip_from_full` compares the ordinary
deletion-specific hard decision with the full-data decision.

### Screening-record histograms

The feature-level screening tables can be plotted without fitting or resuming
any random forests:

```sh
Rscript plot_screening_records.R \
  --input-dir outputs/pilot \
  --output-dir outputs/pilot/figures/screening \
  --bins 20
```

This writes two PNGs safely through temporary files:

- `full_data_soft_q_histograms.png` pools the 50 full-data feature
  probabilities from each selected replicate within each `nu` panel. The
  default 20 equal-width bins have width 0.05, the vertical dashed line marks
  `q=0.5`, and the vertical scale is percent within `nu`.
- `hard_selection_proportion_histograms.png` first computes, for every
  replicate-feature, the proportion selected across full `D` and all 200
  leave-one-out datasets. It pools those 500 proportions and facets them by
  the corresponding full-data selected status; the vertical scale is percent
  within status. The caption notes that the 201 variants entering each
  proportion are dependent.

Use `--replicates 1-5,8` to restrict and pool a subset of replicates, `--bins`
to change the equal-width bin count over `[0,1]`, and `--dpi` to change PNG
resolution. The reusable R function `plot_screening_record_histograms()` is
defined in `R/screening_visualization.R`; it invisibly returns both ggplot
objects, both plotting data frames, and the saved file paths. Run its focused
tests with:

```sh
Rscript tests/test_screening_visualization.R
```

After the pilot finishes, create analysis tables and figures with:

```sh
Rscript summarize_pilot.R outputs/pilot
```

This adds method-level and deletion-level summaries, hard-screening diagnostics,
and five PNG figures under `outputs/pilot/figures/`.

The reported deletion contribution is

```text
mean_k[(f_D(X_test,k) - f_D-minus-i(X_test,k))^2].
```

The dataset result averages this over all `n` deletions. Test responses are unnecessary for stability. Prediction risk is also reported against the known regression function `mu(X_test)`.

## Deterministic coupling

All random objects are derived from a stable hash of `master_seed` and semantic labels. For a given simulated dataset:

- the same forest seed is reused for the full data and every deletion;
- the same uniform mask array is reused across full data, all deletions, both soft implementations, and all values of `nu`;
- implementation 1 gives each mask-specific forest its own seed, reused for the full data and every deletion;
- implementation 2 uses one replicate-specific forest seed, shared across `nu`, full data, deletions, and `mtry` batches; `ranger` deterministically gives tree `b` the internal seed `b * forest_seed`, and padded batching keeps tree `b` in that slot throughout;
- `ranger` is run with one thread per fit to avoid scheduling-dependent changes.

Changing output location or resuming does not change the simulated data or fitted randomness.
