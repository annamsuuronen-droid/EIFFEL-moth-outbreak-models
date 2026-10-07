#===============================================================================
# S3: MCMC CALIBRATION AND CONVERGENCE FOR THE LOCKED ANNUAL EXPLANATORY HMSC MODEL
#     Continues directly from S1/S2 C+D annual matched environmental selection
#===============================================================================
#
# PURPOSE
# -------
# This script is NOT predictive validation.
#
# It does NOT perform:
#   - cross-validation
#   - future holdout
#   - new-site prediction
#   - new-year prediction
#   - predictive model ranking
#
# It performs only:
#   1. loading and validating the locked explanatory model structure
#   2. an intermediate MCMC calibration fit
#   3. convergence diagnostics (PSRF + ESS)
#   4. estimation of a suitable MCMC length for the final S4 fit
#
# The final explanatory model is the model selected by the preceding C+D script.
# If no environmental variables were selected, this is the locked WEATHER_ONLY
# model.
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

output_dir <- file.path(
  hmsc_output_root,
  "HMSC_ANNUAL_EXPLANATORY_CALIBRATION_v2"
)

checkpoint_dir <- file.path(output_dir, "checkpoints")
result_dir <- file.path(output_dir, "results")

dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

run_smoke_test_only <- FALSE
reuse_existing_checkpoint <- TRUE
stop_if_complete <- TRUE

calibration_stages <- list(
  stage1 = list(
    samples = 1000L,
    transient = 10000L,
    thin = 20L,
    chains = 4L,
    parallel = 4L,
    seed = 5101L
  ),
  stage2 = list(
    samples = 2000L,
    transient = 40000L,
    thin = 20L,
    chains = 4L,
    parallel = 4L,
    seed = 5201L
  )
)

calibration_mcmc <- calibration_stages$stage1

# Calibration acceptance thresholds
calibration_rules <- data.frame(
  component = c("Beta", "Gamma", "V", "Rho", "Omega"),
  PSRF_limit = c(1.10, 1.15, 1.15, 1.15, 1.15),
  ESS_limit = c(100, 100, 100, 100, 100),
  stringsAsFactors = FALSE
)

# Final S4 target rules
target_final_ESS <- 400
ESS_safety_factor <- 1.50
minimum_final_samples_per_chain <- 3000L
maximum_final_samples_per_chain <- 10000L
final_thin <- 20L

if (run_smoke_test_only) {
  calibration_stages <- list(
    stage1 = list(
      samples = 5L,
      transient = 5L,
      thin = 1L,
      chains = 2L,
      parallel = 1L,
      seed = 5199L
    ),
    stage2 = list(
      samples = 10L,
      transient = 10L,
      thin = 1L,
      chains = 2L,
      parallel = 1L,
      seed = 5299L
    )
  )
  calibration_mcmc <- calibration_stages$stage1
  target_final_ESS <- 5
  minimum_final_samples_per_chain <- 5L
  maximum_final_samples_per_chain <- 5L
  final_thin <- 1L
}

complete_file <- file.path(result_dir, "S3_CALIBRATION_COMPLETE.txt")

