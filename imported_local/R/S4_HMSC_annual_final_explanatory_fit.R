#===============================================================================
# S4: FINAL LONG FIT OF THE LOCKED ANNUAL EXPLANATORY HMSC MODEL
#     Reads S3 calibration -> runs one final long inference fit
#===============================================================================
#
# PURPOSE
# -------
# This script performs the final long explanatory Hmsc fit after S3 MCMC
# calibration.
#
# It does NOT perform:
#   - variable selection
#   - buffer selection
#   - cross-validation
#   - predictive model ranking
#
# Final outputs:
#   - final MCMC convergence
#   - beta posterior means, medians, 95% credible intervals and support
#   - explanatory fit metrics using explicit effort-offset predictions
#   - posterior predictive checks using explicit effort-offset predictions
#   - occurrence metrics
#   - variance partitioning
#   - residual associations
#   - final model checkpoint
#
# Response: annual total count
# Distribution: lognormal Poisson
# Effort offset: log(total_effort_days / 7)
# Random levels: site and year
#===============================================================================

gc()
set.seed(1)

suppressPackageStartupMessages({
  library(Hmsc)
  library(coda)
})

#===============================================================================
# 1. USER SETTINGS
#===============================================================================

hmsc_output_root <- "E:/EIFFEL uusi/hmsc_outputs"

previous_output_dir <- file.path(
  hmsc_output_root,
  "HMSC_ANNUAL_ONE_BUFFER_MATCHED_ENVIRONMENT_SELECTION_v2_OFFSET_CORRECTED"
)

previous_results_file <- file.path(
  previous_output_dir,
  "HMSC_annual_one_buffer_matched_results.rds"
)

s3_output_dir <- file.path(
  hmsc_output_root,
  "HMSC_ANNUAL_EXPLANATORY_CALIBRATION_v1"
)

s3_result_file <- file.path(
  s3_output_dir,
  "results",
  "S3_CALIBRATION_RESULTS.rds"
)

s3_complete_file <- file.path(
  s3_output_dir,
  "results",
  "S3_CALIBRATION_COMPLETE.txt"
)

output_dir <- file.path(
  hmsc_output_root,
  "HMSC_ANNUAL_FINAL_EXPLANATORY_FIT_v1"
)

checkpoint_dir <- file.path(output_dir, "checkpoints")
result_dir <- file.path(output_dir, "results")

dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

reuse_existing_checkpoint <- TRUE
stop_if_complete <- TRUE

maximum_prediction_draws <- 1000L

# Final convergence thresholds
convergence_rules <- data.frame(
  component = c("Beta", "Gamma", "V", "Rho", "Omega"),
  PSRF_limit = c(1.05, 1.10, 1.10, 1.10, 1.10),
  ESS_limit = c(400, 200, 200, 200, 200),
  stringsAsFactors = FALSE
)

complete_file <- file.path(
  result_dir,
  "S4_FINAL_FIT_COMPLETE.txt"
)

if (
  stop_if_complete &&
  file.exists(complete_file)
) {
  stop(
    "S4 final fit is already marked complete:\n",
    complete_file,
    "\nUse a new output_dir version if a new final fit is intended."
  )
}

#===============================================================================
# 2. HELPERS
#===============================================================================

write_csv2 <- function(x, file) {
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  if (ncol(x) == 0L) {
    x <- data.frame(status = "no_rows", stringsAsFactors = FALSE)
  }
  write.table(
    x,
    file = file,
    sep = ";",
    dec = ",",
    row.names = FALSE,
    col.names = TRUE,
    quote = TRUE,
    na = "",
    fileEncoding = "UTF-8"
  )
}

safe_min <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) min(x) else NA_real_
}

safe_max <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) max(x) else NA_real_
}

safe_median <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) median(x) else NA_real_
}

safe_mean <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) mean(x) else NA_real_
}

model_fingerprint <- function(model) {
  paste(
    nrow(model$Y),
    ncol(model$Y),
    paste(model$spNames, collapse = "|"),
    paste(model$covNames, collapse = "|"),
    paste(names(model$ranLevels), collapse = "|"),
    sep = "::"
  )
}

load_rdata_environment <- function(file, required = character(0)) {
  if (!file.exists(file)) stop("Missing input file: ", file)
  e <- new.env(parent = globalenv())
  loaded <- load(file, envir = e)
  missing <- setdiff(required, loaded)
  if (length(missing)) {
    stop("Missing objects in ", file, ": ", paste(missing, collapse = ", "))
  }
  e
}

