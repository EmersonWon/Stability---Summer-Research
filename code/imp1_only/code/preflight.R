#!/usr/bin/env Rscript

required_packages <- c("ranger", "jsonlite", "digest", "data.table", "ggplot2")
optional_packages <- c("arrow")

package_status <- function(packages) {
  data.frame(
    package = packages,
    installed = vapply(packages, requireNamespace, logical(1), quietly = TRUE),
    version = vapply(packages, function(pkg) {
      if (requireNamespace(pkg, quietly = TRUE)) as.character(utils::packageVersion(pkg)) else NA_character_
    }, character(1)),
    stringsAsFactors = FALSE
  )
}

args <- commandArgs(trailingOnly = TRUE)
strict <- "--strict" %in% args
required <- package_status(required_packages)
optional <- package_status(optional_packages)

cat("R facility preflight\n")
cat("R: ", R.version.string, "\n", sep = "")
cat("Platform: ", R.version$platform, "\n", sep = "")
cat("RNGkind: ", paste(RNGkind(), collapse = " / "), "\n", sep = "")
cat("Locale: ", paste(Sys.getlocale(), collapse = "; "), "\n", sep = "")
cat("Logical cores: ", parallel::detectCores(logical = TRUE), "\n", sep = "")
cat("Library paths:\n  ", paste(.libPaths(), collapse = "\n  "), "\n", sep = "")
cat("\nRequired packages:\n")
print(required, row.names = FALSE)
cat("\nOptional compressed-storage package:\n")
print(optional, row.names = FALSE)

missing <- required$package[!required$installed]
cat("\nStatus: ")
if (length(missing)) {
  cat("NOT READY; missing ", paste(missing, collapse = ", "), ".\n", sep = "")
  if (strict) quit(status = 1L)
} else {
  cat("READY for smoke execution. Run the included tests before any full study.\n")
}