if (
  stop_if_complete &&
  file.exists(complete_file) &&
  !run_smoke_test_only
) {
  stop(
    "S3 calibration is already marked complete:\n",
    complete_file,
    "\nUse a new output_dir version if a new calibration is intended."
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

round_up <- function(x, unit = 250L) {
  as.integer(ceiling(x / unit) * unit)
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

#===============================================================================
# 3. LOAD PREVIOUS C+D RESULTS AND CHOOSE THE LOCKED FINAL MODEL
#===============================================================================

if (!file.exists(previous_results_file)) {
  stop(
    "Previous C+D result file was not found:\n",
    previous_results_file
  )
}

previous_results <- readRDS(previous_results_file)

required_fields <- c(
  "locked_weather_variables",
  "selected_environment_variables",
  "final_sample_ids",
  "final_weather_only",
  "final_weather_plus_environment",
  "final_offset_prediction_used"
)

missing_fields <- setdiff(required_fields, names(previous_results))

if (length(missing_fields) > 0L) {
  stop(
    "Previous C+D results are missing fields: ",
    paste(missing_fields, collapse = ", ")
  )
}

if (!isTRUE(previous_results$final_offset_prediction_used)) {
  stop(
    "Previous final models are not marked as explicitly offset-corrected."
  )
}

locked_weather_variables <- unique(
  as.character(previous_results$locked_weather_variables)
)

selected_environment_table <- as.data.frame(
  previous_results$selected_environment_variables,
  stringsAsFactors = FALSE
)

selected_environment_variables <- if (
  nrow(selected_environment_table) > 0L &&
  "model_variable" %in% names(selected_environment_table)
) {
  unique(as.character(selected_environment_table$model_variable))
} else {
  character(0)
}

selected_environment_variables <- selected_environment_variables[
  !is.na(selected_environment_variables) &
    nzchar(selected_environment_variables)
]

# If environment survived selection, calibrate the full final model.
# Otherwise calibrate WEATHER_ONLY.
if (length(selected_environment_variables) > 0L) {
  locked_result <- previous_results$final_weather_plus_environment
  locked_model_label <- "WEATHER_PLUS_ENVIRONMENT"
} else {
  locked_result <- previous_results$final_weather_only
  locked_model_label <- "WEATHER_ONLY"
}

locked_fitted_file <- locked_result$fitted_file

if (
  is.null(locked_fitted_file) ||
  length(locked_fitted_file) != 1L ||
  is.na(locked_fitted_file) ||
  !file.exists(locked_fitted_file)
) {
  fallback_name <- if (locked_model_label == "WEATHER_ONLY") {
    "FINAL_ANNUAL_WEATHER_ONLY_MATCHED_fitted.RData"
  } else {
    "FINAL_ANNUAL_WEATHER_PLUS_ENVIRONMENT_MATCHED_fitted.RData"
  }

  locked_fitted_file <- file.path(
    previous_output_dir,
    "04_final_models",
    fallback_name
  )
}

if (!file.exists(locked_fitted_file)) {
  stop(
    "Locked final fitted model file was not found:\n",
    locked_fitted_file
  )
}

locked_env <- load_rdata_environment(
  locked_fitted_file,
  required = c(
    "model_unfitted",
    "Y_model",
    "Loff_model",
    "metadata_model",
    "variables_kept"
  )
)

locked_model <- get("model_unfitted", envir = locked_env)
Y_model <- get("Y_model", envir = locked_env)
Loff_model <- get("Loff_model", envir = locked_env)
metadata_model <- get("metadata_model", envir = locked_env)
variables_kept <- unique(as.character(
  get("variables_kept", envir = locked_env)
))

rm(locked_env)

if (!inherits(locked_model, "Hmsc")) {
  stop("Locked object is not an Hmsc model.")
}

if (is.null(locked_model$Loff)) {
  stop("Locked Hmsc model has no Loff.")
}

if (!identical(dim(locked_model$Y), dim(locked_model$Loff))) {
  stop("Locked Hmsc model Y and Loff dimensions differ.")
}

if (!identical(dim(Y_model), dim(Loff_model))) {
  stop("Saved Y_model and Loff_model dimensions differ.")
}

if (!setequal(names(locked_model$ranLevels), c("site", "year"))) {
  stop("Random levels must be exactly site and year.")
}

expected_variables <- unique(c(
  locked_weather_variables,
  selected_environment_variables
))

if (!setequal(variables_kept, expected_variables)) {
  stop(
    "Variables in the locked fitted model differ from the final C+D selection.\n",
    "Missing from fitted model: ",
    paste(setdiff(expected_variables, variables_kept), collapse = ", "),
    "\nUnexpected in fitted model: ",
    paste(setdiff(variables_kept, expected_variables), collapse = ", ")
  )
}

locked_fingerprint <- model_fingerprint(locked_model)

cat("\n========================================================\n")
cat("S3 EXPLANATORY MCMC CALIBRATION\n")
cat("========================================================\n")
cat("Locked model:", locked_model_label, "\n")
cat("Locked fitted file:", locked_fitted_file, "\n")
cat("Observations:", nrow(locked_model$Y), "\n")
cat("Species:", ncol(locked_model$Y), "\n")
cat("Predictors:", length(variables_kept), "\n")
cat("Weather variables:", length(locked_weather_variables), "\n")
cat("Environment variables:", length(selected_environment_variables), "\n")
cat("Explicit effort offset: TRUE\n")

#===============================================================================
# 4. CALIBRATION FIT + AUTOMATIC ESCALATION
#===============================================================================

diagnose_component <- function(x, component, random_level = NA_character_) {
  if (is.null(x) || !inherits(x, "mcmc.list")) return(NULL)

  parameter <- colnames(as.matrix(x[[1]]))
  if (is.null(parameter)) {
    parameter <- paste0("parameter_", seq_len(ncol(x[[1]])))
  }

  ess <- tryCatch(effectiveSize(x), error = function(e) NULL)
  psrf <- tryCatch(
    gelman.diag(x, multivariate = FALSE, autoburnin = FALSE)$psrf,
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
    out$PSRF_upper <- psrf[hit, min(2L, ncol(psrf))]
  }

  if (!is.null(ess)) {
    if (is.null(names(ess)) && length(ess) == nrow(out)) {
      out$ESS <- as.numeric(ess)
    } else {
      out$ESS <- as.numeric(ess[match(parameter, names(ess))])
    }
  }

  out
}

diagnose_calibration <- function(model, stage_name) {
  mpost <- convertToCodaObject(
    model,
    spNamesNumbers = c(TRUE, FALSE),
    covNamesNumbers = c(TRUE, FALSE)
  )

  diagnostic_parts <- list()

  for (component in c("Beta", "Gamma", "V", "Rho")) {
    if (!is.null(mpost[[component]])) {
      diagnostic_parts[[length(diagnostic_parts) + 1L]] <-
        diagnose_component(mpost[[component]], component)
    }
  }

  if (!is.null(mpost$Omega)) {
    random_names <- names(model$ranLevels)
    for (r in seq_along(mpost$Omega)) {
      diagnostic_parts[[length(diagnostic_parts) + 1L]] <-
        diagnose_component(
          mpost$Omega[[r]],
          "Omega",
          random_names[r]
        )
    }
  }

  detailed <- do.call(rbind, Filter(Negate(is.null), diagnostic_parts))

  if (is.null(detailed) || !nrow(detailed)) {
    stop("No convergence diagnostics were produced for ", stage_name, ".")
  }

  key <- interaction(
    detailed$component,
    ifelse(is.na(detailed$random_level), "", detailed$random_level),
    drop = TRUE
  )

  summary <- do.call(
    rbind,
    lapply(split(detailed, key), function(z) {
      rule <- calibration_rules[
        calibration_rules$component == z$component[1],
        ,
        drop = FALSE
      ]

      max_psrf <- safe_max(z$PSRF_upper)
      min_ess <- safe_min(z$ESS)

      data.frame(
        calibration_stage = stage_name,
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
    })
  )

  rownames(summary) <- NULL

  list(
    detailed = detailed,
    summary = summary,
    accepted = all(summary$accepted),
    worst_PSRF = safe_max(detailed$PSRF_upper),
    worst_ESS = safe_min(detailed$ESS)
  )
}

run_calibration_stage <- function(stage_name, settings) {
  checkpoint_file <- file.path(
    checkpoint_dir,
    paste0(
      "CALIBRATION_", stage_name, "_", locked_model_label,
      "_samples_", settings$samples,
      "_transient_", settings$transient,
      "_thin_", settings$thin,
      "_chains_", settings$chains,
      ".RData"
    )
  )

  if (reuse_existing_checkpoint && file.exists(checkpoint_file)) {
    e <- load_rdata_environment(
      checkpoint_file,
      required = c("calibration_model", "locked_fingerprint")
    )

    calibration_model <- get("calibration_model", envir = e)
    checkpoint_fingerprint <- get("locked_fingerprint", envir = e)

    calibration_elapsed_hours <- if (
      exists("calibration_elapsed_hours", envir = e, inherits = FALSE)
    ) {
      get("calibration_elapsed_hours", envir = e)
    } else {
      NA_real_
    }

    rm(e)

    if (!identical(checkpoint_fingerprint, locked_fingerprint)) {
      stop("Calibration checkpoint belongs to a different locked model.")
    }

    cat("Loaded existing calibration checkpoint:\n", checkpoint_file, "\n")
  } else {
    set.seed(settings$seed)
    start_time <- Sys.time()

    calibration_model <- sampleMcmc(
      locked_model,
      samples = settings$samples,
      transient = settings$transient,
      thin = settings$thin,
      nChains = settings$chains,
      nParallel = settings$parallel,
      verbose = 100
    )

    end_time <- Sys.time()

    calibration_elapsed_hours <- as.numeric(
      difftime(end_time, start_time, units = "hours")
    )

    partial <- paste0(checkpoint_file, ".partial")

    save(
      calibration_model,
      settings,
      stage_name,
      locked_fingerprint,
      calibration_elapsed_hours,
      file = partial
    )

    if (!file.rename(partial, checkpoint_file)) {
      stop("Could not finalize calibration checkpoint.")
    }
  }

  if (!has_posterior(calibration_model)) {
    stop(stage_name, " calibration model has no posterior samples.")
  }

  if (is.null(calibration_model$Loff)) {
    stop("Loff disappeared from ", stage_name, " calibration model.")
  }

  diagnostics <- diagnose_calibration(calibration_model, stage_name)

  detailed_out <- diagnostics$detailed
  detailed_out$calibration_stage <- stage_name

  write_csv2(
    detailed_out,
    file.path(result_dir, paste0("S3_", stage_name, "_convergence_detailed.csv2"))
  )

  write_csv2(
    diagnostics$summary,
    file.path(result_dir, paste0("S3_", stage_name, "_convergence_summary.csv2"))
  )

  list(
    stage_name = stage_name,
    settings = settings,
    model = calibration_model,
    elapsed_hours = calibration_elapsed_hours,
    checkpoint_file = checkpoint_file,
    diagnostics = diagnostics
  )
}

cat("\n========================================================\n")
cat("CALIBRATION STAGE 1\n")
cat("========================================================\n")

stage1_result <- run_calibration_stage(
  "stage1",
  calibration_stages$stage1
)

calibration_history <- list(stage1_result)

if (!stage1_result$diagnostics$accepted) {
  cat(
    "\nStage 1 did not meet all PSRF/ESS criteria.\n",
    "Running the longer Stage 2 calibration automatically.\n",
    sep = ""
  )

  cat("\n========================================================\n")
  cat("CALIBRATION STAGE 2\n")
  cat("========================================================\n")

  stage2_result <- run_calibration_stage(
    "stage2",
    calibration_stages$stage2
  )

  calibration_history[[2L]] <- stage2_result
  final_calibration_result <- stage2_result
} else {
  final_calibration_result <- stage1_result
}

calibration_model <- final_calibration_result$model
calibration_mcmc <- final_calibration_result$settings
calibration_elapsed_hours <- final_calibration_result$elapsed_hours
calibration_convergence_detailed <- final_calibration_result$diagnostics$detailed
calibration_convergence_summary <- final_calibration_result$diagnostics$summary
calibration_worst_PSRF <- final_calibration_result$diagnostics$worst_PSRF
calibration_worst_ESS <- final_calibration_result$diagnostics$worst_ESS
calibration_accepted <- final_calibration_result$diagnostics$accepted
calibration_stage_used <- final_calibration_result$stage_name

calibration_history_summary <- do.call(
  rbind,
  lapply(calibration_history, function(x) x$diagnostics$summary)
)
rownames(calibration_history_summary) <- NULL

write_csv2(
  calibration_history_summary,
  file.path(result_dir, "S3_calibration_history_summary.csv2")
)

#===============================================================================
# 6. DETERMINE FINAL S4 MCMC LENGTH
#===============================================================================

if (run_smoke_test_only) {
  ESS_fraction <- NA_real_

  final_settings <- list(
    samples = 5L,
    transient = 5L,
    thin = 1L,
    chains = 2L,
    parallel = 1L,
    seed = 6101L
  )
} else {
  pooled_calibration_samples <-
    calibration_mcmc$samples * calibration_mcmc$chains

  ESS_fraction <- calibration_worst_ESS /
    pooled_calibration_samples

  estimated_samples <- if (
    is.finite(ESS_fraction) &&
    ESS_fraction > 0
  ) {
    target_final_ESS /
      (ESS_fraction * calibration_mcmc$chains) *
      ESS_safety_factor
  } else {
    maximum_final_samples_per_chain
  }

  final_samples <- round_up(
    estimated_samples,
    250L
  )

  final_samples <- max(
    minimum_final_samples_per_chain,
    final_samples
  )

  final_samples <- min(
    maximum_final_samples_per_chain,
    final_samples
  )

  final_transient <- if (
    is.finite(calibration_worst_PSRF) &&
    calibration_worst_PSRF <= 1.05
  ) {
    20000L
  } else if (
    is.finite(calibration_worst_PSRF) &&
    calibration_worst_PSRF <= 1.10
  ) {
    40000L
  } else {
    80000L
  }

  final_settings <- list(
    samples = as.integer(final_samples),
    transient = as.integer(final_transient),
    thin = as.integer(final_thin),
    chains = as.integer(calibration_mcmc$chains),
    parallel = as.integer(calibration_mcmc$parallel),
    seed = 6101L
  )
}

length_decision <- data.frame(
  locked_model = locked_model_label,
  calibration_stage_used = calibration_stage_used,
  calibration_samples_per_chain = calibration_mcmc$samples,
  calibration_transient = calibration_mcmc$transient,
  calibration_thin = calibration_mcmc$thin,
  calibration_chains = calibration_mcmc$chains,
  calibration_maximum_PSRF_upper = calibration_worst_PSRF,
  calibration_minimum_ESS = calibration_worst_ESS,
  calibration_accepted = calibration_accepted,
  estimated_ESS_fraction = ESS_fraction,
  target_final_ESS = target_final_ESS,
  ESS_safety_factor = ESS_safety_factor,
  final_samples_per_chain = final_settings$samples,
  final_transient = final_settings$transient,
  final_thin = final_settings$thin,
  final_chains = final_settings$chains,
  final_parallel = final_settings$parallel,
  final_updates_per_chain =
    final_settings$transient +
    final_settings$samples * final_settings$thin,
  stringsAsFactors = FALSE
)

write_csv2(
  length_decision,
  file.path(
    result_dir,
    "S3_MCMC_length_decision_for_S4.csv2"
  )
)

#===============================================================================
# 7. SAVE S3 RESULTS
#===============================================================================

S3_CALIBRATION_RESULTS <- list(
  analysis = "MCMC calibration for locked annual explanatory Hmsc model",
  predictive_cross_validation = FALSE,
  locked_model_label = locked_model_label,
  locked_fitted_file = locked_fitted_file,
  locked_fingerprint = locked_fingerprint,
  locked_weather_variables = locked_weather_variables,
  selected_environment_variables = selected_environment_variables,
  variables_kept = variables_kept,
  final_sample_ids = previous_results$final_sample_ids,
  calibration_stages = calibration_stages,
  calibration_stage_used = calibration_stage_used,
  calibration_history_summary = calibration_history_summary,
  calibration_mcmc = calibration_mcmc,
  calibration_elapsed_hours = calibration_elapsed_hours,
  calibration_convergence_detailed = calibration_convergence_detailed,
  calibration_convergence_summary = calibration_convergence_summary,
  calibration_worst_PSRF = calibration_worst_PSRF,
  calibration_worst_ESS = calibration_worst_ESS,
  calibration_accepted = calibration_accepted,
  final_settings = final_settings,
  length_decision = length_decision,
  offset_prediction_used = TRUE,
  session_info = capture.output(sessionInfo())
)

saveRDS(
  S3_CALIBRATION_RESULTS,
  file.path(
    result_dir,
    "S3_CALIBRATION_RESULTS.rds"
  )
)

writeLines(
  S3_CALIBRATION_RESULTS$session_info,
  file.path(result_dir, "sessionInfo.txt")
)

#===============================================================================
# 8. SAFETY GATE + CONSOLE SUMMARY
#===============================================================================

cat("\n========================================================\n")
cat("S3 EXPLANATORY MCMC CALIBRATION FINISHED\n")
cat("========================================================\n")

cat("\nCALIBRATION HISTORY\n")
print(calibration_history_summary, row.names = FALSE)

cat("\nFINAL CALIBRATION USED FOR S4 DECISION\n")
print(calibration_convergence_summary, row.names = FALSE)

cat("\nMCMC LENGTH DECISION FOR S4\n")
print(length_decision, row.names = FALSE)

cat("\nResults:", result_dir, "\n")

if (calibration_accepted) {
  writeLines(
    c(
      "S3_CALIBRATION_COMPLETE",
      paste0("smoke_test=", run_smoke_test_only),
      paste0("locked_model=", locked_model_label),
      paste0("calibration_stage_used=", calibration_stage_used),
      "calibration_accepted=TRUE",
      paste0("locked_fingerprint=", locked_fingerprint),
      "offset_used=TRUE"
    ),
    complete_file
  )

  failed_file <- file.path(result_dir, "S3_CALIBRATION_FAILED.txt")
  if (file.exists(failed_file)) unlink(failed_file)

  cat("\nS3 calibration safety gate: PASSED\n")
  cat("S4 may now be started.\n")
  cat("========================================================\n")
} else {
  if (file.exists(complete_file)) unlink(complete_file)

  failed_file <- file.path(result_dir, "S3_CALIBRATION_FAILED.txt")

  writeLines(
    c(
      "S3_CALIBRATION_FAILED",
      paste0("locked_model=", locked_model_label),
      paste0("last_stage=", calibration_stage_used),
      paste0("maximum_PSRF_upper=", calibration_worst_PSRF),
      paste0("minimum_ESS=", calibration_worst_ESS),
      paste0("locked_fingerprint=", locked_fingerprint)
    ),
    failed_file
  )

  cat("\nS3 calibration safety gate: FAILED\n")
  cat("S4 WILL NOT BE STARTED.\n")
  cat("========================================================\n")

  stop(
    "S3 calibration failed after all configured calibration stages. ",
    "Maximum PSRF upper = ",
    round(calibration_worst_PSRF, 3),
    ", minimum ESS = ",
    round(calibration_worst_ESS, 1),
    ". Inspect S3_calibration_history_summary.csv2 and the detailed ",
    "convergence files before changing the model or MCMC settings."
  )
}
