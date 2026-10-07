# Explicit scientific execution wrapper for the reconstructed EIFFEL nested outer CV v2 fold 5.
#
# This file is intentionally separate from the reconstruction/validation script.
# It runs ONLY outer-year fold 5 and ONLY after two explicit acknowledgement flags.
# Folds 1-4 are immutable; outer-site CV is not invoked.

fold5_value <- function(args, flag, default) {
  i <- which(args == flag)
  if (length(i) > 1L) stop("Duplicate option: ", flag)
  if (!length(i)) return(default)
  if (i >= length(args) || startsWith(args[i + 1L], "--")) stop("Missing option value: ", flag)
  args[i + 1L]
}

run_fold5_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  required_flags <- c(
    "--execute-reconstructed-fold5",
    "--acknowledge-nonhistorical-v2"
  )
  missing_flags <- setdiff(required_flags, args)
  if (length(missing_flags)) {
    stop(
      "Scientific execution refused. Missing explicit acknowledgement flag(s): ",
      paste(missing_flags, collapse = ", ")
    )
  }

  value_flags <- c("--repository", "--output-root", "--primary-data")
  allowed <- c(required_flags, value_flags)
  option_tokens <- args[startsWith(args, "--")]
  unknown <- setdiff(option_tokens, allowed)
  if (length(unknown)) stop("Unexpected option(s): ", paste(unique(unknown), collapse = ", "))

  repository <- normalizePath(
    fold5_value(args, "--repository", getwd()),
    winslash = "/",
    mustWork = TRUE
  )
  recon_script <- file.path(
    repository,
    "R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R"
  )
  profile_script <- file.path(
    repository,
    "R/S3_NESTED_OUTER_CV_PREDICTIVE_v2_FINAL_PROFILE.R"
  )
  if (!file.exists(recon_script) || !file.exists(profile_script)) {
    stop("Required reconstruction/profile source is missing.")
  }

  source(recon_script, local = .GlobalEnv)
  source(profile_script, local = .GlobalEnv)

  root <- fold5_value(
    args,
    "--output-root",
    "E:/EIFFEL uusi/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2"
  )
  primary <- fold5_value(
    args,
    "--primary-data",
    file.path(
      dirname(root),
      "HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1",
      "HMSC_annual_three_species_weather_environment_buffers_results.RData"
    )
  )

  profile <- recon_final_profile(repository)
  recon_profile_gate(profile)

  if (!identical(RNGkind(), profile$rng_kind)) {
    stop("Current RNGkind differs from the reconstructed compatibility profile.")
  }
  cores <- parallel::detectCores()
  if (!is.finite(cores) || cores < profile$mcmc$parallel) {
    stop("Insufficient CPU cores for the four-worker reconstructed profile.")
  }

  # Full read-only validation is repeated immediately before any staging/fitting.
  inputs <- recon_load_inputs(primary)
  root_checked <- recon_root(root, execution = TRUE)
  plan <- recon_inspect(root_checked, repository, fold_only = 5L, inputs = inputs)
  r <- plan$folds[["5"]]
  if (isTRUE(r$complete)) {
    cat("Fold 5 already complete: nothing to do.\n")
    return(invisible(plan))
  }
  if (!identical(r$status, "SELECTION_COMPLETE_FINAL_PENDING")) {
    stop("Fold 5 is not in the expected selection-complete/final-pending state.")
  }
  if (length(r$ids$final_train) != 916L || length(r$ids$final_test) != 222L) {
    stop("Fold-5 matched TRAIN/TEST sizes differ from frozen v2 evidence.")
  }

  cat("============================================================\n")
  cat("RECONSTRUCTED EIFFEL NESTED-CV V2: EXECUTING OUTER-YEAR FOLD 5\n")
  cat("Historical v2 exact identity claimed: NO\n")
  cat("Folds 1-4: immutable, not rerun\n")
  cat("Outer-site CV: disabled\n")
  cat("Fold-5 selection: reuse frozen exports\n")
  cat("Matched TRAIN / TEST: 916 / 222\n")
  cat("Scientific work: WEATHER_ONLY final fit, WEATHER_PLUS_ENVIRONMENT final fit, held-out predictions/metrics\n")
  cat("============================================================\n")

  out <- recon_resume_fold5(
    root = root_checked,
    repository = repository,
    primary_file = primary,
    verified_profile = profile,
    fold = 5L
  )

  cat("\n============================================================\n")
  cat("RECONSTRUCTED FOLD-5 EXECUTION COMPLETE\n")
  cat("Final outputs published only after validation.\n")
  cat("Outer-site CV remains disabled.\n")
  cat("============================================================\n")
  invisible(out)
}

if (sys.nframe() == 0L) run_fold5_main()
