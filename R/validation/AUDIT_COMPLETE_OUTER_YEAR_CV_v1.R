# Arithmetic audit only; imports no Hmsc package and executes no scientific model.
full_cv_audit <- function(repository, snapshot, output=file.path(repository,"project_state/outer_year_cv_full_v1")) {
  source(file.path(repository,"R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R"),local=TRUE)
  recon_assert(!file.exists(output),"Audit version already exists; replacement forbidden.")
  manifest <- read.csv(file.path(snapshot,"artifact_manifest.csv"),colClasses="character",check.names=FALSE)
  relative <- "hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_05"
  required <- c(paste0(relative,c("/outer_test_predictions.csv2","/outer_test_metrics.csv2")),"checkpoint_verification.csv","reconstructed_provenance_summary.csv","source_manifest.csv")
  recon_assert(identical(sort(manifest$relative_path),sort(required)) && !anyDuplicated(manifest$relative_path),"Unexpected evidence artifacts.")
  for (i in seq_len(nrow(manifest))) {
    recon_assert(grepl("^[A-Za-z0-9_./-]+$",manifest$relative_path[i]) && !any(strsplit(manifest$relative_path[i],"/",fixed=TRUE)[[1]] %in% c(".","..","")),"Artifact path traversal.")
    path <- file.path(snapshot,manifest$relative_path[i])
    recon_assert(file.exists(path) && file.info(path)$size==as.numeric(manifest$size[i]) && unname(tools::md5sum(path))==manifest$md5[i],"Artifact bytes changed since SHA256 capture.")
  }
  # SHA256 is independently verified in PowerShell at capture; MD5 here detects later edits without a package dependency.
  checks <- read.csv(file.path(snapshot,"checkpoint_verification.csv"),colClasses="character")
  expected_checks <- c("checkpoint_schema","predictions_metrics","primary_partition_and_matched_ids","primary_observed_values","coverage","selected_predictors","r2_provenance","profile_compatibility_not_historical_identity")
  recon_assert(identical(checks$check,expected_checks) && all(checks$status=="PASS"),"Local primary/checkpoint checks incomplete.")
  sources <- read.csv(file.path(snapshot,"source_manifest.csv"),colClasses="character")
  allow <- read.csv(file.path(repository,"project_state/outer_year_cv_recovery_v1/LOCAL_EVIDENCE_ALLOWLIST.csv"),colClasses="character")
  recon_assert(identical(sources$source_relative_path,allow$relative_path) && identical(sources$action,allow$action) && all(grepl("^[a-f0-9]{64}$",sources$sha256)) && all(as.numeric(sources$actual_size)>0 & as.numeric(sources$actual_size)<=as.numeric(allow$max_bytes)),"Source manifest mismatch.")
  recon_assert(all(grepl("^[a-f0-9]{64}$",manifest$sha256)),"Malformed artifact SHA256.")
  for (i in 1:2) {
    a <- manifest[match(sources$source_relative_path[i],manifest$relative_path),,drop=FALSE]
    recon_assert(a$sha256==sources$sha256[i] && a$size==sources$actual_size[i],"Copied-source/artifact manifests disagree.")
  }
  recon_assert(identical(sources$status,c(rep("COPIED_SHA256_VERIFIED",2),rep("READ_ONLY_VERIFIED_NOT_COPIED",3))),"Incomplete capture statuses.")
  provenance <- read.csv(file.path(snapshot,"reconstructed_provenance_summary.csv"),colClasses="character")
  value <- function(key) { z <- provenance$value[provenance$field==key]; recon_assert(length(z)==1L,paste("Missing/duplicate provenance",key)); z }
  recon_assert(value("producer")=="S3_v2_RECONSTRUCTED_r2" && value("historical_v2_exact")=="FALSE" && value("train_rows")=="916" && value("test_rows")=="222","Unexpected reconstruction provenance.")
  expected <- recon_read_expected(repository)
  recon_assert(value("weather")==paste(expected$folds[["5"]]$weather,collapse="|") && value("environment")==paste(expected$folds[["5"]]$environment,collapse="|"),"Selected variables mismatch.")
  historical <- file.path(repository,"imported_local/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2")
  plan <- recon_inspect(historical,repository,evidence_only=TRUE)
  predictions <- list(); metrics <- list(); coverage <- list()
  for (fold in 1:5) {
    dir <- if (fold==5) file.path(snapshot,relative) else file.path(historical,"outer_year",sprintf("fold_%02d",fold))
    pred <- recon_table(file.path(dir,"outer_test_predictions.csv2")); met <- recon_table(file.path(dir,"outer_test_metrics.csv2"))
    cov <- expected$folds[[as.character(fold)]]$coverage
    recon_validate_predictions(pred,met,expected$partition,cov,fold)
    origin <- if (fold==5) "RECONSTRUCTED_COMPATIBILITY_R2" else "HISTORICAL_V2"
    pred$producer_class <- origin
    rec <- recon_metrics(pred); rec$producer_class <- origin
    predictions[[fold]] <- pred; metrics[[fold]] <- rec; coverage[[fold]] <- cov
  }
  all_pred <- do.call(rbind,predictions)
  keys <- paste(all_pred$model_type,all_pred$species,all_pred$sample_id)
  recon_assert(!anyDuplicated(keys),"Repeated held-out IDs across outer folds.")
  pooled_input <- all_pred; pooled_input$outer_fold <- 0L
  pooled <- recon_metrics(pooled_input); pooled$outer_fold <- NULL
  pooled$aggregation <- "POOLED_HELD_OUT_ROWS_FIVE_FOLDS"
  per_fold <- do.call(rbind,metrics)
  numeric_metrics <- c("RMSE","SR2","O.RMSE","O.AUC","O.TjurR2","C.RMSE","C.SR2")
  # n is also reproduced by recon_validate_predictions; it is a count, not averaged here.
  equal_fold <- do.call(rbind,lapply(split(per_fold,paste(per_fold$model_type,per_fold$species)),function(z) {
    data.frame(model_type=z$model_type[1],species=z$species[1],metric=numeric_metrics,
      mean=vapply(z[numeric_metrics],function(v) mean(v,na.rm=FALSE),numeric(1)),
      sd=vapply(z[numeric_metrics],function(v) sd(v,na.rm=FALSE),numeric(1)),aggregation="EQUAL_FOLD_WEIGHT")
  }))
  cov <- do.call(rbind,coverage)
  n_all <- sum(cov$n_site_years[cov$label=="outer_test_all"])
  n_matched <- sum(cov$n_site_years[cov$label=="outer_test_final_complete"])
  recon_assert(n_all==1430L && n_matched==1229L && nrow(all_pred)==7374L,"Full-CV expected coverage mismatch.")
  # Create output only after every validation passes; a partial version is never automatically reused.
  recon_assert(dir.create(output,recursive=FALSE),"Cannot atomically create fresh audit directory.")
  write.csv(per_fold,file.path(output,"recomputed_fold_metrics.csv"),row.names=FALSE)
  write.csv(pooled,file.path(output,"pooled_five_fold_metrics.csv"),row.names=FALSE)
  write.csv(equal_fold,file.path(output,"equal_weight_fold_metrics.csv"),row.names=FALSE)
  write.csv(cov,file.path(output,"fold_coverage.csv"),row.names=FALSE)
  write.csv(data.frame(status="FULL_FIVE_FOLD_OUTER_YEAR_VALIDATED",observations_total=n_all,
    observations_matched=n_matched,observations_excluded=n_all-n_matched,
    included_fraction=n_matched/n_all,historical_folds="1|2|3|4",reconstructed_fold="5",
    reconstructed_producer="S3_v2_RECONSTRUCTED_r2",historical_bitwise_identity=FALSE,
    site_cv_executed=FALSE,outer_test_tuning=FALSE),file.path(output,"STATUS.csv"),row.names=FALSE)
  file.copy(file.path(snapshot,"artifact_manifest.csv"),file.path(output,"INPUT_ARTIFACT_MANIFEST.csv"),overwrite=FALSE)
  writeLines(c("# Full five-fold outer-year validation", "", "Historical folds 1–4 and reconstructed-compatibility r2 fold 5; no bitwise identity claim.",
    "Pooled held-out metrics and equal-fold means are separate estimands. Both models use the same matched observations.",
    "1229/1430 rows evaluated; 201 excluded by fold-specific matched predictor availability.",
    "Shuffled held-out years within the sampled network do not validate new sites or chronological advance forecasts.",
    "The original scientific outputs, folds, selections and thresholds were unchanged."),file.path(output,"README.md"))
  invisible(pooled)
}
if (sys.nframe()==0L) { args<-commandArgs(TRUE); stopifnot(length(args)==2L);full_cv_audit(args[1],args[2]) }
