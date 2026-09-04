#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
smoke <- "--smoke" %in% args
option_value <- function(name) {
  hit <- which(args == name)
  if (!length(hit) || hit[[1L]] == length(args)) stop(name, " requires a value")
  args[[hit[[1L]] + 1L]]
}

six_dir <- normalizePath(option_value("--six-results"), mustWork = TRUE)
soft1_dir <- normalizePath(option_value("--soft1-results"), mustWork = TRUE)
output_dir <- normalizePath(option_value("--output-dir"), mustWork = FALSE)

expected <- if (smoke) list(
  source6_deletion = 120L, source6_dataset = 6L, source6_summary = 6L,
  source1_deletion = 60L, source1_dataset = 3L, source1_summary = 3L,
  combined_deletion = 180L, combined_dataset = 9L, combined_summary = 9L,
  deletions_per_cell = 20L, test_points = 50L, replicates_per_cell = 1L,
  implementation_pair_rows = 3L, implementation_comparison_rows = 3L,
  setting_ids = 1L, replicate_ids = 1L
) else list(
  source6_deletion = 120000L, source6_dataset = 240L, source6_summary = 24L,
  source1_deletion = 60000L, source1_dataset = 120L, source1_summary = 12L,
  combined_deletion = 180000L, combined_dataset = 360L, combined_summary = 36L,
  deletions_per_cell = 500L, test_points = 5000L, replicates_per_cell = 10L,
  implementation_pair_rows = 120L, implementation_comparison_rows = 12L,
  setting_ids = 1:4, replicate_ids = 1:10
)

for (package in c("data.table", "jsonlite", "digest", "ggplot2")) {
  if (!requireNamespace(package, quietly = TRUE)) stop("Package is required: ", package)
}