has_posterior <- function(model) {
  !is.null(model$postList) &&
    length(model$postList) >= 2L &&
    all(vapply(model$postList, length, integer(1)) > 0L)
}

prediction_posterior <- function(model, maximum_draws) {
  if (!has_posterior(model)) {
    stop("Model contains no posterior samples.")
  }

  total_draws <- sum(vapply(
    model$postList,
    length,
    integer(1)
  ))

  posterior_thin <- max(
    1L,
    ceiling(total_draws / maximum_draws)
  )

  post <- poolMcmcChains(
    model$postList,
    start = 1L,
    thin = posterior_thin
  )

  if (length(post) > maximum_draws) {
    keep <- unique(round(
      seq(
        1,
        length(post),
        length.out = maximum_draws
      )
    ))
    post <- post[keep]
  }

  post
}

predict_array_offset <- function(
    model,
    post,
    expected,
    seed
) {
  if (is.null(model$Loff)) {
    stop("Final model has no Loff.")
  }

  set.seed(seed)

  predicted_list <- predict(
    model,
    post = post,
    Loff = model$Loff,
    expected = expected,
    nParallel = 1L
  )

  predicted <- simplify2array(predicted_list)

  expected_dim <- c(
    nrow(model$Y),
    ncol(model$Y),
    length(post)
  )

  if (!identical(
    as.integer(dim(predicted)),
    as.integer(expected_dim)
  )) {
    stop(
      "Unexpected prediction dimensions. Got ",
      paste(dim(predicted), collapse = " x "),
      "; expected ",
      paste(expected_dim, collapse = " x ")
    )
  }

  predicted
}

auc_rank <- function(observed, probability) {
  keep <- is.finite(observed) & is.finite(probability)
  observed <- observed[keep]
  probability <- probability[keep]

  n_positive <- sum(observed == 1)
  n_negative <- sum(observed == 0)

  if (n_positive == 0L || n_negative == 0L) {
    return(NA_real_)
  }

  ranks <- rank(
    probability,
    ties.method = "average"
  )

  (
    sum(ranks[observed == 1]) -
      n_positive * (n_positive + 1) / 2
  ) / (n_positive * n_negative)
}

ppc_interval <- function(draws, observed) {
  draws <- draws[is.finite(draws)]

  if (!length(draws) || !is.finite(observed)) {
    return(
      c(
        q025 = NA_real_,
        median = NA_real_,
        q975 = NA_real_,
        covered = NA_real_,
        p_value = NA_real_
      )
    )
  }

  interval <- quantile(
    draws,
    c(0.025, 0.5, 0.975),
    na.rm = TRUE
  )

  p_value <- min(
    1,
    2 * min(
      mean(draws <= observed),
      mean(draws >= observed)
    )
  )

  c(
    q025 = unname(interval[1]),
    median = unname(interval[2]),
    q975 = unname(interval[3]),
    covered = as.numeric(
      observed >= interval[1] &&
        observed <= interval[3]
    ),
    p_value = p_value
  )
}

#===============================================================================
# 3. LOAD S3 CALIBRATION AND LOCKED MODEL
#===============================================================================

if (!file.exists(s3_complete_file)) {
  stop(
    "S3 calibration has not completed. Missing:\n",
    s3_complete_file
  )
}

if (!file.exists(s3_result_file)) {
  stop(
    "S3 calibration result file is missing:\n",
    s3_result_file
  )
}

S3 <- readRDS(s3_result_file)

required_s3_fields <- c(
  "locked_model_label",
  "locked_fitted_file",
  "locked_fingerprint",
  "locked_weather_variables",
  "selected_environment_variables",
  "variables_kept",
  "final_settings",
  "calibration_accepted"
)

missing_s3 <- setdiff(
  required_s3_fields,
  names(S3)
)

if (length(missing_s3) > 0L) {
  stop(
    "S3 result is missing fields: ",
    paste(missing_s3, collapse = ", ")
  )
}

final_settings <- S3$final_settings
locked_model_label <- S3$locked_model_label
locked_fitted_file <- S3$locked_fitted_file
locked_weather_variables <- S3$locked_weather_variables
selected_environment_variables <- S3$selected_environment_variables
variables_kept <- S3$variables_kept

