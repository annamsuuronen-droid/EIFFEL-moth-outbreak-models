# Independent arithmetic verification after the local evidence commit arrives.
# New audit is temporary; committed scientific summaries are never overwritten.
repository<-normalizePath(getwd(),winslash="/")
source("R/validation/AUDIT_COMPLETE_OUTER_YEAR_CV_v1.R")
source("R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R")
output<-tempfile("cloud-reverified-outer-year-",tmpdir=Sys.getenv("RUNNER_TEMP",tempdir()))
args<-commandArgs(TRUE)
snapshot<-if (length(args)) args[1] else file.path(repository,"imported_fold5_completed_r2_v1")
full_cv_audit(repository,snapshot,output)
for(name in c("recomputed_fold_metrics.csv","pooled_five_fold_metrics.csv","equal_weight_fold_metrics.csv","fold_coverage.csv","STATUS.csv")) {
 saved<-read.csv(file.path(repository,"project_state/outer_year_cv_full_v1",name),check.names=FALSE)
 computed<-read.csv(file.path(output,name),check.names=FALSE)
 recon_same_table(saved,computed,paste("independent cloud recomputation",name))
}
unlink(output,recursive=TRUE)
cat("PASS: published five-fold summaries independently recomputed; no fitting or scientific outputs modified.\n")
