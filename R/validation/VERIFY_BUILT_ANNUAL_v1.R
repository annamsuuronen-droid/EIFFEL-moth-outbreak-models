#!/usr/bin/env Rscript
# Fast local verification of an already completed EIFFEL six-species build.
# Does not create modeling data or refit Hmsc. Uses original catches read-only.
suppressPackageStartupMessages(library(data.table))
script_arg <- grep('^--file=',commandArgs(trailingOnly=FALSE),value=TRUE)
if(length(script_arg)!=1L) stop('Cannot resolve validation script location')
script_path <- sub('^--file=','',script_arg)
repo_root <- normalizePath(file.path(dirname(script_path),'..','..'),
                           winslash='/',mustWork=TRUE)
source(file.path(repo_root,'R','build_six_species_annual_v3.R'),local=TRUE)
build_dir <- Sys.getenv('EIFFEL_AUDIT_BUILD_DIR',unset='')
if(!nzchar(build_dir) || !dir.exists(build_dir))
  stop('EIFFEL_AUDIT_BUILD_DIR must point to an existing build_* directory')
file_in <- function(name) file.path(build_dir,name)
for(f in c('annual_site_species_flight_year.csv','QA_SUMMARY.csv',
           'EXACT_DUPLICATES_EXCLUDED_FROM_DERIVED_DATA.csv',
           'overlap_audit.csv','FROST_INPUT_QA.csv')) {
  if(!file.exists(file_in(f))) stopf('Incomplete/stale build: %s missing',f)
}
annual <- fread(file_in('annual_site_species_flight_year.csv'))
qa <- fread(file_in('QA_SUMMARY.csv'))
duplicates <- fread(file_in('EXACT_DUPLICATES_EXCLUDED_FROM_DERIVED_DATA.csv'))
overlap <- fread(file_in('overlap_audit.csv'))
frost <- fread(file_in('FROST_INPUT_QA.csv'))
input_file <- file.path(cfg$root,'Eiffel_1993_2024.csv')
if(!file.exists(input_file)) stopf('Original source missing: %s',input_file)
raw <- read_catches_deduplicated(input_file)
original <- raw$data
original[,site:=trimws(as.character(site))]
if(cfg$exclude_site_152) original <- original[site!='152'&!is.na(site)]
original[,species:=canonical_species(as.character(species))]
original[,count:=as.numeric(KokMaara)]
observed_sum <- sum(original[species %chin% cfg$species,count])
constructed_sum <- sum(annual$annual_count)

checks <- data.table(check=character(),status=character(),value=character(),explanation=character())
add <- function(key,valid,value,what,review=FALSE) {
  checks <<- rbind(checks,data.table(check=key,
    status=if(review)'REVIEW' else if(isTRUE(valid))'PASS' else 'FAIL',
    value=as.character(value),explanation=what))
}
qa_metric <- function(key) {
  value <- qa[check==key,value]
  if(length(value)!=1L) return(NA_real_)
  as.numeric(value)
}
add('six_species',setequal(unique(annual$species),cfg$species),
    length(unique(annual$species)),'Exactly six target moth species')
add('unique_annual_site_year_species',
    !anyDuplicated(annual,by=c('site','year','species')),
    nrow(annual),'No duplicate annual species keys')
add('annual_rows_match_report',nrow(annual)==qa_metric('annual_rows'),
    nrow(annual),'Annual rows match QA_SUMMARY')
add('raw_catches_exact_duplicate_count',
    nrow(duplicates)==raw$number_removed &&
      qa_metric('raw_exact_duplicate_rows')==raw$number_removed,
    raw$number_removed,'Only identical ORIGINAL source CSV lines are removed')
add('duplicate_source_line_numbers',
    setequal(duplicates$source_csv_row,raw$duplicates$source_csv_row),
    paste(sort(duplicates$source_csv_row),collapse=';'),
    'Removed original CSV line numbers retained in the audit')
add('annual_counts_reconcile_after_exact_dedup',
    isTRUE(all.equal(as.numeric(observed_sum),as.numeric(constructed_sum))) &&
      all(annual$counts_reconciled_after_exact_dedup==TRUE),
    paste('source=',observed_sum,';derived=',constructed_sum),
    'Every retained detected moth is counted exactly once')
add('annual_counts_nonnegative',
    !anyNA(annual$annual_count) &&
      all(is.finite(annual$annual_count)) &&
      all(annual$annual_count>=0) &&
      all(annual$annual_count==floor(annual$annual_count)),
    'counts','No missing/negative/fractional observed counts')
add('true_observed_zeros',
    all(annual$n_observed_zero_intervals ==
        annual$n_explicit_zero_intervals +
        annual$n_zero_filled_from_sampled_events),
    sum(annual$n_observed_zero_intervals),
    'All absent species at registered active sampling events are observed zeros')
add('unknown_effort_is_not_invented',
    all(is.na(annual[n_unknown_effort_intervals>0,effort_days])) &&
      all(is.na(annual[n_unknown_effort_intervals>0,annual_count_per_7d])),
    sum(annual$n_unknown_effort_intervals>0),
    'Same-day unknown trap duration never assigned an arbitrary effort')
add('apparent_overlaps_audit_only',
    nrow(overlap)==qa_metric('overlapping_trap_intervals'),
    nrow(overlap),
    'Recorded overlapping interval dates retained as metadata; moth counts not removed')
add('overlap_recorded_dates_need_effort_review',TRUE,nrow(overlap),
    'Possible source date-entry errors: duration-based effort remains provisional',
    review=nrow(overlap)>0)
add('frost_input_qa_present',nrow(frost)==1L,nrow(frost),
    'Separate frost soil-pupa source is audited; absence is not zero')
add('scientific_qa_pending',TRUE,
    'Weather windows, source date errors, old Hmsc effort offsets',
    'Successful arithmetic does not validate ecological timing, frost as-of or fitted models',
    review=TRUE)
fwrite(checks,file_in('LOCAL_VALIDATION_REPORT.csv'))
summary_md <- c(
  '# EIFFEL local build QA (read-only source)',
  '',
  paste0('- Build: ',normalizePath(build_dir,winslash='/')),
  paste0('- Source: ',normalizePath(input_file,winslash='/')),
  paste0('- Six-species annual rows: ',nrow(annual)),
  paste0('- Count sum AFTER exact raw-source deduplication: ',constructed_sum),
  paste0('- Removed exact source copies (original unmodified): ',nrow(duplicates)),
  paste0('- Apparent overlap date entries retained: ',nrow(overlap)),
  paste0('- Annual species rows with unverified effort: ',
         sum(annual$n_unknown_effort_intervals>0)),
  '',
  '| QA check | Status | Value |',
  '| --- | --- | --- |',
  paste0('| ',checks$check,' | ',checks$status,' | ',
         gsub('\\|','/',checks$value),' |'),
  '',
  'Do not use these records to fit Hmsc until scientific QA is approved.',
  'Previously selected weather variable screening is NOT repeated.'
)
writeLines(summary_md,file_in('LOCAL_VALIDATION_REPORT.md'))
cat(paste(summary_md,collapse='\n'),'\n')
if(any(checks$status=='FAIL')) stop('LOCAL QA FAILED: inspect LOCAL_VALIDATION_REPORT.csv')
cat('\nPASS: source counts, true zeros, exact duplicate removal and QA checks.\n')
cat('Recorded date-overlap entries remain in derived catch tables; no Hmsc run.\n')