if (!file.exists(locked_fitted_file)) {
  stop(
    "Locked fitted file recorded by S3 no longer exists:\n",
    locked_fitted_file
  )
}

locked_env <- load_rdata_environment(
  locked_fitted_file,
  required = c(
    "model_unfitted",
    "metadata_model"
  )
)

locked_model <- get("model_unfitted", envir = locked_env)
metadata_model <- get("metadata_model", envir = locked_env)

rm(locked_env)

if (!inherits(locked_model, "Hmsc")) {
  stop("Locked model is not an Hmsc object.")
}

current_fingerprint <- model_fingerprint(locked_model)

if (!identical(
  current_fingerprint,
  S3$locked_fingerprint
)) {
  stop(
    "The locked model differs from the model calibrated in S3."
  )
}

if (is.null(locked_model$Loff)) {
  stop("Locked model has no effort offset.")
}

cat("\n========================================================\n")
cat("S4 FINAL LONG EXPLANATORY FIT\n")
cat("========================================================\n")
cat("Locked model:", locked_model_label, "\n")
cat("Observations:", nrow(locked_model$Y), "\n")
cat("Species:", ncol(locked_model$Y), "\n")
cat("Predictors:", length(variables_kept), "\n")
cat("Explicit effort offset: TRUE\n")
cat("\nS3 recommended settings:\n")
print(as.data.frame(final_settings), row.names = FALSE)

#===============================================================================
# 4. FINAL LONG MCMC FIT
#===============================================================================

checkpoint_file <- file.path(
  checkpoint_dir,
  paste0(
    "FINAL_",
    locked_model_label,
    "_samples_", final_settings$samples,
    "_transient_", final_settings$transient,
    "_thin_", final_settings$thin,
    "_chains_", final_settings$chains,
    ".RData"
  )
)

if (
  reuse_existing_checkpoint &&
  file.exists(checkpoint_file)
) {
  e <- load_rdata_environment(
    checkpoint_file,
    required = c("final_hmsc_model", "current_fingerprint")
  )

  final_hmsc_model <- get("final_hmsc_model", envir = e)
  checkpoint_fingerprint <- get("current_fingerprint", envir = e)

  final_elapsed_hours <- if (
    exists("final_elapsed_hours", envir = e, inherits = FALSE)
  ) {
    get("final_elapsed_hours", envir = e)
  } else {
    NA_real_
  }

  rm(e)

  if (!identical(
    checkpoint_fingerprint,
    current_fingerprint
  )) {
    stop(
      "Existing final-fit checkpoint belongs to a different model."
    )
  }

  cat("Loaded existing final-fit checkpoint:\n", checkpoint_file, "\n")
} else {
  set.seed(final_settings$seed)

  start_time <- Sys.time()

  final_hmsc_model <- sampleMcmc(
    locked_model,
    samples = final_settings$samples,
    transient = final_settings$transient,
    thin = final_settings$thin,
    nChains = final_settings$chains,
    nParallel = final_settings$parallel,
    verbose = 100
  )

  end_time <- Sys.time()

  final_elapsed_hours <- as.numeric(
    difftime(
      end_time,
      start_time,
      units = "hours"
    )
  )

  partial <- paste0(checkpoint_file, ".partial")

  save(
    final_hmsc_model,
    final_settings,
    current_fingerprint,
    final_elapsed_hours,
    file = partial
  )

  if (!file.rename(partial, checkpoint_file)) {
    stop("Could not finalize final-fit checkpoint.")
  }
}

if (!has_posterior(final_hmsc_model)) {
  stop("Final model contains no posterior samples.")
}

if (is.null(final_hmsc_model$Loff)) {
  stop("Loff disappeared from final model.")
}

#===============================================================================
# 5. FINAL CONVERGENCE
#===============================================================================

