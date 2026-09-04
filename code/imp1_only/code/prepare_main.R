#!/usr/bin/env Rscript

script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
project_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE))
source(file.path(project_dir, "R", "main_config.R"))
source(file.path(project_dir, "R", "main_randomization.R"))

args <- commandArgs(trailingOnly = TRUE)
smoke <- "--smoke" %in% args
value_after <- function(option, default = NULL) {
  hit <- which(args == option)
  if (!length(hit)) return(default)
  if (hit[[1L]] == length(args)) stop(option, " requires a value")
  args[[hit[[1L]] + 1L]]
}

config_path <- value_after("--config", file.path(project_dir, "config.json"))
output_dir <- value_after(
  "--output-dir",
  file.path(project_dir, "outputs", if (smoke) "smoke_schedule" else "main_schedule")
)
cfg <- load_main_config(config_path)
if (smoke) cfg <- make_main_smoke_config(cfg)

atomic_save_rds <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = paste0(".", basename(path), "."), tmpdir = dirname(path))
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  saveRDS(object, tmp, compress = "xz")
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) stop("Could not move file into place: ", path)
}

atomic_write_json <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  text <- jsonlite::toJSON(
    object, auto_unbox = TRUE, pretty = TRUE, digits = 17,
    na = "null", null = "null", dataframe = "rows"
  )
  tmp <- tempfile(pattern = paste0(".", basename(path), "."), tmpdir = dirname(path))
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  writeLines(text, tmp, useBytes = TRUE)
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) stop("Could not move file into place: ", path)
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
theta <- draw_dense_theta(cfg)
atomic_write_json(list(
  coefficient_seed = cfg$coefficient_seed,
  p = length(theta),
  realized_squared_norm = sum(theta^2),
  theta = unname(theta)
), file.path(output_dir, "dense_theta.json"))
atomic_write_json(cfg, file.path(output_dir, "config.resolved.json"))

block_files <- character(cfg$simulation$replicates)
for (replicate_id in seq_len(cfg$simulation$replicates)) {
  message("Preparing replicate block ", replicate_id, "/", cfg$simulation$replicates)
  block <- generate_replicate_block(cfg, replicate_id, theta)
  path <- file.path(output_dir, sprintf("replicate_%03d_schedule.rds", replicate_id))
  atomic_save_rds(block, path)
  block_files[[replicate_id]] <- basename(path)
}

manifest <- list(
  schema_version = 1L,
  prepared_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  smoke = smoke,
  r_version = R.version.string,
  platform = R.version$platform,
  rngkind = unname(RNGkind()),
  coefficient_seed = cfg$coefficient_seed,
  replicate_seeds = cfg$replicate_seeds,
  theta_squared_norm = sum(theta^2),
  generation_order = readRDS(file.path(output_dir, block_files[[1L]]))$generation_order,
  schedule_files = block_files
)
atomic_write_json(manifest, file.path(output_dir, "schedule_manifest.json"))
message("Prepared schedules in ", normalizePath(output_dir, mustWork = TRUE))
