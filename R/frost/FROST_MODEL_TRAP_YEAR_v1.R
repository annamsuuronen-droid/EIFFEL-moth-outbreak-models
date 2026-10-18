# Frost-model source contract: cold_sum20_by_trap_year.csv
# Based on original 2.2_EautumnataOperophteraAllEnvironmentAndWeeklySpeciesData.R.
# No interpolation, no buffer joins, no substitution of daily AIR Tmin.
# Soil-pupa taxa only: Bupalus piniarius and Panolis flammea.
suppressPackageStartupMessages(library(data.table))
frost_species <- c('Bupalus piniarius','Panolis flammea')
frost_vars <- c('frost_n_days20','frost_cold_sum20','frost_min_tmin',
                'frost_mean_tmin_below20')
frost_stop <- function(...) stop(sprintf(...),call.=FALSE)
frost_source_path <- function(data_root,explicit='') {
  if(nzchar(explicit)) {
    if(!file.exists(explicit)) frost_stop('Requested frost-model file missing: %s',explicit)
    return(normalizePath(explicit,winslash='/',mustWork=TRUE))
  }
  candidates <- c(
    file.path(data_root,'inputs_frost','cold_sum20_by_trap_year.csv'),
    file.path(data_root,'cold_sum20_by_trap_year.csv'),
    'D:/EIFFEL_runtime/EIFFELgis/buffer_outputs/frostmodel/cold_sum20_by_trap_year.csv'
  )
  found <- unique(candidates[file.exists(candidates)])
  if(length(found)>1L) frost_stop(
    'Several frost candidates found: %s. Use EIFFEL_FROST_FILE to select one',
    paste(found,collapse='; '))
  if(length(found)==1L) return(normalizePath(found,winslash='/',mustWork=TRUE))
  ''
}
frost_read_trap_year <- function(path) {
  if(!nzchar(path)) return(NULL)
  x <- fread(path,sep=',',na.strings=c('','NA','NaN'),showProgress=FALSE)
  needed <- c('site','year','n_days20','cold_sum20','min_tmin','mean_tmin_below20')
  missing <- setdiff(needed,names(x))
  if(length(missing)) frost_stop('Frost file missing columns: %s',
                                paste(missing,collapse=', '))
  # SOURCE year = adult/flight year. Do not relabel it from the trap interval.
  x[,site:=trimws(as.character(site))]
  x[,year:=suppressWarnings(as.integer(year))]
  if(anyNA(x$site)||any(!nzchar(x$site))||anyNA(x$year))
    frost_stop('Frost site/year keys missing')
  if(anyDuplicated(x,by=c('site','year')))
    frost_stop('Duplicate frost site/year. Do not duplicate annual moth counts')
  for(k in needed[3:6]) set(x,j=k,value=suppressWarnings(as.numeric(x[[k]])))
  numeric_cols <- needed[3:6]
  # NA is allowed for winters with no qualifying days or missing source
  # fields; Inf / -Inf / NaN are not.
  z <- unlist(x[,..numeric_cols],use.names=FALSE)
  if(any(is.infinite(z)|is.nan(z)))
    frost_stop('Non-finite frost values')
  if(any(!is.na(x$n_days20) & (x$n_days20<0|x$n_days20!=floor(x$n_days20))))
    frost_stop('Invalid frost n_days20')
  # Accepted earlier definition: count Tmin <= -20 C, sum the ACTUAL
  # (negative) daily Tmin values on qualifying days.
  # NOT sum(abs(Tmin+20)) and NOT excess below the threshold.
  present <- !is.na(x$n_days20) & !is.na(x$cold_sum20)
  if(any(present & x$n_days20==0 & abs(x$cold_sum20)>1e-6))
    frost_stop('Frost cold_sum20 must equal zero when n_days20=0')
  if(any(present & x$n_days20>0 & x$cold_sum20 > -20*x$n_days20+1e-5))
    frost_stop('Frost cold_sum20 is not the negative sum of actual Tmin below -20')
  both <- present & x$n_days20>0 & !is.na(x$mean_tmin_below20)
  if(any(both & abs(x$cold_sum20/x$n_days20-x$mean_tmin_below20)>0.1))
    frost_stop('Frost conditional mean disagrees with cumulative sum and days')
  if(any(!is.na(x$min_tmin) & !is.na(x$mean_tmin_below20) &
         x$min_tmin>x$mean_tmin_below20+1e-5))
    frost_stop('Frost minimum is warmer than conditional Tmin mean')
  if('available_date' %in% names(x)) {
    x[,frost_available_date:=as.Date(available_date)]
    if(any(!is.na(x$available_date) & is.na(x$frost_available_date)))
      frost_stop('Invalid frost available_date')
  } else x[,frost_available_date:=as.Date(NA)]
  if('winter_end_date' %in% names(x)) {
    x[,frost_winter_end_date:=as.Date(winter_end_date)]
    if(any(!is.na(x$winter_end_date) & is.na(x$frost_winter_end_date)))
      frost_stop('Invalid frost winter_end_date')
  } else x[,frost_winter_end_date:=as.Date(NA)]
  # Old source has only site/year and four annual aggregates: actual source
  # availability and season boundaries are UNKNOWN until independently audited.
  setnames(x,needed[3:6],frost_vars)
  # Requested short label. Exactly identical to legacy frost_min_tmin:
  # NEVER select both aliases as separate predictors in one model.
  x[,frost_min:=frost_min_tmin]
  x[,frost_source_status:='ORIGINAL_FROSTMODEL_NOT_INTERPOLATED']
  x[,c('site','year',frost_vars,'frost_min','frost_available_date',
        'frost_winter_end_date','frost_source_status'),with=FALSE]
}
frost_for_annual <- function(annual,source=NULL,issue=NULL) {
  required <- c('site','year','species')
  if(length(setdiff(required,names(annual)))) frost_stop('Annual keys missing')
  if(anyDuplicated(annual,by=required)) frost_stop('Duplicate annual keys')
  x <- copy(annual[,..required])
  x[,site:=trimws(as.character(site))]
  x[,year:=as.integer(year)]
  x[,frost_relevant:=species %chin% frost_species]
  if(is.null(source)) {
    for(v in frost_vars) x[,(v):=NA_real_]
    x[,frost_min:=NA_real_]
    x[,frost_available_date:=as.Date(NA)]
    x[,frost_winter_end_date:=as.Date(NA)]
    x[,frost_source_status:='NOT_LOCATED_NO_FROST_VALUES_FABRICATED']
  } else {
    x <- merge(x,source,by=c('site','year'),all.x=TRUE,sort=FALSE)
    stopifnot(nrow(x)==nrow(annual))
    x[is.na(frost_source_status),frost_source_status:='NO_SITE_YEAR_FROST_COVERAGE']
  }
  for(v in frost_vars) x[frost_relevant == FALSE,(v):=NA_real_]
  x[frost_relevant == FALSE,frost_min:=NA_real_]
  x[frost_relevant == FALSE,frost_source_status:='NOT_RELEVANT_EGG_OVERWINTERING']
  # Historical data are useful for explanatory modelling; however a source
  # produced retrospectively must NOT leak into 1 May/1 June hindcasts.
  if(!is.null(issue)) {
    cutoff <- if(issue=='may01') '05-01' else if(issue=='jun01') '06-01' else
      frost_stop('Unknown frost forecast issue: %s',issue)
    issue_date <- as.Date(sprintf('%04d-%s',x$year,cutoff))
    # winter bounds explicitly provided for provenance; old no-end-date
    # source still cannot be proven to represent the completed prior winter.
    valid_asof <- x$frost_relevant & !is.na(x$frost_available_date) &
      !is.na(x$frost_winter_end_date) &
      x$frost_winter_end_date < issue_date &
      x$frost_available_date < issue_date
    x[,frost_asof_available:=as.integer(valid_asof)]
    for(v in frost_vars) x[!valid_asof,(v):=NA_real_]
    x[!valid_asof,frost_min:=NA_real_]
    x[frost_relevant & !valid_asof,
      frost_source_status:='NOT_FORECAST_CLEARED_MISSING_RELEASE_OR_SEASON_PROOF']
  }
  stopifnot(!anyDuplicated(x,by=required))
  x
}
frost_keep_features <- function(z,include_audit=FALSE) {
  # Avoid perfect collinearity in predictor tables: select frost_min and
  # keep frost_min_tmin solely in legacy/audit outputs.
  cols <- c('site','year','species',setdiff(frost_vars,'frost_min_tmin'),'frost_min')
  if(include_audit) cols <- c(cols,'frost_asof_available','frost_source_status')
  z[,..cols]
}
