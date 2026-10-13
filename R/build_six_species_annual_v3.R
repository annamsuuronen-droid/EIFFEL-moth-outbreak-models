#!/usr/bin/env Rscript
# EIFFEL v3/v4: phase 1 WEATHER ONLY; no environment/Greenup reads or Hmsc fits.
# IMPORTANT: no Hmsc is fitted. Ecological stage windows are PROVISIONAL.
# Dependencies: data.table (>=1.14). Outputs are new timestamped directories only.
suppressPackageStartupMessages(library(data.table))

cfg <- list(
  root = Sys.getenv('EIFFEL_DATA', 'D:/EIFFEL/data'),
  out_root = Sys.getenv('EIFFEL_BUILD_OUT', 'D:/EIFFEL_runtime/annual_pipeline_v3'),
  min_weather_coverage = 0.95,
  exclude_site_152 = TRUE,
  species = c('Epirrita autumnata', 'Operophtera brumata', 'Operophtera fagata',
              'Lymantria monacha', 'Bupalus piniarius', 'Panolis flammea'),
  winter_flyers = c('Operophtera brumata', 'Operophtera fagata')
)
stopf <- function(...) stop(sprintf(...), call. = FALSE)
require_cols <- function(x, nm, label) {
  missing <- setdiff(nm, names(x))
  if (length(missing)) stopf('%s missing columns: %s', label, paste(missing, collapse=', '))
}
parse_dates <- function(x) {
  x <- trimws(as.character(x))
  z <- as.Date(x, format='%d.%m.%Y')
  i <- is.na(z) & !is.na(x)
  z[i] <- as.Date(x[i], format='%Y-%m-%d')
  z
}
canonical_species <- function(x) {
  x <- gsub(' +', ' ', gsub('_',' ', trimws(x)))
  x[x == 'Bupalus piniaria'] <- 'Bupalus piniarius'
  x
}
fmt <- function(year, mmdd) as.Date(sprintf('%04d-%s', as.integer(year), mmdd))
read_file <- function(path, sep, header_only=FALSE, select=NULL) {
  if (!file.exists(path)) stopf('Source file not found: %s',path)
  fread(path, sep=sep, nrows=if(header_only) 0L else -1L,
        select=select, na.strings=c('', 'NA', 'NaN'), encoding='UTF-8', showProgress=FALSE)
}
# Larva of pine moths is PREVIOUS season for current-year adult abundance.
# Fixed windows are testable hypotheses, not exact emergence dates.
stage_windows <- data.table::data.table(
  species = c('Epirrita autumnata','Epirrita autumnata','Epirrita autumnata',
              'Operophtera brumata','Operophtera brumata','Operophtera brumata',
              'Operophtera fagata','Operophtera fagata','Operophtera fagata',
              'Lymantria monacha','Lymantria monacha','Lymantria monacha','Lymantria monacha',
              'Bupalus piniarius','Bupalus piniarius','Bupalus piniarius',
              'Panolis flammea','Panolis flammea','Panolis flammea'),
  stage = c('egg_winter','larva','adult','egg_winter','larva','adult',
            'egg_winter','larva','adult','egg_winter','larva','pupa','adult',
            'pupa_winter','previous_larva','adult','pupa_winter','previous_larva','adult'),
  start_md = c('10-01','05-01','08-01','11-01','04-01','10-01','11-01','04-01','10-01',
               '09-01','05-01','07-01','07-01','10-01','07-01','05-01','09-01','05-01','04-01'),
  end_md = c('03-31','06-30','10-31','03-31','06-30','12-31','03-31','06-30','12-31',
             '03-31','07-31','08-31','09-30','04-30','10-31','07-31','03-31','07-31','06-30'),
  start_shift = c(-1,0,0,-1,0,0,-1,0,0,-1,0,0,0,-1,-1,0,-1,-1,0),
  end_shift = c(0,0,0,0,0,0,0,0,0,0,0,0,0,0,-1,0,0,-1,0))
stage_windows[, review_status := 'PROVISIONAL_REQUIRES_ECOLOGICAL_REVIEW']

