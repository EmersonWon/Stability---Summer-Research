#!/usr/bin/env Rscript

all_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", all_args, value = TRUE)
project_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE))
for (module in c(
  "main_config.R", "main_randomization.R", "main_models.R",
  "main_storage.R", "main_runner.R", "main_results.R"
)) source(file.path(project_dir, "R", module))

parse_id_spec <- function(text, maximum, label) {
  pieces <- strsplit(text, ",", fixed = TRUE)[[1L]]
  values <- integer()
  for (piece in pieces) {
    piece <- trimws(piece)
    if (grepl("^[0-9]+-[0-9]+$", piece)) {
      bounds <- as.integer(strsplit(piece, "-", fixed = TRUE)[[1L]])
      if (bounds[[1L]] > bounds[[2L]]) stop("Descending range: ", piece)
      values <- c(values, seq.int(bounds[[1L]], bounds[[2L]]))
    } else if (grepl("^[0-9]+$", piece)) {
      values <- c(values, as.integer(piece))
    } else stop("Invalid ", label, " value: ", piece)
  }
  values <- sort(unique(values))
  if (!length(values) || any(values < 1L) || any(values > maximum)) {
    stop(label, " values must be between 1 and ", maximum)
  }
  values
}

args <- commandArgs(trailingOnly = TRUE)
option_value <- function(name, default = NULL) {
  direct <- grep(paste0("^", name, "="), args, value = TRUE)
  if (length(direct)) return(sub(paste0("^", name, "="), "", direct[[1L]]))
  hit <- which(args == name)
  if (!length(hit)) return(default)
  if (hit[[1L]] == length(args)) stop(name, " requires a value")
  args[[hit[[1L]] + 1L]]
}
smoke <- "--smoke" %in% args
force <- "--force" %in% args
aggregate_only <- "--aggregate-only" %in% args
extend_scope <- "--extend-scope" %in% args
if ("--help" %in% args || "-h" %in% args) {
  cat(
    "Four-setting mean-square stability simulation\n\n",
    "Rscript run_main.R [--smoke] [--output-dir PATH] [--replicates 1-10] ",
    "[--settings 1-4] [--methods IDS] [--workers N] [--max-hours HOURS] ",
    "[--extend-scope] [--aggregate-only] [--force]\n"
  )
  quit(status = 0L)
}

config_path <- option_value("--config", file.path(project_dir, "config.json"))
cfg <- load_main_config(config_path)
if (smoke) cfg <- make_main_smoke_config(cfg)
output_dir <- normalizePath(option_value(
  "--output-dir",
  file.path(project_dir, "outputs", if (smoke) "main_smoke" else "main")
), mustWork = FALSE)
workers <- as.integer(option_value("--workers", "1"))
if (is.na(workers) || workers < 1L) stop("--workers must be positive")
max_hours_text <- option_value("--max-hours", NULL)
max_hours <- if (is.null(max_hours_text)) NULL else as.numeric(max_hours_text)
if (!is.null(max_hours) && (length(max_hours) != 1L || !is.finite(max_hours) || max_hours <= 0)) {
  stop("--max-hours must be one positive number")
}
deadline_utc <- if (is.null(max_hours)) NULL else as.numeric(Sys.time()) + 3600 * max_hours
replicate_ids <- parse_id_spec(
  option_value("--replicates", paste0("1-", cfg$simulation$replicates)),
  cfg$simulation$replicates, "replicate"
)
setting_ids <- parse_id_spec(option_value("--settings", "1-4"), 4L, "setting")
all_specs <- build_main_method_specs(cfg)
all_method_ids <- vapply(all_specs, `[[`, character(1), "id")
method_text <- option_value("--methods", paste(all_method_ids, collapse = ","))
method_ids <- trimws(strsplit(method_text, ",", fixed = TRUE)[[1L]])
if (!length(method_ids) || any(!nzchar(method_ids)) || anyDuplicated(method_ids)) {
  stop("--methods must contain unique comma-separated method ids")
}
unknown_methods <- setdiff(method_ids, all_method_ids)
if (length(unknown_methods)) stop("Unknown method id(s): ", paste(unknown_methods, collapse = ", "))
method_ids <- all_method_ids[all_method_ids %in% method_ids]

require_main_ranger()
if (!requireNamespace("data.table", quietly = TRUE)) stop("Package 'data.table' is required")
fingerprint <- initialize_main_output(output_dir, cfg)
scope <- list(
  setting_ids = as.integer(setting_ids),
  replicate_ids = as.integer(replicate_ids),
  method_ids = as.character(method_ids)
)
scope_path <- file.path(output_dir, "execution_scope.json")
if (file.exists(scope_path)) {
  existing_scope <- jsonlite::fromJSON(scope_path, simplifyVector = TRUE)
  same_scope <- identical(as.integer(existing_scope$setting_ids), scope$setting_ids) &&
    identical(as.integer(existing_scope$replicate_ids), scope$replicate_ids) &&
    identical(as.character(existing_scope$method_ids), scope$method_ids)
  if (!same_scope) {
    is_append_only_extension <-
      all(as.integer(existing_scope$setting_ids) %in% scope$setting_ids) &&
      all(as.integer(existing_scope$replicate_ids) %in% scope$replicate_ids) &&
      all(as.character(existing_scope$method_ids) %in% scope$method_ids)
    if (!extend_scope) {
      stop(
        "Output directory belongs to a different execution scope. ",
        "Use --extend-scope only when adding settings, replicates, or methods."
      )
    }
    if (!is_append_only_extension) {
      stop(
        "--extend-scope is append-only: the new scope must retain every existing ",
        "setting, replicate, and method."
      )
    }
    main_atomic_write_json(scope, scope_path)
    message("Execution scope extended; existing checkpoints will be reused.")
  }
} else {
  main_atomic_write_json(scope, scope_path)
}
message("Output: ", output_dir)
message("Configuration fingerprint: ", fingerprint)
message("Execution scope: ", length(setting_ids), " settings x ",
        length(replicate_ids), " replicates x ", length(method_ids), " methods")
if (!is.null(deadline_utc)) {
  message(
    "Checkpoint-safe deadline: ",
    format(as.POSIXct(deadline_utc, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
  )
}

if (!aggregate_only) {
  prepare_main_schedules(cfg, output_dir, replicate_ids)
  run_main_tasks(
    cfg, setting_ids, replicate_ids, output_dir, fingerprint,
    force = force, workers = workers, project_dir = project_dir,
    deadline_utc = deadline_utc, method_ids = method_ids
  )
}
aggregate_main_results(output_dir, cfg, fingerprint, scope)
message("Main-study outputs are up to date.")
