# EIFFEL six-species annual population-history layer, v1.
# Pure base-R transformations. NEVER reads source catches, fits models or selects
# predictors from outer-test outcomes. Use the existing annual builder's output.

population_species_v1 <- c(
  EA = 'Epirrita autumnata', OB = 'Operophtera brumata',
  OF = 'Operophtera fagata', LM = 'Lymantria monacha',
  BP = 'Bupalus piniarius', PF = 'Panolis flammea'
)

population_fail <- function(message) stop(message, call. = FALSE)
population_key <- function(site, year, species) {
  paste(as.character(site), as.character(year), as.character(species), sep = '\035')
}

population_annual_contract <- function(x, require_six_species = TRUE) {
  required <- c('site', 'year', 'species', 'annual_count', 'effort_days',
                'annual_count_per_7d', 'n_sampling_intervals',
                'n_unknown_effort_intervals')
  if (!is.data.frame(x) || !all(required %in% names(x))) {
    population_fail(paste('Annual input contract missing:',
                          paste(setdiff(required, names(x)), collapse = ', ')))
  }
  if (nrow(x) == 0L) population_fail('Annual input has zero rows')
  x$site <- as.character(x$site)
  x$species <- as.character(x$species)
  if (anyNA(x$site) || any(!nzchar(trimws(x$site))) ||
      anyNA(x$species) || any(!nzchar(trimws(x$species))) ||
      any(grepl('\035', x$site, fixed = TRUE))) {
    population_fail('Invalid site/species key')
  }
  if (!is.numeric(x$year) || any(!is.finite(x$year)) ||
      any(x$year != as.integer(x$year)) ||
      any(x$year < 1900 | x$year > 2100)) {
    population_fail('Invalid biological year: use the prebuilt year, never recompute it')
  }
  x$year <- as.integer(x$year)
  if (any(!x$species %in% unname(population_species_v1)) ||
      (require_six_species &&
       !setequal(unique(x$species), unname(population_species_v1)))) {
    population_fail('Species coverage is not the declared six-species contract')
  }
  if (anyDuplicated(population_key(x$site, x$year, x$species))) {
    population_fail('Duplicate site/year/species rows in annual source')
  }
  count <- x$annual_count
  if (!is.numeric(count) || any(!is.finite(count)) ||
      any(count < 0 | count != floor(count))) {
    population_fail('Annual observed counts must be finite nonnegative integers')
  }
  ns <- x$n_sampling_intervals
  nu <- x$n_unknown_effort_intervals
  if (!is.numeric(ns) || !is.numeric(nu) || anyNA(ns) || anyNA(nu) ||
      any(!is.finite(ns) | !is.finite(nu)) ||
      any(ns < 1 | ns != floor(ns)) ||
      any(nu < 0 | nu != floor(nu) | nu > ns)) {
    population_fail('Invalid registered-event or unknown-effort counters')
  }
  if (!is.numeric(x$effort_days) || !is.numeric(x$annual_count_per_7d)) {
    population_fail('Effort and rate must be numeric, including NA for unknown effort')
  }
  known <- nu == 0
  if (any(!is.finite(x$effort_days[known])) ||
      any(x$effort_days[known] <= 0) ||
      any(!is.na(x$effort_days[!known])) ||
      any(!is.na(x$annual_count_per_7d[!known]))) {
    population_fail('Unknown effort must remain NA; known effort must be positive')
  }
  expected <- 7 * count[known] / x$effort_days[known]
  actual <- x$annual_count_per_7d[known]
  if (any(!is.finite(actual)) ||
      any(abs(actual - expected) > 1e-8 * pmax(1, abs(expected)))) {
    population_fail('Stored 7-day rate disagrees with annual count and effort')
  }
  if ('effort_status' %in% names(x)) {
    want <- ifelse(known, 'DATED_EFFORT_COMPLETE',
                   'UNKNOWN_DURATION_RETAIN_ANNUAL_COUNT')
    if (anyNA(x$effort_status) || any(x$effort_status != want)) {
      population_fail('Effort status contradicts unknown-duration indicator')
    }
  }
  x
}

# Historical features use exactly year - k, same site. No nearest-year fill.
# Counts are retained for *audit only*: only normalized lagged rates should be
# offered to a forecasting model (subject to issue-date source availability).
population_make_history <- function(annual, lags = 1:3) {
  x <- population_annual_contract(annual)
  if (!is.numeric(lags) || !length(lags) || anyNA(lags) ||
      any(!is.finite(lags)) || any(lags < 1 | lags != floor(lags)) ||
      anyDuplicated(lags)) population_fail('Lags must be distinct positive whole years')
  lags <- as.integer(lags)
  source_key <- population_key(x$site, x$year, x$species)
  result <- x
  for (lag in lags) {
    for (tag in names(population_species_v1)) {
      driver <- population_species_v1[[tag]]
      prior_key <- population_key(x$site, x$year - lag, driver)
      idx <- match(prior_key, source_key)
      valid <- !is.na(idx)
      count <- rep(NA_real_, nrow(x))
      rate <- rep(NA_real_, nrow(x))
      count[valid] <- x$annual_count[idx[valid]]
      rate[valid] <- x$annual_count_per_7d[idx[valid]]
      prefix <- paste0('lag', lag, '_')
      result[[paste0(prefix, 'count_AUDIT__', tag)]] <- count
      result[[paste0(prefix, 'rate7d__', tag)]] <- rate
      result[[paste0(prefix, 'lograte7d__', tag)]] <- log1p(rate)
    }
  }
  result
}