# The audit preserves original dates; it never guesses, clamps, or drops a
# problematic trap interval. Output stays on the local D: runtime filesystem.
audit_trap_intervals <- function(path, output_dir=NULL) {
  raw <- read_file(path,';')
  require_cols(raw,c('site','year','KokMaara','PvmAlku','PvmLoppu','species'),
               'Original catches interval audit')
  raw[,source_csv_row:=seq_len(.N)+1L] # Header is CSV row 1.
  raw[,site_key:=trimws(as.character(site))]
  raw[,parsed_start:=parse_dates(PvmAlku)]
  raw[,parsed_end:=parse_dates(PvmLoppu)]
  raw[,interval_days:=as.integer(parsed_end-parsed_start)]
  raw[,excluded_site_152:=cfg$exclude_site_152 & site_key=='152']
  raw[is.na(excluded_site_152),excluded_site_152:=FALSE]
  status <- rep('OK',nrow(raw))
  status[is.na(raw$site_key) | !nzchar(raw$site_key)] <- 'MISSING_SITE'
  status[is.na(raw$parsed_start)] <- 'UNPARSEABLE_START'
  status[is.na(raw$parsed_end)] <- 'UNPARSEABLE_END'
  status[!is.na(raw$interval_days) & raw$interval_days==0L] <- 'ZERO_DURATION'
  status[!is.na(raw$interval_days) & raw$interval_days<0L] <- 'END_BEFORE_START'
  raw[,interval_status:=status]
  issues <- raw[interval_status!='OK',.(
    source_csv_row,site=site_key,year,species,KokMaara,
    PvmAlku_raw=as.character(PvmAlku),PvmLoppu_raw=as.character(PvmLoppu),
    parsed_start,parsed_end,interval_days,interval_status,excluded_site_152)]
  # A recorded same-day catch is NOT an observed zero catch, and not proof
  # of zero trapping effort. Preserve its counts; duration stays unknown.
  target_issues <- issues[excluded_site_152==FALSE]
  unknown_duration <- target_issues[interval_status=='ZERO_DURATION']
  blocking <- target_issues[interval_status!='ZERO_DURATION']
  overview <- data.table(metric=c('raw_source_rows','rows_site_152_excluded',
                                  'interval_issues_all','interval_issues_site_152',
                                  'interval_issues_blocking','zero_duration_retained',
                                  'negative_duration_blocking','unparseable_or_missing_blocking'),
    value=c(nrow(raw),sum(raw$excluded_site_152),
            nrow(issues),sum(issues$excluded_site_152),nrow(blocking),
            nrow(unknown_duration),
            sum(blocking$interval_status=='END_BEFORE_START'),
            sum(blocking$interval_status %chin% c('UNPARSEABLE_START','UNPARSEABLE_END','MISSING_SITE'))))
  if(!is.null(output_dir)) {
    dir.create(output_dir,recursive=TRUE,showWarnings=FALSE)
    fwrite(issues,file.path(output_dir,'TRAP_INTERVAL_AUDIT_ISSUES.csv'))
    fwrite(overview,file.path(output_dir,'TRAP_INTERVAL_AUDIT_SUMMARY.csv'))
  }
  cat('Trap interval audit: source rows=',nrow(raw),
      '; ZERO_DURATION catch rows preserved=',nrow(unknown_duration),
      '; invalid intervals that block build=',nrow(blocking),
      '; issues at excluded site 152=',sum(issues$excluded_site_152),'\n',sep='')
  if(nrow(target_issues)) {
    cat('First issues (SOURCE CSV row, site, dates, days, reason):\n')
    print(target_issues[seq_len(min(nrow(target_issues),12L)),
                   .(source_csv_row,site,PvmAlku_raw,PvmLoppu_raw,
                     interval_days,interval_status)])
  }
  list(issues=issues,summary=overview,blocking_count=nrow(blocking),
       unknown_duration_rows=nrow(unknown_duration))
}

