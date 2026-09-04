pilot_control_or <- function(x, y) if (is.null(x) || !length(x)) y else x

pilot_pause_flag_path <- function(output_dir) {
  file.path(output_dir, ".pilot_pause_requested.json")
}

pilot_pause_marker_dir <- function(output_dir) {
  file.path(output_dir, ".pilot_control", "paused_workers")
}

pilot_pause_marker_path <- function(output_dir, replicate_id) {
  replicate_id <- as.integer(replicate_id)
  if (length(replicate_id) != 1L || is.na(replicate_id) || replicate_id < 1L) {
    stop("replicate_id must be one positive integer")
  }
  file.path(
    pilot_pause_marker_dir(output_dir),
    sprintf("replicate_%03d.json", replicate_id)
  )
}

pilot_pause_requested <- function(output_dir) {
  file.exists(pilot_pause_flag_path(output_dir))
}

request_pilot_pause <- function(output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  path <- pilot_pause_flag_path(output_dir)
  if (!file.exists(path)) {
    atomic_write_json(list(
      schema_version = 1L,
      requested_at_utc = utc_timestamp(),
      requester_pid = Sys.getpid()
    ), path)
  }
  invisible(path)
}

pilot_pause_marker_files <- function(output_dir) {
  marker_dir <- pilot_pause_marker_dir(output_dir)
  if (!dir.exists(marker_dir)) return(character())
  sort(list.files(
    marker_dir, pattern = "^replicate_[0-9]+\\.json$",
    full.names = TRUE
  ))
}

remove_pilot_pause_marker <- function(output_dir, replicate_id) {
  path <- pilot_pause_marker_path(output_dir, replicate_id)
  if (file.exists(path) && unlink(path) != 0L) {
    warning("Could not remove pause marker: ", path, call. = FALSE)
  }
  invisible(path)
}

remove_all_pilot_pause_markers <- function(output_dir) {
  paths <- pilot_pause_marker_files(output_dir)
  if (length(paths)) {
    failures <- paths[!vapply(paths, function(path) unlink(path) == 0L, logical(1))]
    if (length(failures)) {
      warning(
        "Could not remove pause marker(s): ", paste(failures, collapse = ", "),
        call. = FALSE
      )
    }
  }
  invisible(paths)
}

resume_pilot <- function(output_dir) {
  flag <- pilot_pause_flag_path(output_dir)
  if (file.exists(flag) && unlink(flag) != 0L) {
    stop("Could not remove pilot pause request: ", flag)
  }
  # Workers also remove their own marker as soon as they observe the cleared
  # flag. Clearing here makes resume idempotent and removes markers left by a
  # worker that exited abnormally.
  remove_all_pilot_pause_markers(output_dir)
  invisible(flag)
}

write_pilot_pause_marker <- function(
  output_dir, replicate_id, boundary, spec_id = NULL, deletion_id = NULL
) {
  marker <- list(
    schema_version = 1L,
    replicate = as.integer(replicate_id),
    worker_pid = Sys.getpid(),
    paused_at_utc = utc_timestamp(),
    boundary = as.character(boundary),
    spec_id = spec_id,
    deletion = if (is.null(deletion_id)) NULL else as.integer(deletion_id)
  )
  path <- pilot_pause_marker_path(output_dir, replicate_id)
  atomic_write_json(marker, path)
  invisible(path)
}

pilot_pause_safe_point <- function(
  output_dir, replicate_id, boundary, spec_id = NULL, deletion_id = NULL,
  poll_seconds = getOption("pilot.pause_poll_seconds", 2),
  sleep_function = Sys.sleep
) {
  if (!pilot_pause_requested(output_dir)) {
    remove_pilot_pause_marker(output_dir, replicate_id)
    return(invisible(FALSE))
  }
  if (length(poll_seconds) != 1L || !is.numeric(poll_seconds) ||
      is.na(poll_seconds) || !is.finite(poll_seconds) || poll_seconds <= 0) {
    stop("poll_seconds must be one positive finite number")
  }
  if (!is.function(sleep_function)) stop("sleep_function must be a function")

  marker_path <- write_pilot_pause_marker(
    output_dir, replicate_id, boundary, spec_id, deletion_id
  )
  on.exit(remove_pilot_pause_marker(output_dir, replicate_id), add = TRUE)
  location <- paste0(
    boundary,
    if (!is.null(spec_id)) paste0(" for ", spec_id) else "",
    if (!is.null(deletion_id)) paste0(", deletion ", deletion_id) else ""
  )
  message(
    "replicate ", replicate_id, " paused at safe point (", location,
    "); marker: ", marker_path
  )
  while (pilot_pause_requested(output_dir)) {
    sleep_function(poll_seconds)
  }
  message("replicate ", replicate_id, " resumed")
  invisible(TRUE)
}

