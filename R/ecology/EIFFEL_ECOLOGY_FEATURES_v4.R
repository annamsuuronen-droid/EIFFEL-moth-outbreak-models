# EIFFEL v4 ecological candidates. No fitted Hmsc models are changed.
# Requires data.table plus fmt(), stopf(), read_file(), require_cols().
ecology_species_registry <- data.table::data.table(
  species=c('Epirrita autumnata','Operophtera brumata','Operophtera fagata',
            'Lymantria monacha','Bupalus piniarius','Panolis flammea'),
  overwinter_stage=c('egg','egg','egg','egg','soil_pupa','soil_pupa'),
  host_group=c('birch_deciduous','broadleaf','birch_deciduous',
               'pine_spruce','pine','pine'),
  focal_cold_temperature_C=c(-37,NA_real_,NA_real_,-29.5,NA_real_,NA_real_),
  cold_threshold_interpretation=c(
    'SENSITIVITY_HYPOTHESIS_NOT_MORTALITY_LIMIT',
    'NO_SPECIES_THRESHOLD_VALIDATED','NO_SPECIES_THRESHOLD_VALIDATED',
    'EXPERIMENTAL_EGG_FREEZING_MEDIAN_NOT_MORTALITY_LIMIT',
    'AIR_TEMPERATURE_IS_NOT_SOIL_TEMPERATURE',
    'AIR_TEMPERATURE_IS_NOT_SOIL_TEMPERATURE'),
  host_priority=c(
    'birch_volume|lehti_mean|clc_broadleaved_forest_pct',
    'lehti_mean|birch_volume|clc_broadleaved_forest_pct',
    'birch_volume|lehti_mean|clc_broadleaved_forest_pct',
    'spruce_volume|pine_volume|havu_mean|clc_coniferous_forest_pct',
    'pine_volume|havu_mean|clc_coniferous_forest_pct|DTW_mean|soil_retention_mean',
    'pine_volume|havu_mean|DTW_mean|soil_retention_mean|OverwinteringSoilBufferIndex'),
  review_status='CANDIDATE_NOT_MODEL_APPROVED')

