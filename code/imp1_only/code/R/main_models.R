require_main_ranger <- function() {
  if (!requireNamespace("ranger", quietly = TRUE)) {
    stop("Package 'ranger' is required; run preflight.R first")
  }
  invisible(TRUE)
}

main_mtry <- function(d) {
  if (length(d) != 1L || !is.finite(d) || d < 1L) stop("d must be positive")
  max(1L, as.integer(floor(d / 3)))
}

fit_main_forest <- function(X, y, X_test, features, num_trees, seed, cfg) {
  features <- as.integer(features)
  if (!length(features)) return(rep(mean(y), nrow(X_test)))
  require_main_ranger()
  fit <- ranger::ranger(
    x = as.data.frame(X[, features, drop = FALSE]),
    y = as.numeric(y),
    num.trees = as.integer(num_trees),
    mtry = main_mtry(length(features)),
    splitrule = "variance",
    min.node.size = as.integer(cfg$random_forest$min_node_size),
    replace = TRUE,
    sample.fraction = 1,
    seed = as.integer(seed),
    num.threads = as.integer(cfg$random_forest$num_threads),
    write.forest = TRUE,
    oob.error = FALSE,
    verbose = FALSE
  )
  as.numeric(predict(
    fit,
    data = as.data.frame(X_test[, features, drop = FALSE]),
    num.threads = as.integer(cfg$random_forest$num_threads)
  )$predictions)
}

predict_main_soft1 <- function(X, y, X_test, q, uniforms, seeds, cfg) {
  counts <- main_effective_counts(cfg)
  if (nrow(uniforms) < counts$masks_1 || ncol(uniforms) != ncol(X)) {
    stop("Soft-1 uniform matrix has incompatible dimensions")
  }
  if (length(seeds) != counts$masks_1) stop("Soft-1 seed count is wrong")
  total <- numeric(nrow(X_test))
  for (b in seq_len(counts$masks_1)) {
    selected <- which(uniforms[b, ] <= q)
    total <- total + fit_main_forest(
      X, y, X_test, selected, counts$trees, seeds[[b]], cfg
    )
  }
  total / counts$masks_1
}

main_soft2_mask_plan <- function(q, uniforms, tree_count, p) {
  if (length(q) != p || anyNA(q) || any(q < 0 | q > 1)) stop("Invalid soft probabilities")
  if (nrow(uniforms) < tree_count || ncol(uniforms) != p) stop("Soft-2 uniform dimensions are wrong")
  masks <- sweep(uniforms[seq_len(tree_count), , drop = FALSE], 2L, q, FUN = "<=")
  sizes <- rowSums(masks)
  mtry <- integer(tree_count)
  nonempty <- sizes > 0L
  mtry[nonempty] <- pmax(1L, as.integer(floor(sizes[nonempty] / 3)))
  list(masks = masks, sizes = as.integer(sizes), mtry = mtry)
}

main_soft2_group_weights <- function(masks, mtry_by_tree, group_mtry, p, dummy_count) {
  tree_count <- nrow(masks)
  inactive <- numeric(p + dummy_count)
  inactive[p + seq_len(group_mtry)] <- 1
  weights <- rep(list(inactive), tree_count)
  active <- which(mtry_by_tree == group_mtry)
  for (b in active) weights[[b]] <- c(as.numeric(masks[b, ]), numeric(dummy_count))
  list(weights = weights, active = active)
}

