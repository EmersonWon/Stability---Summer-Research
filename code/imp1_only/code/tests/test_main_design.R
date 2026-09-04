#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
project_dir <- dirname(dirname(normalizePath(sub("^--file=", "", file_arg[[1L]]), mustWork = TRUE)))
source(file.path(project_dir, "R", "main_config.R"))
source(file.path(project_dir, "R", "main_randomization.R"))

expect_true <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
expect_equal <- function(actual, expected, tolerance = 0, message = "Values differ") {
  ok <- isTRUE(all.equal(actual, expected, tolerance = tolerance, check.attributes = TRUE))
  if (!ok) stop(message, call. = FALSE)
}

cfg_full <- load_main_config(file.path(project_dir, "config.json"))
expect_equal(cfg_full$simulation$n, 500L)
expect_equal(cfg_full$simulation$p, 200L)
expect_equal(cfg_full$simulation$n_test, 5000L)
expect_equal(cfg_full$simulation$replicates, 10L)
expect_equal(length(cfg_full$methods), 9L)
expect_equal(4L * 10L * 9L * 500L, 180000L)

cfg <- make_main_smoke_config(cfg_full)
theta_a <- draw_dense_theta(cfg)
theta_b <- draw_dense_theta(cfg)
expect_equal(theta_a, theta_b, message = "theta is not reproducible")
expect_equal(length(theta_a), cfg$simulation$p)

block_a <- generate_replicate_block(cfg, 1L, theta_a)
block_b <- generate_replicate_block(cfg, 1L, theta_a)
expect_true(identical(block_a, block_b), "replicate block is not bitwise reproducible")

for (s in seq_len(4L)) {
  dat <- block_a$data[[s]]
  expect_equal(dim(dat$X), c(20L, 6L))
  expect_equal(dim(dat$X_test), c(50L, 6L))
  expect_equal(length(dat$y), 20L)
  expect_equal(length(dat$mu_test), 50L)
  expect_true(all(is.finite(dat$y)), paste("non-finite y in setting", s))
}

expect_true(identical(block_a$data$setting_1$X, block_a$data$setting_4$X),
  "Settings 1 and 4 do not share training covariates")
expect_true(identical(block_a$data$setting_1$X_test, block_a$data$setting_4$X_test),
  "Settings 1 and 4 do not share test covariates")
expect_true(!identical(block_a$data$setting_1$y, block_a$data$setting_4$y),
  "Settings 1 and 4 responses should be generated separately")

bound <- sqrt(3)
expect_true(all(block_a$data$setting_2$X >= -bound & block_a$data$setting_2$X <= bound),
  "Setting 2 is outside its prescribed support")
expect_equal(ar1_covariance(4L, 0.9)[1L, ], 0.9^(0:3), tolerance = 1e-15,
  message = "AR(1) covariance construction is wrong")

counts <- main_effective_counts(cfg)
expect_equal(counts$trees, 3L)
expect_equal(counts$masks_1, 2L)
expect_equal(counts$masks_2, 3L)
for (s in seq_len(4L)) {
  expect_equal(dim(block_a$mask_uniforms[[s]]), c(3L, 6L))
  expect_equal(length(block_a$learner_seeds[[s]]$ordinary), 3L)
  expect_equal(length(block_a$learner_seeds[[s]]$soft_implementation_1), 2L)
  expect_equal(length(block_a$learner_seeds[[s]]$soft_implementation_2), 1L)
}

X <- block_a$data$setting_1$X
full_v <- unbiased_feature_variances(X)
full_m <- colMeans(X)
for (i in seq_len(nrow(X))) {
  fast <- leave_one_out_feature_variances(full_v, full_m, X[i, ], nrow(X))
  direct <- unbiased_feature_variances(X[-i, , drop = FALSE])
  expect_equal(fast, direct, tolerance = 1e-12, message = paste("LOO variance mismatch at", i))
}

q <- soft_probabilities_from_variances(c(0.9, 1, 1.1), 1, 0.025)
expect_equal(q[[2L]], 0.5, tolerance = 0)
expect_true(q[[1L]] < 0.5 && q[[3L]] > 0.5, "soft probabilities are not monotone around threshold")

cat("All main-design tests passed.\n")
