regression_mean <- function(X) {
  if (!is.matrix(X) || ncol(X) < 5L) stop("X must be a matrix with at least five columns")
  sin_scale <- sqrt(2 / (1 - exp(-2)))
  sin_scale * sin(X[, 1L]) +
    X[, 2L] * X[, 3L] +
    (X[, 4L]^2 - 1) / sqrt(2) +
    (2 * as.numeric(X[, 5L] > 0) - 1)
}

generate_replicate <- function(cfg, replicate_id) {
  n <- cfg$simulation$n
  p <- cfg$simulation$p
  n_test <- cfg$simulation$n_test
  seed <- derive_seed(cfg$master_seed, "data", replicate_id)
  with_local_seed(seed, {
    X <- matrix(stats::rnorm(n * p), nrow = n, ncol = p)
    colnames(X) <- paste0("X", seq_len(p))
    mu <- regression_mean(X)
    y <- mu + stats::rnorm(n, sd = sqrt(cfg$simulation$noise_variance))
    X_test <- matrix(stats::rnorm(n_test * p), nrow = n_test, ncol = p)
    colnames(X_test) <- colnames(X)
    mu_test <- regression_mean(X_test)
    list(X = X, y = y, mu = mu, X_test = X_test, mu_test = mu_test)
  })
}

unbiased_feature_variances <- function(X) {
  if (!is.matrix(X) || nrow(X) < 2L) stop("At least two rows are required for sample variances")
  apply(X, 2L, stats::var)
}

leave_one_out_feature_variances <- function(full_variances, full_means, x_i, n) {
  if (n <= 2L) stop("n must exceed two for leave-one-out unbiased variances")
  if (length(full_variances) != length(full_means) || length(full_means) != length(x_i)) {
    stop("Variance, mean, and observation vectors must have equal length")
  }
  deleted_m2 <- (n - 1) * full_variances - (n / (n - 1)) * (x_i - full_means)^2
  # Roundoff can produce a tiny negative value for a constant column.
  pmax(deleted_m2 / (n - 2), 0)
}

hard_selected_features <- function(X, threshold) {
  which(unbiased_feature_variances(X) > threshold)
}

soft_inclusion_probabilities <- function(X, threshold, nu) {
  z <- (unbiased_feature_variances(X) - threshold) / nu
  # plogis is stable for large positive and negative inputs.
  stats::plogis(z)
}

soft_probabilities_from_variances <- function(variances, threshold, nu) {
  stats::plogis((variances - threshold) / nu)
}
