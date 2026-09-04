utc_timestamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

ensure_parent_dir <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  invisible(path)
}

atomic_save_rds <- function(object, path) {
  ensure_parent_dir(path)
  temp <- tempfile(pattern = paste0(".", basename(path), "."), tmpdir = dirname(path))
  on.exit(if (file.exists(temp)) unlink(temp), add = TRUE)
  saveRDS(object, temp, compress = "xz")
  if (file.exists(path)) unlink(path)
  if (!file.rename(temp, path)) stop("Could not atomically move checkpoint into place: ", path)
  invisible(path)
}

atomic_write_text <- function(text, path) {
  ensure_parent_dir(path)
  temp <- tempfile(pattern = paste0(".", basename(path), "."), tmpdir = dirname(path))
  on.exit(if (file.exists(temp)) unlink(temp), add = TRUE)
  writeLines(text, temp, useBytes = TRUE)
  if (file.exists(path)) unlink(path)
  if (!file.rename(temp, path)) stop("Could not atomically move file into place: ", path)
  invisible(path)
}

atomic_write_json <- function(object, path, pretty = TRUE) {
  text <- jsonlite::toJSON(
    object, auto_unbox = TRUE, pretty = pretty, digits = 17,
    na = "null", null = "null", dataframe = "rows"
  )
  atomic_write_text(text, path)
}

atomic_write_csv <- function(data, path) {
  ensure_parent_dir(path)
  temp <- tempfile(pattern = paste0(".", basename(path), "."), tmpdir = dirname(path))
  on.exit(if (file.exists(temp)) unlink(temp), add = TRUE)
  utils::write.csv(data, temp, row.names = FALSE, na = "")
  if (file.exists(path)) unlink(path)
  if (!file.rename(temp, path)) stop("Could not atomically move CSV into place: ", path)
  invisible(path)
}

initialize_output_directory <- function(output_dir, cfg) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(output_dir, "checkpoints"), recursive = TRUE, showWarnings = FALSE)
  fingerprint <- config_fingerprint(cfg)
  resolved_path <- file.path(output_dir, "config.resolved.json")
  if (file.exists(resolved_path)) {
    existing <- load_config(resolved_path)
    existing_fingerprint <- config_fingerprint(existing)
    if (!identical(existing_fingerprint, fingerprint)) {
      stop(
        "Output directory belongs to a different configuration. Choose a new --output-dir.\n",
        "Existing fingerprint: ", existing_fingerprint, "\n",
        "Requested fingerprint: ", fingerprint
      )
    }
  } else {
    atomic_write_text(canonical_config_json(cfg), resolved_path)
  }
  fingerprint
}

replicate_checkpoint_dir <- function(output_dir, replicate_id) {
  file.path(output_dir, "checkpoints", sprintf("replicate_%03d", replicate_id))
}

full_checkpoint_path <- function(output_dir, replicate_id, spec_id) {
  file.path(replicate_checkpoint_dir(output_dir, replicate_id), spec_id, "full.rds")
}

deletion_checkpoint_path <- function(output_dir, replicate_id, spec_id, deletion_id) {
  file.path(
    replicate_checkpoint_dir(output_dir, replicate_id), spec_id,
    sprintf("deletion_%03d.rds", deletion_id)
  )
}

read_valid_checkpoint <- function(path, fingerprint) {
  object <- readRDS(path)
  if (is.null(object$config_fingerprint) || !identical(object$config_fingerprint, fingerprint)) {
    stop("Checkpoint has the wrong or missing configuration fingerprint: ", path)
  }
  object
}

checkpoint_files <- function(output_dir, pattern) {
  root <- file.path(output_dir, "checkpoints")
  if (!dir.exists(root)) return(character())
  list.files(root, pattern = pattern, recursive = TRUE, full.names = TRUE)
}

bind_rows_base <- function(rows) {
  if (!length(rows)) return(data.frame())
  all_names <- unique(unlist(lapply(rows, names), use.names = FALSE))
  normalized <- lapply(rows, function(x) {
    missing <- setdiff(all_names, names(x))
    for (name in missing) x[[name]] <- NA
    x[all_names]
  })
  do.call(rbind, normalized)
}

group_key <- function(data, columns) {
  parts <- lapply(columns, function(name) {
    x <- data[[name]]
    ifelse(is.na(x), "<NA>", as.character(x))
  })
  do.call(paste, c(parts, sep = "|"))
}

