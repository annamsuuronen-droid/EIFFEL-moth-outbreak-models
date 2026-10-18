#!/usr/bin/env Rscript
# Safety contract for WEATHER_ONLY_PHASE_1. Synthetic headers only; no Hmsc fit.
stopifnot(requireNamespace('data.table',quietly=TRUE))
script <- 'R/build_six_species_annual_v3.R'
src <- paste(readLines(script,warn=FALSE),collapse='\n')
main <- sub('(?s)^.*?main <- function\\(\\) \\{','main <- function() {',src,perl=TRUE)
stopifnot(grepl('STAGE: WEATHER_ONLY_PHASE_1',main,fixed=TRUE),
  !grepl('read_environment\\(',main),
  !grepl('env_file\\s*<-',main),
  !grepl('ecology_greenup\\(',main),
  !grepl('NDVI_TEMPORAL_POLICY_v1',main,fixed=TRUE),
  !grepl("env\\$data",main,fixed=TRUE))
root <- tempfile('weather_inputs_');dir.create(root)
writeLines('site;year;KokMaara;PvmAlku;PvmLoppu;species',file.path(root,'Eiffel_1993_2024.csv'))
writeLines('site;DateN;MeanDailyT;SumDailyP;MeanSnow;Tmin;Tmax',
           file.path(root,'Daily_weather_from_NC_needed_trap_years_and_previous_year.txt'))
# Do not provide environmental files; invalid Greenup path MUST have no effect.
Sys.setenv(EIFFEL_DATA=root,EIFFEL_GREENUP_FILE=file.path(root,'DOES_NOT_EXIST.csv'))
rscript <- file.path(R.home('bin'),'Rscript')
output <- suppressWarnings(system2(rscript,c('--vanilla',script,'--inspect'),
                                   stdout=TRUE,stderr=TRUE))
status <- attr(output,'status')
stopifnot(is.null(status) || identical(as.integer(status),0L),
          any(grepl('STAGE: WEATHER_ONLY_PHASE_1',output,fixed=TRUE)),
          any(grepl('Eiffel_1993_2024.csv present=TRUE',output,fixed=TRUE)),
          any(grepl('Daily_weather_from_NC_needed_trap_years_and_previous_year.txt present=TRUE',
                    output,fixed=TRUE)),
          !any(grepl('DOES_NOT_EXIST|NDVI|environment_',output)))
unlink(root,recursive=TRUE)
cat('PASS: stage-1 inspect works without environmental/Greenup/NDVI files\n')
