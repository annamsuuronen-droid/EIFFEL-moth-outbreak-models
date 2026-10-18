#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(data.table))
source('R/environment/NDVI_TEMPORAL_POLICY_v1.R',local=TRUE)
adult <- data.table(site='A',year=2023L,
  species=c('Epirrita autumnata','Operophtera brumata','Operophtera fagata',
    'Lymantria monacha','Bupalus piniarius','Panolis flammea'))
w <- ndvi_windows_for_adults(adult)
stopifnot(nrow(w)==6L, all(w[species %chin% c('Bupalus piniarius','Panolis flammea'),larval_year]==2022L),
  all(w[!(species %chin% c('Bupalus piniarius','Panolis flammea')),larval_year]==2023L))
# Dates are intentionally synthetic: sample NDVI before, during and after larvae.
ndvi_scenes <- data.table(site='A',
  acquisition_date=as.Date(c('2022-06-15','2022-08-15','2022-11-01',
                             '2023-04-10','2023-07-15')),
  available_date=as.Date(c('2022-06-20','2022-08-18','2022-11-05',
                            '2023-04-12','2023-07-20')),
  buffer_m=100,ndvi=c(.5,.4,.3,.6,.2))
audit <- ndvi_timing_audit(adult,ndvi_scenes)
stopifnot(nrow(audit)==6L*nrow(ndvi_scenes)*2L)
b <- audit[species=='Bupalus piniarius' & issue=='may01']
stopifnot(b[acquisition_date==as.Date('2022-06-15'),ndvi_stage_class]=='PRE_LARVAL_HOST_BASELINE_CANDIDATE',
          b[acquisition_date==as.Date('2022-08-15'),ndvi_stage_class]=='DURING_FEEDING_POSSIBLE_DEFOLIATION',
          b[acquisition_date==as.Date('2022-11-01'),ndvi_stage_class]=='POST_FEEDING_POSSIBLE_DEFOLIATION_OR_RECOVERY',
          b[acquisition_date==as.Date('2022-11-01'),temporal_availability_only]==1L)
p <- audit[species=='Panolis flammea' & issue=='may01']
stopifnot(p[acquisition_date==as.Date('2022-06-15'),ndvi_stage_class]=='DURING_FEEDING_POSSIBLE_DEFOLIATION')
ea <- audit[species=='Epirrita autumnata' & issue=='may01']
stopifnot(ea[acquisition_date==as.Date('2023-07-15'),temporal_availability_only]==0L,
          ea[acquisition_date==as.Date('2023-07-15'),ndvi_stage_class]=='POST_FEEDING_POSSIBLE_DEFOLIATION_OR_RECOVERY',
          all(audit$forecast_feature_approved==FALSE))
# Annual NDVI statistics alone cannot establish acquisition/release timing.
annual_ndvi <- data.table(site='A',year=2022L,buffer_m=100,NDVI_mean=.4)
stopifnot(inherits(try(ndvi_timing_audit(adult,annual_ndvi),silent=TRUE),'try-error'))
no_release <- copy(ndvi_scenes); no_release[,available_date:=as.Date(NA)]
stopifnot(all(ndvi_timing_audit(adult,no_release)$temporal_availability_only==0L))
cat('PASS: NDVI cohort alignment and defoliation/release-date safety; no model fit\n')
