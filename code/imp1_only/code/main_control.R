#!/usr/bin/env Rscript

all_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", all_args, value = TRUE)
project_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE))
source(file.path(project_dir, "R", "main_config.R"))
source(file.path(project_dir, "R", "main_randomization.R"))
source(file.path(project_dir, "R", "main_storage.R"))

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) || !args[[1L]] %in% c("pause", "resume", "status")) {
  stop("Usage: Rscript main_control.R pause|resume|status --output-dir PATH")
}
command <- args[[1L]]
hit <- which(args == "--output-dir")
if (!length(hit) || hit[[1L]] == length(args)) stop("--output-dir PATH is required")
output_dir <- normalizePath(args[[hit[[1L]] + 1L]], mustWork = command != "resume")

checkpoint_stats <- function(output_dir) {
  full <- main_checkpoint_files(output_dir, "^full\\.rds$")
  deletion <- main_checkpoint_files(output_dir, "^deletion_[0-9]+\\.rds$")
  all_files <- c(full, deletion)
  sizes <- if (length(all_files)) file.info(all_files)$size else numeric()
  latest <- if (length(all_files)) max(file.info(all_files)$mtime, na.rm = TRUE) else as.POSIXct(NA)
  markers_root <- file.path(main_control_dir(output_dir), "paused_workers")
  markers <- if (dir.exists(markers_root)) list.files(markers_root, pattern = "\\.json$", full.names = TRUE) else character()
  list(
    output_dir = output_dir,
    pause_requested = main_pause_requested(output_dir),
    full_checkpoints = length(full),
    deletion_checkpoints = length(deletion),
    checkpoint_bytes = sum(sizes, na.rm = TRUE),
    latest_checkpoint = if (is.na(latest)) NA_character_ else format(latest, "%Y-%m-%dT%H:%M:%S%z"),
    paused_worker_markers = length(markers),
    paused_worker_files = basename(markers)
  )
}

if (command == "pause") {
  request_main_pause(output_dir, "main_control_pause")
  cat("Pause requested. Workers will stop before their next full or deletion fit.\n")
} else if (command == "resume") {
  clear_main_pause(output_dir)
  markers <- file.path(main_control_dir(output_dir), "paused_workers")
  if (dir.exists(markers)) unlink(list.files(markers, full.names = TRUE))
  cat("Pause request cleared. Re-run the original run_main.R command to resume.\n")
}
cat(jsonlite::toJSON(checkpoint_stats(output_dir), auto_unbox = TRUE, pretty = TRUE), "\n")