diagnose_component <- function(x, component, random_level = NA_character_) {
  if (is.null(x) || !inherits(x, "mcmc.list")) {
    return(NULL)
  }

  parameter <- colnames(as.matrix(x[[1]]))

  if (is.null(parameter)) {
    parameter <- paste0(
      "parameter_",
      seq_len(ncol(x[[1]]))
    )
  }

  ess <- tryCatch(
    effectiveSize(x),
    error = function(e) NULL
  )

  psrf <- tryCatch(
    gelman.diag(
      x,
      multivariate = FALSE,
      autoburnin = FALSE
    )$psrf,
    error = function(e) NULL
  )

  out <- data.frame(
    component = component,
    random_level = random_level,
    parameter = parameter,
    PSRF_point = NA_real_,
    PSRF_upper = NA_real_,
    ESS = NA_real_,
    stringsAsFactors = FALSE
  )

  if (!is.null(psrf)) {
    rn <- rownames(psrf)
    if (is.null(rn)) rn <- parameter
    hit <- match(parameter, rn)
    out$PSRF_point <- psrf[hit, 1]
    out$PSRF_upper <- psrf[
      hit,
      min(2L, ncol(psrf))
    ]
  }

  if (!is.null(ess)) {
    if (
      is.null(names(ess)) &&
      length(ess) == nrow(out)
    ) {
      out$ESS <- as.numeric(ess)
    } else {
      out$ESS <- as.numeric(
        ess[match(parameter, names(ess))]
      )
    }
  }

  out
}

mpost <- convertToCodaObject(
  final_hmsc_model,
  spNamesNumbers = c(TRUE, FALSE),
  covNamesNumbers = c(TRUE, FALSE)
)

diagnostic_parts <- list()

for (component in c("Beta", "Gamma", "V", "Rho")) {
  if (!is.null(mpost[[component]])) {
    diagnostic_parts[[length(diagnostic_parts) + 1L]] <-
      diagnose_component(
        mpost[[component]],
        component
      )
  }
}

if (!is.null(mpost$Omega)) {
  random_names <- names(final_hmsc_model$ranLevels)

  for (r in seq_along(mpost$Omega)) {
    diagnostic_parts[[length(diagnostic_parts) + 1L]] <-
      diagnose_component(
        mpost$Omega[[r]],
        "Omega",
        random_names[r]
      )
  }
}

final_convergence_detailed <- do.call(
  rbind,
  Filter(Negate(is.null), diagnostic_parts)
)

if (
  is.null(final_convergence_detailed) ||
  !nrow(final_convergence_detailed)
) {
  stop("No final convergence diagnostics were produced.")
}

key <- interaction(
  final_convergence_detailed$component,
  ifelse(
    is.na(final_convergence_detailed$random_level),
    "",
    final_convergence_detailed$random_level
  ),
  drop = TRUE
)

final_convergence_summary <- do.call(
  rbind,
  lapply(
    split(final_convergence_detailed, key),
    function(z) {
      rule <- convergence_rules[
        convergence_rules$component == z$component[1],
        ,
        drop = FALSE
      ]

      max_psrf <- safe_max(z$PSRF_upper)
      min_ess <- safe_min(z$ESS)

      data.frame(
        component = z$component[1],
        random_level = z$random_level[1],
        n_parameters = nrow(z),
        maximum_PSRF_upper = max_psrf,
        median_PSRF_upper = safe_median(z$PSRF_upper),
        minimum_ESS = min_ess,
        median_ESS = safe_median(z$ESS),
        PSRF_limit = rule$PSRF_limit[1],
        ESS_limit = rule$ESS_limit[1],
        accepted =
          is.finite(max_psrf) &&
          is.finite(min_ess) &&
          max_psrf <= rule$PSRF_limit[1] &&
          min_ess >= rule$ESS_limit[1],
        stringsAsFactors = FALSE
      )
    }
  )
)

rownames(final_convergence_summary) <- NULL

final_accepted <- all(
  final_convergence_summary$accepted
)

final_status <- if (final_accepted) {
  "ACCEPTED_FOR_FINAL_INFERENCE"
} else {
  "NOT_ACCEPTED_FOR_FINAL_INFERENCE"
}

write_csv2(
  final_convergence_detailed,
  file.path(
    result_dir,
    "S4_FINAL_convergence_detailed.csv2"
  )
)

write_csv2(
  final_convergence_summary,
  file.path(
    result_dir,
    "S4_FINAL_convergence_summary.csv2"
  )
)

#===============================================================================
# 6. BETA POSTERIOR
#===============================================================================

post_beta <- getPostEstimate(
  final_hmsc_model,
  "Beta",
  q = c(0.025, 0.5, 0.975)
)

beta_mean <- post_beta$mean
species_names <- colnames(beta_mean)
predictor_names <- rownames(beta_mean)

if (is.null(species_names)) {
  species_names <- final_hmsc_model$spNames
}

if (is.null(predictor_names)) {
  predictor_names <- final_hmsc_model$covNames
}

