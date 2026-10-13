#!/usr/bin/env Rscript
# Source-row diagnostics for anomalous historic trap intervals; synthetic data.
suppressPackageStartupMessages(library(data.table))
source('R/build_six_species_annual_v3.R',local=TRUE)
td <- tempfile('eiffel_trap_interval_audit_'); dir.create(td)
path <- file.path(td,'Eiffel_1993_2024.csv')
r <- data.table(
  site=c('1001','1001','1001','152','1002'),
  year=2023L,
  PvmAlku=c('01.07.2023','05.07.2023','12.07.2023','01.07.2023','01.07.2023'),
  PvmLoppu=c('08.07.2023','05.07.2023','11.07.2023','01.07.2023','08.07.2023'),
  KokMaara=c(3,2,1,4,2),
  species='Bupalus piniarius')
fwrite(r,path,sep=';')
a <- audit_trap_intervals(path,td)
stopifnot(nrow(a$issues)==3L,a$blocking_count==1L,
  a$unknown_duration_rows==1L,
  a$summary[metric=='zero_duration_retained',value]==1L,
  a$issues[source_csv_row==3L,interval_status]=='ZERO_DURATION',
  a$issues[source_csv_row==4L,interval_status]=='END_BEFORE_START',
  a$issues[source_csv_row==5L,excluded_site_152],
  file.exists(file.path(td,'TRAP_INTERVAL_AUDIT_ISSUES.csv')),
  file.exists(file.path(td,'TRAP_INTERVAL_AUDIT_SUMMARY.csv')))
src <- fread(path,sep=';')
stopifnot(nrow(src)==5L,identical(src$KokMaara,c(3L,2L,1L,4L,2L)))
stopifnot(inherits(try(build_catches(path),silent=TRUE),'try-error'))
# A faulty interval solely at excluded site 152 must not kill the build.
clean <- r[c(1L,4L,5L)]
fwrite(clean,path,sep=';')
a2 <- audit_trap_intervals(path,td)
stopifnot(a2$blocking_count==0L,nrow(a2$issues)==1L,
          a2$issues$excluded_site_152)
b <- build_catches(path)
stopifnot(sum(b$annual$annual_count)==5L,all(b$annual$site!='152'),
          all(b$annual$effort_days==7L))
# Explicit audit mode operates WITHOUT weather/frost, even if frost path wrong.
d <- file.path(td,'input');dir.create(d)
file.copy(path,file.path(d,'Eiffel_1993_2024.csv'))
out <- file.path(td,'runtime');dir.create(out)
Sys.setenv(EIFFEL_DATA=d,EIFFEL_BUILD_OUT=out,
           EIFFEL_FROST_FILE=file.path(td,'ABSENT_FROST.csv'))
rExe <- file.path(R.home('bin'),'Rscript')
lines <- suppressWarnings(system2(rExe,
  c('--vanilla','R/build_six_species_annual_v3.R','--audit'),
  stdout=TRUE,stderr=TRUE))
if(!is.null(attr(lines,'status')) && attr(lines,'status')!=0L) {
  cat(lines,sep='\n')
  stop('Audit mode unexpectedly failed')
}
folders <- list.dirs(out,recursive=FALSE,full.names=TRUE)
stopifnot(length(folders)==1L,
  file.exists(file.path(folders[1],'TRAP_INTERVAL_AUDIT_ISSUES.csv')),
  file.exists(file.path(folders[1],'TRAP_INTERVAL_AUDIT_SUMMARY.csv')),
  !file.exists(file.path(folders[1],'annual_site_species_flight_year.csv')))
# Audit-only mode must still complete when real target sites contain bad dates.
fwrite(r,file.path(d,'Eiffel_1993_2024.csv'),sep=';')
lines_bad <- suppressWarnings(system2(rExe,
  c('--vanilla','R/build_six_species_annual_v3.R','--audit'),
  stdout=TRUE,stderr=TRUE))
stopifnot(is.null(attr(lines_bad,'status')) || attr(lines_bad,'status')==0L,
          any(grepl('blocking intervals REQUIRE MANUAL REVIEW',lines_bad,fixed=TRUE)))
new_folders <- setdiff(list.dirs(out,recursive=FALSE,full.names=TRUE),folders)
stopifnot(length(new_folders)==1L,
  fread(file.path(new_folders[1],'TRAP_INTERVAL_AUDIT_SUMMARY.csv'))[
     metric=='interval_issues_blocking',value]==1L,
  !file.exists(file.path(new_folders[1],'annual_site_species_flight_year.csv')))
unlink(td,recursive=TRUE)
cat('PASS: anomalous trap intervals audited with CSV rows, site 152 exclusion, no date clamping or source changes\n')