# Use raw catches for every observed site/trapping interval. Nothing outside trap operation is zero-filled.
build_catches <- function(path) {
  r <- read_file(path, ';')
  require_cols(r,c('site','year','KokMaara','PvmAlku','PvmLoppu','species'), 'Original catches')
  r[, site := trimws(as.character(site))]
  # Excluded site 152 may contain malformed legacy dates; it is not part of
  # the analysed trapping grid, but remains visible in the read-only audit.
  if(cfg$exclude_site_152) r <- r[!is.na(site) & site!='152']
  if(!nrow(r)) stopf('No catches after exclusions')
  r[, species := canonical_species(as.character(species))]
  r[, start := parse_dates(PvmAlku)]
  r[, end := parse_dates(PvmLoppu)]
  r[, count := suppressWarnings(as.numeric(KokMaara))]
  if (anyNA(r$site) || any(!nzchar(r$site)) || anyNA(r$start) || anyNA(r$end))
    stopf('Invalid site/date in original catches')
  if (anyNA(r$count) || any(!is.finite(r$count)) || any(r$count < 0) ||
      any(r$count != floor(r$count))) stopf('Counts must be finite nonnegative integers')
  if (any(r$end < r$start))
    stopf('End before start; audit invalid interval before data construction')
  # Same-day source entries remain valid CATCH EVENTS, not known-duration
  # trapping periods; even if count=0 their count observation is preserved.
  raw_duplicate_n <- nrow(r) - uniqueN(r)
  if (raw_duplicate_n) warning(raw_duplicate_n,
    ' EXACT duplicate source rows: retained, not silently dropped. Audit before fitting.')
  events <- unique(r[,.(site,start,end)])
  setorder(events, site,start,end)
  events[, last_end := shift(end),by=site]
  overlap <- events[!is.na(last_end) & start < last_end]
  events[,last_end := NULL]
  events[, recorded_interval_days := as.integer(end-start)] # original date difference
  events[, interval_days := as.integer(NA)]
  events[recorded_interval_days > 0L,interval_days := recorded_interval_days]
  events[, duration_unknown := is.na(interval_days)]
  events[, interval_status := fifelse(duration_unknown,
                                    'SAME_DAY_EFFORT_UNKNOWN','DATED_INTERVAL')]
  # Same-day event's observation date is known, but its actual exposure is not.
  events[, mid := start]
  events[duration_unknown == FALSE,mid := start + floor(interval_days/2)]
  events[, sample_id := paste(site,start,end,sep='_')]
  event_counts <- r[species %chin% cfg$species,
      .(count=sum(count),source_rows=.N,
        explicit_zero_source_rows=sum(count==0)),
      by=.(site,start,end,species)]
  if (!nrow(event_counts)) stopf('No target species observations')
  grid <- CJ(site_event=seq_len(nrow(events)),species=cfg$species, sorted=FALSE)
  grid <- cbind(grid,events[grid$site_event,
              .(site,start,end,mid,sample_id,interval_days,
                recorded_interval_days,duration_unknown,interval_status)])
  grid[,site_event:=NULL]
  grid <- merge(grid,event_counts,by=c('site','start','end','species'),all.x=TRUE,sort=FALSE)
  # A source-verified zero is different from filling in an unlisted species
  # at a known sampling event. Both remain counts of zero, with provenance.
  grid[, zero_filled_from_sampled_event := is.na(source_rows)]
  grid[is.na(count),count:=0]
  grid[is.na(source_rows),source_rows:=0L]
  grid[is.na(explicit_zero_source_rows),explicit_zero_source_rows:=0L]
  grid[, calendar_year := as.integer(format(mid,'%Y'))]
  grid[, month := as.integer(format(mid,'%m'))]
  grid[, year := calendar_year - as.integer(species %chin% cfg$winter_flyers & month <= 3L)]
  grid[, count_per_7d := as.numeric(NA)]
  grid[duration_unknown == FALSE,
       count_per_7d := 7*count/interval_days]
  annual <- grid[, .(
       annual_count=sum(count),
       # Known-day sum is useful QA, but NEVER the denominator for a
       # site-year containing unknown-duration visits.
       known_effort_days=sum(interval_days,na.rm=TRUE),
       n_unknown_effort_intervals=sum(duration_unknown),
       effort_days=if(any(duration_unknown)) NA_real_ else sum(interval_days),
       n_sampling_intervals=.N,
       n_positive_intervals=sum(count>0),
       n_explicit_zero_source_rows=sum(explicit_zero_source_rows),
       n_zero_filled_from_sampled_events=sum(zero_filled_from_sampled_event),
       first_sample=min(start),last_sample=max(end)),
       by=.(site,year,species)]
  annual[, annual_count_per_7d := as.numeric(NA)]
  annual[!is.na(effort_days) & effort_days>0,
         annual_count_per_7d := 7*annual_count/effort_days]
  annual[, effort_status := fifelse(n_unknown_effort_intervals>0,
           'UNKNOWN_DURATION_RETAIN_ANNUAL_COUNT',
           'DATED_EFFORT_COMPLETE')]
  # Catch-count provenance differs from effort completeness.
  annual[, response_checked := raw_duplicate_n==0 && nrow(overlap)==0]
  source_target_sum <- sum(r[species %chin% cfg$species,count])
  stopifnot(!anyDuplicated(annual,by=c('site','year','species')),
            sum(annual$annual_count) == sum(grid$count),
            sum(annual$annual_count) == source_target_sum)
  list(annual=annual, weekly=grid,
       overlapping_events=overlap, duplicate_source_rows=raw_duplicate_n,
       sites=unique(r$site))
}