extract_quantile <- function(q_array, index, target_dim) {
  d <- dim(q_array)

  if (length(d) != 3L) {
    stop("Unexpected Beta posterior quantile dimensions.")
  }

  if (all(d[2:3] == target_dim)) {
    return(q_array[index, , , drop = TRUE])
  }

  if (all(d[1:2] == target_dim)) {
    return(q_array[, , index, drop = TRUE])
  }

  stop("Beta posterior quantiles do not match posterior means.")
}

q025 <- extract_quantile(
  post_beta$quantiles,
  1L,
  dim(beta_mean)
)

q500 <- extract_quantile(
  post_beta$quantiles,
  2L,
  dim(beta_mean)
)

q975 <- extract_quantile(
  post_beta$quantiles,
  3L,
  dim(beta_mean)
)

beta_results <- data.frame(
  species = rep(
    species_names,
    each = length(predictor_names)
  ),
  predictor = rep(
    predictor_names,
    times = length(species_names)
  ),
  posterior_mean = as.vector(beta_mean),
  posterior_median = as.vector(q500),
  lower_95_CI = as.vector(q025),
  upper_95_CI = as.vector(q975),
  support_positive = as.vector(post_beta$support),
  support_negative = as.vector(post_beta$supportNeg),
  stringsAsFactors = FALSE
)

beta_results$posterior_support <- pmax(
  beta_results$support_positive,
  beta_results$support_negative
)

beta_results$direction <- ifelse(
  beta_results$posterior_mean > 0,
  "positive",
  ifelse(
    beta_results$posterior_mean < 0,
    "negative",
    "zero"
  )
)

beta_results$evidence <- ifelse(
  beta_results$posterior_support >= 0.95,
  "strong",
  ifelse(
    beta_results$posterior_support >= 0.80,
    "moderate",
    "weak"
  )
)

write_csv2(
  beta_results,
  file.path(
    result_dir,
    "S4_FINAL_beta_coefficients.csv2"
  )
)

#===============================================================================
# 7. EXPLANATORY FIT WITH EXPLICIT OFFSET
#===============================================================================

prediction_post <- prediction_posterior(
  final_hmsc_model,
  maximum_prediction_draws
)

pred_expected <- predict_array_offset(
  final_hmsc_model,
  prediction_post,
  expected = TRUE,
  seed = 7001L
)

explanatory_fit <- evaluateModelFit(
  hM = final_hmsc_model,
  predY = pred_expected
)

explanatory_fit_table <- data.frame(
  species = species_names,
  stringsAsFactors = FALSE
)

for (metric in names(explanatory_fit)) {
  value <- explanatory_fit[[metric]]

  if (
    is.atomic(value) &&
    length(value) == length(species_names)
  ) {
    explanatory_fit_table[[metric]] <- as.numeric(value)
  }
}

write_csv2(
  explanatory_fit_table,
  file.path(
    result_dir,
    "S4_FINAL_explanatory_fit_offset_corrected.csv2"
  )
)

#===============================================================================
# 8. OCCURRENCE METRICS + POSTERIOR PREDICTIVE CHECK
#===============================================================================

pred_realized <- predict_array_offset(
  final_hmsc_model,
  prediction_post,
  expected = FALSE,
  seed = 7002L
)

presence_probability <- 1 - apply(
  pred_realized == 0,
  c(1, 2),
  mean,
  na.rm = TRUE
)

occurrence_metrics <- do.call(
  rbind,
  lapply(seq_len(ncol(final_hmsc_model$Y)), function(j) {
    observed_occurrence <- as.numeric(
      final_hmsc_model$Y[, j] > 0
    )

    probability <- presence_probability[, j]

    positive <- observed_occurrence == 1
    negative <- observed_occurrence == 0

    data.frame(
      species = species_names[j],
      O.RMSE = sqrt(
        mean(
          (observed_occurrence - probability)^2,
          na.rm = TRUE
        )
      ),
      O.AUC = auc_rank(
        observed_occurrence,
        probability
      ),
      O.TjurR2 = if (
        any(positive) &&
        any(negative)
      ) {
        mean(
          probability[positive],
          na.rm = TRUE
        ) -
          mean(
            probability[negative],
            na.rm = TRUE
          )
      } else {
        NA_real_
      },
      stringsAsFactors = FALSE
    )
  })
)

write_csv2(
  occurrence_metrics,
  file.path(
    result_dir,
    "S4_FINAL_occurrence_metrics.csv2"
  )
)

