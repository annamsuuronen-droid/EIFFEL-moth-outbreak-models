#!/usr/bin/env Rscript
# Full phase-1 synthetic build. No study data, no environmental files, no Hmsc.
suppressPackageStartupMessages(library(data.table))
td <- tempfile('eiffel_frost_end_to_end_'); dir.create(td)
data_dir <- file.path(td,'data');dir.create(data_dir)
out_dir <- file.path(td,'out');dir.create(out_dir)
# Both ordinary 7-day events and positive/zero same-day catches.
# There are three observed events, each zero-filled ONLY across six species.
raw <- data.table(site='1001',year=2023L,
  KokMaara=c(2,1,5,0,1),
  PvmAlku=c('1.7.2023','1.7.2023',
            '12.7.2023','12.7.2023','13.7.2023'),
  PvmLoppu=c('8.7.2023','8.7.2023',
             '12.7.2023','12.7.2023','13.7.2023'),
  species=c('Bupalus piniarius','Panolis flammea',
            'Bupalus piniarius','Panolis flammea','Panolis flammea'))
fwrite(raw,file.path(data_dir,'Eiffel_1993_2024.csv'),sep=';')
days <- seq(as.Date('2021-01-01'),as.Date('2023-12-31'),by='day')
weather <- data.table(site='1001',DateN=as.character(days),
  MeanDailyT=4,SumDailyP=2,MeanSnow=1,Tmin=-4,Tmax=12)
fwrite(weather,file.path(data_dir,
  'Daily_weather_from_NC_needed_trap_years_and_previous_year.txt'),sep=';')
frost_path <- file.path(td,'cold_sum20_by_trap_year.csv')
fwrite(data.table(site='1001',year=2023L,n_days20=2,
  cold_sum20=-45,min_tmin=-24,mean_tmin_below20=-22.5,
  available_date='2023-04-12',winter_end_date='2023-03-31'),frost_path)
Sys.setenv(EIFFEL_DATA=data_dir,EIFFEL_BUILD_OUT=out_dir,
  EIFFEL_FROST_FILE=frost_path,
  EIFFEL_GREENUP_FILE='NO_GREENUP_INPUT_MUST_NOT_BE_READ.csv')
rExe <- file.path(R.home('bin'),'Rscript')
output <- suppressWarnings(system2(rExe,
  c('--vanilla','R/build_six_species_annual_v3.R','--build'),
  stdout=TRUE,stderr=TRUE))
status <- attr(output,'status')
if(!is.null(status) && status!=0L) {
  cat(paste(output,collapse='\n'),'\n')
  stop('Synthetic end-to-end weather+frost build failed')
}
folders <- list.dirs(out_dir,recursive=FALSE,full.names=TRUE)
stopifnot(length(folders)==1L)
o <- folders[1]
response <- fread(file.path(o,'annual_site_species_flight_year.csv'))
may <- as.data.table(read.csv(gzfile(file.path(o,'predictive_may01_FEATURES_ONLY_UNVALIDATED.csv.gz')),check.names=FALSE))
expl <- as.data.table(read.csv(gzfile(file.path(o,'annual_weather_stages_EXPLANATORY_CANDIDATES.csv.gz')),check.names=FALSE))
qa <- fread(file.path(o,'FROST_INPUT_QA.csv'))
scope <- fread(file.path(o,'PHASE_1_SCOPE.csv'))
interval_qa <- fread(file.path(o,'SAME_DAY_EVENTS_EFFORT_UNKNOWN.csv'))
stopifnot(nrow(interval_qa)==12L,
          all(is.na(interval_qa$interval_days)),
          all(is.na(interval_qa$count_per_7d)),
          sum(interval_qa$count)==6,
          any(interval_qa$count==0),
          interval_qa[species=='Panolis flammea' &
            start=='2023-07-12',explicit_zero_source_rows]==1L,
          interval_qa[species=='Panolis flammea' &
            start=='2023-07-12',zero_filled_from_sampled_event]==FALSE,
          interval_qa[species=='Epirrita autumnata' &
            start=='2023-07-12',zero_filled_from_sampled_event]==TRUE)
stopifnot(nrow(response)==6L,sum(response$annual_count)==9,
  response[species=='Bupalus piniarius',annual_count]==7,
  response[species=='Panolis flammea',annual_count]==2,
  all(is.na(response$effort_days)),
  all(is.na(response$annual_count_per_7d)),
  all(response$known_effort_days==7),
  all(response$n_unknown_effort_intervals==2L),
  response[species=='Panolis flammea',n_explicit_zero_source_rows]==1L,
  response[species=='Epirrita autumnata',n_zero_filled_from_sampled_events]==3L,
  all(response$effort_status=='UNKNOWN_DURATION_RETAIN_ANNUAL_COUNT'),
  nrow(may)==nrow(response),nrow(expl)==nrow(response),
  nrow(qa)==1L,qa$frost_source_rows==1L,
  scope$frostmodel_inputs==1L,scope$environment_inputs==0L,
  'frost_min' %in% names(may),'frost_min' %in% names(expl),
  !('frost_min_tmin' %in% names(may)),
  !('frost_min_tmin' %in% names(expl)),
  !any(c('NDVI_mean','annual_count','effort_days') %in% names(may)),
  may[species=='Bupalus piniarius',frost_min]==-24,
  may[species=='Panolis flammea',frost_cold_sum20]==-45,
  expl[species=='Bupalus piniarius',frost_cold_sum20]==-45,
  all(is.na(may[!(species %chin% c('Bupalus piniarius','Panolis flammea')),frost_min])))
stopifnot(!file.exists(file.path(o,'environment_by_site_year_buffer_REVIEW.csv.gz')))
Sys.setenv(EIFFEL_AUDIT_BUILD_DIR=o)
v <- suppressWarnings(system2(rExe,
  c('--vanilla','R/validation/VERIFY_BUILT_ANNUAL_v1.R'),
  stdout=TRUE,stderr=TRUE))
if(!is.null(attr(v,'status')) && attr(v,'status')!=0L) {
  cat(v,sep='\n')
  stop('Local-source QA verification failed on completed synthetic build')
}
checks <- fread(file.path(o,'LOCAL_VALIDATION_REPORT.csv'))
stopifnot(nrow(checks)>=10L, !any(checks$status=='FAIL'),
          checks[check=='annual_counts_reconcile_after_exact_dedup',status]=='PASS',
          checks[check=='apparent_overlaps_audit_only',status]=='PASS',
          file.exists(file.path(o,'LOCAL_VALIDATION_REPORT.md')))
unlink(td,recursive=TRUE)
cat('PASS: full synthetic weather/frost phase-1 build; no environment reads, no Hmsc\n')
