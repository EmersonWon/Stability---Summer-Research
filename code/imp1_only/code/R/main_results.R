main_read_deletion_results <- function(output_dir, fingerprint) {
  files <- main_checkpoint_files(output_dir, "^deletion_[0-9]+\\.rds$")
  if (!length(files)) return(data.frame())
  rows <- lapply(files, function(path) {
    record <- read_main_checkpoint(path, fingerprint)
    if (!identical(record$type, "deletion")) return(NULL)
    record$row
  })
  rows <- Filter(Negate(is.null), rows)
  as.data.frame(data.table::rbindlist(rows, fill = TRUE, use.names = TRUE))
}

main_tail_curve_data <- function(deltas, common_max) {
  x <- sort(unique(c(0, deltas, common_max)))
  data.frame(delta_threshold = x, tail_probability = vapply(
    x, function(value) mean(deltas > value), numeric(1)
  ))
}

save_main_plots <- function(deletion_data, cfg, output_dir, displayed_replicate = 1L) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Package 'ggplot2' is required")
  displayed <- deletion_data[deletion_data$replicate == displayed_replicate, , drop = FALSE]
  if (!nrow(displayed)) return(invisible(list()))
  saved <- list()
  for (setting_id in sort(unique(displayed$setting))) {
    dat <- displayed[displayed$setting == setting_id, , drop = FALSE]
    dat$method_label <- factor(
      dat$method_label,
      levels = unique(dat$method_label[order(dat$method_order)])
    )
    facet_rows <- max(1L, as.integer(ceiling(nlevels(dat$method_label) / 3)))
    d_max <- max(dat$delta)
    plot_max <- if (is.finite(d_max) && d_max > 0) d_max else 1
    breaks <- seq(0, plot_max, length.out = 31L)
    hist_data_path <- file.path(
      output_dir, "plot_data", sprintf("histogram_data_setting_%d.csv", setting_id)
    )
    main_atomic_write_csv(dat[, c(
      "setting", "replicate", "deletion", "method_order",
      "method_id", "method_label", "delta"
    )], hist_data_path)

    histogram <- ggplot2::ggplot(dat, ggplot2::aes(x = delta)) +
      ggplot2::geom_histogram(breaks = breaks, color = "white", fill = "#315F8C") +
      ggplot2::facet_wrap(~method_label, nrow = facet_rows, ncol = 3L) +
      ggplot2::coord_cartesian(xlim = c(0, plot_max)) +
      ggplot2::labs(
        title = paste0("Setting ", setting_id, ": leave-one-out perturbations"),
        subtitle = paste0("Replicate ", displayed_replicate, "; 30 common bins"),
        x = expression(Delta[i]), y = "Count"
      ) +
      ggplot2::theme_bw(base_size = 10) +
      ggplot2::theme(strip.text = ggplot2::element_text(size = 8))
    hist_path <- file.path(output_dir, "figures", sprintf("histograms_setting_%d.png", setting_id))
    ggplot2::ggsave(hist_path, histogram, width = 10, height = 8, dpi = 160)

    groups <- split(dat, dat$method_id)
    tail_rows <- lapply(groups, function(g) {
      curve <- main_tail_curve_data(g$delta, plot_max)
      curve$setting <- setting_id
      curve$replicate <- displayed_replicate
      curve$method_order <- g$method_order[[1L]]
      curve$method_id <- g$method_id[[1L]]
      curve$method_label <- as.character(g$method_label[[1L]])
      curve
    })
    tail_data <- as.data.frame(data.table::rbindlist(tail_rows, fill = TRUE))
    tail_data$method_label <- factor(
      tail_data$method_label,
      levels = unique(tail_data$method_label[order(tail_data$method_order)])
    )
    tail_data_path <- file.path(
      output_dir, "plot_data", sprintf("tail_curve_data_setting_%d.csv", setting_id)
    )
    main_atomic_write_csv(tail_data, tail_data_path)
    tail_plot <- ggplot2::ggplot(
      tail_data,
      ggplot2::aes(x = delta_threshold, y = tail_probability)
    ) +
      ggplot2::geom_step(direction = "hv", linewidth = 0.55, color = "#8C3B31") +
      ggplot2::facet_wrap(~method_label, nrow = facet_rows, ncol = 3L) +
      ggplot2::coord_cartesian(xlim = c(0, plot_max), ylim = c(0, 1)) +
      ggplot2::labs(
        title = paste0("Setting ", setting_id, ": empirical tail probabilities"),
        subtitle = paste0("Replicate ", displayed_replicate, "; no smoothing"),
        x = expression(delta), y = expression(hat(T)(delta))
      ) +
      ggplot2::theme_bw(base_size = 10) +
      ggplot2::theme(strip.text = ggplot2::element_text(size = 8))
    tail_path <- file.path(output_dir, "figures", sprintf("tail_curves_setting_%d.png", setting_id))
    ggplot2::ggsave(tail_path, tail_plot, width = 10, height = 8, dpi = 160)
    saved[[paste0("setting_", setting_id)]] <- list(
      histogram = basename(hist_path), tail_curve = basename(tail_path),
      histogram_data = basename(hist_data_path), tail_curve_data = basename(tail_data_path),
      common_horizontal_max = plot_max
    )
  }
  invisible(saved)
}