build_daily <- function(path) {
  w <- read_file(path,';')
  require_cols(w,c('site','DateN','MeanDailyT','Tmin','Tmax','SumDailyP','MeanSnow'), 'Daily weather')
  w[,site:=trimws(as.character(site))]
  w[,date:=as.Date(DateN)]
  if (anyNA(w$date)) stopf('Unparseable daily weather dates')
  cols <- c('MeanDailyT','Tmin','Tmax','SumDailyP','MeanSnow')
  for (z in cols) set(w,j=z,value=suppressWarnings(as.numeric(w[[z]])))
  if (any(!is.finite(unlist(w[,..cols])),na.rm=TRUE)) stopf('Infinite daily-weather values')
  if (any(w$SumDailyP < 0 | w$MeanSnow < 0,na.rm=TRUE)) stopf('Negative precipitation/snow')
  if (any(w$Tmin > w$Tmax,na.rm=TRUE)) stopf('Tmin > Tmax')
  if (anyDuplicated(w,by=c('site','date'))) stopf('Duplicate site/date daily weather rows')
  setkey(w,site,date)
  w
}
# Strict presence and coverage: missing weather is never treated as 0.
weather_window <- function(w, site, start, end, completeness=cfg$min_weather_coverage) {
  dates <- seq.Date(start,end,by='day')
  if (!length(dates)) stopf('Bad weather window')
  # Restrict directly to the requested site and interval. An earlier
  # join multiplied every site-day into every expected day on some inputs.
  site_id <- as.character(site)
  x <- w[site == site_id & date >= start & date <= end]
  n <- length(dates)
  if (nrow(x) > n || anyDuplicated(x$date))
    stopf('Duplicate or multiplied daily weather rows at site %s (%s to %s)',site_id,start,end)
  required <- c('MeanDailyT','Tmin','Tmax','SumDailyP','MeanSnow')
  cover <- vapply(required,function(z) sum(!is.na(x[[z]]))/n,numeric(1))
  valid <- all(cover >= completeness)
  # Even 95% coverage biases cumulative rain, degree days and frost-day totals.
  # Always demand 100% of expected days before publishing a cumulative value.
  full_daily_coverage <- all(cover == 1)
  mean_ok <- function(z) if(valid) mean(z,na.rm=TRUE) else NA_real_
  min_ok <- function(z) if(full_daily_coverage) min(z,na.rm=TRUE) else NA_real_
  max_ok <- function(z) if(full_daily_coverage) max(z,na.rm=TRUE) else NA_real_
  sum_ok <- function(z) if(full_daily_coverage) sum(z,na.rm=TRUE) else NA_real_
  c(n_expected=n,n_complete=min(vapply(required,function(z) sum(!is.na(x[[z]])),numeric(1))),
    min_coverage=min(cover),available=as.integer(valid),
    cumulative_stats_complete=as.integer(full_daily_coverage),
    mean_temperature=mean_ok(x$MeanDailyT),
    mean_Tmin=mean_ok(x$Tmin),min_Tmin=min_ok(x$Tmin),
    mean_Tmax=mean_ok(x$Tmax),max_Tmax=max_ok(x$Tmax),
    sum_precipitation=sum_ok(x$SumDailyP),mean_snow=mean_ok(x$MeanSnow),
    max_snow=max_ok(x$MeanSnow),
    GDD5=sum_ok(pmax(x$MeanDailyT-5,0)),
    GDD4_9=sum_ok(pmax(x$MeanDailyT-4.9,0)),
    GDD0=sum_ok(pmax(x$MeanDailyT,0)),
    frost_days=sum_ok(as.numeric(x$Tmin<0)),
    cold_days_minus20=sum_ok(as.numeric(x$Tmin< -20)),
    cold_days_minus29_5=sum_ok(as.numeric(x$Tmin< -29.5)),
    cold_exposure_minus20=sum_ok(pmax(-20-x$Tmin,0)),
    cold_exposure_minus29_5=sum_ok(pmax(-29.5-x$Tmin,0)),
    cold_days_minus37=sum_ok(as.numeric(x$Tmin < -37)),
    cold_exposure_minus37=sum_ok(pmax(-37-x$Tmin,0)))
}
# The predictions available by May 1 / June 1 use completed windows only.
weather_features <- function(w,annual, stages=stage_windows) {
  keys <- unique(annual[,.(site,year)])
  setorder(keys,site,year)
  feature_list <- vector('list',nrow(keys))
  for(i in seq_len(nrow(keys))) {
    s <- keys$site[i];yr <- keys$year[i]
    row <- list(site=s,year=yr)
    periods <- list(may01=c(fmt(yr,'01-01'),fmt(yr,'04-30')),
                    jun01=c(fmt(yr,'01-01'),fmt(yr,'05-31')),
                    recent_winter=c(fmt(yr-1,'10-01'),fmt(yr,'03-31')),
                    lag1_annual=c(fmt(yr-1,'01-01'),fmt(yr-1,'12-31')),
                    lag2_annual=c(fmt(yr-2,'01-01'),fmt(yr-2,'12-31')),
                    current_annual=c(fmt(yr,'01-01'),fmt(yr,'12-31')))
    for(label in names(periods)) {
      p <- periods[[label]]
      st <- weather_window(w,s,p[1],p[2])
      row[paste0(label,'_',names(st))] <- as.list(st)
    }
    feature_list[[i]] <- as.data.table(row)
  }
  climate <- rbindlist(feature_list,fill=TRUE)
  # Lajikohtaiset stage-ikkunat only as candidate explanatory ecological variables.
  stagekeys <- merge(annual[,.(site,year,species)], stages, by='species', allow.cartesian=TRUE)
  stage_records <- vector('list',nrow(stagekeys))
  for (i in seq_len(nrow(stagekeys))) {
    q <- stagekeys[i]
    lo <- fmt(q$year+q$start_shift,q$start_md)
    hi <- fmt(q$year+q$end_shift,q$end_md)
    if (lo>hi) stopf('Invalid stage for %s %s',q$species,q$stage)
    # Adult weather may alter detection; not automatically a causal driver of abundance.
    measures <- weather_window(w,q$site,lo,hi)
    stage_records[[i]] <- as.data.table(c(list(site=q$site,year=q$year,
                           species=q$species,stage=q$stage,start_date=lo,end_date=hi,
                           review_status=q$review_status),as.list(measures)))
  }
  stage_long <- rbindlist(stage_records,fill=TRUE)
  list(climate=climate,stage_long=stage_long)
}
# Include stage-weather only when the COMPLETE fixed stage ends before issue day.
# No future climate or observation-derived flight timing enters these features.
completed_stages_wide <- function(stage_long, issue_md) {
  x <- data.table::copy(stage_long[end_date <= fmt(year, issue_md) & available == 1L])
  # Species-specific freezing hypotheses; other species get NA, not false thresholds.
  x[!(species=='Lymantria monacha' & stage=='egg_winter'),
    c('cold_days_minus29_5','cold_exposure_minus29_5'):=list(NA_real_,NA_real_)]
  x[!(species=='Epirrita autumnata' & stage=='egg_winter'),
    c('cold_days_minus37','cold_exposure_minus37'):=list(NA_real_,NA_real_)]
  x[stage!='egg_winter',
    c('cold_days_minus20','cold_exposure_minus20'):=list(NA_real_,NA_real_)]
  # 4.9 C is an exploratory B. piniaria development base, not a fitted choice.
  x[species!='Bupalus piniarius',GDD4_9:=NA_real_]
  measures <- c('mean_temperature','min_Tmin','sum_precipitation','GDD5','GDD4_9',
                'mean_snow','cold_days_minus20','cold_days_minus29_5',
                'cold_days_minus37','cold_exposure_minus20',
                'cold_exposure_minus29_5','cold_exposure_minus37')
  if(!nrow(x)) return(unique(stage_long[,.(site,year,species)])[0])
  x <- melt(x,id.vars=c('site','year','species','stage'),measure.vars=measures,
            variable.name='metric', value.name='value')
  x[,key:=paste0('stage_',stage,'_',metric)]
  out <- dcast(x,site+year+species~key,value.var='value')
  stopifnot(!anyDuplicated(out,by=c('site','year','species')))
  out
}

