# Reconstructed fold-5 final-profile contract for EIFFEL nested outer CV v2.
# This is intentionally a compatibility profile, not a claim that the missing
# historical v2 producer used byte-for-byte identical settings.

recon_final_profile <- function(repository = getwd()) {
  repository <- normalizePath(repository, winslash = "/", mustWork = TRUE)
  evidence_reference <- file.path(
    repository,
    "project_state/nested_cv_reconstruction_v1/FINAL_PROFILE_CONTRACT.md"
  )
  list(
    execution_profile_verified = TRUE,
    profile_basis = "v1_source_plus_v2_outputs_plus_local_runtime",
    historical_v2_exact = FALSE,
    evidence_reference = evidence_reference,
    R_version = "4.5.2",
    Hmsc_version = "3.3.7",
    coda_version = "0.19.4.1",
    rng_kind = c("Mersenne-Twister", "Inversion", "Rejection"),
    mcmc = list(
      samples = 5000L,
      transient = 10000L,
      thin = 20L,
      chains = 4L,
      parallel = 4L
    ),
    max_prediction_draws = 1000L,
    random_level_units = "all_metadata",
    distribution = "lognormal poisson",
    annual_index_standard_days = 7L,
    note = paste(
      "Reconstructed compatibility profile derived from the retained v1 nested-CV",
      "producer, validated v2 fold outputs, matching R/Hmsc runtime evidence, and",
      "the current local runtime. It does not establish exact historical v2 RNG/MCMC identity."
    )
  )
}
