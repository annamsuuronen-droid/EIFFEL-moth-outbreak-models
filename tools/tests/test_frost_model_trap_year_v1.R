#!/usr/bin/env Rscript
# Synthetic frost source only. Do NOT access EIFFEL datasets or fit Hmsc.
stopifnot(requireNamespace('data.table',quietly=TRUE))
library(data.table)
source('R/frost/FROST_MODEL_TRAP_YEAR_v1.R',local=TRUE)
td <- tempfile('frost_fixture_');dir.create(td)
path <- file.path(td,'cold_sum20_by_trap_year.csv')
annual <- CJ(site=c('1001','1002'),year=2023L,
  species=c('Epirrita autumnata','Operophtera brumata','Operophtera fagata',
            'Lymantria monacha','Bupalus piniarius','Panolis flammea'))
source_data <- data.table(site=c('1001','1002'),year=c(2023L,2023L),
 n_days20=c(2,0),cold_sum20=c(-45,0),
 min_tmin=c(-24,-7),mean_tmin_below20=c(-22.5,NA_real_),
 winter_end_date=c('2023-03-31',NA_character_),
 available_date=c('2023-04-10',NA_character_))
fwrite(source_data,path)
frost <- frost_read_trap_year(path)
stopifnot(nrow(frost)==2L, !anyDuplicated(frost,by=c('site','year')),
 frost[site=='1001',frost_min_tmin]==-24,
 frost[site=='1001',frost_cold_sum20]==-45,
 frost[site=='1001',frost_n_days20]==2,
 frost[site=='1002',frost_cold_sum20]==0)
joined <- frost_for_annual(annual,frost)
stopifnot(nrow(joined)==nrow(annual), !anyDuplicated(joined,by=c('site','year','species')),
 sum(!is.na(joined$frost_cold_sum20))==4L,
 all(is.na(joined[!frost_relevant,frost_min_tmin])),
 joined[site=='1001'&species=='Bupalus piniarius',frost_cold_sum20]==-45)
may <- frost_for_annual(annual,frost,'may01')
june <- frost_for_annual(annual,frost,'jun01')
stopifnot(may[site=='1001'&species=='Panolis flammea',frost_cold_sum20]==-45,
  may[site=='1001'&species=='Panolis flammea',frost_asof_available]==1,
  is.na(may[site=='1002'&species=='Panolis flammea',frost_cold_sum20]),
  is.na(june[site=='1002'&species=='Panolis flammea',frost_min_tmin]))
# Old CSV has NO as-of metadata: retain historical explanatory values, but
# suppress operational forecasts, including May/June.
legacy <- copy(source_data)[,c('available_date','winter_end_date'):=NULL]
fwrite(legacy,path)
old <- frost_read_trap_year(path)
stopifnot(nrow(old)==2L,
  frost_for_annual(annual,old)[site=='1001'&species=='Bupalus piniarius',
                               frost_cold_sum20]==-45,
  is.na(frost_for_annual(annual,old,'may01')[
      site=='1001'&species=='Bupalus piniarius',frost_cold_sum20]))
stopifnot(all(is.na(frost_for_annual(annual,NULL)[frost_relevant,frost_min_tmin])))
# Post-cutoff release / post-cutoff period cannot appear in May 1 predictors.
late <- copy(source_data)
late[site=='1001',available_date:='2023-05-05']
fwrite(late,path)
late_read <- frost_read_trap_year(path)
stopifnot(is.na(frost_for_annual(annual,late_read,'may01')[
    site=='1001'&species=='Bupalus piniarius',frost_cold_sum20]),
    frost_for_annual(annual,late_read,'jun01')[
    site=='1001'&species=='Bupalus piniarius',frost_cold_sum20]==-45)
# Threshold-excess sum -5 rather than negative actual Tmin -45 must fail.
bad <- copy(legacy);bad[1,cold_sum20:=-5]
fwrite(bad,path)
stopifnot(inherits(try(frost_read_trap_year(path),silent=TRUE),'try-error'))
dup <- rbind(legacy,legacy[1]);fwrite(dup,path)
stopifnot(inherits(try(frost_read_trap_year(path),silent=TRUE),'try-error'))
# Original frost field is not aliased from air-temperature frost_days.
stopifnot(!any(c('Tmin','MeanDailyT') %in% names(frost)))
unlink(td,recursive=TRUE)
cat('PASS: frost Tmin negative cold sum, soil-pupa restriction, unique site-years, May/June provenance\n')
