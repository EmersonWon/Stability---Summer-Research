require_ranger <- function() {
  if (!requireNamespace("ranger", quietly = TRUE)) {
    stop(
      "Package 'ranger' is required. Run `Rscript install_dependencies.R` ",
      "from the StartingCode directory first."
    )
  }
  invisible(TRUE)
}

mtry_for_dimension <- function(d) {
  if (length(d) != 1L || !is.finite(d) || d < 1L) stop("d must be a positive integer")
  max(1L, as.integer(floor(d / 3)))
}

constant_prediction <- function(y, n_test) {
  rep(mean(y), n_test)
}

fit_forest_predict <- function(X, y, X_test, features, num_trees, seed, cfg) {
  n_test <- nrow(X_test)
  features <- as.integer(features)
  if (!length(features)) return(constant_prediction(y, n_test))
  require_ranger()
  train_x <- as.data.frame(X[, features, drop = FALSE])
  test_x <- as.data.frame(X_test[, features, drop = FALSE])
  fit <- ranger::ranger(
    x = train_x,
    y = as.numeric(y),
    num.trees = as.integer(num_trees),
    mtry = mtry_for_dimension(length(features)),
    splitrule = "variance",
    min.node.size = cfg$random_forest$min_node_size,
    replace = TRUE,
    sample.fraction = 1,
    seed = as.integer(seed),
    num.threads = cfg$random_forest$num_threads,
    write.forest = TRUE,
    verbose = FALSE
  )
  as.numeric(predict(fit, data = test_x, num.threads = cfg$random_forest$num_threads)$predictions)
}

predict_ordinary_forest <- function(X, y, X_test, features, cfg, replicate_id) {
  list(prediction = fit_forest_predict(
    X, y, X_test, features,
    num_trees = cfg$random_forest$trees,
    seed = ordinary_forest_seed(cfg, replicate_id),
    cfg = cfg
  ))
}

predict_soft_implementation_1 <- function(X, y, X_test, q, mask_uniforms, cfg, replicate_id) {
  levels <- cfg$soft_screening$implementation_1_masks
  max_masks <- max(levels)
  if (nrow(mask_uniforms) < max_masks || ncol(mask_uniforms) != ncol(X)) {
    stop("Mask uniform array has incompatible dimensions")
  }
  running_sum <- numeric(nrow(X_test))
  output <- list()
  for (b in seq_len(max_masks)) {
    selected <- which(mask_uniforms[b, ] <= q)
    component_prediction <- fit_forest_predict(
      X, y, X_test, selected,
      num_trees = cfg$random_forest$trees,
      seed = component_seed(cfg, replicate_id, "soft_implementation_1", b),
      cfg = cfg
    )
    running_sum <- running_sum + component_prediction
    if (b %in% levels) output[[paste0("M_", b)]] <- running_sum / b
  }
  output
}

soft2_mask_plan <- function(q, mask_uniforms, tree_count, p) {
  if (!is.numeric(q) || length(q) != p || anyNA(q) || any(q < 0 | q > 1)) {
    stop("q must contain one inclusion probability in [0, 1] per feature")
  }
  if (nrow(mask_uniforms) < tree_count || ncol(mask_uniforms) != p) {
    stop("Mask uniform array has incompatible dimensions")
  }
  mask_matrix <- sweep(
    mask_uniforms[seq_len(tree_count), , drop = FALSE],
    2L, q, FUN = "<="
  )
  mask_sizes <- rowSums(mask_matrix)
  mtry_by_tree <- integer(tree_count)
  nonempty <- mask_sizes > 0L
  mtry_by_tree[nonempty] <- pmax(1L, as.integer(floor(mask_sizes[nonempty] / 3)))
  list(
    mask_matrix = mask_matrix,
    mask_sizes = as.integer(mask_sizes),
    mtry_by_tree = mtry_by_tree
  )
}

