# Read-only Hmsc initialization diagnostic for reconstructed EIFFEL fold 5.
# Builds the two fold-5 Hmsc objects and runs computeInitialParameters only.
# No MCMC is sampled and no scientific output is written.

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
source(file.path(repository, "R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R"))
source(file.path(repository, "R/S3_NESTED_OUTER_CV_PREDICTIVE_v2_FINAL_PROFILE.R"))

root <- value("--output-root", "D:/EIFFEL_runtime/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2")
primary <- value(
  "--primary-data",
  file.path(dirname(root),
            "HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1",
            "HMSC_annual_three_species_weather_environment_buffers_results.RData")
)

profile <- recon_final_profile(repository)
recon_profile_gate(profile)
root <- recon_root(root, execution = TRUE)
inputs <- recon_load_inputs(primary)
plan <- recon_inspect(root, repository, fold_only = 5L, inputs = inputs)
r <- plan$folds[["5"]]
if (!identical(r$status, "SELECTION_COMPLETE_FINAL_PENDING")) {
  stop("Fold 5 is not in the expected selection-complete/final-pending state.")
}

backend <- recon_v1_backend(inputs, profile)
seed_base <- as.integer(20260818L %% 100000L + 5L * 10000000L)

cases <- list(
  WEATHER_ONLY = list(vars = r$weather, seed = seed_base + 30000000L),
  WEATHER_PLUS_ENVIRONMENT = list(vars = c(r$weather, r$environment),
                                  seed = seed_base + 40000000L)
)

cat("HMSC FOLD-5 INITIALIZATION DIAGNOSTIC (NO MCMC)\n")
cat("Reconstruction: ", recon_version, "\n", sep = "")

for (nm in names(cases)) {
  z <- cases[[nm]]
  prepared <- backend$prepare(z$vars, r$ids$final_train, z$seed)
  m <- prepared$model
  cat("\n", nm, "\n", sep = "")
  cat("  TRAIN rows: ", length(prepared$train_ids), "\n", sep = "")
  for (rr in seq_len(m$nr)) {
    cat("  random level ", m$rLNames[rr],
        ": np=", m$np[rr],
        ", Pi_range=", min(m$Pi[, rr]), "-", max(m$Pi[, rr]),
        ", ranLevel_N=", m$rL[[rr]]$N, "\n", sep = "")
  }
  compute_initial <- getFromNamespace("computeInitialParameters", "Hmsc")
  invisible(compute_initial(m, initPar = NULL))
  cat("  computeInitialParameters: PASS\n")
}

cat("\nHMSC FOLD-5 INITIALIZATION DIAGNOSTIC: PASS\n")
cat("No MCMC sampled. No scientific outputs written.\n")
