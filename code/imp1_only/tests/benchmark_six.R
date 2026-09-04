args <- commandArgs(FALSE)
test_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", args, value = TRUE)[[1]])))
run_root <- dirname(test_dir)
code <- file.path(run_root, "code")
for (f in c("main_config.R", "main_randomization.R", "main_models.R", "main_storage.R")) source(file.path(code, "R", f))
cfg <- load_main_config(file.path(code, "config.json"))
profile <- jsonlite::fromJSON(file.path(run_root, "run_profile.json"))
block <- generate_replicate_block(cfg, 1L, draw_dense_theta(cfg))
data <- block$data$setting_1
variances <- unbiased_feature_variances(data$X)
hard <- which(variances > cfg$simulation$variance_threshold)
deleted <- data
deleted$X <- data$X[-1L, , drop = FALSE]
deleted$y <- data$y[-1L]
deleted$mu <- data$mu[-1L]
deleted_v <- leave_one_out_feature_variances(variances, colMeans(data$X), data$X[1L, ], nrow(data$X))
specs <- Filter(function(s) s$id %in% profile$methods, build_main_method_specs(cfg))
rows <- list()
for (spec in specs) for (variant in c("full", "delete_1")) {
  message("Timing ", spec$id, " / ", variant)
  elapsed <- system.time(pred <- predict_main_method(
    spec, if (variant == "full") data else deleted,
    if (variant == "full") variances else deleted_v,
    hard, block$mask_uniforms$setting_1, block$learner_seeds$setting_1, cfg
  ))[["elapsed"]]
  stopifnot(length(pred) == 5000L, all(is.finite(pred)))
  rows[[length(rows) + 1L]] <- data.frame(method_id = spec$id, variant = variant, elapsed_seconds = elapsed)
}
timing <- do.call(rbind, rows)
write.csv(timing, file.path(test_dir, "six_method_timing.csv"), row.names = FALSE)
method_means <- tapply(timing$elapsed_seconds, timing$method_id, mean)
cpu_hours <- 4 * 10 * 501 * sum(method_means) / 3600
estimate <- list(
  measured_at = main_utc_timestamp(), setting = 1L, replicate = 1L,
  method_mean_seconds = as.list(method_means),
  estimated_single_worker_hours = cpu_hours,
  idealized_eight_worker_hours = cpu_hours / 8,
  caveat = "One full and one deleted fit per method; not a guarantee. Parallel contention, cooling, differing settings/masks, and I/O alter wall time."
)
main_atomic_write_json(estimate, file.path(test_dir, "timing_estimate.json"))
packages <- c("ranger", "data.table", "jsonlite", "digest", "ggplot2")
environment <- list(R = R.version.string, platform = R.version$platform, library_paths = .libPaths(),
  logical_cores = parallel::detectCores(), packages = as.list(setNames(vapply(packages,
    function(p) as.character(utils::packageVersion(p)), character(1)), packages)))
main_atomic_write_json(environment, file.path(test_dir, "environment.json"))
print(estimate)
