main_mask_diagnostics <- function(q_full, q_deleted, uniforms, mask_count) {
  U <- uniforms[seq_len(mask_count), , drop = FALSE]
  full <- sweep(U, 2L, q_full, FUN = "<=")
  deleted <- sweep(U, 2L, q_deleted, FUN = "<=")
  list(
    average_symmetric_difference = mean(rowSums(full != deleted)),
    average_size_full = mean(rowSums(full)),
    average_size_deleted = mean(rowSums(deleted))
  )
}

main_deadline_reached <- function(deadline_utc) {
  !is.null(deadline_utc) && length(deadline_utc) == 1L &&
    is.finite(deadline_utc) && as.numeric(Sys.time()) >= deadline_utc
}

main_pause_or_deadline <- function(
  output_dir, deadline_utc, setting_id, replicate_id,
  boundary, spec_id = NULL, deletion_id = NULL
) {
  if (main_deadline_reached(deadline_utc) && !main_pause_requested(output_dir)) {
    try(request_main_pause(output_dir, "max_hours_deadline"), silent = TRUE)
  }
  if (!main_pause_requested(output_dir)) return(FALSE)
  mark_main_worker_paused(
    output_dir, setting_id, replicate_id, boundary, spec_id, deletion_id
  )
  TRUE
}

fit_main_full <- function(
  spec, data, full_variances, hard_full, uniforms, seeds,
  cfg, setting_id, replicate_id, output_dir, fingerprint, force
) {
  path <- main_full_checkpoint_path(output_dir, setting_id, replicate_id, spec$id)
  if (file.exists(path) && !force) return(read_main_checkpoint(path, fingerprint))
  prediction <- predict_main_method(
    spec, data, full_variances, hard_full, uniforms, seeds, cfg
  )
  record <- list(
    type = "full",
    created_at_utc = main_utc_timestamp(),
    config_fingerprint = fingerprint,
    setting = setting_id,
    replicate = replicate_id,
    spec = spec,
    prediction = prediction,
    prediction_risk = mean((prediction - data$mu_test)^2),
    test_prediction_count = length(prediction)
  )
  main_atomic_save_rds(record, path)
  record
}

main_deletion_row <- function(
  spec, deletion_id, data, deleted_data, full_variances, deleted_variances,
  hard_full, uniforms, seeds, full_record, cfg, setting_id, replicate_id
) {
  deleted_prediction <- predict_main_method(
    spec, deleted_data, deleted_variances, hard_full, uniforms, seeds, cfg
  )
  if (length(deleted_prediction) != length(full_record$prediction)) {
    stop("Full/deleted prediction lengths differ")
  }
  threshold <- cfg$simulation$variance_threshold
  hard_deleted <- which(deleted_variances > threshold)
  counts <- main_effective_counts(cfg)
  M <- if (is.na(spec$implementation)) NA_integer_ else if (spec$implementation == 1L) counts$masks_1 else counts$masks_2
  trees_per_mask <- if (is.na(spec$implementation) || spec$implementation == 1L) counts$trees else 1L
  total_trees <- if (is.na(M)) counts$trees else M * trees_per_mask
  mask_stats <- list(
    average_symmetric_difference = NA_real_,
    average_size_full = NA_real_,
    average_size_deleted = NA_real_
  )
  q_change <- NA_real_
  if (!is.na(spec$implementation)) {
    q_full <- soft_probabilities_from_variances(full_variances, threshold, spec$nu)
    q_deleted <- soft_probabilities_from_variances(deleted_variances, threshold, spec$nu)
    q_change <- sum((q_full - q_deleted)^2)
    mask_stats <- main_mask_diagnostics(q_full, q_deleted, uniforms, M)
  }
  hard_full_indicator <- full_variances > threshold
  hard_deleted_indicator <- deleted_variances > threshold
  data.frame(
    setting = as.integer(setting_id),
    replicate = as.integer(replicate_id),
    deletion = as.integer(deletion_id),
    method_order = as.integer(spec$order),
    method_id = spec$id,
    method_label = spec$label,
    method = spec$method,
    implementation = spec$implementation,
    nu = spec$nu,
    M = M,
    T = counts$trees,
    trees_per_mask = trees_per_mask,
    total_trees = total_trees,
    delta = mean((full_record$prediction - deleted_prediction)^2),
    prediction_risk_full = full_record$prediction_risk,
    test_prediction_count = length(deleted_prediction),
    hard_selected_count_full = length(hard_full),
    hard_selected_count_deleted = length(hard_deleted),
    hard_flip_count = sum(hard_full_indicator != hard_deleted_indicator),
    variance_change_squared_sum = sum((full_variances - deleted_variances)^2),
    q_change_squared_sum = q_change,
    average_mask_symmetric_difference = mask_stats$average_symmetric_difference,
    average_mask_size_full = mask_stats$average_size_full,
    average_mask_size_deleted = mask_stats$average_size_deleted,
    stringsAsFactors = FALSE
  )
}

