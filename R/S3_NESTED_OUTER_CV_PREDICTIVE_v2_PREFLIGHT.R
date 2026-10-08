# Read-only preflight for the reconstructed EIFFEL nested outer CV v2 fold-5 continuation.
# This script never calls recon_resume_fold5() and never writes scientific outputs.

args <- commandArgs(trailingOnly = TRUE)
value <- function(flag, default) {
  i <- which(args == flag)
  if (length(i) > 1L) stop("Duplicate option: ", flag)
  if (!length(i)) return(default)
  if (i >= length(args) || startsWith(args[i + 1L], "--")) stop("Missing option value: ", flag)
  args[i + 1L]
}
allowed <- c("--repository", "--output-root", "--primary-data")
unknown <- args[startsWith(args, "--") & !args %in% allowed]
if (length(unknown)) stop("Unexpected option(s): ", paste(unique(unknown), collapse = ", "))

repository <- normalizePath(value("--repository", getwd()), winslash = "/", mustWork = TRUE)
recon_script <- file.path(repository, "R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R")
profile_script <- file.path(repository, "R/S3_NESTED_OUTER_CV_PREDICTIVE_v2_FINAL_PROFILE.R")
if (!file.exists(recon_script) || !file.exists(profile_script)) stop("Required reconstruction/profile script is missing.")

source(recon_script, local = .GlobalEnv)
source(profile_script, local = .GlobalEnv)

root <- value("--output-root", "D:/EIFFEL_runtime/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2")
primary <- value(
  "--primary-data",
  file.path(dirname(root),
            "HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1",
            "HMSC_annual_three_species_weather_environment_buffers_results.RData")
)

profile <- recon_final_profile(repository)
recon_profile_gate(profile)

if (!identical(RNGkind(), profile$rng_kind)) {
  stop("Current RNGkind differs from the reconstructed compatibility profile.")
}
cores <- parallel::detectCores()
if (!is.finite(cores) || cores < profile$mcmc$parallel) {
  stop("Fewer CPU cores detected than the four-worker reconstructed profile requires.")
}

root <- recon_root(root, execution = TRUE)
inputs <- recon_load_inputs(primary)
plan <- recon_inspect(root, repository, fold_only = 5L, inputs = inputs)
r <- plan$folds[["5"]]

if (!identical(r$status, "SELECTION_COMPLETE_FINAL_PENDING")) {
  stop("Fold 5 is not in the expected selection-complete/final-pending state.")
}
if (isTRUE(r$complete)) stop("Fold 5 is already complete; refusing reconstructed continuation preflight.")

if (length(r$ids$final_train) != 916L || length(r$ids$final_test) != 222L) {
  stop("Fold-5 matched TRAIN/TEST sizes differ from frozen v2 evidence.")
}
expected_weather <- c(
  "lag1_summer_mean_Tmin",
  "lag1_summer_min_Tmin",
  "lag1_summer_mean_Tmax",
  "lag1_summer_max_Tmax",
  "lag2_growing_sum_precipitation",
  "lag2_autumn_sum_precipitation",
  "lag2_autumn_mean_precipitation"
)
expected_environment <- c(
  "HostTreeDroughtStressIndex__b100m",
  "SoilDrynessSensitivityIndex__b100m"
)
if (!identical(r$weather, expected_weather)) stop("Fold-5 weather selection differs from frozen evidence.")
if (!identical(r$environment, expected_environment)) stop("Fold-5 environment selection differs from frozen evidence.")

fd <- file.path(root, "outer_year/fold_05")
final_outputs <- file.path(fd, c(
  "outer_test_predictions.csv2",
  "outer_test_metrics.csv2",
  "OUTER_FOLD_COMPLETE.rds"
))
if (any(file.exists(final_outputs))) stop("Fold-5 final output already exists; refusing preflight.")
stage <- file.path(fd, "RECONSTRUCTED_r2")
if (dir.exists(stage)) stop("A reconstructed staging directory already exists; inspect recovery state before starting a new run.")

cat("RECONSTRUCTED FOLD-5 PREFLIGHT: PASS\n")
cat("Profile basis: ", profile$profile_basis, "\n", sep = "")
cat("Historical v2 exact identity claimed: NO\n")
cat("R: ", profile$R_version, "; Hmsc: ", profile$Hmsc_version,
    "; coda: ", profile$coda_version, "\n", sep = "")
cat("RNGkind: ", paste(profile$rng_kind, collapse = " | "), "\n", sep = "")
cat("MCMC: samples=", profile$mcmc$samples,
    ", transient=", profile$mcmc$transient,
    ", thin=", profile$mcmc$thin,
    ", chains=", profile$mcmc$chains,
    ", parallel=", profile$mcmc$parallel, "\n", sep = "")
cat("Prediction draws cap: ", profile$max_prediction_draws, "\n", sep = "")
cat("Fold 1-4: immutable complete, skipped\n")
cat("Fold 5 selection: reuse frozen exports\n")
cat("Fold 5 matched TRAIN/TEST: 916 / 222\n")
cat("Next scientific work if explicitly authorized: two outer-final TRAIN fits (WEATHER_ONLY and WEATHER_PLUS_ENVIRONMENT), then held-out predictions/metrics.\n")
cat("Outer-site CV: DISABLED\n")
