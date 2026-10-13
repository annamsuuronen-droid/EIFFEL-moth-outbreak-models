#!/usr/bin/env Rscript
# Exact source duplicates must NOT be counted twice. Recorded overlapping
# trapping dates are retained; neither their counts nor observed zeros vanish.
suppressPackageStartupMessages(library(data.table))
source('R/build_six_species_annual_v3.R',local=TRUE)
td <- tempfile('eiffel_duplicates_overlap_');dir.create(td)
src <- file.path(td,'Eiffel_1993_2024.csv')
raw <- data.table(
  site='1001', year=2023L,
  PvmAlku=c('1.7.2023','1.7.2023','1.7.2023',
            '5.7.2023','5.7.2023','13.7.2023'),
  PvmLoppu=c('8.7.2023','8.7.2023','8.7.2023',
             '12.7.2023','12.7.2023','13.7.2023'),
  KokMaara=c(3L,3L,2L,4L,1L,7L),
  species=c('Epirrita autumnata','Epirrita autumnata',
            'Operophtera brumata','Panolis flammea',
            'Bupalus piniarius','Lymantria monacha'))
fwrite(raw,src,sep=';')
d <- read_catches_deduplicated(src)
stopifnot(d$number_removed==1L,nrow(d$data)==5L,
  nrow(d$duplicates)==1L,d$duplicates$source_csv_row==3L,
  d$duplicates$KokMaara==3L,
  nrow(fread(src,sep=';'))==6L) # source unchanged
built <- build_catches(src)
stopifnot(built$duplicate_source_rows==1L,
 nrow(built$removed_exact_duplicate_rows)==1L,
 nrow(built$overlapping_events)==1L,
 built$overlapping_events$site=='1001',
 sum(built$annual$annual_count)==17,
 built$annual[species=='Epirrita autumnata',annual_count]==3,
 built$annual[species=='Panolis flammea',annual_count]==4,
 built$annual[species=='Bupalus piniarius',annual_count]==1,
 built$annual[species=='Lymantria monacha',annual_count]==7,
 nrow(built$weekly)==3L*6L,
 all(built$annual$counts_reconciled_after_exact_dedup),
 all(is.na(built$annual$response_checked)),
 all(built$weekly$observed_during_trapping),
 all(built$weekly[zero_filled_from_sampled_event==TRUE,count]==0),
 all(is.na(built$annual$effort_days)),
 nrow(fread(src,sep=';'))==6L)
# Two similar but NOT exactly identical source catches must remain separate.
raw2 <- copy(raw);raw2[2,KokMaara:=9L]
fwrite(raw2,src,sep=';')
x <- build_catches(src)
stopifnot(x$duplicate_source_rows==0L,
          x$annual[species=='Epirrita autumnata',annual_count]==12L)
unlink(td,recursive=TRUE)
cat('PASS: exact duplicates removed only from derived counts; overlaps retained; original unchanged\n')