soft2_group_split_weights <- function(mask_matrix, mtry_by_tree, group_mtry, p, dummy_count) {
  tree_count <- nrow(mask_matrix)
  inactive_weights <- numeric(p + dummy_count)
  inactive_weights[p + seq_len(group_mtry)] <- 1
  weights <- rep(list(inactive_weights), tree_count)
  active <- which(mtry_by_tree == group_mtry)
  for (b in active) {
    weights[[b]] <- c(as.numeric(mask_matrix[b, ]), numeric(dummy_count))
  }
  list(weights = weights, active = active)
}

soft2_batched_tree_predictions <- function(
  X, y, X_test, q, mask_uniforms, cfg, forest_seed
) {
  tree_count <- cfg$random_forest$trees
  p <- ncol(X)
  if (!is.matrix(X) || !is.matrix(X_test) || ncol(X_test) != p) {
    stop("X and X_test must be matrices with the same number of columns")
  }
  plan <- soft2_mask_plan(q, mask_uniforms, tree_count, p)
  tree_predictions <- matrix(
    mean(y), nrow = nrow(X_test), ncol = tree_count
  )
  positive_mtry <- sort(unique(plan$mtry_by_tree[plan$mtry_by_tree > 0L]))
  if (!length(positive_mtry)) return(tree_predictions)

  require_ranger()
  # Keep the augmented feature dimension fixed across nu and all deletions.
  # Zero-weight dummy columns then cannot introduce an incidental dimensional
  # change into the common-random-number coupling.
  dummy_count <- mtry_for_dimension(p)
  feature_names <- colnames(X)
  if (is.null(feature_names)) feature_names <- paste0("X", seq_len(p))
  augmented_names <- make.unique(c(
    feature_names,
    paste0(".soft2_constant_dummy_", seq_len(dummy_count))
  ))
  train_augmented <- cbind(X, matrix(0, nrow = nrow(X), ncol = dummy_count))
  test_augmented <- cbind(X_test, matrix(0, nrow = nrow(X_test), ncol = dummy_count))
  colnames(train_augmented) <- augmented_names
  colnames(test_augmented) <- augmented_names
  train_frame <- as.data.frame(train_augmented)
  test_frame <- as.data.frame(test_augmented)

  for (group_mtry in positive_mtry) {
    group <- soft2_group_split_weights(
      plan$mask_matrix, plan$mtry_by_tree, group_mtry, p, dummy_count
    )
    fit <- ranger::ranger(
      x = train_frame,
      y = as.numeric(y),
      num.trees = tree_count,
      mtry = group_mtry,
      splitrule = "variance",
      min.node.size = cfg$random_forest$min_node_size,
      replace = TRUE,
      sample.fraction = 1,
      split.select.weights = group$weights,
      seed = as.integer(forest_seed),
      num.threads = cfg$random_forest$num_threads,
      write.forest = TRUE,
      oob.error = FALSE,
      verbose = FALSE
    )
    group_predictions <- predict(
      fit, data = test_frame, predict.all = TRUE,
      num.threads = cfg$random_forest$num_threads
    )$predictions
    if (is.null(dim(group_predictions))) {
      group_predictions <- matrix(
        group_predictions, nrow = nrow(X_test), ncol = tree_count
      )
    }
    tree_predictions[, group$active] <- group_predictions[, group$active, drop = FALSE]
  }
  tree_predictions
}

predict_soft_implementation_2 <- function(X, y, X_test, q, mask_uniforms, cfg, replicate_id) {
  tree_count <- cfg$random_forest$trees
  tree_predictions <- soft2_batched_tree_predictions(
    X, y, X_test, q, mask_uniforms, cfg,
    forest_seed = soft_implementation_2_forest_seed(cfg, replicate_id)
  )
  setNames(list(rowMeans(tree_predictions)), paste0("M_", tree_count))
}

mask_diagnostics <- function(q_full, q_deleted, mask_uniforms, mask_count) {
  U <- mask_uniforms[seq_len(mask_count), , drop = FALSE]
  full_mask <- sweep(U, 2L, q_full, FUN = "<=")
  deleted_mask <- sweep(U, 2L, q_deleted, FUN = "<=")
  list(
    average_mask_symmetric_difference = mean(rowSums(full_mask != deleted_mask)),
    average_mask_size_full = mean(rowSums(full_mask)),
    average_mask_size_deleted = mean(rowSums(deleted_mask))
  )
}
