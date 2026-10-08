# Synthetic arithmetic and rejection checks only; no Hmsc or sampling.
repository <- normalizePath(getwd(),winslash="/")
source("R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R")
source("R/validation/AUDIT_COMPLETE_OUTER_YEAR_CV_v1.R")
source("R/validation/EXTRACT_COMPLETED_FOLD5_v1.R")
source("R/S4_PREDICTIVE_FULL_DATA_v2_CONFIG_PREFLIGHT.R")
for(path in c("R/validation/EXTRACT_COMPLETED_FOLD5_v1.R","R/validation/AUDIT_COMPLETE_OUTER_YEAR_CV_v1.R","R/S4_PREDICTIVE_FULL_DATA_v2_CONFIG_PREFLIGHT.R")) parse(path)
reject <- function(expr) stopifnot(inherits(try(force(expr),silent=TRUE),"try-error"))
expected <- recon_read_expected(repository)
f <- expected$folds[["5"]]; years <- expected$partition$block_value[expected$partition$fold==5]
n <- 222L; year <- rep(years,length.out=n); site <- sprintf("synthetic_%03d",seq_len(n))
parts <- list()
for(model in c("WEATHER_ONLY","WEATHER_PLUS_ENVIRONMENT")) for(sp in c("Epirrita autumnata","Operophtera brumata","Operophtera fagata")) {
 parts[[length(parts)+1L]] <- data.frame(evaluation="outer_year",model_type=model,sample_id=paste0(site,"__",year),site=site,year=year,species=sp,
 observed=rep(c(0,1,4),length.out=n),predicted_median=rep(c(0,2,3),length.out=n),presence_probability=rep(c(.1,.6,.9),length.out=n),outer_fold=5L,scheme="year")
}
pred <- do.call(rbind,parts); met <- recon_metrics(pred)
stopifnot(nrow(pred)==1332L,nrow(met)==6L,all(met$n==222),all(abs(met$RMSE-sqrt(2/3))<1e-12),all(met$O.AUC==1))
recon_validate_predictions(pred,met,expected$partition,f$coverage,5L)
bad<-pred;bad$year[1]<-1993;reject(recon_validate_predictions(bad,met,expected$partition,f$coverage,5L))
bad<-pred;bad$presence_probability[1]<-2;reject(recon_validate_predictions(bad,met,expected$partition,f$coverage,5L))
bad<-pred;bad$species[1]<-'unexpected';reject(recon_validate_predictions(bad,met,expected$partition,f$coverage,5L))
bad<-pred;bad$observed[nrow(bad)]<-999;reject(recon_validate_predictions(bad,met,expected$partition,f$coverage,5L))
bad<-met;bad$RMSE[1]<-999;reject(recon_validate_predictions(pred,bad,expected$partition,f$coverage,5L))
primary_ids<-unique(pred$sample_id)
primary_y<-matrix(rep(rep(c(0,1,4),length.out=n),3),nrow=n,dimnames=list(primary_ids,c("Epirrita autumnata","Operophtera brumata","Operophtera fagata")))
primary_fixture<-list(base_ids=primary_ids,Y_annual_all=primary_y)
fold5_validate_primary_rows(pred,primary_fixture,primary_ids)
reject(fold5_validate_primary_rows(pred,primary_fixture,primary_ids[-1]))
bad<-pred;bad$observed[1]<-999;reject(fold5_validate_primary_rows(bad,primary_fixture,primary_ids))
pool<-pred;pool$outer_fold<-0L;pooled<-recon_metrics(pool);stopifnot(all(pooled$RMSE==met$RMSE))
cfg<-s4_predictive_preflight(repository);stopifnot(!cfg$execution_enabled,length(cfg$weather)==5,length(cfg$environment)==3,cfg$matched_rows==1277)
work<-tempfile("eiffel-audit-");dir.create(work)
reject(full_cv_audit(repository,work,file.path(work,"absent")));stopifnot(!dir.exists(file.path(work,"absent")))
dir.create(file.path(work,"existing"));writeLines("sentinel",file.path(work,"existing/sentinel"))
reject(full_cv_audit(repository,work,file.path(work,"existing")));stopifnot(readLines(file.path(work,"existing/sentinel"))=="sentinel")
# End-to-end full audit: immutable real historical folds1-4 plus explicitly SYNTHETIC fold5.
# Outputs remain in temporary test directories; never publish synthetic scientific summaries.
snapshot<-file.path(work,"synthetic_capture");dir.create(snapshot)
relative<-"hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_05"
dir.create(file.path(snapshot,relative),recursive=TRUE)
write.csv2(pred,file.path(snapshot,relative,"outer_test_predictions.csv2"),row.names=FALSE)
write.csv2(met,file.path(snapshot,relative,"outer_test_metrics.csv2"),row.names=FALSE)
checks<-c("checkpoint_schema","predictions_metrics","primary_partition_and_matched_ids","primary_observed_values","coverage","selected_predictors","r2_provenance","profile_compatibility_not_historical_identity","historical_folds_primary_observations","all_folds_exact_primary_matched_test_ids")
write.csv(data.frame(check=checks,status="PASS"),file.path(snapshot,"checkpoint_verification.csv"),row.names=FALSE)
write.csv(data.frame(field=c("producer","historical_v2_exact","train_rows","test_rows","weather","environment"),
 value=c("S3_v2_RECONSTRUCTED_r2","FALSE","916","222",paste(f$weather,collapse="|"),paste(f$environment,collapse="|"))),file.path(snapshot,"reconstructed_provenance_summary.csv"),row.names=FALSE)
