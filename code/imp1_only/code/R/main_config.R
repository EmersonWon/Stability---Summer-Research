assert_scalar_number <- function(x, name, lower = -Inf, strict_lower = FALSE) {
  ok <- is.numeric(x) && length(x) == 1L && is.finite(x)
  if (ok) ok <- if (strict_lower) x > lower else x >= lower
  if (!ok) stop(name, " must be one finite number ", if (strict_lower) "> " else ">= ", lower)
  invisible(TRUE)
}

assert_whole_number <- function(x, name, lower = 1L) {
  assert_scalar_number(x, name, lower)
  if (x != floor(x)) stop(name, " must be an integer")
  invisible(TRUE)
}

validate_main_config <- function(cfg) {
  if (!is.list(cfg)) stop("Configuration must be a JSON object")
  required <- c(
    "schema_version", "algorithm_version", "rng", "coefficient_seed",
    "replicate_seeds", "simulation", "settings", "random_forest",
    "soft_screening", "methods"
  )
  missing <- setdiff(required, names(cfg))
  if (length(missing)) stop("Missing configuration field(s): ", paste(missing, collapse = ", "))
  if (!identical(as.integer(cfg$schema_version), 3L)) stop("schema_version must be 3")
  if (!identical(cfg$algorithm_version, "main_study_v1")) {
    stop("algorithm_version must be 'main_study_v1'")
  }
  assert_whole_number(cfg$coefficient_seed, "coefficient_seed", 1L)

  sim <- cfg$simulation
  for (name in c("replicates", "n", "p", "n_test", "variance_threshold", "noise_variance")) {
    if (is.null(sim[[name]])) stop("Missing simulation.", name)
  }
  assert_whole_number(sim$replicates, "simulation.replicates", 1L)
  assert_whole_number(sim$n, "simulation.n", 3L)
  assert_whole_number(sim$p, "simulation.p", 5L)
  assert_whole_number(sim$n_test, "simulation.n_test", 1L)
  assert_scalar_number(sim$variance_threshold, "simulation.variance_threshold", 0, TRUE)
  assert_scalar_number(sim$noise_variance, "simulation.noise_variance", 0)

  seeds <- as.numeric(cfg$replicate_seeds)
  if (length(seeds) != sim$replicates || any(!is.finite(seeds)) ||
      any(seeds < 1) || any(seeds != floor(seeds)) || anyDuplicated(seeds)) {
    stop("replicate_seeds must contain one distinct positive integer per replicate")
  }
  if (cfg$coefficient_seed %in% seeds) stop("coefficient_seed must differ from all replicate seeds")

  expected_rng <- c("kind", "normal_kind", "sample_kind")
  if (!all(expected_rng %in% names(cfg$rng))) stop("rng must record kind, normal_kind, and sample_kind")

  settings <- cfg$settings
  if (!is.data.frame(settings) || !identical(as.integer(settings$id), 1:4)) {
    stop("settings must contain rows with ids 1, 2, 3, 4 in order")
  }
  if (!isTRUE(all.equal(as.numeric(settings$rho[settings$id == 3L]), 0.9))) {
    stop("Setting 3 must use rho=0.9")
  }
  sparse <- settings$id <= 3L
  if (any(!is.finite(settings$a[sparse])) || any(!is.finite(settings$b[sparse]))) {
    stop("Settings 1-3 must record finite a and b constants")
  }

  rf <- cfg$random_forest
  if (!identical(as.integer(rf$trees), 250L) || !identical(as.integer(rf$min_node_size), 5L) ||
      !identical(as.integer(rf$num_threads), 1L) || !identical(rf$mtry_rule, "floor_d_over_3")) {
    stop("Random-forest settings must be T=250, min.node.size=5, one thread, and floor(d/3) mtry")
  }
  soft <- cfg$soft_screening
  if (!isTRUE(all.equal(as.numeric(soft$nu), c(0.005, 0.025, 0.1)))) {
    stop("soft_screening.nu must be 0.005, 0.025, 0.1 in order")
  }
  if (!identical(as.integer(soft$implementation_1_masks), 25L) ||
      !identical(as.integer(soft$implementation_2_masks), 250L)) {
    stop("Soft implementations must use M1=25 and M2=250")
  }
  if (!is.character(cfg$methods) || length(cfg$methods) != 9L || anyDuplicated(cfg$methods)) {
    stop("methods must list the nine unique reporting procedures")
  }

  cfg$schema_version <- 3L
  cfg$coefficient_seed <- as.integer(cfg$coefficient_seed)
  cfg$replicate_seeds <- as.integer(seeds)
  cfg$simulation$replicates <- as.integer(sim$replicates)
  cfg$simulation$n <- as.integer(sim$n)
  cfg$simulation$p <- as.integer(sim$p)
  cfg$simulation$n_test <- as.integer(sim$n_test)
  cfg
}

load_main_config <- function(path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Package 'jsonlite' is required")
  if (!file.exists(path)) stop("Configuration file not found: ", path)
  validate_main_config(jsonlite::fromJSON(path, simplifyVector = TRUE))
}

make_main_smoke_config <- function(cfg) {
  cfg$simulation$replicates <- 1L
  cfg$simulation$n <- 20L
  cfg$simulation$p <- 6L
  cfg$simulation$n_test <- 50L
  cfg$replicate_seeds <- cfg$replicate_seeds[1L]
  cfg$execution_overrides <- list(
    random_forest_trees = 3L,
    implementation_1_masks = 2L,
    implementation_2_masks = 3L
  )
  validate_main_config(cfg)
}

canonical_main_config_json <- function(cfg) {
  jsonlite::toJSON(cfg, auto_unbox = TRUE, pretty = TRUE, digits = 17, null = "null")
}
