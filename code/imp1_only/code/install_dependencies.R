#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) {
  normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE)
} else {
  normalizePath("install_dependencies.R", mustWork = TRUE)
}
project_dir <- dirname(script_path)
local_lib <- file.path(project_dir, "Rlib")
dir.create(local_lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(local_lib, .libPaths()))

required <- c("ranger", "jsonlite", "digest", "data.table", "ggplot2")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  install.packages(
    missing,
    repos = "https://cloud.r-project.org",
    lib = local_lib,
    dependencies = c("Depends", "Imports", "LinkingTo")
  )
}

still_missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(still_missing)) {
  stop("Could not install required package(s): ", paste(still_missing, collapse = ", "))
}

cat("Dependencies are available in ", local_lib, "\n", sep = "")
for (pkg in required) {
  cat(pkg, " ", as.character(utils::packageVersion(pkg)), "\n", sep = "")
}
