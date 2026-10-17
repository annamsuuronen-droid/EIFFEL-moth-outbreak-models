#!/usr/bin/env Rscript
# Explicit local-only derived stage. Reads *existing* annual builder output.
# Does not touch raw moth source, FROST, previous models, weather selection or CV.

population_build_cli <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  if (!identical(args, '--build')) stop('Explicit --build required', call. = FALSE)
  file_arg <- grep('^--file=', commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) != 1L) stop('Script path unavailable', call. = FALSE)
  this_file <- normalizePath(sub('^--file=', '', file_arg), winslash = '/', mustWork = TRUE)
  repo <- normalizePath(file.path(dirname(this_file), '..', '..'),
                        winslash = '/', mustWork = TRUE)
  module_file <- file.path(repo, 'R', 'population_dynamics', 'POPULATION_HISTORY_v1.R')
  source(module_file, local = TRUE)
  build_dir <- Sys.getenv('EIFFEL_AUDIT_BUILD_DIR', unset = '')
  output <- Sys.getenv('EIFFEL_POP_HISTORY_OUT', unset = '')
  if (!nzchar(build_dir) || !nzchar(output) || !dir.exists(build_dir)) {
    stop('EIFFEL_AUDIT_BUILD_DIR (existing annual build) and EIFFEL_POP_HISTORY_OUT required',
         call. = FALSE)
  }
  input <- file.path(build_dir, 'annual_site_species_flight_year.csv')
  qa <- file.path(build_dir, 'LOCAL_VALIDATION_REPORT.csv')
  if (!file.exists(input) || !file.exists(qa)) {
    stop('No approved existing annual build: input and previous local QA required', call. = FALSE)
  }
  # Require the existing runtime wrapper; never allow output into the checkout,
  # the annual source folder, or a caller-selected historical result directory.
  runtime <- Sys.getenv('EIFFEL_BUILD_OUT', unset = '')
  if (!nzchar(runtime) || !dir.exists(runtime)) {
    stop('Existing runtime wrapper required (EIFFEL_BUILD_OUT)', call. = FALSE)
  }
  runtime <- normalizePath(runtime, winslash = '/', mustWork = TRUE)
  build_dir <- normalizePath(build_dir, winslash = '/', mustWork = TRUE)
  same_path <- function(a, b) {
    if (.Platform$OS.type == 'windows') identical(tolower(a), tolower(b)) else identical(a, b)
  }
  population_root <- file.path(runtime, 'population_history_v1')
  parent <- dirname(output)
  if (!same_path(normalizePath(dirname(parent), winslash = '/', mustWork = TRUE), runtime) ||
      basename(parent) != 'population_history_v1' ||
      !grepl('^history_[A-Za-z0-9_]+$', basename(output)) ||
      !same_path(dirname(build_dir), runtime) || !grepl('^build_', basename(build_dir)) ||
      startsWith(tolower(paste0(runtime, '/')), tolower(paste0(repo, '/')))) {
    stop('Population output must be a new history_* under runtime/population_history_v1; existing build_* required',
         call. = FALSE)
  }
  if (dir.exists(population_root) &&
      !same_path(normalizePath(population_root, winslash = '/', mustWork = TRUE), population_root)) {
    stop('Population output parent must not redirect outside runtime', call. = FALSE)
  }
  fingerprint <- function() unname(tools::md5sum(c(input, qa, module_file, this_file)))
  sources_before <- fingerprint()
  checks <- utils::read.csv(qa, stringsAsFactors = FALSE)
  mandatory <- c('annual_counts_reconcile_after_exact_dedup',
                 'true_observed_zeros', 'unknown_effort_is_not_invented')
  if (!all(c('check', 'status') %in% names(checks)) ||
      nrow(checks) == 0L || anyNA(checks$check) || anyNA(checks$status) ||
      any(!nzchar(trimws(checks$check))) ||
      any(!checks$status %in% c('PASS', 'REVIEW', 'FAIL')) ||
      any(checks$status == 'FAIL') ||
      !all(vapply(mandatory, function(k) {
        z <- checks$status[checks$check == k]
        length(z) == 1L && identical(z, 'PASS')
      }, logical(1)))) {
    stop('Local annual QA must pass required source/zero/effort gates; no automatic rerun',
         call. = FALSE)
  }
  if (file.exists(output)) stop('Refusing to overwrite existing population output', call. = FALSE)
  if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE)) {
    stop('Cannot create local population output parent', call. = FALSE)
  }
  stage <- paste0(output, '.part_', Sys.getpid())
  if (file.exists(stage) || !dir.create(stage)) {
    stop('Refusing to reuse existing stage directory', call. = FALSE)
  }
  finished <- FALSE
  on.exit(if (!finished && dir.exists(stage)) unlink(stage, recursive = TRUE), add = TRUE)

  x <- utils::read.csv(input, check.names = FALSE, stringsAsFactors = FALSE,
                       colClasses = c(site = 'character', species = 'character',
                         year = 'numeric', annual_count = 'numeric',
                         effort_days = 'numeric', annual_count_per_7d = 'numeric',
                         n_sampling_intervals = 'numeric', n_unknown_effort_intervals = 'numeric'))
  history <- population_make_history(x)
  coverage <- population_lag_coverage(history)
  # Production site-year rows stay in the local runtime, never in GitHub/logs.
  # CI invokes this stage only with generated synthetic fixtures.
  utils::write.csv(history, file.path(stage, 'population_history_lag1to3_LOCAL.csv'),
                   row.names = FALSE, na = '')
  utils::write.csv(coverage, file.path(stage, 'population_lag_coverage_LOCAL.csv'),
                   row.names = FALSE, na = '')
  if (!identical(sources_before, fingerprint())) {
    stop('Annual input, QA or population code changed during derivation', call. = FALSE)
  }
  manifest <- data.frame(
    item = c('status', 'annual_source_basename', 'annual_source_md5', 'annual_qa_md5',
             'population_module_md5', 'population_runner_md5',
             'n_species', 'history_rows', 'model_fits', 'history_scope'),
    value = c('DERIVED_ONLY_LOCAL_QA_NOT_MODEL_VALIDATION', basename(input),
              sources_before[1], sources_before[2], sources_before[3],
              sources_before[4], length(population_species_v1),
              nrow(history), 0,
              'EXACT_PREVIOUS_BIOLOGICAL_YEARS_WITH_EFFORT_VALIDITY'),
    stringsAsFactors = FALSE
  )
  utils::write.csv(manifest, file.path(stage, 'POPULATION_HISTORY_MANIFEST.csv'),
                   row.names = FALSE)
  outputs <- c('population_history_lag1to3_LOCAL.csv',
               'population_lag_coverage_LOCAL.csv',
               'POPULATION_HISTORY_MANIFEST.csv')
  hashes <- data.frame(filename = outputs,
                       md5 = unname(tools::md5sum(file.path(stage, outputs))),
                       stringsAsFactors = FALSE)
  utils::write.csv(hashes, file.path(stage, 'OUTPUT_HASHES.csv'), row.names = FALSE)
  writeLines('COMPLETE_DERIVED_ONLY_NOT_SCIENTIFIC_MODEL_APPROVAL',
             file.path(stage, 'COMPLETE.txt'))
  if (file.exists(output) || !file.rename(stage, output)) {
    stop('Cannot atomically publish derived outputs: existing path or filesystem failure',
         call. = FALSE)
  }
  finished <- TRUE
  cat('DONE: six-species population history derived from QA-gated EXISTING annual build.\n')
  cat('No weather selection, Hmsc fit, MCMC, CV, threshold fit or original source rewrite.\n')
  cat('Output:', output, '\n')
}
population_build_cli()