# Summary reports coverage separately for each target and historical driver.
# The denominator is the target's *usable* response-rate panel, not the union
# of six species. Never mistake matched-panel gains for whole-network gains.
population_lag_coverage <- function(history, lags = 1:3) {
  population_annual_contract(history)
  ans <- vector('list', length(population_species_v1)^2 * length(lags))
  i <- 0L
  for (target in unname(population_species_v1)) {
    response <- history$species == target &
                is.finite(history$annual_count_per_7d)
    for (tag in names(population_species_v1)) {
      for (lag in lags) {
        field <- paste0('lag', lag, '_rate7d__', tag)
        if (!field %in% names(history)) population_fail(paste('Missing:', field))
        i <- i + 1L
        ok <- response & is.finite(history[[field]])
        nt <- sum(response)
        ans[[i]] <- data.frame(
          target_species = target, driver_species = population_species_v1[[tag]],
          lag_years = as.integer(lag), target_usable = nt,
          matched_usable = sum(ok),
          coverage_of_target = if (nt) sum(ok) / nt else NA_real_,
          matched_sites = length(unique(history$site[ok])),
          matched_years = length(unique(history$year[ok])),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  do.call(rbind, ans)
}

# Availability-only panel for variable sets with unequal site/year coverage.
# Pass a single environment variable and ONE buffer at a time; duplicate keys
# are refused. No complete-case restriction is applied to the source annual data.
population_covariate_coverage <- function(annual, covariate, variable,
                                          keys = c('site', 'year')) {
  x <- population_annual_contract(annual)
  if (!is.data.frame(covariate) || length(variable) != 1L ||
      !is.character(variable) || !nzchar(variable) ||
      !variable %in% names(covariate) ||
      !identical(sort(keys), sort(intersect(keys, c('site', 'year', 'species')))) ||
      !all(c('site', 'year') %in% keys) ||
      !all(keys %in% names(covariate))) {
    population_fail('Covariate needs explicit site/year keys and one named value')
  }
  z <- covariate
  z$site <- as.character(z$site)
  if ('species' %in% keys) z$species <- as.character(z$species)
  if (anyNA(z$site) || anyNA(z$year) ||
      ('species' %in% keys && anyNA(z$species))) {
    population_fail('Missing source covariate keys')
  }
  source_key <- do.call(population_key, list(z$site, z$year,
                    if ('species' %in% keys) z$species else '*'))
  if (anyDuplicated(source_key)) {
    population_fail('Duplicate environment keys: select one buffer/source before comparison')
  }
  v <- z[[variable]]
  if (!is.numeric(v)) population_fail('Covariate values must be numeric')
  annual_key <- population_key(x$site, x$year,
                    if ('species' %in% keys) x$species else '*')
  ix <- match(annual_key, source_key)
  available <- rep(FALSE, nrow(x))
  found <- !is.na(ix)
  available[found] <- is.finite(v[ix[found]])
  out <- lapply(unname(population_species_v1), function(s) {
    rows <- x$species == s
    valid_response <- rows & is.finite(x$annual_count_per_7d)
    matched <- valid_response & available
    n <- sum(valid_response)
    data.frame(species = s, variable = variable,
               reference_rate_rows = n,
               matched_rate_rows = sum(matched),
               coverage_of_usable = if (n) sum(matched) / n else NA_real_,
               matched_sites = length(unique(x$site[matched])),
               matched_years = length(unique(x$year[matched])),
               stringsAsFactors = FALSE)
  })
  list(availability = available, summary = do.call(rbind, out))
}

# A high-abundance *candidate* is not a biologically validated outbreak.
# Threshold must never see the outer-test partition. Caller supplies explicit
# training membership; no test labels or features enter the calculation.
population_training_thresholds <- function(annual, is_training,
                                           quantile_probability = 0.75,
                                           min_positive = 10L) {
  x <- population_annual_contract(annual)
  if (!is.logical(is_training) || length(is_training) != nrow(x) ||
      anyNA(is_training) || !is.numeric(quantile_probability) ||
      length(quantile_probability) != 1L ||
      !is.finite(quantile_probability) ||
      quantile_probability <= 0 || quantile_probability >= 1 ||
      length(min_positive) != 1L || !is.numeric(min_positive) ||
      is.na(min_positive) || min_positive < 1 ||
      min_positive != floor(min_positive)) {
    population_fail('Specify explicit training rows, quantile (0,1) and min positives')
  }
  do.call(rbind, lapply(unname(population_species_v1), function(s) {
    r <- x$annual_count_per_7d[is_training & x$species == s]
    valid <- r[is.finite(r)]
    positive <- valid[valid > 0]
    enough <- length(positive) >= min_positive
    data.frame(species = s,
               proposed_high_abundance_candidate =
                 if (enough) as.numeric(stats::quantile(
                   positive, probs = quantile_probability, names = FALSE)) else NA_real_,
               training_usable = length(valid),
               training_positive = length(positive),
               threshold_status = if (enough) 'TRAINING_ONLY_CANDIDATE_NOT_OUTBREAK' else
                 'INSUFFICIENT_TRAINING_POSITIVES',
               stringsAsFactors = FALSE)
  }))
}