# All old-species observation columns and weather/phenology must be EXCLUDED.
# Environmental data are BUFFER-LEVEL: never merge raw rows to annual responses.
read_environment <- function(path) {
  header <- names(read_file(path,',',header_only=TRUE))
  needed <- c('site','year','buffer_m')
  if(length(setdiff(needed,header))) stopf('Environment lacks site/year/buffer_m')
  pattern <- paste0('^(DTW_|HostTree|LocalWet|OverwinteringSoil|Soil|soil_|',
                    'low_soil_|clc_|NDVI_|havu_|lehti_|age$|mean_diameter$|',
                    'mean_height$|canopy_cover$|broadleaf_canopy_cover$|',
                    'basal_area$|volume$|pine_volume$|spruce_volume$|',
                    'birch_volume$|other_broadleaf_volume$|site_type$|land_class$|',
                    'main_site_type$|fra_class$|frost_)')
  variables <- grep(pattern,header,value=TRUE)
  flags <- intersect(c('corine_temporally_filled','havu_temporally_filled',
                       'lehti_temporally_filled','vmi_temporally_filled'),header)
  if(!length(variables)) stopf('No recognized environmental variables: review schema')
  x <- read_file(path,',',select=c(needed,variables,flags))
  x[,site:=trimws(as.character(site))]
  x[,year:=as.integer(year)]
  x[,buffer_m:=as.numeric(buffer_m)]
  if(anyNA(x[,..needed])) stopf('Missing environmental join keys')
  # Multiple old species/sample_id rows are expected. Conflict at same key is not.
  x <- unique(x)
  keys <- c('site','year','buffer_m')
  if(anyDuplicated(x,by=keys)) {
    # When some fields are NA in one old-species row, merge only if non-NA values agree.
    conflicts <- x[,lapply(.SD,function(z) uniqueN(z[!is.na(z)])>1L),
                   by=keys,.SDcols=c(variables,flags)]
    bad <- conflicts[,rowSums(.SD)>0, .SDcols=c(variables,flags)]
    if(any(bad)) stopf('Environment inconsistent within site/year/buffer: %d conflicting groups',sum(bad))
    first_present <- function(z) {
      v <- z[!is.na(z)]
      if (length(v)) v[1] else z[NA_integer_][1L]
    }
    x <- x[, lapply(.SD, first_present), by=keys, .SDcols=c(variables,flags)]
  }
  stopifnot(!anyDuplicated(x,by=keys))
  # Retrospectively filled environmental years might look into the future.
  # ALL extracted rows are NOT_FORECAST_CLEARED until temporal-provenance audit.
  x[,forecast_approval:='NOT_APPROVED_TEMPORAL_PROVENANCE_UNKNOWN']
  list(data=x, variables=variables, flags=flags)
}

