#!/usr/bin/env Rscript
# Synthetic scientific logic checks; never read or mutate EIFFEL original data.
stopifnot(requireNamespace('data.table',quietly=TRUE))
library(data.table)
source('R/build_six_species_annual_v3.R',local=TRUE)
source('R/ecology/EIFFEL_ECOLOGY_FEATURES_v4.R',local=TRUE)
stopifnot(nrow(ecology_species_registry)==6L,
  all(ecology_species_registry[species %in% c('Bupalus piniarius','Panolis flammea'),
      overwinter_stage]=='soil_pupa'))
yr <- 2023L
lo <- fmt(yr+stage_windows$start_shift,stage_windows$start_md)
hi <- fmt(yr+stage_windows$end_shift,stage_windows$end_md)
stopifnot(all(lo<=hi))
bp <- stage_windows[species=='Bupalus piniarius' & stage=='pupa_winter']
bl <- stage_windows[species=='Bupalus piniarius' & stage=='previous_larva']
stopifnot(fmt(yr+bp$start_shift,bp$start_md)==as.Date('2022-10-01'),
          fmt(yr+bp$end_shift,bp$end_md)==as.Date('2023-04-30'),
          fmt(yr+bl$start_shift,bl$start_md)==as.Date('2022-07-01'),
          fmt(yr+bl$end_shift,bl$end_md)==as.Date('2022-10-31'))
d <- seq(as.Date('2021-01-01'),as.Date('2023-12-31'),by='day')
w <- data.table(site='1001',date=d,MeanDailyT=4,Tmin=-4,Tmax=12,
                SumDailyP=2,MeanSnow=0)
setkey(w,site,date)
annual <- CJ(site='1001',year=2023L,species=cfg$species)
# Verify that 95% coverage cannot silently become a full rainfall total.
w_partial <- copy(w)
w_partial[date==as.Date('2023-04-01'),SumDailyP:=NA_real_]
z <- weather_window(w_partial,'1001',as.Date('2023-01-01'),as.Date('2023-04-30'))
stopifnot(z['available']==1,z['cumulative_stats_complete']==0,
          is.na(z['sum_precipitation']),is.na(z['GDD5']))
# Ecological spring and short rain window are unchanged by future changes.
f <- ecology_weather_by_issue(w,annual)
w2 <- copy(w)
w2[date>=as.Date('2023-05-01'),MeanDailyT:=25]
w2[date>=as.Date('2023-05-01'),SumDailyP:=20]
f2 <- ecology_weather_by_issue(w2,annual)
m1 <- f[issue=='may01']; m2 <- f2[issue=='may01']
stopifnot(identical(m1,m2),
          m1$rain30_complete_mm==60,m1$rain90_complete_mm==180,
          f2[issue=='jun01',rain30_complete_mm]>f[issue=='jun01',rain30_complete_mm])
# Greenup after cutoff or released after cutoff must never enter May forecast.
tmp <- tempfile(fileext='.csv')
fwrite(data.table(site='1001',year=2023L,greenup_doy=110L,
                  available_date='2023-05-15'),tmp)
g <- ecology_greenup(tmp,unique(annual[,.(site,year)]))
may <- ecology_combine_asof(f,g,'may01')
june <- ecology_combine_asof(f,g,'jun01')
stopifnot(nrow(may)==1L,nrow(june)==1L,
          is.na(may$greenup_doy),may$greenup_available_by_issue==0,
          june$greenup_doy==110L,june$greenup_available_by_issue==1)
# Even early publication cannot make a later greenup occurrence predictable.
fwrite(data.table(site='1001',year=2023L,greenup_doy=140L,
                  available_date='2023-04-20'),tmp)
g <- ecology_greenup(tmp,unique(annual[,.(site,year)]))
stopifnot(is.na(ecology_combine_asof(f,g,'may01')$greenup_doy))
# Source without actual release date is not suitable for advance forecasts.
fwrite(data.table(site='1001',year=2023L,greenup_doy=110L),tmp)
stopifnot(inherits(try(ecology_greenup(tmp,unique(annual[,.(site,year)])),
                       silent=TRUE),'try-error'))
unlink(tmp)
# Completed stages must not apply egg survival thresholds to soil pupae.
wx <- weather_features(w,annual)
st <- completed_stages_wide(wx$stage_long,'12-31')
stopifnot(nrow(st)==6L,
  is.na(st[species=='Panolis flammea',stage_pupa_winter_cold_days_minus29_5]),
  is.na(st[species=='Bupalus piniarius',stage_pupa_winter_cold_days_minus37]),
  !is.na(st[species=='Bupalus piniarius',stage_pupa_winter_GDD4_9]))
cat('PASS: ecology v4, six life stages, full daily coverage, no May/June leakage\n')
