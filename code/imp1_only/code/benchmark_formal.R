#!/usr/bin/env Rscript

all_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", all_args, value = TRUE)
project_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE))
for (module in c(
  "main_config.R", "main_randomization.R", "main_models.R", "main_storage.R"
)) source(file.path(project_dir, "R", module))

args <- commandArgs(trailingOnly = TRUE)
hit <- which(args == "--output-dir")
if (!length(hit) || hit[[1L]] == length(args)) stop("--output-dir PATH is required")
output_dir <- normalizePath(args[[hit[[1L]] + 1L]], mustWork = FALSE)
cfg <- load_main_config(file.path(project_dir, "config.json"))
fingerprint <- initialize_main_output(output_dir, cfg)
prepare_main_schedules(cfg, output_dir, 1L)

block <- readRDS(main_schedule_path(output_dir, 1L))
data <- block$data$setting_1
uniforms <- block$mask_uniforms$setting_1
seeds <- block$learner_seeds$setting_1
full_variances <- unbiased_feature_variances(data$X)
full_means <- colMeans(data$X)
hard_full <- which(full_variances > cfg$simulation$variance_threshold)
deleted_variances <- leave_one_out_feature_variances(
  full_variances, full_means, data$X[1L, ], nrow(data$X)
)
deleted_data <- data
deleted_data$X <- data$X[-1L, , drop = FALSE]
deleted_data$y <- data$y[-1L]
deleted_data$mu <- data$mu[-1L]

ensure_main_screening_audit(data, uniforms, cfg, 1L, 1L, output_dir)
specs <- build_main_method_specs(cfg)
selected_ids <- c(
  "all_features", "hard_screening", "soft1_nu_0.025", "soft2_nu_0.025"
)
selected <- specs[vapply(specs, function(x) x$id %in% selected_ids, logical(1))]
timings <- list()
pred_dir <- file.path(output_dir, "benchmark")
dir.create(pred_dir, recursive = TRUE, showWarnings = FALSE)
cursor <- 0L
for (spec in selected) {
  for (variant in c("full", "delete_1")) {
    message("Benchmarking ", spec$id, " / ", variant)
    gc()
    elapsed <- system.time({
      prediction <- if (variant == "full") {
        predict_main_method(spec, data, full_variances, hard_full, uniforms, seeds, cfg)
      } else {
        predict_main_method(spec, deleted_data, deleted_variances, hard_full, uniforms, seeds, cfg)
      }
    })[["elapsed"]]
    pred_path <- file.path(pred_dir, paste0(spec$id, "_", variant, "_prediction.rds"))
    main_atomic_save_rds(prediction, pred_path)
    cursor <- cursor + 1L
    timings[[cursor]] <- data.frame(
      method_id = spec$id,
      variant = variant,
      elapsed_seconds = elapsed,
      prediction_count = length(prediction),
      prediction_file_bytes = file.info(pred_path)$size,
      stringsAsFactors = FALSE
    )
  }
}
timing <- do.call(rbind, timings)
main_atomic_write_csv(timing, file.path(output_dir, "timing_benchmark.csv"))

means <- tapply(timing$elapsed_seconds, timing$method_id, mean)
per_variant <- unname(
  means[["all_features"]] + 2 * means[["hard_screening"]] +
  3 * means[["soft1_nu_0.025"]] + 3 * means[["soft2_nu_0.025"]]
)
total_seconds <- 4 * cfg$simulation$replicates * (cfg$simulation$n + 1) * per_variant
schedule_size <- file.info(main_schedule_path(output_dir, 1L))$size
audit_size <- file.info(main_screening_audit_path(output_dir, 1L, 1L))$size
estimate <- list(
  created_at_utc = main_utc_timestamp(),
  config_fingerprint = fingerprint,
  benchmark_setting = 1L,
  benchmark_replicate = 1L,
  benchmark_deletion = 1L,
  method_family_mean_seconds = as.list(means),
  estimated_seconds_per_full_or_loo_across_nine_methods = per_variant,
  estimated_single_worker_total_hours = total_seconds / 3600,
  caveat = "Linear extrapolation from four representative method families; actual runtime changes with masks, selected dimensions, OS load, cooling, and checkpoint overhead.",
  measured_one_replicate_schedule_bytes = schedule_size,
  projected_ten_schedule_bytes = 10 * schedule_size,
  measured_one_setting_replicate_screening_audit_bytes = audit_size,
  projected_forty_screening_audit_bytes = 40 * audit_size
)
main_atomic_write_json(estimate, file.path(output_dir, "resource_estimate.json"))
cat(jsonlite::toJSON(estimate, auto_unbox = TRUE, pretty = TRUE), "\n")