# Weather-only, NOT true emergence / host budburst / soil temperature.
ecology_first_run <- function(flag, dates, run_days=5L) {
  if(length(flag)<run_days || anyNA(flag)) return(NA_integer_)
  starts <- which(vapply(seq_len(length(flag)-run_days+1L),
    function(i) all(flag[i:(i+run_days-1L)]),logical(1)))
  if(!length(starts)) NA_integer_ else as.integer(format(dates[starts[1]],'%j'))
}
ecology_gdd_cross <- function(v,dates,base=5,threshold=50) {
  if(!length(v) || anyNA(v)) return(NA_integer_)
  hit <- which(cumsum(pmax(v-base,0))>=threshold)
  if(!length(hit)) NA_integer_ else as.integer(format(dates[hit[1]],'%j'))
}
ecology_weather_by_issue <- function(w, annual) {
  keys <- unique(annual[,.(site,year)])
  issues <- data.table::data.table(issue=c('may01','jun01','explanatory'),
                                    end_md=c('04-30','05-31','12-31'))
  ans <- vector('list',nrow(keys)*nrow(issues)); k <- 0L
  for(i in seq_len(nrow(keys))) {
    s <- keys$site[i]; yy <- keys$year[i]
    for(j in seq_len(nrow(issues))) {
      label <- issues$issue[j]; end <- fmt(yy,issues$end_md[j])
      start <- fmt(yy,'01-01'); expected <- seq.Date(start,end,by='day')
      obs <- w[site == s & date >= start & date <= end]
      data.table::setorder(obs,date)
      all_days <- nrow(obs)==length(expected) && all(obs$date==expected)
      complete_temp <- all_days && !anyNA(obs$MeanDailyT)
      complete_snow <- all_days && !anyNA(obs$MeanSnow)
      spring0 <- spring5 <- gdd50 <- gdd100 <- snowfree <- snow_last <- NA_integer_
      if(complete_temp) {
        spring_obs <- obs[date>=fmt(yy,'03-01')]
        spring0 <- ecology_first_run(spring_obs$MeanDailyT>0,spring_obs$date,5L)
        spring5 <- ecology_first_run(spring_obs$MeanDailyT>5,spring_obs$date,5L)
        gdd50 <- ecology_gdd_cross(obs$MeanDailyT,obs$date,5,50)
        gdd100 <- ecology_gdd_cross(obs$MeanDailyT,obs$date,5,100)
      }
      if(complete_snow) {
        snowdays <- which(obs$MeanSnow>0.5)
        if(length(snowdays)) {
          snow_last <- as.integer(format(obs$date[max(snowdays)],'%j'))
          spring_obs <- obs[date>=fmt(yy,'02-01')]
          snowfree <- ecology_first_run(spring_obs$MeanSnow<=0.5,
                                         spring_obs$date,7L)
        }
      }
      # Rain and API require complete dates; no partial sums passed as totals.
      rain <- rep(NA_real_,3L)
      for(nd in c(30L,90L)) {
        lo <- end-as.integer(nd-1L)
        part <- w[site == s & date >= lo & date <= end]
        if(nrow(part)==nd && !anyNA(part$SumDailyP) &&
           !anyDuplicated(part$date)) {
          data.table::setorder(part,date)
          if(nd==30L) rain[1] <- sum(part$SumDailyP)
          else {
            rain[2] <- sum(part$SumDailyP)
            age <- rev(seq_len(nd)-1L)
            rain[3] <- sum(part$SumDailyP*2^(-age/7))
          }
        }
      }
      k <- k+1L
      ans[[k]] <- data.table::data.table(
        site=s,year=yy,issue=label,
        data_complete_through_issue=as.integer(all_days),
        spring_start_0_doy=spring0,spring_start_5_doy=spring5,
        gdd5_50_crossing_doy=gdd50,gdd5_100_crossing_doy=gdd100,
        first_snowfree7_doy_sofar=snowfree,last_snow_day_doy_sofar=snow_last,
        rain30_complete_mm=rain[1],rain90_complete_mm=rain[2],
        api90_7d_half_life_mm=rain[3],
        phenology_interpretation='METEOROLOGICAL_PROXY_NOT_LARVAL_HATCH')
    }
  }
  data.table::rbindlist(ans,use.names=TRUE)
}
ecology_greenup <- function(path,keys) {
  out <- data.table::copy(keys)
  out[,':='(greenup_doy=NA_integer_,greenup_available_date=as.Date(NA),
             greenup_source_status='NO_ASOF_GREENUP_SOURCE')]
  if(!nzchar(path)) return(out)
  if(!file.exists(path)) stopf('Explicit Greenup source missing: %s',path)
  g <- read_file(path,if(grepl('\\.csv$',path,ignore.case=TRUE)) ',' else ';')
  require_cols(g,c('site','year','greenup_doy','available_date'),'As-of Greenup source')
  g[,site:=trimws(as.character(site))]
  g[,year:=as.integer(year)]
  g[,greenup_doy:=as.integer(greenup_doy)]
  g[,greenup_available_date:=as.Date(available_date)]
  if(anyNA(g[,.(site,year,greenup_doy,greenup_available_date)]))
    stopf('Greenup file has missing keys/dates; do not infer availability')
  if(any(g$greenup_doy<1L | g$greenup_doy>366L))
    stopf('Invalid Greenup day-of-year')
  if(anyDuplicated(g,by=c('site','year'))) stopf('Duplicate Greenup site/year')
  g[,greenup_source_status:='ASOF_PROVENANCE_NEEDS_SCIENTIFIC_REVIEW']
  merge(out[,.(site,year)],g[,.(site,year,greenup_doy,
    greenup_available_date,greenup_source_status)],
    by=c('site','year'),all.x=TRUE,sort=FALSE)
}
ecology_combine_asof <- function(e,g,issue) {
  requested_issue <- issue
  x <- e[issue == requested_issue]
  x <- merge(x,g,by=c('site','year'),all.x=TRUE,sort=FALSE)
  if(!nrow(x)) return(x)
  end <- if(issue=='may01') fmt(x$year,'04-30') else if(issue=='jun01')
    fmt(x$year,'05-31') else fmt(x$year,'12-31')
  gdate <- as.Date(paste0(x$year,'-01-01')) + x$greenup_doy-1L
  eligible <- !is.na(x$greenup_doy) & !is.na(x$greenup_available_date) &
    x$greenup_available_date<=end & gdate<=end
  x[!eligible,greenup_doy:=NA_integer_]
  x[,greenup_available_by_issue:=as.integer(eligible)]
  x[,greenup_minus_gdd5_50_proxy_days:=greenup_doy-gdd5_50_crossing_doy]
  x
}
