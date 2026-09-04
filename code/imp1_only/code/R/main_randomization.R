with_recorded_rng <- function(cfg, seed, code) {
  old_kind <- RNGkind()
  existed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (existed) old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (existed) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  RNGkind(cfg$rng$kind, cfg$rng$normal_kind, cfg$rng$sample_kind)
  set.seed(as.integer(seed))
  force(code)
}

sparse_base_function <- function(X) {
  if (!is.matrix(X) || ncol(X) < 5L) stop("X must have at least five columns")
  c_sin <- sqrt(2 / (1 - exp(-2)))
  c_sin * sin(X[, 1L]) + X[, 2L] * X[, 3L] +
    (X[, 4L]^2 - 1) / sqrt(2) + 2 * as.numeric(X[, 5L] > 0) - 1
}

sparse_setting_mean <- function(X, a, b) a * (sparse_base_function(X) - b)

draw_dense_theta <- function(cfg) {
  p <- cfg$simulation$p
  with_recorded_rng(cfg, cfg$coefficient_seed, {
    theta <- stats::runif(p, -1, 1) * sqrt(6 / p)
    names(theta) <- paste0("X", seq_len(p))
    theta
  })
}

ar1_covariance <- function(p, rho) {
  rho ^ abs(outer(seq_len(p), seq_len(p), "-"))
}

draw_ar1_gaussian <- function(n, p, rho) {
  Z <- matrix(stats::rnorm(n * p), nrow = n, ncol = p)
  Z %*% chol(ar1_covariance(p, rho))
}

main_effective_counts <- function(cfg) {
  override <- cfg$execution_overrides
  list(
    trees = as.integer(if (is.null(override)) cfg$random_forest$trees else override$random_forest_trees),
    masks_1 = as.integer(if (is.null(override)) cfg$soft_screening$implementation_1_masks else override$implementation_1_masks),
    masks_2 = as.integer(if (is.null(override)) cfg$soft_screening$implementation_2_masks else override$implementation_2_masks)
  )
}

draw_component_seeds <- function(count) {
  sample.int(.Machine$integer.max - 1L, count, replace = FALSE)
}

generate_replicate_block <- function(cfg, replicate_id, theta) {
  if (replicate_id < 1L || replicate_id > cfg$simulation$replicates) stop("Invalid replicate_id")
  n <- cfg$simulation$n
  p <- cfg$simulation$p
  n_test <- cfg$simulation$n_test
  sigma_eps <- sqrt(cfg$simulation$noise_variance)
  counts <- main_effective_counts(cfg)
  base_seed <- cfg$replicate_seeds[[replicate_id]]
  setting <- function(id) cfg$settings[cfg$settings$id == id, , drop = FALSE]

  with_recorded_rng(cfg, base_seed, {
    feature_names <- paste0("X", seq_len(p))
    X14 <- matrix(stats::rnorm(n * p), nrow = n, ncol = p)
    X14_test <- matrix(stats::rnorm(n_test * p), nrow = n_test, ncol = p)
    eps1 <- stats::rnorm(n, sd = sigma_eps)
    eps4 <- stats::rnorm(n, sd = sigma_eps)

    X2 <- matrix(stats::runif(n * p, -sqrt(3), sqrt(3)), nrow = n, ncol = p)
    X2_test <- matrix(stats::runif(n_test * p, -sqrt(3), sqrt(3)), nrow = n_test, ncol = p)
    eps2 <- stats::rnorm(n, sd = sigma_eps)

    rho3 <- setting(3L)$rho[[1L]]
    X3 <- draw_ar1_gaussian(n, p, rho3)
    X3_test <- draw_ar1_gaussian(n_test, p, rho3)
    eps3 <- stats::rnorm(n, sd = sigma_eps)

    colnames(X14) <- colnames(X14_test) <- feature_names
    colnames(X2) <- colnames(X2_test) <- feature_names
    colnames(X3) <- colnames(X3_test) <- feature_names

    s1 <- setting(1L); s2 <- setting(2L); s3 <- setting(3L)
    mu1 <- sparse_setting_mean(X14, s1$a[[1L]], s1$b[[1L]])
    mu1_test <- sparse_setting_mean(X14_test, s1$a[[1L]], s1$b[[1L]])
    mu2 <- sparse_setting_mean(X2, s2$a[[1L]], s2$b[[1L]])
    mu2_test <- sparse_setting_mean(X2_test, s2$a[[1L]], s2$b[[1L]])
    mu3 <- sparse_setting_mean(X3, s3$a[[1L]], s3$b[[1L]])
    mu3_test <- sparse_setting_mean(X3_test, s3$a[[1L]], s3$b[[1L]])
    mu4 <- as.numeric(X14 %*% theta)
    mu4_test <- as.numeric(X14_test %*% theta)

    data <- list(
      setting_1 = list(X = X14, y = mu1 + eps1, mu = mu1, X_test = X14_test, mu_test = mu1_test),
      setting_2 = list(X = X2, y = mu2 + eps2, mu = mu2, X_test = X2_test, mu_test = mu2_test),
      setting_3 = list(X = X3, y = mu3 + eps3, mu = mu3, X_test = X3_test, mu_test = mu3_test),
      setting_4 = list(X = X14, y = mu4 + eps4, mu = mu4, X_test = X14_test, mu_test = mu4_test)
    )

    mask_count <- max(counts$masks_1, counts$masks_2)
    mask_uniforms <- lapply(seq_len(4L), function(i) {
      matrix(stats::runif(mask_count * p), nrow = mask_count, ncol = p, byrow = TRUE)
    })
    names(mask_uniforms) <- names(data)

    learner_seeds <- lapply(seq_len(4L), function(i) list(
      ordinary = setNames(draw_component_seeds(3L), c("all_features", "hard_screening", "frozen_hard_screening")),
      soft_implementation_1 = draw_component_seeds(counts$masks_1),
      soft_implementation_2 = draw_component_seeds(1L)
    ))
    names(learner_seeds) <- names(data)

    list(
      schema_version = 1L,
      replicate = as.integer(replicate_id),
      base_seed = as.integer(base_seed),
      rngkind = unname(RNGkind()),
      generation_order = c(
        "shared_setting_1_4_train_X", "shared_setting_1_4_test_X",
        "setting_1_response_noise", "setting_4_response_noise",
        "setting_2_train_X", "setting_2_test_X", "setting_2_response_noise",
        "setting_3_train_X", "setting_3_test_X", "setting_3_response_noise",
        "setting_specific_mask_uniforms", "setting_specific_learner_component_seeds"
      ),
      effective_counts = counts,
      data = data,
      mask_uniforms = mask_uniforms,
      learner_seeds = learner_seeds
    )
  })
}

unbiased_feature_variances <- function(X) apply(X, 2L, stats::var)

leave_one_out_feature_variances <- function(full_variances, full_means, x_i, n) {
  if (n <= 2L) stop("n must exceed two")
  deleted_m2 <- (n - 1) * full_variances - (n / (n - 1)) * (x_i - full_means)^2
  pmax(deleted_m2 / (n - 2), 0)
}

soft_probabilities_from_variances <- function(variances, threshold, nu) {
  stats::plogis((variances - threshold) / nu)
}