predict_main_soft2 <- function(X, y, X_test, q, uniforms, forest_seed, cfg) {
  counts <- main_effective_counts(cfg)
  tree_count <- counts$masks_2
  if (counts$trees != tree_count) {
    stop("Soft implementation 2 requires one mask per tree")
  }
  p <- ncol(X)
  plan <- main_soft2_mask_plan(q, uniforms, tree_count, p)
  tree_predictions <- matrix(mean(y), nrow = nrow(X_test), ncol = tree_count)
  positive_mtry <- sort(unique(plan$mtry[plan$mtry > 0L]))
  if (!length(positive_mtry)) return(rowMeans(tree_predictions))

  require_main_ranger()
  dummy_count <- main_mtry(p)
  feature_names <- colnames(X)
  if (is.null(feature_names)) feature_names <- paste0("X", seq_len(p))
  augmented_names <- make.unique(c(feature_names, paste0(".soft2_dummy_", seq_len(dummy_count))))
  train_augmented <- cbind(X, matrix(0, nrow(X), dummy_count))
  test_augmented <- cbind(X_test, matrix(0, nrow(X_test), dummy_count))
  colnames(train_augmented) <- colnames(test_augmented) <- augmented_names
  train_frame <- as.data.frame(train_augmented)
  test_frame <- as.data.frame(test_augmented)

  for (group_mtry in positive_mtry) {
    group <- main_soft2_group_weights(
      plan$masks, plan$mtry, group_mtry, p, dummy_count
    )
    fit <- ranger::ranger(
      x = train_frame,
      y = as.numeric(y),
      num.trees = tree_count,
      mtry = group_mtry,
      splitrule = "variance",
      min.node.size = as.integer(cfg$random_forest$min_node_size),
      replace = TRUE,
      sample.fraction = 1,
      split.select.weights = group$weights,
      seed = as.integer(forest_seed),
      num.threads = as.integer(cfg$random_forest$num_threads),
      write.forest = TRUE,
      oob.error = FALSE,
      verbose = FALSE
    )
    predicted <- predict(
      fit, data = test_frame, predict.all = TRUE,
      num.threads = as.integer(cfg$random_forest$num_threads)
    )$predictions
    if (is.null(dim(predicted))) {
      predicted <- matrix(predicted, nrow = nrow(X_test), ncol = tree_count)
    }
    tree_predictions[, group$active] <- predicted[, group$active, drop = FALSE]
  }
  rowMeans(tree_predictions)
}

build_main_method_specs <- function(cfg) {
  specs <- list(
    list(order = 1L, id = "all_features", label = "All-feature RF", method = "all_features", implementation = NA_integer_, nu = NA_real_),
    list(order = 2L, id = "hard_screening", label = "Hard screen", method = "hard_screening", implementation = NA_integer_, nu = NA_real_),
    list(order = 3L, id = "frozen_hard_screening", label = "Frozen hard screen", method = "frozen_hard_screening", implementation = NA_integer_, nu = NA_real_)
  )
  cursor <- 3L
  for (nu in cfg$soft_screening$nu) {
    cursor <- cursor + 1L
    specs[[cursor]] <- list(
      order = cursor, id = paste0("soft1_nu_", format(nu, trim = TRUE, scientific = FALSE)),
      label = paste0("Soft 1, nu=", format(nu, trim = TRUE, scientific = FALSE)),
      method = "soft_screening", implementation = 1L, nu = as.numeric(nu)
    )
  }
  for (nu in cfg$soft_screening$nu) {
    cursor <- cursor + 1L
    specs[[cursor]] <- list(
      order = cursor, id = paste0("soft2_nu_", format(nu, trim = TRUE, scientific = FALSE)),
      label = paste0("Soft 2, nu=", format(nu, trim = TRUE, scientific = FALSE)),
      method = "soft_screening", implementation = 2L, nu = as.numeric(nu)
    )
  }
  specs
}

predict_main_method <- function(spec, data, variances, hard_full, uniforms, seeds, cfg) {
  threshold <- cfg$simulation$variance_threshold
  if (identical(spec$method, "all_features")) {
    return(fit_main_forest(
      data$X, data$y, data$X_test, seq_len(ncol(data$X)),
      main_effective_counts(cfg)$trees, seeds$ordinary[["all_features"]], cfg
    ))
  }
  if (identical(spec$method, "hard_screening")) {
    return(fit_main_forest(
      data$X, data$y, data$X_test, which(variances > threshold),
      main_effective_counts(cfg)$trees, seeds$ordinary[["hard_screening"]], cfg
    ))
  }
  if (identical(spec$method, "frozen_hard_screening")) {
    return(fit_main_forest(
      data$X, data$y, data$X_test, hard_full,
      main_effective_counts(cfg)$trees, seeds$ordinary[["frozen_hard_screening"]], cfg
    ))
  }
  q <- soft_probabilities_from_variances(variances, threshold, spec$nu)
  if (identical(spec$implementation, 1L)) {
    return(predict_main_soft1(
      data$X, data$y, data$X_test, q, uniforms,
      seeds$soft_implementation_1, cfg
    ))
  }
  if (identical(spec$implementation, 2L)) {
    return(predict_main_soft2(
      data$X, data$y, data$X_test, q, uniforms,
      seeds$soft_implementation_2[[1L]], cfg
    ))
  }
  stop("Unknown method: ", spec$id)
}