aggregate_checkpoint_results <- function(output_dir, cfg, fingerprint) {
  deletion_files <- checkpoint_files(output_dir, "^deletion_[0-9]+\\.rds$")
  rows <- list()
  cursor <- 0L
  for (path in deletion_files) {
    record <- read_valid_checkpoint(path, fingerprint)
    if (!identical(record$type, "deletion")) next
    record_rows <- split(record$rows, seq_len(nrow(record$rows)))
    for (row in record_rows) {
      cursor <- cursor + 1L
      rows[[cursor]] <- row
    }
  }
  deletion_data <- bind_rows_base(rows)
  if (nrow(deletion_data)) {
    if (!"q_change_squared_mean" %in% names(deletion_data)) {
      deletion_data$q_change_squared_mean <- deletion_data$q_change_squared_sum / cfg$simulation$p
    } else {
      missing_q_mean <- is.na(deletion_data$q_change_squared_mean) &
        !is.na(deletion_data$q_change_squared_sum)
      deletion_data$q_change_squared_mean[missing_q_mean] <-
        deletion_data$q_change_squared_sum[missing_q_mean] / cfg$simulation$p
    }
    deletion_data <- deletion_data[order(
      deletion_data$replicate, deletion_data$method,
      ifelse(is.na(deletion_data$nu), -Inf, deletion_data$nu),
      ifelse(is.na(deletion_data$M), -1, deletion_data$M),
      deletion_data$deletion
    ), , drop = FALSE]
  }
  atomic_write_csv(deletion_data, file.path(output_dir, "deletion_results.csv"))

  dataset_data <- data.frame()
  summary_data <- data.frame()
  if (nrow(deletion_data)) {
    grouping <- c("replicate", "method", "implementation", "nu", "M", "T", "forest_trees_per_mask")
    groups <- split(deletion_data, group_key(deletion_data, grouping))
    dataset_rows <- lapply(groups, function(g) {
      complete <- setequal(unique(g$deletion), seq_len(cfg$simulation$n))
      data.frame(
        replicate = g$replicate[[1]],
        method = g$method[[1]],
        implementation = g$implementation[[1]],
        nu = g$nu[[1]],
        M = g$M[[1]],
        T = g$T[[1]],
        forest_trees_per_mask = g$forest_trees_per_mask[[1]],
        total_trees = g$total_trees[[1]],
        deletions_completed = length(unique(g$deletion)),
        all_deletions_complete = complete,
        beta2_hat = if (complete) mean(g$beta2_contribution) else NA_real_,
        beta2_mean_completed = mean(g$beta2_contribution),
        prediction_risk_full = g$prediction_risk_full[[1]],
        mean_hard_flip_count = mean(g$hard_flip_count),
        probability_any_hard_flip = mean(g$hard_flip_count > 0),
        mean_variance_change_squared_sum = mean(g$variance_change_squared_sum),
        mean_q_change_squared_sum = if (all(is.na(g$q_change_squared_sum))) NA_real_ else mean(g$q_change_squared_sum, na.rm = TRUE),
        mean_q_change_squared_per_feature = if (all(is.na(g$q_change_squared_mean))) NA_real_ else mean(g$q_change_squared_mean, na.rm = TRUE),
        mean_mask_symmetric_difference = if (all(is.na(g$average_mask_symmetric_difference))) NA_real_ else mean(g$average_mask_symmetric_difference, na.rm = TRUE),
        stringsAsFactors = FALSE
      )
    })
    dataset_data <- do.call(rbind, dataset_rows)
    dataset_data <- dataset_data[order(
      dataset_data$replicate, dataset_data$method,
      ifelse(is.na(dataset_data$nu), -Inf, dataset_data$nu),
      ifelse(is.na(dataset_data$M), -1, dataset_data$M)
    ), , drop = FALSE]
    rownames(dataset_data) <- NULL

    complete_data <- dataset_data[dataset_data$all_deletions_complete & !is.na(dataset_data$beta2_hat), , drop = FALSE]
    if (nrow(complete_data)) {
      summary_grouping <- c("method", "implementation", "nu", "M", "T", "forest_trees_per_mask")
      summary_groups <- split(complete_data, group_key(complete_data, summary_grouping))
      summary_rows <- lapply(summary_groups, function(g) data.frame(
        method = g$method[[1]],
        implementation = g$implementation[[1]],
        nu = g$nu[[1]],
        M = g$M[[1]],
        T = g$T[[1]],
        forest_trees_per_mask = g$forest_trees_per_mask[[1]],
        completed_replicates = nrow(g),
        mean_beta2 = mean(g$beta2_hat),
        sd_beta2_between_replicates = if (nrow(g) > 1L) stats::sd(g$beta2_hat) else NA_real_,
        mean_prediction_risk = mean(g$prediction_risk_full),
        stringsAsFactors = FALSE
      ))
      summary_data <- do.call(rbind, summary_rows)
      summary_data <- summary_data[order(
        summary_data$method,
        ifelse(is.na(summary_data$nu), -Inf, summary_data$nu),
        ifelse(is.na(summary_data$M), -1, summary_data$M)
      ), , drop = FALSE]
      rownames(summary_data) <- NULL
    }
  }
  atomic_write_csv(dataset_data, file.path(output_dir, "dataset_results.csv"))
  atomic_write_csv(summary_data, file.path(output_dir, "summary.csv"))

  screening_records <- write_feature_screening_tables(output_dir, cfg)
  full_files <- checkpoint_files(output_dir, "^full\\.rds$")
  manifest <- list(
    schema_version = cfg$schema_version,
    algorithm_version = cfg$algorithm_version %||% NULL,
    updated_at_utc = utc_timestamp(),
    config_fingerprint = fingerprint,
    completed_full_fit_checkpoints = length(full_files),
    completed_deletion_checkpoints = length(deletion_files),
    deletion_result_rows = nrow(deletion_data),
    complete_dataset_method_rows = if (nrow(dataset_data)) sum(dataset_data$all_deletions_complete) else 0L,
    r_version = R.version.string,
    packages = list(
      ranger = if (requireNamespace("ranger", quietly = TRUE)) as.character(utils::packageVersion("ranger")) else NULL,
      jsonlite = as.character(utils::packageVersion("jsonlite")),
      digest = as.character(utils::packageVersion("digest"))
    ),
    feature_screening_records = screening_records
  )
  atomic_write_json(manifest, file.path(output_dir, "run_manifest.json"))
  invisible(list(deletion = deletion_data, dataset = dataset_data, summary = summary_data, manifest = manifest))
}