read_pilot_control_json <- function(path) {
  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = TRUE),
    error = function(e) structure(
      list(file = path, error = conditionMessage(e)), class = "pilot_control_read_error"
    )
  )
}

pilot_control_status <- function(output_dir) {
  flag_path <- pilot_pause_flag_path(output_dir)
  flag <- if (file.exists(flag_path)) read_pilot_control_json(flag_path) else NULL
  marker_paths <- pilot_pause_marker_files(output_dir)
  markers <- lapply(marker_paths, read_pilot_control_json)

  full_files <- checkpoint_files(output_dir, "^full\\.rds$")
  deletion_files <- checkpoint_files(output_dir, "^deletion_[0-9]+\\.rds$")
  all_checkpoints <- c(full_files, deletion_files)
  last_checkpoint <- NULL
  if (length(all_checkpoints)) {
    info <- file.info(all_checkpoints)
    valid <- !is.na(info$mtime)
    if (any(valid)) {
      valid_paths <- all_checkpoints[valid]
      valid_info <- info[valid, , drop = FALSE]
      index <- which.max(valid_info$mtime)
      last_checkpoint <- list(
        path = valid_paths[[index]],
        modified_at_utc = format(
          valid_info$mtime[[index]], "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
        )
      )
    }
  }

  list(
    output_dir = output_dir,
    output_exists = dir.exists(output_dir),
    pause_requested = file.exists(flag_path),
    pause_request = flag,
    paused_worker_count = length(marker_paths),
    paused_workers = markers,
    completed_full_fit_checkpoints = length(full_files),
    completed_deletion_checkpoints = length(deletion_files),
    last_checkpoint = last_checkpoint
  )
}

pilot_control_relative_path <- function(path, output_dir) {
  output_prefix <- paste0(normalizePath(output_dir, mustWork = FALSE), .Platform$file.sep)
  normalized <- normalizePath(path, mustWork = FALSE)
  if (startsWith(normalized, output_prefix)) {
    substring(normalized, nchar(output_prefix) + 1L)
  } else {
    normalized
  }
}

print_pilot_control_status <- function(status) {
  cat("Output directory: ", status$output_dir, "\n", sep = "")
  cat("Pause requested: ", if (status$pause_requested) "yes" else "no", sep = "")
  if (status$pause_requested && !inherits(
    status$pause_request, "pilot_control_read_error"
  )) {
    requested_at <- pilot_control_or(status$pause_request$requested_at_utc, NULL)
    if (!is.null(requested_at)) cat(" (since ", requested_at, ")", sep = "")
  }
  cat("\n")
  cat("Workers at pause safe points: ", status$paused_worker_count, "\n", sep = "")
  if (length(status$paused_workers)) {
    for (marker in status$paused_workers) {
      if (inherits(marker, "pilot_control_read_error")) {
        cat("  unreadable marker: ", marker$file, " (", marker$error, ")\n", sep = "")
      } else {
        detail <- paste0(
          "  replicate ", pilot_control_or(marker$replicate, "?"),
          ": ", pilot_control_or(marker$boundary, "unknown boundary")
        )
        if (!is.null(marker$spec_id)) detail <- paste0(detail, ", ", marker$spec_id)
        if (!is.null(marker$deletion)) detail <- paste0(detail, ", deletion ", marker$deletion)
        if (!is.null(marker$paused_at_utc)) {
          detail <- paste0(detail, " (since ", marker$paused_at_utc, ")")
        }
        cat(detail, "\n", sep = "")
      }
    }
  }
  cat("Completed full-fit checkpoints: ", status$completed_full_fit_checkpoints, "\n", sep = "")
  cat("Completed deletion checkpoints: ", status$completed_deletion_checkpoints, "\n", sep = "")
  if (is.null(status$last_checkpoint)) {
    cat("Last checkpoint: none\n")
  } else {
    cat(
      "Last checkpoint: ", status$last_checkpoint$modified_at_utc, " (",
      pilot_control_relative_path(status$last_checkpoint$path, status$output_dir), ")\n",
      sep = ""
    )
  }
  invisible(status)
}
