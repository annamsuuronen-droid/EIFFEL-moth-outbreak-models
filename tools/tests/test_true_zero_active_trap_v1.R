#!/usr/bin/env Rscript
# Ecological zero policy: registry lists POSITIVE records, active trapping event
# implies truly observed zero for every absent focal moth species.
suppressPackageStartupMessages(library(data.table))
source('R/build_six_species_annual_v3.R',local=TRUE)
tmp <- tempfile('eiffel_true_zeros_');dir.create(tmp)
file <- file.path(tmp,'Eiffel_1993_2024.csv')
r <- data.table(
 site=c('1001','1001','1001','1002'),
 year=c(2023L,2023L,2023L,2023L),
 PvmAlku=c('1.7.2023','1.7.2023','12.7.2023','1.7.2023'),
 PvmLoppu=c('8.7.2023','8.7.2023','12.7.2023','8.7.2023'),
 species=c('Bupalus piniarius','Panolis flammea',
           'Epirrita autumnata','Lymantria monacha'),
 KokMaara=c(7L,3L,2L,1L))
stopifnot(all(r$KokMaara>0)) # as in the moth record system
fwrite(r,file,sep=';')
x <- build_catches(file)
z <- x$weekly
stopifnot(nrow(z)==3L*6L,all(z$observed_during_trapping),
  sum(z$count)==sum(r$KokMaara),
  all(z$observed_zero==(z$count==0)),
  all(z[zero_filled_from_sampled_event==TRUE,count]==0),
  all(z[zero_filled_from_sampled_event==TRUE,
         observation_origin]=='OBSERVED_ZERO_SPECIES_UNLISTED_DURING_TRAPPING'),
  nrow(z[site=='1001'&start==as.Date('2023-07-01')])==6L,
  nrow(z[site=='1001'&start==as.Date('2023-07-12')])==6L,
  # No invented records for a period when no trapping took place.
  nrow(z[site=='1001'&start==as.Date('2023-07-10')])==0L,
  nrow(z[site=='1002'&start==as.Date('2023-07-12')])==0L,
  z[site=='1001'&start==as.Date('2023-07-12')&
    species=='Panolis flammea',observed_zero],
  z[site=='1001'&start==as.Date('2023-07-12')&
    species=='Bupalus piniarius',observed_zero])
a <- x$annual
stopifnot(!anyNA(a$annual_count),all(a$annual_count>=0),
  a[site=='1001'&species=='Panolis flammea',annual_count]==3,
  a[site=='1001'&species=='Bupalus piniarius',annual_count]==7,
  a[site=='1001'&species=='Lymantria monacha',annual_count]==0,
  a[site=='1001'&species=='Lymantria monacha',n_observed_zero_intervals]==2L,
  a[site=='1001'&species=='Lymantria monacha',
    n_zero_filled_from_sampled_events]==2L,
  all(a$n_observed_zero_intervals ==
      a$n_explicit_zero_intervals + a$n_zero_filled_from_sampled_events),
  all(is.na(a[site=='1001',effort_days])),
  all(!is.na(a[site=='1002',effort_days])))
unlink(tmp,recursive=TRUE,force=TRUE)
cat('PASS: all unlisted study species at ACTIVE trap events are genuine observed zeros; untrapped times have no records\n')