required_files <- c(
  "deletion_results.csv", "dataset_results.csv", "setting_method_summary.csv",
  "validation_report.json", "run_manifest.json", "config.resolved.json", "dense_theta.json"
)
for (directory in c(six_dir, soft1_dir)) {
  missing <- required_files[!file.exists(file.path(directory, required_files))]
  if (length(missing)) stop("Missing source file(s) in ", directory, ": ", paste(missing, collapse = ", "))
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
for (subdir in c("figures", "plot_data", "source_validation")) {
  dir.create(file.path(output_dir, subdir), recursive = TRUE, showWarnings = FALSE)
}

write_csv_atomic <- function(x, path) {
  temporary <- paste0(path, ".", Sys.getpid(), ".tmp")
  data.table::fwrite(x, temporary)
  if (file.exists(path)) file.remove(path)
  if (!file.rename(temporary, path)) stop("Could not publish: ", path)
}

write_json_atomic <- function(x, path) {
  temporary <- paste0(path, ".", Sys.getpid(), ".tmp")
  jsonlite::write_json(x, temporary, auto_unbox = TRUE, pretty = TRUE, digits = 17, null = "null")
  if (file.exists(path)) file.remove(path)
  if (!file.rename(temporary, path)) stop("Could not publish: ", path)
}

v6 <- jsonlite::read_json(file.path(six_dir, "validation_report.json"), simplifyVector = TRUE)
v1 <- jsonlite::read_json(file.path(soft1_dir, "validation_report.json"), simplifyVector = TRUE)
m6 <- jsonlite::read_json(file.path(six_dir, "run_manifest.json"), simplifyVector = TRUE)
m1 <- jsonlite::read_json(file.path(soft1_dir, "run_manifest.json"), simplifyVector = TRUE)

source6_ok <- isTRUE(v6$actual_deletion_rows == expected$source6_deletion) &&
  isTRUE(v6$actual_dataset_method_rows == expected$source6_dataset) &&
  isTRUE(v6$actual_setting_method_summary_rows == expected$source6_summary) &&
  isTRUE(v6$duplicate_deletion_keys == 0) &&
  isTRUE(v6$every_prediction_comparison_uses_n_test) &&
  isTRUE(v6$every_completed_cell_has_all_deletions)
source1_ok <- isTRUE(v1$actual_deletion_rows == expected$source1_deletion) &&
  isTRUE(v1$actual_dataset_method_rows == expected$source1_dataset) &&
  isTRUE(v1$actual_setting_method_summary_rows == expected$source1_summary) &&
  isTRUE(v1$duplicate_deletion_keys == 0) &&
  isTRUE(v1$every_prediction_comparison_uses_n_test) &&
  isTRUE(v1$every_completed_cell_has_all_deletions)
if (!source6_ok) stop("The six-method source failed strict validation")
if (!source1_ok) stop("The Soft implementation 1 source failed strict validation")
if (!identical(as.character(m6$config_fingerprint), as.character(m1$config_fingerprint))) {
  stop("The two runs have different configuration fingerprints")
}
if (!identical(
  digest::digest(file.path(six_dir, "dense_theta.json"), algo = "sha256", file = TRUE),
  digest::digest(file.path(soft1_dir, "dense_theta.json"), algo = "sha256", file = TRUE)
)) stop("The dense coefficient vectors differ between runs")

d6 <- data.table::fread(file.path(six_dir, "deletion_results.csv"))
d1 <- data.table::fread(file.path(soft1_dir, "deletion_results.csv"))
dataset6 <- data.table::fread(file.path(six_dir, "dataset_results.csv"))
dataset1 <- data.table::fread(file.path(soft1_dir, "dataset_results.csv"))

deletion <- data.table::rbindlist(list(d6, d1), use.names = TRUE, fill = TRUE)
dataset <- data.table::rbindlist(list(dataset6, dataset1), use.names = TRUE, fill = TRUE)
data.table::setorder(deletion, setting, replicate, method_order, deletion)
data.table::setorder(dataset, setting, replicate, method_order)

expected_methods <- c(
  "all_features", "hard_screening", "frozen_hard_screening",
  "soft1_nu_0.005", "soft1_nu_0.025", "soft1_nu_0.1",
  "soft2_nu_0.005", "soft2_nu_0.025", "soft2_nu_0.1"
)
deletion_key <- deletion[, .(setting, replicate, method_id, deletion)]
dataset_key <- dataset[, .(setting, replicate, method_id)]
duplicate_deletion_keys <- anyDuplicated(deletion_key)
duplicate_dataset_keys <- anyDuplicated(dataset_key)

summary <- dataset[all_deletions_complete == TRUE & !is.na(beta2_hat), .(
  method_order = method_order[[1L]],
  method_label = method_label[[1L]],
  method = method[[1L]],
  implementation = implementation[[1L]],
  nu = nu[[1L]],
  M = M[[1L]],
  T = T[[1L]],
  completed_replicates = .N,
  mean_beta2 = mean(beta2_hat),
  sd_beta2_between_replicates = stats::sd(beta2_hat)
), by = .(setting, method_id)]
data.table::setorder(summary, method_order, setting)

performance <- dataset[all_deletions_complete == TRUE & !is.na(beta2_hat), .(
  method_order = method_order[[1L]],
  method_label = method_label[[1L]],
  implementation = implementation[[1L]],
  nu = nu[[1L]],
  replicates = .N,
  mean_beta2 = mean(beta2_hat),
  sd_beta2_between_replicates = stats::sd(beta2_hat),
  mean_prediction_risk = mean(prediction_risk_full),
  sd_prediction_risk_between_replicates = stats::sd(prediction_risk_full)
), by = .(setting, method_id)]
data.table::setorder(performance, setting, method_order)

display <- data.table::copy(summary)
display[, value := sprintf("%.6g (%.6g)", mean_beta2, sd_beta2_between_replicates)]
display[, setting_column := paste0("Setting_", setting)]
stability_table <- data.table::dcast(
  display,
  method_order + method_id + method_label ~ setting_column,
  value.var = "value"
)
data.table::setorder(stability_table, method_order)

baseline <- performance[method_id == "all_features", .(
  setting,
  all_features_mean_beta2 = mean_beta2,
  all_features_mean_prediction_risk = mean_prediction_risk
)]
comparison_baseline <- merge(performance, baseline, by = "setting", all.x = TRUE)
comparison_baseline[, `:=`(
  beta2_ratio_to_all_features = mean_beta2 / all_features_mean_beta2,
  beta2_percent_change_vs_all_features = 100 * (mean_beta2 / all_features_mean_beta2 - 1),
  prediction_risk_ratio_to_all_features = mean_prediction_risk / all_features_mean_prediction_risk,
  prediction_risk_percent_change_vs_all_features =
    100 * (mean_prediction_risk / all_features_mean_prediction_risk - 1)
)]
data.table::setorder(comparison_baseline, setting, method_order)

pairs1 <- dataset[implementation == 1L, .(
  setting, replicate, nu,
  soft1_method_id = method_id,
  soft1_beta2 = beta2_hat,
  soft1_prediction_risk = prediction_risk_full
)]
pairs2 <- dataset[implementation == 2L, .(
  setting, replicate, nu,
  soft2_method_id = method_id,
  soft2_beta2 = beta2_hat,
  soft2_prediction_risk = prediction_risk_full
)]
implementation_pairs <- merge(pairs1, pairs2, by = c("setting", "replicate", "nu"), all = FALSE)
implementation_pairs[, `:=`(
  beta2_difference_soft1_minus_soft2 = soft1_beta2 - soft2_beta2,
  prediction_risk_difference_soft1_minus_soft2 = soft1_prediction_risk - soft2_prediction_risk,
  soft1_has_lower_beta2 = soft1_beta2 < soft2_beta2,
  soft1_has_lower_prediction_risk = soft1_prediction_risk < soft2_prediction_risk
)]
data.table::setorder(implementation_pairs, setting, nu, replicate)

implementation_comparison <- implementation_pairs[, .(
  paired_replicates = .N,
  mean_soft1_beta2 = mean(soft1_beta2),
  mean_soft2_beta2 = mean(soft2_beta2),
  mean_beta2_difference_soft1_minus_soft2 = mean(beta2_difference_soft1_minus_soft2),
  sd_paired_beta2_difference = stats::sd(beta2_difference_soft1_minus_soft2),
  proportion_replicates_soft1_lower_beta2 = mean(soft1_has_lower_beta2),
  mean_soft1_prediction_risk = mean(soft1_prediction_risk),
  mean_soft2_prediction_risk = mean(soft2_prediction_risk),
  mean_risk_difference_soft1_minus_soft2 = mean(prediction_risk_difference_soft1_minus_soft2),
  sd_paired_risk_difference = stats::sd(prediction_risk_difference_soft1_minus_soft2),
  proportion_replicates_soft1_lower_risk = mean(soft1_has_lower_prediction_risk)
), by = .(setting, nu)]
data.table::setorder(implementation_comparison, setting, nu)

write_csv_atomic(deletion, file.path(output_dir, "deletion_results.csv"))
write_csv_atomic(dataset, file.path(output_dir, "dataset_results.csv"))
write_csv_atomic(summary, file.path(output_dir, "setting_method_summary.csv"))
write_csv_atomic(stability_table, file.path(output_dir, "stability_table.csv"))
write_csv_atomic(performance, file.path(output_dir, "performance_summary.csv"))
write_csv_atomic(comparison_baseline, file.path(output_dir, "comparison_vs_all_features.csv"))
write_csv_atomic(implementation_pairs, file.path(output_dir, "implementation1_vs_2_replicate_pairs.csv"))
write_csv_atomic(implementation_comparison, file.path(output_dir, "implementation1_vs_2_summary.csv"))

cfg <- jsonlite::read_json(file.path(soft1_dir, "config.resolved.json"), simplifyVector = TRUE)
find_run_root <- function(path) {
  candidate <- normalizePath(path, mustWork = TRUE)
  repeat {
    if (file.exists(file.path(candidate, "code", "R", "main_storage.R"))) return(candidate)
    parent <- dirname(candidate)
    if (identical(parent, candidate)) stop("Could not locate the frozen code directory from: ", path)
    candidate <- parent
  }
}
run_root <- find_run_root(soft1_dir)
source(file.path(run_root, "code", "R", "main_storage.R"))
source(file.path(run_root, "code", "R", "main_results.R"))
plot_files <- save_main_plots(as.data.frame(deletion), cfg, output_dir, displayed_replicate = 1L)

method_levels <- unique(performance[order(method_order), method_label])
performance[, method_label_plot := factor(method_label, levels = rev(method_levels))]
summary_plot <- ggplot2::ggplot(
  performance,
  ggplot2::aes(y = method_label_plot, x = mean_beta2,
               xmin = pmax(0, mean_beta2 - sd_beta2_between_replicates),
               xmax = mean_beta2 + sd_beta2_between_replicates)
) +
  ggplot2::geom_errorbar(orientation = "y", width = 0.25, color = "#58728C") +
  ggplot2::geom_point(size = 2.1, color = "#173F5F") +
  ggplot2::facet_wrap(~setting, scales = "free_x", ncol = 2,
                      labeller = ggplot2::label_both) +
  ggplot2::labs(
    title = "Mean-square stability across 10 Monte Carlo replicates",
    subtitle = "Point: mean beta2-hat; bar: mean +/- between-replicate SD (descriptive)",
    x = "Mean beta2-hat (lower is more stable)", y = NULL
  ) +
  ggplot2::theme_bw(base_size = 10)
ggplot2::ggsave(
  file.path(output_dir, "figures", "all9_stability_mean_sd.png"),
  summary_plot, width = 11, height = 8.5, dpi = 180
)

soft_performance <- performance[!is.na(implementation)]
soft_performance[, implementation_label := paste("Implementation", implementation)]
implementation_plot <- ggplot2::ggplot(
  soft_performance,
  ggplot2::aes(x = factor(nu), y = mean_beta2, color = implementation_label,
               group = implementation_label)
) +
  ggplot2::geom_line(linewidth = 0.65) +
  ggplot2::geom_point(size = 2.2) +
  ggplot2::facet_wrap(~setting, scales = "free_y", ncol = 2,
                      labeller = ggplot2::label_both) +
  ggplot2::labs(
    title = "Soft implementation 1 versus 2",
    subtitle = "Matched settings, datasets, test samples and prespecified randomization",
    x = "nu", y = "Mean beta2-hat", color = NULL
  ) +
  ggplot2::theme_bw(base_size = 10)
ggplot2::ggsave(
  file.path(output_dir, "figures", "soft1_vs_soft2_stability.png"),
  implementation_plot, width = 10, height = 7.5, dpi = 180
)

tradeoff_plot <- ggplot2::ggplot(
  performance,
  ggplot2::aes(x = mean_prediction_risk, y = mean_beta2, label = method_label)
) +
  ggplot2::geom_point(size = 2, color = "#8C3B31") +
  ggplot2::geom_text(size = 2.5, check_overlap = TRUE, nudge_y = 0.0002) +
  ggplot2::facet_wrap(~setting, scales = "free", ncol = 2,
                      labeller = ggplot2::label_both) +
  ggplot2::labs(
    title = "Prediction risk and stability are different criteria",
    x = "Mean prediction risk against mu_test (lower is better)",
    y = "Mean beta2-hat (lower is more stable)"
  ) +
  ggplot2::theme_bw(base_size = 10)
ggplot2::ggsave(
  file.path(output_dir, "figures", "stability_risk_tradeoff.png"),
  tradeoff_plot, width = 11, height = 8, dpi = 180
)

write_csv_atomic(performance, file.path(output_dir, "plot_data", "all9_stability_mean_sd.csv"))
write_csv_atomic(soft_performance, file.path(output_dir, "plot_data", "soft1_vs_soft2_stability.csv"))

file.copy(file.path(soft1_dir, "config.resolved.json"), file.path(output_dir, "config.resolved.json"), overwrite = TRUE)
file.copy(file.path(soft1_dir, "dense_theta.json"), file.path(output_dir, "dense_theta.json"), overwrite = TRUE)
file.copy(file.path(six_dir, "validation_report.json"),
          file.path(output_dir, "source_validation", "six_method_validation_report.json"), overwrite = TRUE)
file.copy(file.path(soft1_dir, "validation_report.json"),
          file.path(output_dir, "source_validation", "soft1_validation_report.json"), overwrite = TRUE)
file.copy(file.path(six_dir, "run_manifest.json"),
          file.path(output_dir, "source_validation", "six_method_run_manifest.json"), overwrite = TRUE)
file.copy(file.path(soft1_dir, "run_manifest.json"),
          file.path(output_dir, "source_validation", "soft1_run_manifest.json"), overwrite = TRUE)

scope <- list(
  setting_ids = expected$setting_ids,
  replicate_ids = expected$replicate_ids,
  method_ids = expected_methods
)
write_json_atomic(scope, file.path(output_dir, "execution_scope.json"))

checks <- list(
  six_method_source_passed = source6_ok,
  soft1_source_passed = source1_ok,
  matching_config_fingerprint = identical(as.character(m6$config_fingerprint), as.character(m1$config_fingerprint)),
  expected_deletion_rows = nrow(deletion) == expected$combined_deletion,
  expected_dataset_method_rows = nrow(dataset) == expected$combined_dataset,
  expected_setting_method_summary_rows = nrow(summary) == expected$combined_summary,
  no_duplicate_deletion_keys = duplicate_deletion_keys == 0L,
  no_duplicate_dataset_keys = duplicate_dataset_keys == 0L,
  exactly_nine_methods = identical(sort(unique(deletion$method_id)), sort(expected_methods)),
  all_cells_have_expected_deletions = all(
    dataset$deletions_completed == expected$deletions_per_cell & dataset$all_deletions_complete
  ),
  all_prediction_comparisons_use_expected_test_points = all(
    deletion$test_prediction_count == expected$test_points
  ),
  every_summary_cell_has_expected_replicates = all(
    summary$completed_replicates == expected$replicates_per_cell
  ),
  implementation_pair_rows = nrow(implementation_pairs) == expected$implementation_pair_rows,
  implementation_comparison_rows =
    nrow(implementation_comparison) == expected$implementation_comparison_rows
)
validation <- c(list(
  updated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  config_fingerprint = as.character(m1$config_fingerprint),
  actual_deletion_rows = nrow(deletion),
  actual_dataset_method_rows = nrow(dataset),
  actual_setting_method_summary_rows = nrow(summary),
  observed_method_count = data.table::uniqueN(deletion$method_id),
  duplicate_deletion_keys = duplicate_deletion_keys,
  duplicate_dataset_keys = duplicate_dataset_keys,
  all_checks_pass = all(unlist(checks))
), checks)
write_json_atomic(validation, file.path(output_dir, "combined_validation_report.json"))

manifest <- list(
  schema_version = 1L,
  updated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  config_fingerprint = as.character(m1$config_fingerprint),
  sources = list(
    six_method_results = six_dir,
    soft_implementation_1_results = soft1_dir
  ),
  output_rows = list(deletion = nrow(deletion), dataset = nrow(dataset), summary = nrow(summary)),
  methods = expected_methods,
  primary_tables = c(
    "stability_table.csv", "performance_summary.csv", "comparison_vs_all_features.csv",
    "implementation1_vs_2_summary.csv", "implementation1_vs_2_replicate_pairs.csv"
  ),
  plots = c(plot_files, list(
    all9_stability_mean_sd = "all9_stability_mean_sd.png",
    soft1_vs_soft2_stability = "soft1_vs_soft2_stability.png",
    stability_risk_tradeoff = "stability_risk_tradeoff.png"
  )),
  validation_report = "combined_validation_report.json"
)
write_json_atomic(manifest, file.path(output_dir, "combined_manifest.json"))

if (!isTRUE(validation$all_checks_pass)) stop("Combined output failed validation")
message("Combined nine-method outputs passed all validation checks: ", output_dir)