aggregate_main_results <- function(output_dir, cfg, fingerprint, scope = NULL) {
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Package 'data.table' is required")
  deletion_data <- main_read_deletion_results(output_dir, fingerprint)
  if (!nrow(deletion_data)) {
    main_atomic_write_csv(data.frame(), file.path(output_dir, "deletion_results.csv"))
    return(invisible(list()))
  }
  deletion_data <- deletion_data[order(
    deletion_data$setting, deletion_data$replicate,
    deletion_data$method_order, deletion_data$deletion
  ), , drop = FALSE]
  key <- deletion_data[, c("setting", "replicate", "method_id", "deletion")]
  if (anyDuplicated(key)) stop("Duplicate deletion result keys detected")
  main_atomic_write_csv(deletion_data, file.path(output_dir, "deletion_results.csv"))

  dt <- data.table::as.data.table(deletion_data)
  n_required <- cfg$simulation$n
  dataset <- dt[, .(
    method_order = method_order[[1L]],
    method_label = method_label[[1L]],
    method = method[[1L]],
    implementation = implementation[[1L]],
    nu = nu[[1L]],
    M = M[[1L]],
    T = T[[1L]],
    total_trees = total_trees[[1L]],
    deletions_completed = data.table::uniqueN(deletion),
    all_deletions_complete = setequal(unique(deletion), seq_len(n_required)),
    beta2_hat = if (setequal(unique(deletion), seq_len(n_required))) mean(delta) else NA_real_,
    prediction_risk_full = prediction_risk_full[[1L]],
    mean_hard_flip_count = mean(hard_flip_count),
    probability_any_hard_flip = mean(hard_flip_count > 0),
    mean_mask_symmetric_difference = if (all(is.na(average_mask_symmetric_difference))) NA_real_ else mean(average_mask_symmetric_difference, na.rm = TRUE)
  ), by = .(setting, replicate, method_id)]
  data.table::setorder(dataset, setting, replicate, method_order)
  main_atomic_write_csv(as.data.frame(dataset), file.path(output_dir, "dataset_results.csv"))

  complete <- dataset[all_deletions_complete == TRUE & !is.na(beta2_hat)]
  summary <- complete[, .(
    method_order = method_order[[1L]],
    method_label = method_label[[1L]],
    method = method[[1L]],
    implementation = implementation[[1L]],
    nu = nu[[1L]],
    M = M[[1L]],
    T = T[[1L]],
    completed_replicates = .N,
    mean_beta2 = mean(beta2_hat),
    sd_beta2_between_replicates = if (.N > 1L) stats::sd(beta2_hat) else NA_real_
  ), by = .(setting, method_id)]
  data.table::setorder(summary, method_order, setting)
  main_atomic_write_csv(as.data.frame(summary), file.path(output_dir, "setting_method_summary.csv"))

  display <- data.table::copy(summary)
  display[, value := ifelse(
    is.na(sd_beta2_between_replicates),
    sprintf("%.6g (NA)", mean_beta2),
    sprintf("%.6g (%.6g)", mean_beta2, sd_beta2_between_replicates)
  )]
  display[, setting_column := paste0("Setting_", setting)]
  table_data <- data.table::dcast(
    display,
    method_order + method_id + method_label ~ setting_column,
    value.var = "value"
  )
  data.table::setorder(table_data, method_order)
  main_atomic_write_csv(as.data.frame(table_data), file.path(output_dir, "stability_table.csv"))

  plot_files <- save_main_plots(deletion_data, cfg, output_dir, 1L)
  full_files <- main_checkpoint_files(output_dir, "^full\\.rds$")
  deletion_files <- main_checkpoint_files(output_dir, "^deletion_[0-9]+\\.rds$")
  audit_files <- list.files(
    file.path(output_dir, "screening_audits"), pattern = "\\.rds$", full.names = TRUE
  )
  expected_settings <- if (is.null(scope)) 1:4 else as.integer(scope$setting_ids)
  expected_replicates <- if (is.null(scope)) seq_len(cfg$simulation$replicates) else as.integer(scope$replicate_ids)
  expected_methods <- if (is.null(scope)) vapply(build_main_method_specs(cfg), `[[`, character(1), "id") else as.character(scope$method_ids)
  expected_deletion_rows <- length(expected_settings) * length(expected_replicates) *
    length(expected_methods) * cfg$simulation$n
  validation <- list(
    expected_complete_study_deletion_rows = expected_deletion_rows,
    actual_deletion_rows = nrow(deletion_data),
    actual_dataset_method_rows = nrow(dataset),
    actual_setting_method_summary_rows = nrow(summary),
    duplicate_deletion_keys = anyDuplicated(key),
    every_prediction_comparison_uses_n_test = all(deletion_data$test_prediction_count == cfg$simulation$n_test),
    every_completed_cell_has_all_deletions = all(dataset$all_deletions_complete),
    expected_method_count = length(expected_methods),
    observed_method_count = data.table::uniqueN(deletion_data$method_id),
    full_fit_checkpoints = length(full_files),
    deletion_checkpoints = length(deletion_files),
    screening_audit_files = length(audit_files)
  )
  main_atomic_write_json(validation, file.path(output_dir, "validation_report.json"))
  manifest <- list(
    schema_version = 1L,
    updated_at_utc = main_utc_timestamp(),
    config_fingerprint = fingerprint,
    r_version = R.version.string,
    platform = R.version$platform,
    rngkind = unname(RNGkind()),
    packages = list(
      ranger = as.character(utils::packageVersion("ranger")),
      data.table = as.character(utils::packageVersion("data.table")),
      jsonlite = as.character(utils::packageVersion("jsonlite")),
      digest = as.character(utils::packageVersion("digest")),
      ggplot2 = as.character(utils::packageVersion("ggplot2"))
    ),
    output_rows = list(
      deletion = nrow(deletion_data), dataset = nrow(dataset), summary = nrow(summary)
    ),
    execution_scope = scope,
    plots = plot_files,
    validation_report = "validation_report.json"
  )
  main_atomic_write_json(manifest, file.path(output_dir, "run_manifest.json"))
  invisible(list(
    deletion = deletion_data,
    dataset = as.data.frame(dataset),
    summary = as.data.frame(summary),
    stability_table = as.data.frame(table_data),
    validation = validation,
    manifest = manifest
  ))
}