main <- function() {
  args <- commandArgs(trailingOnly=TRUE)
  mode <- if('--inspect' %in% args) 'inspect' else if('--audit' %in% args) 'audit' else if('--build' %in% args) 'build' else 'help'
  if (mode=='help') {cat('Usage: Rscript --vanilla build_six_species_annual_v3.R --inspect OR --audit OR --build\n');return(invisible())}
  catches_file <- file.path(cfg$root,'Eiffel_1993_2024.csv')
  weather_file <- file.path(cfg$root,'Daily_weather_from_NC_needed_trap_years_and_previous_year.txt')
  frost_module <- file.path('frost','FROST_MODEL_TRAP_YEAR_v1.R')
  if(!file.exists(frost_module))
    frost_module <- file.path('R','frost','FROST_MODEL_TRAP_YEAR_v1.R')
  if(!file.exists(frost_module)) stopf('Frost module missing')
  source(frost_module,local=TRUE)
  requested_frost <- Sys.getenv('EIFFEL_FROST_FILE',unset='')
  # Phase 1: observations + daily weather, plus an OPTIONAL distinct frost model.
  # No vegetation, buffer environmental variables, NDVI or Greenup are read.
  if (mode=='inspect') {
    cat('STAGE: WEATHER_ONLY_PHASE_1 (no environment or Greenup)\n')
    for (f in c(catches_file,weather_file)) {
      cat('\n',f,' present=',file.exists(f),'\n',sep='')
      if(file.exists(f)) cat('columns: ',paste(names(read_file(f,';',header_only=TRUE)),collapse=', '),'\n')
    }
    frost_path <- frost_source_path(cfg$root,requested_frost)
    cat('Optional frostmodel source: ',if(nzchar(frost_path)) frost_path else 'NOT FOUND', '\n',sep='')
    if(nzchar(frost_path))
      cat('frost columns: ',paste(names(read_file(frost_path,',',header_only=TRUE)),collapse=', '),'\n')
    return(invisible())
  }
  requested_sources <- if(mode=='audit') catches_file else c(catches_file,weather_file)
  for (f in requested_sources) if(!file.exists(f)) stopf('Missing: %s',f)
  normalized_out <- normalizePath(cfg$out_root,winslash='/',mustWork=FALSE)
  if (!grepl('^([A-Za-z]:/|/)',normalized_out))
    stopf('Expected absolute output path (D: on Windows, /path on Linux): %s', normalized_out)
  id <- format(Sys.time(),'%Y%m%d_%H%M%S')
  out <- file.path(cfg$out_root,paste0('build_',id))
  if(dir.exists(out)) stopf('Output directory already exists: %s',out)
  dir.create(out,recursive=TRUE,showWarnings=FALSE)
  cat('Output:',out,'\n')
  trap_audit <- audit_trap_intervals(catches_file,out)
  if(mode=='audit') {
    if(trap_audit$blocking_count>0L)
      cat('AUDIT COMPLETE: ',trap_audit$blocking_count,
          ' blocking intervals REQUIRE MANUAL REVIEW. CSV saved to: ',out,'\n',sep='')
    else
      cat('PASS: interval audit completed without any blocking intervals.\n')
    cat('No original catches changed and no weather/frost/Hmsc work performed.\n')
    return(invisible(out))
  }
  if(trap_audit$blocking_count>0L)
    stopf('%d invalid analysed trap interval(s). Audit saved: %s. No counts changed.',
          trap_audit$blocking_count,file.path(out,'TRAP_INTERVAL_AUDIT_ISSUES.csv'))
  # Preserve original files and make provenance explicit.
  frost_path <- frost_source_path(cfg$root,requested_frost)
  manifest_sources <- c(catches_file,weather_file)
  if(nzchar(frost_path)) manifest_sources <- c(manifest_sources,frost_path)
  manifest <- data.table(source=manifest_sources,
                         bytes=as.numeric(file.info(manifest_sources)$size),
                         md5=unname(tools::md5sum(manifest_sources)))
  fwrite(data.table(stage='WEATHER_AND_OPTIONAL_FROST_PHASE_1',
       environment_inputs=0L,greenup_inputs=0L,
       frostmodel_inputs=as.integer(nzchar(frost_path)),hmsc_models_fitted=0L),
       file.path(out,'PHASE_1_SCOPE.csv'))
  fwrite(manifest,file.path(out,'source_manifest.csv'))
  catches <- build_catches(catches_file)
  fwrite(catches$annual,file.path(out,'annual_site_species_flight_year.csv'))
  fwrite(catches$weekly,file.path(out,'sampling_intervals_with_zeros.csv.gz'))
  fwrite(catches$weekly[duration_unknown == TRUE,
    .(site,year,species,start,end,interval_status,count,
      interval_days,count_per_7d)],
    file.path(out,'SAME_DAY_EVENTS_EFFORT_UNKNOWN.csv'))
  fwrite(catches$annual[n_unknown_effort_intervals>0],
    file.path(out,'ANNUAL_COUNTS_UNKNOWN_EFFORT_REVIEW.csv'))
  fwrite(catches$overlapping_events,file.path(out,'overlap_audit.csv'))
  # Historical frost-model: join ONLY site/year to soil-pupating moths.
  # Preserve annual counts and never fill missing modeled frost years.
  frost_raw <- frost_read_trap_year(frost_path)
  frost_all <- frost_for_annual(catches$annual,frost_raw)
  fwrite(frost_all,file.path(out,'frost_soil_pupae_site_year_EXPLANATORY_CANDIDATES.csv'))
  frost_qa <- data.table(
    input_path=if(nzchar(frost_path)) frost_path else NA_character_,
    frost_sites=if(is.null(frost_raw)) 0L else uniqueN(frost_raw$site),
    frost_source_rows=if(is.null(frost_raw)) 0L else nrow(frost_raw),
    n_target_annual_rows=sum(frost_all$frost_relevant),
    n_target_rows_with_frost_min=sum(frost_all$frost_relevant & !is.na(frost_all$frost_min_tmin)),
    n_target_rows_with_frost_sum=sum(frost_all$frost_relevant & !is.na(frost_all$frost_cold_sum20)),
    n_frost_forecast_provenance_rows=if(is.null(frost_raw)) 0L else
      sum(!is.na(frost_raw$frost_available_date)&!is.na(frost_raw$frost_winter_end_date)))
  fwrite(frost_qa,file.path(out,'FROST_INPUT_QA.csv'))
  w <- build_daily(weather_file)
  wx <- weather_features(w,catches$annual)
  # Species-specific metadata and weather-only phenology, plus optional Greenup.
  ecology_module <- file.path('ecology','EIFFEL_ECOLOGY_FEATURES_v4.R')
  if(!file.exists(ecology_module))
    ecology_module <- file.path('R','ecology','EIFFEL_ECOLOGY_FEATURES_v4.R')
  if(!file.exists(ecology_module)) stopf('Ecology module missing')
  source(ecology_module,local=TRUE)
  eco_weather <- ecology_weather_by_issue(w,catches$annual)
  # Phase 1 exports only actual weather and meteorological proxies.
  # Vegetation Greenup and NDVI remain strictly excluded from both data and
  # exported predictor schemas until a later source-specific stage is audited.
  fwrite(ecology_species_registry,file.path(out,'species_ecological_registry_REVIEW.csv'))
  fwrite(eco_weather,file.path(out,'weather_phenology_asof_AUDIT.csv.gz'))
  eco_features <- function(issue_name) {
    requested_issue <- issue_name
    z <- eco_weather[issue == requested_issue]
    cols <- c('spring_start_0_doy','spring_start_5_doy',
      'gdd5_50_crossing_doy','gdd5_100_crossing_doy',
      'first_snowfree7_doy_sofar','last_snow_day_doy_sofar',
      'rain30_complete_mm','rain90_complete_mm','api90_7d_half_life_mm')
    stopifnot(!anyDuplicated(z,by=c('site','year')),all(cols %in% names(z)))
    z <- z[,c('site','year',cols),with=FALSE]
    data.table::setnames(z,cols,paste0('eco_',cols))
    z
  }
  fwrite(wx$stage_long,file.path(out,'species_stage_weather_PROVISIONAL.csv.gz'))
  fwrite(stage_windows,file.path(out,'stage_definitions_REQUIRE_REVIEW.csv'))
  base <- merge(catches$annual,wx$climate,by=c('site','year'),all.x=TRUE,sort=FALSE)
  stopifnot(nrow(base)==nrow(catches$annual))
  # STRICT forecast-only inputs. Observed annual response and realized full-year effort
  # are unavailable on the issue dates. Keep them ONLY in the response table.
  # Future forecasts must not infer an offset from later realized trap operations.
  common <- c('site','year','species')
  prior <- grep('^(lag1_annual_|lag2_annual_|recent_winter_)',names(base),value=TRUE)
  may_weather <- base[,c(common,grep('^may01_',names(base),value=TRUE),prior),with=FALSE]
  june_weather <- base[,c(common,grep('^jun01_',names(base),value=TRUE),prior),with=FALSE]
  may_stages <- completed_stages_wide(wx$stage_long,'04-30')
  june_stages <- completed_stages_wide(wx$stage_long,'05-31')
  may_weather <- merge(may_weather,may_stages,by=c('site','year','species'),all.x=TRUE,sort=FALSE)
  june_weather <- merge(june_weather,june_stages,by=c('site','year','species'),all.x=TRUE,sort=FALSE)
  may_weather <- merge(may_weather,eco_features('may01'),by=c('site','year'),all.x=TRUE,sort=FALSE)
  june_weather <- merge(june_weather,eco_features('jun01'),by=c('site','year'),all.x=TRUE,sort=FALSE)
  frost_may <- frost_for_annual(catches$annual,frost_raw,issue='may01')
  frost_june <- frost_for_annual(catches$annual,frost_raw,issue='jun01')
  may_weather <- merge(may_weather,frost_keep_features(frost_may),
      by=c('site','year','species'),all.x=TRUE,sort=FALSE)
  june_weather <- merge(june_weather,frost_keep_features(frost_june),
      by=c('site','year','species'),all.x=TRUE,sort=FALSE)
  fwrite(frost_may[,.(site,year,species,frost_asof_available,frost_source_status)],
      file.path(out,'frost_asof_may01_AUDIT.csv'))
  fwrite(frost_june[,.(site,year,species,frost_asof_available,frost_source_status)],
      file.path(out,'frost_asof_jun01_AUDIT.csv'))
  stopifnot(nrow(may_weather)==nrow(base), nrow(june_weather)==nrow(base))
  # Explicit ban on phase-2 NDVI/Greenup and all vegetation/soil attributes.
  blocked_names <- c('greenup','ndvi','corine','clc_','vmi_','havu_','lehti_',
                     'dtw_','soil_','pine_volume','spruce_volume','birch_volume')
  for (table in list(may_weather,june_weather)) {
    if (any(vapply(blocked_names,function(k) any(grepl(k,names(table),fixed=TRUE,ignore.case=TRUE)),logical(1))))
      stopf('Weather-only phase 1 unexpectedly contains environment/vegetation features')
  }
  forbidden <- c('annual_count','effort_days','annual_count_per_7d',
                 'n_sampling_intervals','n_positive_intervals','first_sample',
                 'last_sample','current_annual_mean_temperature')
  if (any(forbidden %in% names(may_weather)) || any(forbidden %in% names(june_weather)))
    stopf('Forecast table contains post-issuance response/effort features')
  may_weather[, forecast_issue_date := fmt(year,'05-01')]
  june_weather[, forecast_issue_date := fmt(year,'06-01')]
  fwrite(may_weather,file.path(out,'predictive_may01_FEATURES_ONLY_UNVALIDATED.csv.gz'))
  fwrite(june_weather,file.path(out,'predictive_jun01_FEATURES_ONLY_UNVALIDATED.csv.gz'))
  # Full historical stages are permitted as explanatory candidates, not advance predictors.
  explanatory_stages <- completed_stages_wide(wx$stage_long,'12-31')
  expl <- merge(base,explanatory_stages,by=c('site','year','species'),all.x=TRUE,sort=FALSE)
  expl <- merge(expl,eco_features('explanatory'),by=c('site','year'),all.x=TRUE,sort=FALSE)
  expl <- merge(expl,frost_all[,c('site','year','species',
                      setdiff(frost_vars,'frost_min_tmin'),'frost_min'),with=FALSE],
                by=c('site','year','species'),all.x=TRUE,sort=FALSE)
  stopifnot(nrow(expl)==nrow(base))
  fwrite(expl,file.path(out,'annual_weather_stages_EXPLANATORY_CANDIDATES.csv.gz'))
  # PHASE 2 (future): environmental sources are coverage-incompatible and
  # will each need a separate QA/availability audit, then join by site-year-buffer
  # without restricting the weather-only site-years or multiplying annual counts.
  # No environmental table is read, joined or exported here.
  coverage <- base[,.(species,site,year,annual_count,effort_days,
                       weather_may_available=may01_available,
                       weather_june_available=jun01_available,
                       previous_year_available=lag1_annual_available,
                       two_years_back_available=lag2_annual_available)]
  fwrite(coverage,file.path(out,'readiness_by_site_species_year.csv'))
  summary <- data.table(check=c('species_count','annual_rows','raw_exact_duplicate_rows',
                               'overlapping_trap_intervals','source_rows_same_day_retained',
                               'annual_rows_effort_unknown','environment_inputs_read',
                               'environment_rows_joined','may01_weather_available_rows',
                               'jun01_weather_available_rows'),
                        value=c(length(unique(catches$annual$species)),nrow(catches$annual),
                                catches$duplicate_source_rows,nrow(catches$overlapping_events),
                                trap_audit$unknown_duration_rows,
                                sum(catches$annual$n_unknown_effort_intervals>0),
                                0L,0L,sum(base$may01_available==1,na.rm=TRUE),
                                sum(base$jun01_available==1,na.rm=TRUE)))
  fwrite(summary,file.path(out,'QA_SUMMARY.csv'))
  writeLines(c('STAGE: WEATHER_ONLY_PHASE_1. Environmental and Greenup sources were NOT read.',
    'NOT SCIENTIFICALLY VALIDATED: NO Hmsc fits run.',
    'Ecological stage windows require species-specific scientific review.',
    'Potential response/effort duplicate source rows and overlaps require sign-off.',
    'SAME-DAY PvmAlku=PvmLoppu catches including positive and zero counts are retained.',
    'Same-day events have UNKNOWN effort; no one-day assumption or count normalization.',
    'If any unknown-duration event is present in an annual site/species row, effort_days and annual_count_per_7d are NA.',
    'Known effort_days is QA only until complete effort can be established from source logs.',
    'Zero fill applies only to actual recorded sampling events, never unsampled periods.',
    'An explicitly recorded zero and a zero-filled unlisted species are flagged separately.',
    'Zero-fill validity requires source confirmation that all target species were sampled at each event.',
    'Precipitation, temperature, snow units require source audit.',
    'Optional frostmodel is distinct from AIR Tmin; site + adult flight year join, no buffers.',
    'Frost threshold Tmin <= -20 C; frost_cold_sum20 sums ACTUAL NEGATIVE Tmin, not threshold excess.',
    'frost_min is exactly frost_min_tmin from source; use one alias, NOT both, in any model.',
    'Frost_min refers to min_tmin of modeled frost source; check original model units and depth.',
    'Nov(t-1)-Mar(t) frost-year semantics require independent confirmation from source model.',
    'Legacy frost source without winter_end_date and available_date is explanatory ONLY, not May/June predictor.',
    'Missing frost source/year remains NA for Bupalus and Panolis, not zero or filled.',
    'Other four species receive no frost-model predictor.',
    'Lag2 weather is not guaranteed by 1.2 original extraction; missing = NA.',
    'Historical environmental source data were intentionally excluded from phase 1.',
    'Environment layers have unequal availability, buffer scales and year coverage.',
    'Each environment source requires independent coverage and provenance checks in phase 2.',
    'New spring DOY/GDD dates are meteorological proxies, not measured insect hatching.',
    'Greenup is EXCLUDED in weather-only phase 1, regardless of EIFFEL_GREENUP_FILE.',
    'Meteorological spring-start and GDD proxy dates do not establish host Greenup.',
    '30/90-day precipitation and API require complete daily weather, not 95 percent.',
    'All cumulative daily weather and extreme statistics require 100 percent data coverage.',
    'B. piniarius stage GDD4_9 is exploratory, and not an automatic fitted threshold.',
    'E. autumnata -37 C sensitivity and L. monacha -29.5 C egg freezing median differ.',
    'Soil-pupating moths never receive egg-freezing thresholds as ecological predictors.',
    'Host-tree priority registry is candidate metadata, not an automatically fitted model.',
    'Forecast as-of release dates, greenup and phenology require further audits.',
    'Outer CV predictor selection/imputation/selection must be training-only.',
    'Forecast FEATURE files exclude annual outcome and realized future effort; merge for evaluation only.',
    'No forecast-time effort offset is established; standardization requires a scientific decision.',
    'NDVI year t may reflect larval feeding damage, not an independent host vegetation predictor.',
    'For Bupalus and Panolis adult year t corresponds to larval year t-1.',
    'No vegetation/NDVI temporal semantics are validated until dated scene audit.',
    'Use annual_site_species_flight_year.csv as response; never sum per-buffer rows.'),
    file.path(out,'REQUIRED_REVIEW.txt'))
  cat('Finished WEATHER + OPTIONAL FROST phase 1. No environment or Greenup read. DO NOT fit Hmsc until gates pass.\n')
  invisible(out)
}
if(sys.nframe()==0L) main()