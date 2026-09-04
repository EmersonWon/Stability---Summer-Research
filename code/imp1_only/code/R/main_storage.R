main_utc_timestamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

main_ensure_parent <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  invisible(path)
}

main_atomic_save_rds <- function(object, path) {
  main_ensure_parent(path)
  temp <- tempfile(pattern = paste0(".", basename(path), "."), tmpdir = dirname(path))
  on.exit(if (file.exists(temp)) unlink(temp), add = TRUE)
  saveRDS(object, temp, compress = "xz")
  if (file.exists(path)) unlink(path)
  if (!file.rename(temp, path)) stop("Could not atomically move file into place: ", path)
  invisible(path)
}

main_atomic_write_csv <- function(data, path) {
  main_ensure_parent(path)
  temp <- tempfile(pattern = paste0(".", basename(path), "."), tmpdir = dirname(path))
  on.exit(if (file.exists(temp)) unlink(temp), add = TRUE)
  utils::write.csv(data, temp, row.names = FALSE, na = "")
  if (file.exists(path)) unlink(path)
  if (!file.rename(temp, path)) stop("Could not atomically move CSV into place: ", path)
  invisible(path)
}

main_atomic_write_json <- function(object, path) {
  main_ensure_parent(path)
  text <- jsonlite::toJSON(
    object, auto_unbox = TRUE, pretty = TRUE, digits = 17,
    na = "null", null = "null", dataframe = "rows"
  )
  temp <- tempfile(pattern = paste0(".", basename(path), "."), tmpdir = dirname(path))
  on.exit(if (file.exists(temp)) unlink(temp), add = TRUE)
  writeLines(text, temp, useBytes = TRUE)
  if (file.exists(path)) unlink(path)
  if (!file.rename(temp, path)) stop("Could not atomically move JSON into place: ", path)
  invisible(path)
}

main_config_fingerprint <- function(cfg) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required")
  digest::digest(canonical_main_config_json(cfg), algo = "sha256", serialize = FALSE)
}

initialize_main_output <- function(output_dir, cfg) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  for (folder in c("schedules", "screening_audits", "checkpoints", "figures", "plot_data")) {
    dir.create(file.path(output_dir, folder), recursive = TRUE, showWarnings = FALSE)
  }
  fingerprint <- main_config_fingerprint(cfg)
  resolved <- file.path(output_dir, "config.resolved.json")
  if (file.exists(resolved)) {
    existing <- load_main_config(resolved)
    if (!identical(main_config_fingerprint(existing), fingerprint)) {
      stop("Output directory belongs to a different resolved configuration")
    }
  } else {
    main_atomic_write_json(cfg, resolved)
  }
  fingerprint
}

main_schedule_path <- function(output_dir, replicate_id) {
  file.path(output_dir, "schedules", sprintf("replicate_%03d.rds", replicate_id))
}

main_screening_audit_path <- function(output_dir, setting_id, replicate_id) {
  file.path(
    output_dir, "screening_audits",
    sprintf("setting_%02d_replicate_%03d.rds", setting_id, replicate_id)
  )
}

main_checkpoint_dir <- function(output_dir, setting_id, replicate_id, spec_id) {
  file.path(
    output_dir, "checkpoints",
    sprintf("setting_%02d", setting_id),
    sprintf("replicate_%03d", replicate_id), spec_id
  )
}

main_full_checkpoint_path <- function(output_dir, setting_id, replicate_id, spec_id) {
  file.path(main_checkpoint_dir(output_dir, setting_id, replicate_id, spec_id), "full.rds")
}

main_deletion_checkpoint_path <- function(output_dir, setting_id, replicate_id, spec_id, deletion_id) {
  file.path(
    main_checkpoint_dir(output_dir, setting_id, replicate_id, spec_id),
    sprintf("deletion_%03d.rds", deletion_id)
  )
}

read_main_checkpoint <- function(path, fingerprint) {
  object <- readRDS(path)
  if (!identical(object$config_fingerprint, fingerprint)) {
    stop("Checkpoint fingerprint mismatch: ", path)
  }
  object
}

main_checkpoint_files <- function(output_dir, pattern) {
  root <- file.path(output_dir, "checkpoints")
  if (!dir.exists(root)) return(character())
  list.files(root, pattern = pattern, recursive = TRUE, full.names = TRUE)
}

main_control_dir <- function(output_dir) file.path(output_dir, "control")

