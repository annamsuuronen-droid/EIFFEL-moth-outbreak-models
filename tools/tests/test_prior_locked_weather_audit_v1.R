#!/usr/bin/env Rscript
# No Hmsc, no large data. Test locked historical selections against fake header.
suppressPackageStartupMessages(library(data.table))
repo <- getwd()
td <- tempfile('locked_weather_');dir.create(td)
data_dir <- file.path(td,'data');dir.create(data_dir)
out <- file.path(td,'out');dir.create(out)
historical <- file.path(td,'archive.csv')
fwrite(data.table(site='1001',year=2023L,
 lag1_summer_mean_Tmin=1,lag1_summer_mean_Tmax=3,
 lag1_summer_max_Tmax=5,lag1_growing_sum_precipitation=10,
 lag1_autumn_mean_Tmax=2),historical)
Sys.setenv(EIFFEL_DATA=data_dir,EIFFEL_BUILD_OUT=out,
           EIFFEL_HISTORICAL_WEATHER=historical)
rExe <- file.path(R.home('bin'),'Rscript')
out_text <- suppressWarnings(system2(rExe,
  c('--vanilla','R/validation/AUDIT_REUSE_LOCKED_WEATHER_v1.R','--inspect'),
  stdout=TRUE,stderr=TRUE))
if(!is.null(attr(out_text,'status')) && attr(out_text,'status')!=0L) {
 cat(out_text,sep='\n');stop('Historical lock audit failed')
}
folders <- list.dirs(out,recursive=FALSE,full.names=TRUE)
stopifnot(length(folders)==1L)
locked <- fread(file.path(folders[1],'EXISTING_LOCKED_WEATHER_VARIABLES.csv'))
audit <- fread(file.path(folders[1],'LOCKED_WEATHER_SOURCE_SCHEMA_AUDIT.csv'))
stopifnot(nrow(locked)==18L,
 locked[branch=='predictive_weather',.N]==5L,
 locked[branch=='explanatory_and_S5_baseline',.N]==13L,
 nrow(audit)==18L,sum(audit$predictor_present)==5L,
 all(audit[branch=='predictive_weather',availability_status]=='EXACT_COLUMN_PRESENT'),
 all(audit[branch=='explanatory_and_S5_baseline',
           availability_status]=='MISSING_EXACT_COLUMN_DO_NOT_SUBSTITUTE'),
 all(locked$reuse_action=='RETAIN_PRESELECTED_VARIABLES_NO_NEW_SCREENING'),
 !file.exists(file.path(folders[1],'HMSC_model.rds')))
unlink(td,recursive=TRUE)
cat('PASS: prior 13+5 locked variable evidence and read-only schema audit; no fitting\n')