posterior_predictive_check <- do.call(
  rbind,
  lapply(seq_len(ncol(final_hmsc_model$Y)), function(j) {
    predicted_species <- pred_realized[
      , j, , drop = FALSE
    ]

    draw_mean <- apply(
      predicted_species,
      3,
      mean,
      na.rm = TRUE
    )

    draw_zero <- apply(
      predicted_species,
      3,
      function(z) mean(z == 0, na.rm = TRUE)
    )

    draw_q95 <- apply(
      predicted_species,
      3,
      function(z) unname(
        quantile(z, 0.95, na.rm = TRUE)
      )
    )

    draw_q99 <- apply(
      predicted_species,
      3,
      function(z) unname(
        quantile(z, 0.99, na.rm = TRUE)
      )
    )

    draw_maximum <- apply(
      predicted_species,
      3,
      max,
      na.rm = TRUE
    )

    observed <- final_hmsc_model$Y[, j]

    observed_mean <- mean(
      observed,
      na.rm = TRUE
    )

    observed_zero <- mean(
      observed == 0,
      na.rm = TRUE
    )

    observed_q95 <- unname(
      quantile(
        observed,
        0.95,
        na.rm = TRUE
      )
    )

    observed_q99 <- unname(
      quantile(
        observed,
        0.99,
        na.rm = TRUE
      )
    )

    observed_maximum <- max(
      observed,
      na.rm = TRUE
    )

    mean_check <- ppc_interval(
      draw_mean,
      observed_mean
    )

    zero_check <- ppc_interval(
      draw_zero,
      observed_zero
    )

    q95_check <- ppc_interval(
      draw_q95,
      observed_q95
    )

    q99_check <- ppc_interval(
      draw_q99,
      observed_q99
    )

    maximum_check <- ppc_interval(
      draw_maximum,
      observed_maximum
    )

    core_ok <- isTRUE(all(c(
      mean_check["covered"],
      zero_check["covered"],
      q95_check["covered"]
    ) == 1))

    central_and_zero_ok <- isTRUE(all(c(
      zero_check["covered"],
      q95_check["covered"]
    ) == 1))

    tail_ok <- isTRUE(all(c(
      q99_check["covered"],
      maximum_check["covered"]
    ) == 1))

    ppc_status <- if (
      core_ok &&
      tail_ok
    ) {
      "OK"
    } else if (
      central_and_zero_ok &&
      (!core_ok || !tail_ok)
    ) {
      "UPPER_TAIL_REQUIRES_REVIEW"
    } else {
      "REQUIRES_REVIEW"
    }

    data.frame(
      species = species_names[j],
      observed_mean = observed_mean,
      predicted_mean_q025 = mean_check["q025"],
      predicted_mean_median = mean_check["median"],
      predicted_mean_q975 = mean_check["q975"],
      mean_covered_95 = as.logical(mean_check["covered"]),
      observed_zero_proportion = observed_zero,
      predicted_zero_q025 = zero_check["q025"],
      predicted_zero_median = zero_check["median"],
      predicted_zero_q975 = zero_check["q975"],
      zero_covered_95 = as.logical(zero_check["covered"]),
      observed_q95 = observed_q95,
      predicted_q95_q025 = q95_check["q025"],
      predicted_q95_median = q95_check["median"],
      predicted_q95_q975 = q95_check["q975"],
      q95_covered_95 = as.logical(q95_check["covered"]),
      observed_q99 = observed_q99,
      predicted_q99_q025 = q99_check["q025"],
      predicted_q99_median = q99_check["median"],
      predicted_q99_q975 = q99_check["q975"],
      q99_covered_95 = as.logical(q99_check["covered"]),
      observed_maximum = observed_maximum,
      predicted_maximum_q025 = maximum_check["q025"],
      predicted_maximum_median = maximum_check["median"],
      predicted_maximum_q975 = maximum_check["q975"],
      maximum_covered_95 = as.logical(maximum_check["covered"]),
      ppc_status = ppc_status,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  })
)

write_csv2(
  posterior_predictive_check,
  file.path(
    result_dir,
    "S4_FINAL_PPC_offset_corrected.csv2"
  )
)

#===============================================================================
# 9. VARIANCE PARTITIONING
#===============================================================================

covariates <- final_hmsc_model$covNames

if (is.null(covariates)) {
  covariates <- colnames(final_hmsc_model$XData)
}

selected_environment_table <- if (
  file.exists(previous_results_file)
) {
  previous_results <- readRDS(previous_results_file)
  as.data.frame(
    previous_results$selected_environment_variables,
    stringsAsFactors = FALSE
  )
} else {
  data.frame()
}

vp_labels <- rep(
  NA_character_,
  length(covariates)
)

vp_labels[
  covariates %in% c("(Intercept)", "Intercept")
] <- "Intercept"

for (v in locked_weather_variables) {
  vp_labels[covariates == v] <- paste0(
    "weather: ",
    v
  )
}

if (
  nrow(selected_environment_table) > 0L &&
  "model_variable" %in% names(selected_environment_table)
) {
  for (i in seq_len(nrow(selected_environment_table))) {
    v <- selected_environment_table$model_variable[i]

    group_name <- if (
      "ecological_group" %in% names(selected_environment_table)
    ) {
      selected_environment_table$ecological_group[i]
    } else {
      "environment"
    }

    buffer_value <- if (
      "selected_buffer_m" %in% names(selected_environment_table)
    ) {
      selected_environment_table$selected_buffer_m[i]
    } else {
      NA_real_
    }

    label <- if (is.finite(buffer_value)) {
      paste0(
        "environment: ",
        group_name,
        " (",
        buffer_value,
        " m)"
      )
    } else {
      paste0(
        "environment: ",
        group_name
      )
    }

    vp_labels[covariates == v] <- label
  }
}

# If Hmsc includes an intercept in covNames but naming differs
vp_labels[
  is.na(vp_labels) &
    grepl(
      "intercept",
      covariates,
      ignore.case = TRUE
    )
] <- "Intercept"

if (anyNA(vp_labels)) {
  stop(
    "Missing variance-partitioning group for: ",
    paste(
      covariates[is.na(vp_labels)],
      collapse = ", "
    )
  )
}

vp_group_names <- unique(vp_labels)
vp_group <- match(
  vp_labels,
  vp_group_names
)

variance_partitioning <- computeVariancePartitioning(
  final_hmsc_model,
  group = vp_group,
  groupnames = vp_group_names
)

vp <- as.matrix(
  variance_partitioning$vals
)

if (
  !is.null(rownames(vp)) &&
  setequal(
    rownames(vp),
    species_names
  )
) {
  vp <- vp[
    species_names,
    ,
    drop = FALSE
  ]
} else if (
  !is.null(colnames(vp)) &&
  setequal(
    colnames(vp),
    species_names
  )
) {
  vp <- t(
    vp[
      ,
      species_names,
      drop = FALSE
    ]
  )
} else if (
  nrow(vp) == length(species_names)
) {
  rownames(vp) <- species_names
} else {
  stop(
    "Could not identify species in variance-partitioning output."
  )
}

vp_long <- do.call(
  rbind,
  lapply(seq_len(nrow(vp)), function(i) {
    data.frame(
      species = rownames(vp)[i],
      variance_group = colnames(vp),
      variance_proportion = as.numeric(vp[i, ]),
      variance_percent = 100 * as.numeric(vp[i, ]),
      stringsAsFactors = FALSE
    )
  })
)

vp_mapping <- data.frame(
  covariate = covariates,
  variance_group = vp_labels,
  group_id = vp_group,
  stringsAsFactors = FALSE
)

write_csv2(
  vp_mapping,
  file.path(
    result_dir,
    "S4_FINAL_VP_mapping.csv2"
  )
)

write_csv2(
  vp_long,
  file.path(
    result_dir,
    "S4_FINAL_variance_partitioning.csv2"
  )
)

#===============================================================================
# 10. RESIDUAL ASSOCIATIONS
#===============================================================================

residual_associations <- tryCatch(
  computeAssociations(
    final_hmsc_model
  ),
  error = function(e) {
    list(
      error = conditionMessage(e)
    )
  }
)

saveRDS(
  residual_associations,
  file.path(
    result_dir,
    "S4_FINAL_residual_associations.rds"
  )
)

#===============================================================================
# 11. MODEL STRUCTURE + SUMMARY
#===============================================================================

predictor_table <- data.frame(
  predictor = variables_kept,
  role = ifelse(
    variables_kept %in% locked_weather_variables,
    "locked_weather",
    "locked_environment"
  ),
  stringsAsFactors = FALSE
)

write_csv2(
  predictor_table,
  file.path(
    result_dir,
    "S4_FINAL_predictors.csv2"
  )
)

model_structure <- data.frame(
  item = c(
    "analysis_goal",
    "locked_model",
    "distribution",
    "n_observations",
    "n_species",
    "n_predictors",
    "random_levels",
    "effort_offset",
    "variable_selection_repeated",
    "cross_validation",
    "final_status"
  ),
  value = c(
    "explanatory",
    locked_model_label,
    "lognormal Poisson",
    nrow(final_hmsc_model$Y),
    ncol(final_hmsc_model$Y),
    length(variables_kept),
    paste(
      names(final_hmsc_model$ranLevels),
      collapse = " | "
    ),
    "log(total_effort_days / 7)",
    "no",
    "no",
    final_status
  ),
  stringsAsFactors = FALSE
)

write_csv2(
  model_structure,
  file.path(
    result_dir,
    "S4_FINAL_model_structure.csv2"
  )
)

#===============================================================================
# 12. SAVE FINAL RESULT OBJECT
#===============================================================================

S4_FINAL_RESULTS <- list(
  analysis = "final long fit of locked annual explanatory Hmsc model",
  predictive_cross_validation = FALSE,
  locked_model_label = locked_model_label,
  locked_fitted_file = locked_fitted_file,
  current_fingerprint = current_fingerprint,
  final_settings = final_settings,
  final_elapsed_hours = final_elapsed_hours,
  final_status = final_status,
  final_convergence_detailed = final_convergence_detailed,
  final_convergence_summary = final_convergence_summary,
  locked_weather_variables = locked_weather_variables,
  selected_environment_variables = selected_environment_variables,
  predictors = variables_kept,
  beta_results = beta_results,
  explanatory_fit = explanatory_fit_table,
  occurrence_metrics = occurrence_metrics,
  posterior_predictive_check = posterior_predictive_check,
  variance_partitioning = vp_long,
  vp_mapping = vp_mapping,
  residual_associations = residual_associations,
  offset_prediction_used = TRUE,
  session_info = capture.output(sessionInfo())
)

saveRDS(
  S4_FINAL_RESULTS,
  file.path(
    result_dir,
    "S4_FINAL_RESULTS.rds"
  )
)

writeLines(
  S4_FINAL_RESULTS$session_info,
  file.path(result_dir, "sessionInfo.txt")
)

writeLines(
  normalizePath(
    checkpoint_file,
    winslash = "/",
    mustWork = TRUE
  ),
  file.path(
    result_dir,
    "S4_FINAL_MODEL_CHECKPOINT.txt"
  )
)

writeLines(
  c(
    "S4_FINAL_FIT_COMPLETE",
    paste0("status=", final_status),
    paste0("locked_model=", locked_model_label),
    paste0("model_fingerprint=", current_fingerprint),
    "offset_prediction_used=TRUE",
    "predictive_cross_validation=FALSE"
  ),
  complete_file
)

rm(
  pred_expected,
  pred_realized
)
gc()

#===============================================================================
# 13. CONSOLE SUMMARY
#===============================================================================

cat("\n========================================================\n")
cat("S4 FINAL EXPLANATORY HMSC FIT COMPLETE\n")
cat("========================================================\n")

cat("Status:", final_status, "\n")
cat("Results:", result_dir, "\n")

cat("\nFINAL CONVERGENCE\n")
print(
  final_convergence_summary,
  row.names = FALSE
)

cat("\nEXPLANATORY FIT\n")
print(
  explanatory_fit_table,
  row.names = FALSE
)

cat("\nBETA COEFFICIENTS WITH >= 0.80 POSTERIOR SUPPORT\n")
print(
  beta_results[
    beta_results$predictor != "(Intercept)" &
      beta_results$posterior_support >= 0.80,
    ,
    drop = FALSE
  ],
  row.names = FALSE
)

cat("\nPOSTERIOR PREDICTIVE CHECK\n")
print(
  posterior_predictive_check,
  row.names = FALSE
)

cat("\nVARIANCE PARTITIONING\n")
print(
  vp_long,
  row.names = FALSE
)

if (!final_accepted) {
  cat(
    "\nWARNING: the final model did not meet every PSRF/ESS rule.\n",
    "Do not use it for final ecological inference before the failing\n",
    "component(s) have been resolved.\n",
    sep = ""
  )
}

cat("========================================================\n")