run_main_method <- function(
  spec, data, full_variances, full_means, hard_full, uniforms, seeds,
  cfg, setting_id, replicate_id, output_dir, fingerprint, force = FALSE,
  deadline_utc = NULL
) {
  if (main_pause_or_deadline(
    output_dir, deadline_utc, setting_id, replicate_id,
    "before_full_fit", spec$id, 1L
  )) {
    return(FALSE)
  }
  message("setting ", setting_id, ", replicate ", replicate_id, ": ", spec$id)
  full_record <- fit_main_full(
    spec, data, full_variances, hard_full, uniforms, seeds,
    cfg, setting_id, replicate_id, output_dir, fingerprint, force
  )
  n <- nrow(data$X)
  progress_every <- max(1L, floor(n / 4L))
  for (deletion_id in seq_len(n)) {
    path <- main_deletion_checkpoint_path(
      output_dir, setting_id, replicate_id, spec$id, deletion_id
    )
    if (file.exists(path) && !force) next
    if (main_pause_or_deadline(
      output_dir, deadline_utc, setting_id, replicate_id,
      "before_deletion_fit", spec$id, deletion_id
    )) {
      return(FALSE)
    }
    deleted_variances <- leave_one_out_feature_variances(
      full_variances, full_means, data$X[deletion_id, ], n
    )
    keep <- seq_len(n) != deletion_id
    deleted_data <- data
    deleted_data$X <- data$X[keep, , drop = FALSE]
    deleted_data$y <- data$y[keep]
    deleted_data$mu <- data$mu[keep]
    row <- main_deletion_row(
      spec, deletion_id, data, deleted_data, full_variances,
      deleted_variances, hard_full, uniforms, seeds, full_record,
      cfg, setting_id, replicate_id
    )
    record <- list(
      type = "deletion",
      created_at_utc = main_utc_timestamp(),
      config_fingerprint = fingerprint,
      setting = setting_id,
      replicate = replicate_id,
      deletion = deletion_id,
      spec_id = spec$id,
      row = row
    )
    main_atomic_save_rds(record, path)
    if (deletion_id %% progress_every == 0L || deletion_id == n) {
      message("  completed deletion ", deletion_id, "/", n)
    }
  }
  TRUE
}

run_main_setting_replicate <- function(
  cfg, setting_id, replicate_id, output_dir, fingerprint, force = FALSE,
  deadline_utc = NULL, method_ids = NULL
) {
  clear_main_worker_marker(output_dir, setting_id, replicate_id)
  block <- readRDS(main_schedule_path(output_dir, replicate_id))
  setting_name <- paste0("setting_", setting_id)
  data <- block$data[[setting_name]]
  uniforms <- block$mask_uniforms[[setting_name]]
  seeds <- block$learner_seeds[[setting_name]]
  if (is.null(data) || is.null(uniforms) || is.null(seeds)) stop("Saved schedule is incomplete")
  ensure_main_screening_audit(
    data, uniforms, cfg, setting_id, replicate_id, output_dir
  )
  full_variances <- unbiased_feature_variances(data$X)
  full_means <- colMeans(data$X)
  hard_full <- which(full_variances > cfg$simulation$variance_threshold)
  specs <- build_main_method_specs(cfg)
  if (!is.null(method_ids)) {
    specs <- Filter(function(spec) spec$id %in% method_ids, specs)
  }
  for (spec in specs) {
    completed <- run_main_method(
      spec, data, full_variances, full_means, hard_full, uniforms, seeds,
      cfg, setting_id, replicate_id, output_dir, fingerprint, force,
      deadline_utc
    )
    if (!isTRUE(completed)) return(invisible(list(paused = TRUE)))
  }
  invisible(list(paused = FALSE))
}

run_main_tasks <- function(
  cfg, setting_ids, replicate_ids, output_dir, fingerprint,
  force = FALSE, workers = 1L, project_dir = NULL, deadline_utc = NULL,
  method_ids = NULL
) {
  tasks <- unlist(lapply(replicate_ids, function(r) {
    lapply(setting_ids, function(s) list(setting = s, replicate = r))
  }), recursive = FALSE)
  worker <- function(task) {
    tryCatch({
      result <- run_main_setting_replicate(
        cfg, task$setting, task$replicate, output_dir, fingerprint, force,
        deadline_utc, method_ids
      )
      list(ok = TRUE, paused = isTRUE(result$paused), task = task, error = NULL)
    }, error = function(e) {
      list(ok = FALSE, task = task, error = conditionMessage(e))
    })
  }
  workers <- as.integer(workers)
  if (workers > 1L && length(tasks) > 1L) {
    if (is.null(project_dir)) stop("project_dir is required for parallel execution")
    cluster <- parallel::makeCluster(
      min(workers, length(tasks)),
      outfile = file.path(output_dir, "worker_messages.log")
    )
    on.exit(parallel::stopCluster(cluster), add = TRUE)
    parallel::clusterExport(
      cluster,
      c("cfg", "output_dir", "fingerprint", "force", "project_dir", "deadline_utc", "method_ids"),
      envir = environment()
    )
    parallel::clusterEvalQ(cluster, {
      source(file.path(project_dir, "R", "main_config.R"))
      source(file.path(project_dir, "R", "main_randomization.R"))
      source(file.path(project_dir, "R", "main_models.R"))
      source(file.path(project_dir, "R", "main_storage.R"))
      source(file.path(project_dir, "R", "main_runner.R"))
      NULL
    })
    # Every task reads saved data/uniforms/seeds, so assignment is independent
    # of worker RNG state. Dispatch one task at a time to reduce idle workers.
    results <- parallel::parLapplyLB(cluster, tasks, worker, chunk.size = 1L)
  } else {
    results <- lapply(tasks, worker)
  }
  failed <- Filter(function(x) !isTRUE(x$ok), results)
  if (length(failed)) {
    detail <- vapply(failed, function(x) paste0(
      "setting ", x$task$setting, ", replicate ", x$task$replicate, ": ", x$error
    ), character(1))
    stop("One or more tasks failed:\n", paste(detail, collapse = "\n"))
  }
  paused <- Filter(function(x) isTRUE(x$paused), results)
  if (length(paused)) {
    message(length(paused), " task(s) stopped at checkpoint-safe pause boundaries")
  }
  invisible(results)
}
