#!/usr/bin/env Rscript
# Synthetic regression only; no actual study data, Hmsc fits or existing outputs.
stopifnot(requireNamespace('data.table', quietly=TRUE))
library(data.table)
source('R/build_six_species_annual_v3.R', local=TRUE)
td <- tempfile('eiffel_synthetic_'); dir.create(td)
raw <- data.table(site=c('1001','1001','1001','1001'),
  year=c(2022L,2023L,2023L,2023L),KokMaara=c(3,4,5,2),
  PvmAlku=c('1.12.2022','1.2.2023','1.7.2023','1.7.2023'),
  PvmLoppu=c('8.12.2022','8.2.2023','8.7.2023','8.7.2023'),
  species=c('Operophtera brumata','Operophtera brumata','Lymantria monacha','Panolis flammea'),
  NimiRysapaikka='Synthetic',ETRS_TM35FIN_N=7000000,ETRS_TM35FIN_E=300000)
raw_path <- file.path(td,'raw.csv'); fwrite(raw,raw_path,sep=';')
b <- build_catches(raw_path)
stopifnot(b$duplicate_source_rows==0L,nrow(b$overlapping_events)==0L,
  length(unique(b$annual$species))==6L,
  !anyDuplicated(b$annual,by=c('site','year','species')),
  sum(b$annual$annual_count)==sum(raw$KokMaara),
  b$annual[year==2022 & species=='Operophtera brumata',annual_count]==7,
  b$annual[year==2023 & species=='Lymantria monacha',annual_count]==5,
  b$annual[year==2023 & species=='Panolis flammea',annual_count]==2,
  b$annual[year==2023 & species=='Bupalus piniarius',annual_count]==0,
  b$annual[year==2022 & species=='Operophtera brumata',effort_days]==14)
raw2 <- rbind(raw,raw[3]); raw2_path <- file.path(td,'duplicated.csv')
fwrite(raw2,raw2_path,sep=';')
b2 <- suppressWarnings(build_catches(raw2_path))
stopifnot(b2$duplicate_source_rows==1L,
  all(is.na(b2$annual$response_checked)),
  nrow(b2$removed_exact_duplicate_rows)==1L,
  b2$annual[year==2023 & species=='Lymantria monacha',annual_count]==5,
  sum(b2$annual$annual_count)==sum(raw$KokMaara))
dates <- seq(as.Date('2020-01-01'),as.Date('2023-12-31'),by='day')
w <- data.table(site='1001',DateN=as.character(dates),
  MeanDailyT=4,Tmin=-4,Tmax=12,SumDailyP=2,MeanSnow=1)
wpath <- file.path(td,'weather.txt');fwrite(w,wpath,sep=';')
w <- build_daily(wpath)
x <- weather_window(w,'1001',as.Date('2023-01-01'),as.Date('2023-04-30'))
cat('DEBUG precipitation and coverage: ', paste(names(x), as.character(x), sep='=', collapse='; '), '\n')
stopifnot(x['available']==1,x['n_expected']==120,
  x['sum_precipitation']==240,x['GDD5']==0)
w_bad <- copy(w); w_bad[date>='2023-01-01' & date<='2023-04-30',SumDailyP:=NA_real_]
xb <- weather_window(w_bad,'1001',as.Date('2023-01-01'),as.Date('2023-04-30'))
stopifnot(xb['available']==0,is.na(xb['sum_precipitation']))
y <- weather_features(w,b$annual)
w_future <- copy(w);w_future[date>='2023-05-01',MeanDailyT:=8]
y_future <- weather_features(w_future,b$annual)
cols <- grep('^(may01_|recent_winter_|lag1_annual_|lag2_annual_)',
  names(y$climate),value=TRUE)
stopifnot(identical(y$climate[year==2023,..cols],y_future$climate[year==2023,..cols]),
  y_future$climate[year==2023,jun01_mean_temperature] >
    y$climate[year==2023,jun01_mean_temperature])
base <- merge(b$annual,y$climate,by=c('site','year'),all.x=TRUE)
forecast <- base[,c('site','year','species',
  grep('^may01_',names(base),value=TRUE),
  grep('^(recent_winter_|lag1_annual_|lag2_annual_)',names(base),value=TRUE)),with=FALSE]
stopifnot(!any(c('annual_count','effort_days','annual_count_per_7d',
  'n_sampling_intervals') %in% names(forecast)))
env <- data.table(site=c('1001','1001','1001'),year=c(2023,2023,2023),
  buffer_m=c(100,100,200),species=c('Epirrita autumnata','Operophtera fagata','Epirrita autumnata'),
  sample_id=c('a','b','c'),count=c(888,777,666),NDVI_mean=c(.5,.5,.7),
  DTW_mean=c(.1,.1,.2),corine_temporally_filled=FALSE)
epath <- file.path(td,'environment.csv');fwrite(env,epath)
e <- read_environment(epath)
stopifnot(nrow(e$data)==2L,!anyDuplicated(e$data,by=c('site','year','buffer_m')),
  !any(c('count','species','sample_id') %in% names(e$data)),
  all(e$data$forecast_approval=='NOT_APPROVED_TEMPORAL_PROVENANCE_UNKNOWN'))
joined <- merge(base,e$data,by=c('site','year'),all.x=TRUE,allow.cartesian=TRUE)
stopifnot(!anyDuplicated(joined,by=c('site','year','species','buffer_m')))
conflicted <- copy(env);conflicted[2,NDVI_mean:=0.6]
fwrite(conflicted,epath)
stopifnot(inherits(try(read_environment(epath),silent=TRUE),'try-error'))
unlink(td,recursive=TRUE,force=TRUE)
cat('PASS: synthetic annual response, cutoff weather, environment join safety\n')
