#!/usr/bin/env Rscript
# EIFFEL: reuse locked, already-screened weather predictors for the old three
# moth species. This is a FAST source/schema/provenance audit, NEVER Hmsc fit.
# Historical lock sets are repository EVIDENCE, not recalculated selections.
suppressPackageStartupMessages(library(data.table))
repo <- normalizePath(file.path(getwd(),'..','..'),winslash='/',mustWork=TRUE)
root <- Sys.getenv('EIFFEL_DATA',unset='D:/EIFFEL/data')
outroot <- Sys.getenv('EIFFEL_BUILD_OUT',unset='D:/EIFFEL_runtime/annual_pipeline_v3')
id <- sprintf('locked_weather_audit_%s_%d',format(Sys.time(),'%Y%m%d_%H%M%S'),Sys.getpid())
output <- file.path(outroot,id)
dir.create(output,recursive=TRUE,showWarnings=FALSE)
locked_path <- file.path(repo,'project_state/audit_v1/LOCKED_PREDICTORS.csv')
evidence <- c(
 explanatory_and_S5_baseline=file.path(repo,
  'imported_local_evidence_v1/hmsc_outputs/HMSC_ANNUAL_PRIMARY_EXPLANATORY_LOGNORMAL_POISSON_v1/selected_weather_variables_final.txt'),
 predictive_weather=file.path(repo,
  'imported_local_evidence_v1/hmsc_outputs/HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1/selected_weather_variables_final.txt'))
if(!file.exists(locked_path)||any(!file.exists(evidence)))
  stop('Locked historical variable evidence missing; do NOT rerun selection automatically')
index <- fread(locked_path)
stopifnot(all(c('branch','variable','evidence','status') %in% names(index)),
          !anyDuplicated(index,by=c('branch','variable')))
data <- rbindlist(lapply(names(evidence),function(n) {
  x <- fread(evidence[[n]])
  if(!identical(names(x),'variable')) stop('Unexpected legacy selection format')
  if(anyDuplicated(x$variable)) stop('Duplicate historical predictor')
  x[,branch:=n]
  x
}))
data <- merge(data,index,by=c('branch','variable'),all.x=TRUE,sort=FALSE)
if(anyNA(data$status) || any(data$status!='VERIFIED_RECORDED_SELECTION_NOT_VALIDATION'))
  stop('Locked variables disagree with prior repository evidence manifest')
if(data[branch=='explanatory_and_S5_baseline',.N]!=13L ||
   data[branch=='predictive_weather',.N]!=5L)
  stop('Unexpected historical selection sizes: expected explanatory 13/predictive 5')
data[,model_context:=fifelse(branch=='predictive_weather',
    'HISTORICAL_YEAR_BLOCKED_PREDICTION_NOT_MAY_JUNE_VALIDATION',
    'EXPLANATORY_RETROSPECTIVE_NOT_ISSUE_TIME_PREDICTORS')]
data[,reuse_action:='RETAIN_PRESELECTED_VARIABLES_NO_NEW_SCREENING']
fwrite(data,file.path(output,'EXISTING_LOCKED_WEATHER_VARIABLES.csv'))

# Read only headers. Do not ingest large old data or 1.3GB environmental table,
# and never run models or retry S1/S2 selection here.
custom <- Sys.getenv('EIFFEL_HISTORICAL_WEATHER',unset='')
candidates <- if(nzchar(custom)) custom else c(
  file.path(root,'Epirrita_Operophtera_species_weather_greenup_current_lag1_lag2.txt'),
  file.path(root,'model_data_environment_nearly_constant_years_filled.csv'))
candidates <- unique(candidates)
headers <- lapply(candidates,function(p) {
  if(!file.exists(p)) return(character())
  names(fread(p,nrows=0L,showProgress=FALSE))
})
names(headers) <- candidates
inventory <- rbindlist(lapply(seq_along(candidates),function(i) {
  if(!length(headers[[i]])) return(data.table(
   source=candidates[i],branch=data$branch,variable=data$variable,
   file_present=FALSE,predictor_present=FALSE))
  data.table(source=candidates[i],branch=data$branch,variable=data$variable,
   file_present=TRUE,predictor_present=data$variable %chin% headers[[i]])
}))
inventory[,availability_status:=fifelse(!file_present,'SOURCE_NOT_FOUND',
  fifelse(predictor_present,'EXACT_COLUMN_PRESENT',
          'MISSING_EXACT_COLUMN_DO_NOT_SUBSTITUTE'))]
fwrite(inventory,file.path(output,'LOCKED_WEATHER_SOURCE_SCHEMA_AUDIT.csv'))

# New six-species build computes a DIFFERENT, narrower weather feature schema.
# Never equate similarly named current/annual values with the old definitions.
recent <- Sys.getenv('EIFFEL_AUDIT_BUILD_DIR',unset='')
if(nzchar(recent)) {
  p <- c(explanatory_and_S5_baseline=file.path(recent,
                 'annual_weather_stages_EXPLANATORY_CANDIDATES.csv.gz'),
         predictive_weather=file.path(recent,
                 'predictive_may01_FEATURES_ONLY_UNVALIDATED.csv.gz'))
  coverage <- rbindlist(lapply(names(p),function(b) {
    h <- if(file.exists(p[[b]])) names(fread(p[[b]],nrows=0L,
                                       showProgress=FALSE)) else character()
    x <- data[branch==b,.(branch,variable)]
    x[,build_file:=p[[b]]]
    x[,build_file_exists:=length(h)>0L]
    x[,exact_name_present:=variable %chin% h]
    x
  }))
  fwrite(coverage,file.path(output,'NEW_BUILD_EXACT_FEATURE_COMPARISON.csv'))
  cat('New-build exact-name coverage:',
      coverage[,sum(exact_name_present)],'/',nrow(coverage),'\n')
}
cat('Historical variable selections are LOCKED: explanatory=13, predictive=5.\n')
for(p in candidates) {
  z <- inventory[source==p]
  cat('Schema:',p,'file=',any(z$file_present),
      'exact selected columns=',sum(z$predictor_present),'/',nrow(z),'\n')
}
cat('Audit output:',normalizePath(output,winslash='/'),'\n')
cat('NO weather preselection, Hmsc fitting, CV or expensive data import performed.\n')
cat('WARNING: Historical explanatory SAME-YEAR variables can leak after 1 May/1 June.\n')
cat('WARNING: Historical fitted models/metrics need comparable response and effort provenance.\n')
