# Conditional, read-only configuration inspection. Never source the legacy S4 executor.
s4_predictive_configuration <- function(repository=getwd(), runtime="D:/EIFFEL_runtime") {
  source(file.path(repository,"R/S3_NESTED_OUTER_CV_PREDICTIVE_v2_FINAL_PROFILE.R"),local=TRUE)
  list(version="S4_PREDICTIVE_FULL_DATA_v2_CONFIG_ONLY", execution_enabled=FALSE,
    primary=file.path(runtime,"hmsc_outputs/HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1/HMSC_annual_three_species_weather_environment_buffers_results.RData"),
    selector=file.path(runtime,"hmsc_outputs/HMSC_ANNUAL_PREDICTIVE_ONE_BUFFER_MATCHED_ENVIRONMENT_SELECTION_v2/HMSC_annual_predictive_one_buffer_matched_results.rds"),
    weather=c("lag1_summer_mean_Tmin","lag1_summer_mean_Tmax","lag1_summer_max_Tmax","lag1_growing_sum_precipitation","lag1_autumn_mean_Tmax"),
    environment=c("NDVI_mean__b100m","NDVI_median__b100m","NDVI_max__b100m"),
    matched_rows=1277L,offset="annual effort exposure; standard 7 days",distribution="lognormal poisson",
    compatibility_profile=recon_final_profile(repository),
    cv_status=file.path(repository,"project_state/outer_year_cv_full_v1/STATUS.csv"),
    stage="INSPECT_EXISTING_FULL_DATA_FITS_AND_DIAGNOSTICS_BEFORE_ANY_REFIT",
    fit_decision="NOT_AUTHORIZED; existing full-data fits may already suffice; no adaptive sampler implemented")
}
s4_predictive_preflight <- function(repository=getwd(),runtime="D:/EIFFEL_runtime",check_local=FALSE) {
  cfg <- s4_predictive_configuration(repository,runtime)
  locked <- read.csv(file.path(repository,"project_state/audit_v1/LOCKED_PREDICTORS.csv"),colClasses="character")
  stopifnot(identical(cfg$weather,locked$variable[locked$branch=="predictive_weather"]),identical(cfg$environment,locked$variable[locked$branch=="predictive_environment"]))
  status <- if (file.exists(cfg$cv_status)) read.csv(cfg$cv_status,colClasses="character") else NULL
  cfg$cv_evidence_complete <- !is.null(status) && nrow(status)==1L && identical(status$status,"FULL_FIVE_FOLD_OUTER_YEAR_VALIDATED")
  if (check_local) {
    # Read only small selector/primary inputs, never large final models or conifer result directories.
    stopifnot(normalizePath(runtime,winslash="/",mustWork=TRUE)=="D:/EIFFEL_runtime")
    source(file.path(repository,"R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R"),local=TRUE)
    stopifnot(file.info(cfg$selector)$size>0,file.info(cfg$selector)$size<=262144,file.info(cfg$primary)$size<=4194304)
    selection <- readRDS(cfg$selector); inputs <- recon_load_inputs(cfg$primary)
    env <- selection$selected_environment_variables
    env <- if (is.data.frame(env)) as.character(env$model_variable) else as.character(env)
    stopifnot(identical(as.character(selection$locked_weather_variables),cfg$weather),identical(env,cfg$environment))
    variables <- c(cfg$weather,cfg$environment)
    ids <- recon_complete_ids(inputs,variables,inputs$base_ids)
    stopifnot(length(ids)==cfg$matched_rows,identical(as.character(selection$final_sample_ids),ids))
    x <- inputs$X_sample[match(ids,inputs$base_ids),variables,drop=FALSE]
    stopifnot(all(vapply(x,function(v) is.finite(sd(v)) && sd(v)>0,logical(1))))
    y <- inputs$Y_annual_all[ids,,drop=FALSE]
    stopifnot(all(!is.finite(y) | (y>=0 & abs(y-round(y))<1e-8)))
    cfg$local_input_checks <- "PASS; no predictor dropping or outcome rounding"
  }
  cfg
}
if (sys.nframe()==0L) {
  args <- commandArgs(TRUE)
  stopifnot(all(args %in% "--check-local"))
  print(s4_predictive_preflight(check_local="--check-local" %in% args))
  cat("CONFIGURATION ONLY: fitting disabled, no outputs or scientific results modified.\n")
}
