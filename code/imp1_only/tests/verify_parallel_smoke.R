args <- commandArgs(FALSE)
test_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", args, value = TRUE)[[1]])))
serial <- read.csv(file.path(test_dir, "smoke_serial", "deletion_results.csv"))
parallel_data <- read.csv(file.path(test_dir, "smoke_parallel", "deletion_results.csv"))
stopifnot(identical(serial, parallel_data), nrow(serial) == 480L,
  length(unique(serial$method_id)) == 6L, !any(grepl("^soft1_", serial$method_id)),
  all(serial$test_prediction_count == 50L), all(is.finite(serial$delta)),
  !anyDuplicated(serial[c("setting", "replicate", "method_id", "deletion")]))
ds <- read.csv(file.path(test_dir, "smoke_parallel", "dataset_results.csv"))
sm <- read.csv(file.path(test_dir, "smoke_parallel", "setting_method_summary.csv"))
stopifnot(nrow(ds) == 24L, all(ds$all_deletions_complete), nrow(sm) == 24L)
files <- list.files(file.path(test_dir, "smoke_serial", "checkpoints"), pattern = "^full\\.rds$", recursive = TRUE)
for (relative in files) {
  a <- readRDS(file.path(test_dir, "smoke_serial", "checkpoints", relative))
  b <- readRDS(file.path(test_dir, "smoke_parallel", "checkpoints", relative))
  stopifnot(identical(a$prediction, b$prediction))
}
report <- list(pass = TRUE, deletion_rows = 480L, methods = 6L, settings = 4L,
  complete_dataset_method_cells = 24L, serial_parallel_predictions_identical = TRUE,
  serial_parallel_result_rows_identical = TRUE, no_soft1_fits = TRUE)
writeLines(jsonlite::toJSON(report, auto_unbox = TRUE, pretty = TRUE), file.path(test_dir, "parallel_verification.json"))
cat("PASS: all 480 rows and 24 full prediction vectors match exactly between 1 and 2 workers.\n")