allow<-read.csv("project_state/outer_year_cv_recovery_v1/LOCAL_EVIDENCE_ALLOWLIST.csv",colClasses="character")
hash<-paste(rep("0",64),collapse="") # Fixture marker, not a claimed real capture digest.
sources<-data.frame(source_relative_path=allow$relative_path,action=allow$action,expected_size="UNKNOWN_BEFORE_CAPTURE",
 maximum_size=allow$max_bytes,actual_size=c(file.info(file.path(snapshot,relative,"outer_test_predictions.csv2"))$size,file.info(file.path(snapshot,relative,"outer_test_metrics.csv2"))$size,1,1,1),
 sha256=hash,destination_path=c(allow$relative_path[1:2],rep("",3)),status=c(rep("COPIED_SHA256_VERIFIED",2),rep("READ_ONLY_VERIFIED_NOT_COPIED",3)))
write.csv(sources,file.path(snapshot,"source_manifest.csv"),row.names=FALSE)
files<-list.files(snapshot,recursive=TRUE)
manifest<-data.frame(relative_path=files,size=file.info(file.path(snapshot,files))$size,sha256=hash,md5=unname(tools::md5sum(file.path(snapshot,files))))
write.csv(manifest,file.path(snapshot,"artifact_manifest.csv"),row.names=FALSE)
result<-full_cv_audit(repository,snapshot,file.path(work,"synthetic_full_audit"))
stopifnot(nrow(result)==6L,all(file.exists(file.path(work,"synthetic_full_audit",c("STATUS.csv","pooled_five_fold_metrics.csv","equal_weight_fold_metrics.csv")))))
status<-read.csv(file.path(work,"synthetic_full_audit/STATUS.csv"));stopifnot(status$observations_matched==1229L,status$observations_excluded==201L)
# Tampering after capture must fail without creating an output directory.
writeLines("corrupted",file.path(snapshot,"checkpoint_verification.csv"))
reject(full_cv_audit(repository,snapshot,file.path(work,"corruption_must_not_publish")))
stopifnot(!dir.exists(file.path(work,"corruption_must_not_publish")))
unlink(work,recursive=TRUE)
cat("PASS: synthetic metric, partition, schema, corruption, overwrite and fixed S4 configuration tests. No model execution.\n")
