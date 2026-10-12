# EIFFEL NDVI temporal contract v1. PHASE 2 PLANNING ONLY.
# No user data are read, no annual responses are merged, and no model is fitted.
# Dates are provisional Finnish study-life-stage windows to review from trap data.
suppressPackageStartupMessages(library(data.table))

ndvi_larval_windows <- data.table(
  species=c('Epirrita autumnata','Operophtera brumata','Operophtera fagata',
            'Lymantria monacha','Bupalus piniarius','Panolis flammea'),
  larva_start_md=c('05-01','04-01','04-01','05-01','07-01','05-01'),
  larva_end_md=c('06-30','06-30','06-30','07-31','10-31','07-31'),
  larva_year_offset=c(0L,0L,0L,0L,-1L,-1L),
  timing_review='PROVISIONAL_VERIFY_FINLAND_FLIGHT_AND_LARVAL_DATES'
)
ndvi_windows_for_adults <- function(adult) {
  stopifnot(is.data.table(adult),all(c('site','year','species') %in% names(adult)))
  x <- merge(copy(adult[,.(site,year,species)]),ndvi_larval_windows,
             by='species',all.x=TRUE,sort=FALSE)
  if(anyNA(x$larva_year_offset)) stop('Unknown species; NDVI larval timing not defined')
  x[,larval_year:=as.integer(year)+larva_year_offset]
  x[,larva_start:=as.Date(sprintf('%04d-%s',larval_year,larva_start_md))]
  x[,larva_end:=as.Date(sprintf('%04d-%s',larval_year,larva_end_md))]
  if(any(x$larva_end < x$larva_start)) stop('Invalid larval stage interval')
  x
}
ndvi_timing_audit <- function(adult,scenes) {
  stopifnot(is.data.table(scenes))
  required <- c('site','acquisition_date','available_date','buffer_m','ndvi')
  if(length(setdiff(required,names(scenes)))) stop('Scene-level NDVI metadata are required: site, acquisition_date, available_date, buffer_m, ndvi')
  x <- copy(scenes)
  x[,site:=as.character(site)]
  x[,acquisition_date:=as.Date(acquisition_date)]
  x[,available_date:=as.Date(available_date)]
  x[,buffer_m:=as.numeric(buffer_m)]
  x[,ndvi:=as.numeric(ndvi)]
  if(anyNA(x$site) || anyNA(x$buffer_m) || any(x$buffer_m<=0))
    stop('Site or buffer_m values are missing/invalid')
  if(anyDuplicated(x,by=c('site','acquisition_date','buffer_m')))
    stop('Duplicate NDVI acquisition date/site/buffer, audit sensor aggregation first')
  if(any(!is.na(x$ndvi) & (x$ndvi < -1 | x$ndvi>1)))
    stop('NDVI outside physical [-1,1] range')
  x <- merge(ndvi_windows_for_adults(adult),x,by='site',allow.cartesian=TRUE,sort=FALSE)
  # A non-dated annual NDVI summary is not a dated satellite acquisition;
  # it cannot be classified as pre/post caterpillar feeding.
  x[,ndvi_stage_class:=fcase(
    is.na(acquisition_date), 'UNRESOLVED_ACQUISITION_DATE',
    as.integer(format(acquisition_date,'%Y')) != larval_year, 'OUTSIDE_LARVAL_YEAR',
    acquisition_date < larva_start, 'PRE_LARVAL_HOST_BASELINE_CANDIDATE',
    acquisition_date <= larva_end, 'DURING_FEEDING_POSSIBLE_DEFOLIATION',
    default='POST_FEEDING_POSSIBLE_DEFOLIATION_OR_RECOVERY')]
  x[,ndvi_interpretation:=fcase(
    ndvi_stage_class == 'PRE_LARVAL_HOST_BASELINE_CANDIDATE', 'HOST_CONDITION_HYPOTHESIS_NOT_CAUSAL_PROOF',
    ndvi_stage_class %chin% c('DURING_FEEDING_POSSIBLE_DEFOLIATION',
                              'POST_FEEDING_POSSIBLE_DEFOLIATION_OR_RECOVERY'),
        'POSSIBLE_LARVAL_DAMAGE_RESPONSE_NOT_INDEPENDENT_HABITAT',
    default='UNRESOLVED_OR_DIFFERENT_YEAR')]
  x[,ndvi_timing_qa:='SCENE_LEVEL_AUDIT_ONLY_NO_AUTOMATIC_MODEL_FEATURE']
  issue <- data.table(issue=c('may01','jun01'),issue_md=c('05-01','06-01'),join_key=1L)
  x[,join_key:=1L]
  z <- merge(x,issue,by='join_key',allow.cartesian=TRUE,sort=FALSE)
  z[,join_key:=NULL]
  z[,forecast_issue_date:=as.Date(sprintf('%04d-%s',year,issue_md))]
  z[,temporal_availability_only:=as.integer(!is.na(acquisition_date) &
      !is.na(available_date) & !is.na(ndvi) &
      acquisition_date<forecast_issue_date &
      available_date<forecast_issue_date)]
  z[,forecast_feature_approved:=FALSE]
  # A scene observed during/after feeding may still be a *historical damage
  # proxy* available at issuance. It must never be labelled pre-feeding baseline.
  # Cloud/shadow/snow masking, sensor harmonization and training-only selection
  # are NOT checked here.
  z
}
