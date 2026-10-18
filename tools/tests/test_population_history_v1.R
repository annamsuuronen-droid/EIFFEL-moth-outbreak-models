#!/usr/bin/env Rscript
# Entirely synthetic population-history/availability/threshold checks.
# Runs under base R only. Never opens protected data or fitted Hmsc objects.
source('R/population_dynamics/POPULATION_HISTORY_v1.R')
checks <- 0L
ok <- function(expr) { stopifnot(isTRUE(expr)); checks <<- checks + 1L }
refuse <- function(expr) {
  caught <- tryCatch({ force(expr); FALSE }, error = function(e) TRUE)
  ok(caught)
}
sp <- unname(population_species_v1)
intervals <- data.frame(site = c(rep('A', 3), rep('B', 2)),
                        year = c(2020L, 2022L, 2023L, 2021L, 2022L),
                        stringsAsFactors = FALSE)
a <- intervals[rep(seq_len(nrow(intervals)), each = length(sp)), ]
a$species <- rep(sp, times = nrow(intervals))
a$annual_count <- as.integer((a$year - 2020L) +
                             match(a$species, sp) - 1L)
a$n_sampling_intervals <- 4L
a$n_unknown_effort_intervals <- 0L
a$effort_days <- 28
a$annual_count_per_7d <- 7 * a$annual_count / 28
a$effort_status <- 'DATED_EFFORT_COMPLETE'
unknown <- (a$site == 'A' & a$year == 2022 & a$species == sp[3]) |
           (a$site == 'B' & a$year == 2021 & a$species == sp[5])
a$n_unknown_effort_intervals[unknown] <- 1L
a$effort_days[unknown] <- NA_real_
a$annual_count_per_7d[unknown] <- NA_real_
a$effort_status[unknown] <- 'UNKNOWN_DURATION_RETAIN_ANNUAL_COUNT'

ok(nrow(population_annual_contract(a)) == 30L)
h <- population_make_history(a)
ok(nrow(h) == nrow(a))
ok(identical(h$site, a$site) && identical(h$year, a$year) &&
   identical(h$species, a$species))
get <- function(site, year, species, column) {
  q <- h[h$site == site & h$year == year & h$species == species, column]
  stopifnot(length(q) == 1L)
  q
}
# 2021 is missing at site A: no nearest-year substitution or zero fill.
ok(is.na(get('A', 2022, sp[2], 'lag1_rate7d__EA')))
ok(get('A', 2022, sp[2], 'lag2_rate7d__EA') == 0)
ok(get('A', 2023, sp[1], 'lag1_rate7d__EA') == 0.5)
ok(is.na(get('A', 2023, sp[1], 'lag2_rate7d__EA')))
ok(get('A', 2023, sp[1], 'lag3_rate7d__EA') == 0)
ok(get('A', 2023, sp[1], 'lag1_count_AUDIT__OF') == 4)
ok(is.na(get('A', 2023, sp[1], 'lag1_rate7d__OF')))
# A stored observed 0 remains 0; an absent source year remains NA.
ok(a$annual_count[a$site == 'A' & a$year == 2020 & a$species == sp[1]] == 0)
ok(get('B', 2022, sp[2], 'lag1_count_AUDIT__BP') == 5)
ok(is.na(get('B', 2022, sp[2], 'lag1_rate7d__BP')))
ok(is.na(get('B', 2021, sp[2], 'lag1_rate7d__EA')))
ok(all(grepl('^lag[123]_', setdiff(names(h), names(a)))))

cov <- population_lag_coverage(h)
ok(nrow(cov) == 6L * 6L * 3L)
t <- cov[cov$target_species == sp[1] &
         cov$driver_species == sp[3] & cov$lag_years == 1, ]
ok(nrow(t) == 1L && t$target_usable == 5L &&
   t$matched_usable == 1L)
ok(all(cov$matched_usable <= cov$target_usable))
ok(all(cov$coverage_of_target >= 0 & cov$coverage_of_target <= 1))

# Sparse source keys: availability only, no restriction to common complete panel.
e <- data.frame(site = c('A', 'A', 'B', 'A'),
                year = c(2020L, 2023L, 2021L, 2022L),
                moisture = c(0.1, 0.2, 0.3, NA_real_))
p <- population_covariate_coverage(a, e, 'moisture')
ok(length(p$availability) == nrow(a))
ok(nrow(p$summary) == 6L && all(p$summary$matched_rate_rows <=
                              p$summary$reference_rate_rows))
pa <- p$summary[p$summary$species == sp[1], ]
ok(pa$reference_rate_rows == 5L && pa$matched_rate_rows == 3L &&
   pa$matched_sites == 2L)
ok(identical(a$annual_count, intervals[rep(seq_len(nrow(intervals)),
                                         each = length(sp)), 'year'] - 2020L +
                            rep(seq_along(sp), nrow(intervals)) - 1L))
refuse(population_covariate_coverage(a, rbind(e, e[1, ]), 'moisture'))
refuse(population_covariate_coverage(a, e, 'missing_feature'))

train <- a$year != 2023L
thr <- population_training_thresholds(a, train, min_positive = 2L)
ok(nrow(thr) == 6L &&
   all(thr$threshold_status == 'TRAINING_ONLY_CANDIDATE_NOT_OUTBREAK'))
test_changed <- a
test_changed$annual_count[!train] <- 100000L
test_changed$annual_count_per_7d[!train] <- 25000
thr_changed <- population_training_thresholds(test_changed, train, min_positive = 2L)
ok(identical(thr$proposed_high_abundance_candidate,
             thr_changed$proposed_high_abundance_candidate))
not_enough <- population_training_thresholds(a, train, min_positive = 99L)
ok(all(is.na(not_enough$proposed_high_abundance_candidate)) &&
   all(not_enough$threshold_status == 'INSUFFICIENT_TRAINING_POSITIVES'))
refuse(population_training_thresholds(a, rep(TRUE, nrow(a) - 1L)))
refuse(population_training_thresholds(a, c(rep(TRUE, nrow(a) - 1L), NA)))
refuse(population_training_thresholds(a, train, quantile_probability = 1))

bad <- a; bad$annual_count[1] <- NA_real_
refuse(population_annual_contract(bad))
bad <- a; bad$annual_count_per_7d[1] <- 25
refuse(population_annual_contract(bad))
bad <- a; bad$effort_days[which(unknown)[1]] <- 28
refuse(population_annual_contract(bad))
bad <- a; bad$effort_days[which(!unknown)[1]] <- 0
refuse(population_annual_contract(bad))
bad <- rbind(a, a[1, ])
refuse(population_annual_contract(bad))
bad <- a; bad$n_sampling_intervals[1] <- 0L
refuse(population_annual_contract(bad))
bad <- a; bad$year[1] <- NA_integer_
refuse(population_annual_contract(bad))
bad <- a; bad$species[1] <- 'Unlisted sp.'
refuse(population_annual_contract(bad))
refuse(population_make_history(a, lags = c(0, 1)))
refuse(population_make_history(a, lags = c(1, 1)))
# Biological year must be used unchanged; winter calendar dates are not rederived.
ok(!'PvmLoppu' %in% names(h) &&
   get('A', 2022, sp[2], 'lag2_rate7d__EA') == 0)
cat('PASS:', checks, 'synthetic-only annual-history, cross-species lag,',
    'missingness, matched coverage and train-only threshold checks; NO models or real data.\n')