main_pause_flag_path <- function(output_dir) {
  file.path(main_control_dir(output_dir), "pause.request.json")
}

main_pause_requested <- function(output_dir) {
  file.exists(main_pause_flag_path(output_dir))
}

request_main_pause <- function(output_dir, reason = "user_or_automation_request") {
  dir.create(main_control_dir(output_dir), recursive = TRUE, showWarnings = FALSE)
  main_atomic_write_json(list(
    requested_at_utc = main_utc_timestamp(),
    reason = reason
  ), main_pause_flag_path(output_dir))
  invisible(main_pause_flag_path(output_dir))
}

clear_main_pause <- function(output_dir) {
  path <- main_pause_flag_path(output_dir)
  if (file.exists(path)) unlink(path)
  invisible(!file.exists(path))
}

main_worker_pause_marker <- function(output_dir, setting_id, replicate_id) {
  file.path(
    main_control_dir(output_dir), "paused_workers",
    sprintf("setting_%02d_replicate_%03d.json", setting_id, replicate_id)
  )
}

mark_main_worker_paused <- function(output_dir, setting_id, replicate_id, boundary, spec_id = NULL, deletion_id = NULL) {
  main_atomic_write_json(list(
    paused_at_utc = main_utc_timestamp(), setting = setting_id,
    replicate = replicate_id, boundary = boundary,
    method = spec_id, next_deletion = deletion_id
  ), main_worker_pause_marker(output_dir, setting_id, replicate_id))
  invisible(TRUE)
}

clear_main_worker_marker <- function(output_dir, setting_id, replicate_id) {
  path <- main_worker_pause_marker(output_dir, setting_id, replicate_id)
  if (file.exists(path)) unlink(path)
  invisible(TRUE)
}

prepare_main_schedules <- function(cfg, output_dir, replicate_ids = seq_len(cfg$simulation$replicates)) {
  theta_path <- file.path(output_dir, "dense_theta.json")
  theta <- draw_dense_theta(cfg)
  if (!file.exists(theta_path)) {
    main_atomic_write_json(list(
      coefficient_seed = cfg$coefficient_seed,
      p = length(theta),
      realized_squared_norm = sum(theta^2),
      theta = unname(theta)
    ), theta_path)
  }
  for (replicate_id in replicate_ids) {
    path <- main_schedule_path(output_dir, replicate_id)
    if (!file.exists(path)) {
      message("Preparing saved randomization block ", replicate_id)
      block <- generate_replicate_block(cfg, replicate_id, theta)
      main_atomic_save_rds(block, path)
    }
  }
  invisible(theta)
}

build_main_screening_audit <- function(data, uniforms, cfg, setting_id, replicate_id) {
  n <- nrow(data$X)
  p <- ncol(data$X)
  threshold <- cfg$simulation$variance_threshold
  full_variances <- unbiased_feature_variances(data$X)
  full_means <- colMeans(data$X)
  deleted <- t(vapply(seq_len(n), function(i) {
    leave_one_out_feature_variances(full_variances, full_means, data$X[i, ], n)
  }, numeric(p)))
  variances <- rbind(full = full_variances, deleted)
  hard <- variances > threshold
  q <- lapply(cfg$soft_screening$nu, function(nu) {
    stats::plogis((variances - threshold) / nu)
  })
  names(q) <- paste0("nu_", format(cfg$soft_screening$nu, trim = TRUE, scientific = FALSE))
  list(
    schema_version = 1L,
    setting = as.integer(setting_id),
    replicate = as.integer(replicate_id),
    variant_rows = c("full", paste0("delete_", seq_len(n))),
    feature_names = colnames(data$X),
    threshold = threshold,
    nu = cfg$soft_screening$nu,
    unbiased_variances = variances,
    hard_selected = hard,
    soft_inclusion_probabilities = q,
    shared_mask_uniforms = uniforms,
    binary_mask_reconstruction = "mask[b,j] = (shared_mask_uniforms[b,j] <= soft_inclusion_probabilities[[nu]][variant,j])"
  )
}

ensure_main_screening_audit <- function(data, uniforms, cfg, setting_id, replicate_id, output_dir) {
  path <- main_screening_audit_path(output_dir, setting_id, replicate_id)
  if (!file.exists(path)) {
    audit <- build_main_screening_audit(data, uniforms, cfg, setting_id, replicate_id)
    main_atomic_save_rds(audit, path)
  }
  invisible(path)
}
