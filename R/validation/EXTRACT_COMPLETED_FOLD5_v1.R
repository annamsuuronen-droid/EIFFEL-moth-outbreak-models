# Base-R read-only validation. No Hmsc loading, fitting, prediction or model execution.
fold5_validate_primary_rows <- function(predictions, inputs, expected_ids) {
  if (!setequal(unique(predictions$sample_id),expected_ids)) stop("Matched TEST IDs differ from primary complete cases.",call.=FALSE)
  observed <- inputs$Y_annual_all[cbind(match(predictions$sample_id,inputs$base_ids),match(predictions$species,colnames(inputs$Y_annual_all)))]
  actual <- as.numeric(gsub(",", ".", predictions$observed, fixed=TRUE))
  if (!isTRUE(all.equal(unname(actual),unname(observed),tolerance=1e-12))) stop("Observed values differ from saved primary input.",call.=FALSE)
  invisible(TRUE)
}
fold5_extract <- function(source_root, repository, target) {
  source(file.path(repository, "R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R"), local = TRUE)
  source(file.path(repository, "R/S3_NESTED_OUTER_CV_PREDICTIVE_v2_FINAL_PROFILE.R"), local = TRUE)
  expected <- recon_read_expected(repository); f <- expected$folds[["5"]]
  relative <- "hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_05"
  local_dir <- file.path(source_root, relative)
  imported <- file.path(target, relative)
  cp <- readRDS(file.path(local_dir, "OUTER_FOLD_COMPLETE.rds"))
  provenance <- readRDS(file.path(local_dir, "RECONSTRUCTED_r2/PROVENANCE.rds"))
  primary <- file.path(source_root, "hmsc_outputs/HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1/HMSC_annual_three_species_weather_environment_buffers_results.RData")
  inputs <- recon_load_inputs(primary)
  # Validate the immutable historical snapshots against the SAME saved primary input.
  # This reads repository copies only, not additional Windows source directories.
  historical_root <- file.path(repository,"imported_local/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2")
  historical_plan <- recon_inspect(historical_root,repository,evidence_only=TRUE,inputs=inputs)
  for (fold in 1:4) {
    r <- historical_plan$folds[[as.character(fold)]]
    fold5_validate_primary_rows(r$predictions,inputs,r$ids$final_test)
  }
  pred <- recon_table(file.path(imported, "outer_test_predictions.csv2"))
  metrics <- recon_table(file.path(imported, "outer_test_metrics.csv2"))
  report <- list(fold=5L, weather=f$weather, environment=f$environment, coverage=f$coverage,
                 partition=expected$partition, predictions=pred, metrics=metrics)
  recon_validate_predictions(pred, metrics, expected$partition, f$coverage, 5L)
  recon_validate_checkpoint(cp, report, inputs)
  recon_assert(identical(cp$reconstructed_provenance, provenance), "Completion/provenance disagree.")
  recon_assert(identical(provenance$producer, "S3_v2_RECONSTRUCTED_r2"), "Unexpected producer.")
  profile <- recon_final_profile(repository)
  for (key in setdiff(names(profile), c("note", "evidence_reference"))) {
    recon_assert(identical(provenance$profile[[key]], profile[[key]]), paste("Profile mismatch:", key))
  }
  recon_assert(identical(unname(provenance$primary_md5), unname(tools::md5sum(primary))), "Primary-input MD5 differs from training provenance.")
  recon_assert(identical(provenance$train_ids, cp$final_train_ids) && identical(provenance$test_ids, cp$final_test_ids), "Provenance row IDs mismatch.")
  recon_assert(identical(provenance$weather, f$weather) && identical(provenance$environment, f$environment), "Provenance predictors mismatch.")
  recon_same_table(provenance$partition, expected$partition, "provenance partition")
  ids <- recon_partition_ids(inputs, expected$partition, 5L)
  matched <- c(f$weather, f$environment)
  derived <- rbind(recon_coverage(inputs,ids$train,f$coverage$label[1],5L),
    recon_coverage(inputs,recon_complete_ids(inputs,matched,ids$train),f$coverage$label[2],5L),
    recon_coverage(inputs,ids$test,f$coverage$label[3],5L),
    recon_coverage(inputs,recon_complete_ids(inputs,matched,ids$test),f$coverage$label[4],5L))
  recon_same_table(derived,f$coverage,"primary-derived coverage")
  fold5_validate_primary_rows(pred,inputs,cp$final_test_ids)
  output <- file.path(target,"checkpoint_verification.csv")
  recon_assert(!file.exists(output) && !file.exists(file.path(target,"reconstructed_provenance_summary.csv")),"Summary overwrite forbidden.")
  checks <- c("checkpoint_schema", "predictions_metrics", "primary_partition_and_matched_ids", "primary_observed_values", "coverage", "selected_predictors", "r2_provenance", "profile_compatibility_not_historical_identity", "historical_folds_primary_observations", "all_folds_exact_primary_matched_test_ids")
  write.csv(data.frame(check=checks,status="PASS"),output,row.names=FALSE,na="")
  # Whitelisted scalars/vectors only: no binary objects or raw input tables are exported.
  fields <- list(producer=provenance$producer, historical_v2_exact=FALSE,
    R_version=profile$R_version,Hmsc_version=profile$Hmsc_version,coda_version=profile$coda_version,
    rng_kind=paste(profile$rng_kind,collapse=" / "),samples=profile$mcmc$samples,
    transient=profile$mcmc$transient,thin=profile$mcmc$thin,chains=profile$mcmc$chains,
    parallel=profile$mcmc$parallel,max_prediction_draws=profile$max_prediction_draws,
    distribution=profile$distribution,random_level_units=profile$random_level_units,
    annual_index_standard_days=profile$annual_index_standard_days,
    train_rows=length(cp$final_train_ids),test_rows=length(cp$final_test_ids),
    weather=paste(f$weather,collapse="|"),environment=paste(f$environment,collapse="|"),
    primary_md5=unname(provenance$primary_md5), extraction_R_version=as.character(getRversion()))
  write.csv(data.frame(field=names(fields),value=vapply(fields,as.character,character(1))),file.path(target,"reconstructed_provenance_summary.csv"),row.names=FALSE)
  invisible(TRUE)
}
if (sys.nframe()==0L) {
  args <- commandArgs(TRUE); stopifnot(length(args)==3L)
  fold5_extract(args[1],args[2],args[3])
}
