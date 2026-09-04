#!/usr/bin/env Rscript

all_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", all_args, value = TRUE)
project_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE))
for (module in c(
  "main_config.R", "main_randomization.R", "main_models.R",
  "main_storage.R", "main_results.R"
)) source(file.path(project_dir, "R", module))

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("Usage: Rscript summarize_main.R OUTPUT_DIR")
output_dir <- normalizePath(args[[1L]], mustWork = TRUE)
cfg <- load_main_config(file.path(output_dir, "config.resolved.json"))
fingerprint <- main_config_fingerprint(cfg)
scope_path <- file.path(output_dir, "execution_scope.json")
scope <- if (file.exists(scope_path)) {
  jsonlite::fromJSON(scope_path, simplifyVector = TRUE)
} else NULL
aggregate_main_results(output_dir, cfg, fingerprint, scope)
message("Summaries and figures regenerated in ", output_dir)
