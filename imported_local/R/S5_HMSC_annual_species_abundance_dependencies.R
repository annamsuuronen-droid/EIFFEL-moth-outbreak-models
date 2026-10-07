#===============================================================================
# S5: SAME-YEAR AND PREVIOUS-YEAR SPECIES ABUNDANCE EFFECTS
#===============================================================================
# Uses the completed species-specific S4 analysis as the final environmental
# baseline and S3 templates only to recover row-level Y/X/site/year/Loff data.
#
# Tests, for each response species:
#   1) abundance of the OTHER two species in the SAME year
#   2) abundance of the SAME species in the PREVIOUS calendar year (t-1)
#   3) abundance of the OTHER two species in the PREVIOUS calendar year (t-1)
#
# IMPORTANT:
# - same-year effects = contemporaneous conditional associations, not causal
# - lag1 = EXACT previous calendar year at the SAME site
# - no nearest-year substitution
# - abundance predictors are effort-standardized:
#       z(log1p(count / exp(Loff)))
# - species remain separate Hmsc response models; problematic cross-species
#   site-level Omega is not reintroduced.
#===============================================================================

gc()
set.seed(1)

suppressPackageStartupMessages({
  library(Hmsc)
  library(coda)
})

#===============================================================================
# 1. PATHS / SETTINGS
#===============================================================================

hmsc_output_root <- "E:/EIFFEL uusi/hmsc_outputs"

s4_output_dir <- file.path(
  hmsc_output_root,
  "HMSC_ANNUAL_SPECIES_SPECIFIC_FINAL_FITS_v4_INFERENCE_GATE"
)

s4_result_file <- file.path(
  s4_output_dir,
  "results",
  "S4_FINAL_SPECIES_SPECIFIC_RESULTS.rds"
)

s4_complete_file <- file.path(
  s4_output_dir,
  "results",
  "S4_ALL_SPECIES_FINAL_FITS_COMPLETE.txt"
)

s3_output_dir <- file.path(
  hmsc_output_root,
  "HMSC_ANNUAL_SPECIES_SPECIFIC_CALIBRATION_v2_INFERENCE_GATE"
)

s3_result_file <- file.path(
  s3_output_dir,
  "results",
  "S3_SPECIES_CALIBRATION_RESULTS.rds"
)

output_dir <- file.path(
  hmsc_output_root,
  "HMSC_ANNUAL_SPECIES_ABUNDANCE_DEPENDENCIES_v2_RANDOMLEVEL_REBUILT"
)

checkpoint_dir <- file.path(output_dir, "checkpoints")
result_dir <- file.path(output_dir, "results")
dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

reuse_existing_checkpoint <- TRUE
stop_if_complete <- TRUE
maximum_prediction_draws <- 1000L

support_threshold <- 0.95
strong_support_threshold <- 0.975

minimum_samples_per_chain <- 3000L
minimum_transient <- 40000L
minimum_thin <- 20L
n_chains <- 4L
n_parallel <- 4L

# One automatic longer retry if a blocking component fails.
retry_multiplier_samples <- 1.5
retry_multiplier_transient <- 2

# Same inference-gate policy as final one-species S4:
# V is diagnosed and reported, but does not alone block inference.
convergence_rules <- data.frame(
  component = c("Beta", "Gamma", "V", "Rho", "Omega"),
  PSRF_limit = c(1.05, 1.10, 1.10, 1.10, 1.10),
  ESS_limit = c(400, 200, 200, 200, 200),
  blocks_inference = c(TRUE, TRUE, FALSE, TRUE, TRUE),
  stringsAsFactors = FALSE
)

complete_file <- file.path(
  result_dir,
  "S5_SPECIES_ABUNDANCE_DEPENDENCIES_COMPLETE.txt"
)

if (stop_if_complete && file.exists(complete_file)) {
  stop("S5 is already marked complete:\n", complete_file)
}

#===============================================================================
# 2. HELPERS
#===============================================================================

write_csv2 <- function(x, file) {
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  if (ncol(x) == 0L) x <- data.frame(status = "no_rows")
  write.table(
    x, file = file, sep = ";", dec = ",",
    row.names = FALSE, col.names = TRUE,
    quote = TRUE, na = "", fileEncoding = "UTF-8"
  )
}

safe_name <- function(x) gsub("[^A-Za-z0-9_]+", "_", as.character(x))

safe_min <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) min(x) else NA_real_
}

safe_max <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) max(x) else NA_real_
}

safe_median <- function(x) {
  x <- x[is.finite(x)]
  if (length(x)) median(x) else NA_real_
}

z_scale <- function(x) {
  mu <- mean(x, na.rm = TRUE)
  ss <- sd(x, na.rm = TRUE)
  if (!is.finite(ss) || ss <= 0) stop("Cannot standardize predictor.")
  (x - mu) / ss
}

has_posterior <- function(model) {
  !is.null(model$postList) &&
    length(model$postList) >= 2L &&
    all(vapply(model$postList, length, integer(1)) > 0L)
}

make_formula <- function(variable_names) {
  reformulate(variable_names, intercept = TRUE)
}


#-------------------------------------------------------------------------------
# Rebuild random levels after subsetting rows
#-------------------------------------------------------------------------------
#
# Do NOT reuse HmscRandomLevel objects from the full S3/S4 dataset after
# lag1 matching has removed rows. Their internal unit indexing belongs to the
# original study design and can cause:
#
#   Eta[[r]][hM$Pi[, r], ] : subscript out of bounds
#
rebuild_random_levels <- function(
    study_design,
    site_nf_min = 1L,
    site_nf_max = 1L,
    year_nf_min = 1L,
    year_nf_max = 1L
) {
  if (!all(c("site", "year") %in% colnames(study_design))) {
    stop("studyDesign must contain site and year.")
  }

  study_design <- as.data.frame(
    study_design,
    stringsAsFactors = FALSE
  )

  study_design$site <- factor(
    as.character(study_design$site)
  )

  study_design$year <- factor(
    as.character(study_design$year)
  )

  if (anyNA(study_design$site) || anyNA(study_design$year)) {
    stop("NA in subsetted site/year studyDesign.")
  }

  site_rl <- HmscRandomLevel(
    units = study_design$site
  )

  year_rl <- HmscRandomLevel(
    units = study_design$year
  )

  site_rl <- setPriors(
    site_rl,
    nfMin = site_nf_min,
    nfMax = site_nf_max
  )

  year_rl <- setPriors(
    year_rl,
    nfMin = year_nf_min,
    nfMax = year_nf_max
  )

  list(
    studyDesign = study_design,
    ranLevels = list(
      site = site_rl,
      year = year_rl
    )
  )
}

#-------------------------------------------------------------------------------
# Convergence diagnostics
#-------------------------------------------------------------------------------

diagnose_component <- function(x, component, random_level = NA_character_) {
  if (is.null(x) || !inherits(x, "mcmc.list")) return(NULL)

  parameter <- colnames(as.matrix(x[[1]]))
  if (is.null(parameter)) {
    parameter <- paste0("parameter_", seq_len(ncol(x[[1]])))
  }

  ess <- tryCatch(effectiveSize(x), error = function(e) NULL)
  psrf <- tryCatch(
    gelman.diag(x, multivariate = FALSE, autoburnin = FALSE)$psrf,
    error = function(e) NULL
  )

  out <- data.frame(
    component = component,
    random_level = random_level,
    parameter = parameter,
    PSRF_point = NA_real_,
    PSRF_upper = NA_real_,
    ESS = NA_real_,
    stringsAsFactors = FALSE
  )

  if (!is.null(psrf)) {
    rn <- rownames(psrf)
    if (is.null(rn)) rn <- parameter
    hit <- match(parameter, rn)
    out$PSRF_point <- psrf[hit, 1]
    out$PSRF_upper <- psrf[hit, min(2L, ncol(psrf))]
  }

  if (!is.null(ess)) {
    if (is.null(names(ess)) && length(ess) == nrow(out)) {
      out$ESS <- as.numeric(ess)
    } else {
      out$ESS <- as.numeric(ess[match(parameter, names(ess))])
    }
  }

  out
}

diagnose_model <- function(model, species, model_name) {
  mpost <- convertToCodaObject(
    model,
    spNamesNumbers = c(TRUE, FALSE),
    covNamesNumbers = c(TRUE, FALSE)
  )

  pieces <- list()

  for (component in c("Beta", "Gamma", "V", "Rho")) {
    if (!is.null(mpost[[component]])) {
      pieces[[length(pieces) + 1L]] <-
        diagnose_component(mpost[[component]], component)
    }
  }

  if (!is.null(mpost$Omega)) {
    random_names <- names(model$ranLevels)
    for (r in seq_along(mpost$Omega)) {
      pieces[[length(pieces) + 1L]] <-
        diagnose_component(mpost$Omega[[r]], "Omega", random_names[r])
    }
  }

  detailed <- do.call(rbind, Filter(Negate(is.null), pieces))
  if (is.null(detailed) || !nrow(detailed)) {
    stop(species, " / ", model_name, ": no convergence diagnostics.")
  }

  detailed$species <- species
  detailed$model <- model_name

  rule_id <- match(detailed$component, convergence_rules$component)
  if (anyNA(rule_id)) stop("Undefined convergence component.")

  detailed$PSRF_limit <- convergence_rules$PSRF_limit[rule_id]
  detailed$ESS_limit <- convergence_rules$ESS_limit[rule_id]
  detailed$blocks_inference <- convergence_rules$blocks_inference[rule_id]
  detailed$diagnostic_accepted <-
    is.finite(detailed$PSRF_upper) &
    is.finite(detailed$ESS) &
    detailed$PSRF_upper <= detailed$PSRF_limit &
    detailed$ESS >= detailed$ESS_limit
  detailed$accepted_parameter <-
    !detailed$blocks_inference | detailed$diagnostic_accepted

  key <- interaction(
    detailed$component,
    ifelse(is.na(detailed$random_level), "", detailed$random_level),
    drop = TRUE
  )

  summary <- do.call(rbind, lapply(split(detailed, key), function(z) {
    rule <- convergence_rules[
      convergence_rules$component == z$component[1], , drop = FALSE
    ]
    max_psrf <- safe_max(z$PSRF_upper)
    min_ess <- safe_min(z$ESS)
    diagnostic_ok <-
      is.finite(max_psrf) && is.finite(min_ess) &&
      max_psrf <= rule$PSRF_limit[1] &&
      min_ess >= rule$ESS_limit[1]

    data.frame(
      species = species,
      model = model_name,
      component = z$component[1],
      random_level = z$random_level[1],
      n_parameters = nrow(z),
      maximum_PSRF_upper = max_psrf,
      median_PSRF_upper = safe_median(z$PSRF_upper),
      minimum_ESS = min_ess,
      median_ESS = safe_median(z$ESS),
      PSRF_limit = rule$PSRF_limit[1],
      ESS_limit = rule$ESS_limit[1],
      blocks_inference = rule$blocks_inference[1],
      diagnostic_accepted = diagnostic_ok,
      accepted = !rule$blocks_inference[1] | diagnostic_ok,
      stringsAsFactors = FALSE
    )
  }))
  rownames(summary) <- NULL

  list(
    detailed = detailed,
    summary = summary,
    accepted = all(summary$accepted)
  )
}

#-------------------------------------------------------------------------------
# Fit model with one retry if blocking convergence fails
#-------------------------------------------------------------------------------

fit_hmsc_checked <- function(model_template, species, model_name, settings) {
  attempts <- list(
    initial = settings,
    retry = list(
      samples = as.integer(ceiling(settings$samples * retry_multiplier_samples)),
      transient = as.integer(ceiling(settings$transient * retry_multiplier_transient)),
      thin = settings$thin,
      chains = settings$chains,
      parallel = settings$parallel,
      seed = settings$seed + 10000L
    )
  )

  for (attempt_name in names(attempts)) {
    s <- attempts[[attempt_name]]

    checkpoint_file <- file.path(
      checkpoint_dir,
      paste0(
        safe_name(species), "__", model_name, "__", attempt_name,
        "__samples_", s$samples,
        "__transient_", s$transient,
        "__thin_", s$thin,
        "__chains_", s$chains,
        ".RData"
      )
    )

    if (reuse_existing_checkpoint && file.exists(checkpoint_file)) {
      e <- new.env(parent = globalenv())
      loaded <- load(checkpoint_file, envir = e)
      if (!"fitted_model" %in% loaded) {
        stop("Incomplete checkpoint: ", checkpoint_file)
      }
      fitted_model <- get("fitted_model", envir = e)
      elapsed_hours <- if (exists("elapsed_hours", envir = e, inherits = FALSE)) {
        get("elapsed_hours", envir = e)
      } else NA_real_
      rm(e)
    } else {
      set.seed(s$seed)
      start_time <- Sys.time()

      fitted_model <- sampleMcmc(
        model_template,
        samples = s$samples,
        transient = s$transient,
        thin = s$thin,
        nChains = s$chains,
        nParallel = s$parallel,
        verbose = 100
      )

      elapsed_hours <- as.numeric(
        difftime(Sys.time(), start_time, units = "hours")
      )

      partial <- paste0(checkpoint_file, ".partial")
      save(
        fitted_model, s, species, model_name, elapsed_hours,
        file = partial
      )
      if (!file.rename(partial, checkpoint_file)) {
        stop("Could not finalize checkpoint.")
      }
    }

    if (!has_posterior(fitted_model)) {
      stop(species, " / ", model_name, ": posterior missing.")
    }

    diagnostics <- diagnose_model(fitted_model, species, model_name)

    write_csv2(
      diagnostics$detailed,
      file.path(
        result_dir,
        paste0(
          safe_name(species), "__", model_name, "__", attempt_name,
          "__convergence_detailed.csv2"
        )
      )
    )

    write_csv2(
      diagnostics$summary,
      file.path(
        result_dir,
        paste0(
          safe_name(species), "__", model_name, "__", attempt_name,
          "__convergence_summary.csv2"
        )
      )
    )

    if (diagnostics$accepted) {
      return(list(
        model = fitted_model,
        diagnostics = diagnostics,
        settings = s,
        attempt = attempt_name,
        elapsed_hours = elapsed_hours,
        checkpoint_file = checkpoint_file
      ))
    }

    if (attempt_name == "initial") {
      cat("\n", species, " / ", model_name,
          ": blocking convergence failed -> longer retry.\n", sep = "")
    }
  }

  stop(species, " / ", model_name,
       ": blocking convergence failed after retry.")
}

#-------------------------------------------------------------------------------
# Robust one-species Beta posterior extraction
#-------------------------------------------------------------------------------

beta_table_one_species <- function(model, species, model_name) {
  post_beta <- getPostEstimate(
    model, "Beta", q = c(0.025, 0.5, 0.975)
  )

  beta_q <- if (!is.null(post_beta$q) && length(post_beta$q) > 0L) {
    post_beta$q
  } else {
    stop(species, " / ", model_name, ": Beta quantiles missing.")
  }

  beta_mean <- post_beta$mean
  if (is.null(dim(beta_mean))) beta_mean <- matrix(as.numeric(beta_mean), ncol = 1L)
  if (nrow(beta_mean) == 1L && ncol(beta_mean) > 1L) beta_mean <- t(beta_mean)
  if (is.null(rownames(beta_mean))) rownames(beta_mean) <- model$covNames
  if (is.null(colnames(beta_mean))) colnames(beta_mean) <- species

  n_beta <- length(beta_mean)
  dq <- dim(beta_q)

  get_q <- function(index) {
    if (is.null(dq)) {
      if (n_beta == 1L && length(beta_q) == 3L) return(as.numeric(beta_q[index]))
      stop("Unexpected Beta q vector.")
    }

    if (length(dq) == 2L) {
      if (dq[1] == n_beta && dq[2] >= 3L) return(as.numeric(beta_q[, index]))
      if (dq[2] == n_beta && dq[1] >= 3L) return(as.numeric(beta_q[index, ]))
      stop("Unexpected Beta q dimensions: ", paste(dq, collapse = " x "))
    }

    if (length(dq) == 3L) {
      if (dq[1] >= 3L && prod(dq[2:3]) == n_beta) {
        return(as.numeric(beta_q[index, , , drop = TRUE]))
      }
      if (dq[3] >= 3L && prod(dq[1:2]) == n_beta) {
        return(as.numeric(beta_q[, , index, drop = TRUE]))
      }
      if (dq[2] >= 3L && dq[1] * dq[3] == n_beta) {
        return(as.numeric(beta_q[, index, , drop = TRUE]))
      }
    }

    stop("Unsupported Beta q structure.")
  }

  out <- data.frame(
    species = species,
    model = model_name,
    predictor = rownames(beta_mean),
    posterior_mean = as.numeric(beta_mean),
    lower_95_CI = get_q(1L),
    posterior_median = get_q(2L),
    upper_95_CI = get_q(3L),
    support_positive = as.numeric(post_beta$support),
    support_negative = as.numeric(post_beta$supportNeg),
    stringsAsFactors = FALSE
  )

  out$posterior_support <- pmax(out$support_positive, out$support_negative)
  out$direction <- ifelse(
    out$posterior_mean > 0, "positive",
    ifelse(out$posterior_mean < 0, "negative", "zero")
  )
  out
}

#-------------------------------------------------------------------------------
# Explanatory fit with explicit offset
#-------------------------------------------------------------------------------

prediction_posterior <- function(model, maximum_draws) {
  total_draws <- sum(vapply(model$postList, length, integer(1)))
  posterior_thin <- max(1L, ceiling(total_draws / maximum_draws))

  post <- poolMcmcChains(
    model$postList,
    start = 1L,
    thin = posterior_thin
  )

  if (length(post) > maximum_draws) {
    keep <- unique(round(seq(1, length(post), length.out = maximum_draws)))
    post <- post[keep]
  }

  post
}

evaluate_explanatory_fit <- function(model, species, model_name, seed) {
  post <- prediction_posterior(model, maximum_prediction_draws)
  set.seed(seed)

  pred <- simplify2array(
    predict(
      model,
      post = post,
      Loff = model$Loff,
      expected = TRUE,
      nParallel = 1L
    )
  )

  fit <- evaluateModelFit(hM = model, predY = pred)

  out <- data.frame(
    species = species,
    model = model_name,
    stringsAsFactors = FALSE
  )

  for (metric in names(fit)) {
    value <- fit[[metric]]
    if (is.atomic(value) && length(value) == 1L) {
      out[[metric]] <- as.numeric(value)
    }
  }

  out
}

#===============================================================================
# 3. LOAD COMPLETED S4 + S3 RESULTS
#===============================================================================

if (!file.exists(s4_complete_file)) {
  stop("S4 is not marked complete:\n", s4_complete_file)
}
if (!file.exists(s4_result_file)) stop("S4 result missing: ", s4_result_file)
if (!file.exists(s3_result_file)) stop("S3 result missing: ", s3_result_file)

S4 <- readRDS(s4_result_file)
S3 <- readRDS(s3_result_file)

required_s4 <- c(
  "target_species",
  "locked_weather_variables",
  "selected_environment_variables",
  "variables_kept",
  "offset_prediction_used"
)

missing_s4 <- setdiff(required_s4, names(S4))
if (length(missing_s4)) {
  stop("S4 result missing: ", paste(missing_s4, collapse = ", "))
}

if (!isTRUE(S4$offset_prediction_used)) {
  stop("S4 is not marked offset-corrected.")
}

target_species <- as.character(S4$target_species)
if (length(target_species) != 3L) stop("Expected exactly three target species.")

locked_weather_variables <- as.character(S4$locked_weather_variables)
selected_environment_variables <- as.character(S4$selected_environment_variables)
variables_kept <- as.character(S4$variables_kept)

if (!all(target_species %in% names(S3$template_files))) {
  stop("S3 templates do not cover all S4 target species.")
}

#===============================================================================
# 4. LOAD SPECIES TEMPLATES AND VERIFY ROW ALIGNMENT
#===============================================================================

templates <- setNames(vector("list", length(target_species)), target_species)

for (species in target_species) {
  template_file <- unname(S3$template_files[[species]])
  if (!file.exists(template_file)) {
    stop(species, ": template missing: ", template_file)
  }

  template <- readRDS(template_file)
  if (!inherits(template, "Hmsc")) stop(species, ": template is not Hmsc.")
  if (ncol(template$Y) != 1L) stop(species, ": expected one response species.")
  if (is.null(template$Loff)) stop(species, ": Loff missing.")

  templates[[species]] <- template
}

reference_species <- target_species[1]
reference_model <- templates[[reference_species]]
reference_study <- reference_model$studyDesign

if (!all(c("site", "year") %in% colnames(reference_study))) {
  stop("studyDesign must contain site and year.")
}

n_rows <- nrow(reference_model$Y)

for (species in target_species[-1]) {
  m <- templates[[species]]
  if (nrow(m$Y) != n_rows) stop(species, ": row count differs.")
  if (!identical(as.character(m$studyDesign$site), as.character(reference_study$site))) {
    stop(species, ": site ordering differs.")
  }
  if (!identical(as.character(m$studyDesign$year), as.character(reference_study$year))) {
    stop(species, ": year ordering differs.")
  }
}

#===============================================================================
# 5. EFFORT-STANDARDIZED ABUNDANCE + EXACT t-1 MATCHING
#===============================================================================

abundance <- data.frame(
  row_id = seq_len(n_rows),
  site = as.character(reference_study$site),
  year = as.integer(as.character(reference_study$year)),
  stringsAsFactors = FALSE
)

if (anyNA(abundance$year)) stop("Could not convert year to integer.")

site_year_key <- paste(abundance$site, abundance$year, sep = "||")
if (anyDuplicated(site_year_key)) {
  stop("Duplicate site-year rows found; lag1 requires one annual row per site-year.")
}

species_short <- setNames(safe_name(target_species), target_species)

for (species in target_species) {
  m <- templates[[species]]
  count <- as.numeric(m$Y[, 1])
  effort_units <- exp(as.numeric(m$Loff[, 1]))

  if (any(!is.finite(effort_units)) || any(effort_units <= 0)) {
    stop(species, ": invalid effort from Loff.")
  }

  rate <- count / effort_units
  nm <- species_short[species]

  abundance[[paste0("count__", nm)]] <- count
  abundance[[paste0("rate__", nm)]] <- rate
  abundance[[paste0("lograte__", nm)]] <- log1p(rate)
}

previous_key <- paste(abundance$site, abundance$year - 1L, sep = "||")
lag_index <- match(previous_key, site_year_key)
abundance$lag1_row_id <- lag_index

for (species in target_species) {
  nm <- species_short[species]
  current <- abundance[[paste0("lograte__", nm)]]
  lagged <- rep(NA_real_, n_rows)
  ok <- !is.na(lag_index)
  lagged[ok] <- current[lag_index[ok]]
  abundance[[paste0("lag1_lograte__", nm)]] <- lagged
}

write_csv2(
  abundance,
  file.path(result_dir, "S5_abundance_and_exact_lag1_table.csv2")
)

#===============================================================================
# 6. FIT MATCHED BASELINE + FULL DYNAMIC MODEL FOR EACH RESPONSE SPECIES
#===============================================================================

species_results <- setNames(vector("list", length(target_species)), target_species)
all_dynamic_beta <- list()
all_beta <- list()
all_fit <- list()
all_vp <- list()
all_convergence <- list()
sample_summary <- list()

for (response_species in target_species) {
  cat("\n========================================================\n")
  cat("S5 RESPONSE SPECIES: ", response_species, "\n", sep = "")
  cat("========================================================\n")

  response_model <- templates[[response_species]]
  other_species <- setdiff(target_species, response_species)
  response_short <- species_short[response_species]

  same_year_names <- paste0("sameyr_other__", species_short[other_species])
  lag1_own_name <- paste0("lag1_own__", response_short)
  lag1_other_names <- paste0("lag1_other__", species_short[other_species])
  dynamic_names <- c(same_year_names, lag1_own_name, lag1_other_names)

  X_full <- as.data.frame(response_model$XData, stringsAsFactors = FALSE)

  if (!all(variables_kept %in% colnames(X_full))) {
    stop(
      response_species,
      ": environmental variables missing from XData: ",
      paste(setdiff(variables_kept, colnames(X_full)), collapse = ", ")
    )
  }

  # Same-year OTHER species.
  for (i in seq_along(other_species)) {
    sp <- other_species[i]
    X_full[[same_year_names[i]]] <- z_scale(
      abundance[[paste0("lograte__", species_short[sp])]]
    )
  }

  # Exact previous-year OWN species.
  X_full[[lag1_own_name]] <- z_scale(
    abundance[[paste0("lag1_lograte__", response_short)]]
  )

  # Exact previous-year OTHER species.
  for (i in seq_along(other_species)) {
    sp <- other_species[i]
    X_full[[lag1_other_names[i]]] <- z_scale(
      abundance[[paste0("lag1_lograte__", species_short[sp])]]
    )
  }

  required_columns <- c(variables_kept, dynamic_names)

  matched_rows <- complete.cases(X_full[, required_columns, drop = FALSE]) &
    is.finite(as.numeric(response_model$Y[, 1])) &
    is.finite(as.numeric(response_model$Loff[, 1]))

  n_matched <- sum(matched_rows)
  if (n_matched < 100L) {
    stop(response_species, ": fewer than 100 matched rows: ", n_matched)
  }

  sample_summary[[response_species]] <- data.frame(
    species = response_species,
    n_original = nrow(response_model$Y),
    n_with_exact_previous_year = sum(!is.na(lag_index)),
    n_matched_dynamic = n_matched,
    proportion_retained = n_matched / nrow(response_model$Y),
    stringsAsFactors = FALSE
  )

  Y_sub <- response_model$Y[matched_rows, , drop = FALSE]
  Loff_sub <- response_model$Loff[matched_rows, , drop = FALSE]

  study_sub_raw <- response_model$studyDesign[
    matched_rows,
    ,
    drop = FALSE
  ]

  # CRITICAL FIX:
  # Build fresh site/year random levels for the matched lag1 subset.
  rebuilt_random <- rebuild_random_levels(
    study_design = study_sub_raw,
    site_nf_min = 1L,
    site_nf_max = 1L,
    year_nf_min = 1L,
    year_nf_max = 1L
  )

  study_sub <- rebuilt_random$studyDesign
  ran_sub <- rebuilt_random$ranLevels

  if (
    nrow(study_sub) != nrow(Y_sub) ||
    nrow(study_sub) != nrow(Loff_sub)
  ) {
    stop(
      response_species,
      ": row mismatch after rebuilding random levels."
    )
  }

  random_level_summary <- data.frame(
    species = response_species,
    n_rows = nrow(study_sub),
    n_sites = nlevels(study_sub$site),
    n_years = nlevels(study_sub$year),
    site_nfMin = ran_sub$site$nfMin,
    site_nfMax = ran_sub$site$nfMax,
    year_nfMin = ran_sub$year$nfMin,
    year_nfMax = ran_sub$year$nfMax,
    stringsAsFactors = FALSE
  )

  write_csv2(
    random_level_summary,
    file.path(
      result_dir,
      paste0(
        safe_name(response_species),
        "__S5_random_level_structure.csv2"
      )
    )
  )

  X_baseline <- X_full[matched_rows, variables_kept, drop = FALSE]
  X_dynamic <- X_full[matched_rows, c(variables_kept, dynamic_names), drop = FALSE]

  baseline_template <- Hmsc(
    Y = Y_sub,
    distr = response_model$distr,
    Loff = Loff_sub,
    XData = X_baseline,
    XScale = FALSE,
    YScale = FALSE,
    XFormula = make_formula(variables_kept),
    studyDesign = study_sub,
    ranLevels = ran_sub
  )

  full_template <- Hmsc(
    Y = Y_sub,
    distr = response_model$distr,
    Loff = Loff_sub,
    XData = X_dynamic,
    XScale = FALSE,
    YScale = FALSE,
    XFormula = make_formula(c(variables_kept, dynamic_names)),
    studyDesign = study_sub,
    ranLevels = ran_sub
  )

  inherited <- S3$species_final_settings[[response_species]]

  initial_settings <- list(
    samples = max(minimum_samples_per_chain, as.integer(inherited$samples)),
    transient = max(minimum_transient, as.integer(inherited$transient)),
    thin = max(minimum_thin, as.integer(inherited$thin)),
    chains = n_chains,
    parallel = n_parallel,
    seed = 13001L + 100L * match(response_species, target_species)
  )

  baseline_fit <- fit_hmsc_checked(
    baseline_template,
    response_species,
    "BASELINE_MATCHED",
    initial_settings
  )

  dynamic_fit <- fit_hmsc_checked(
    full_template,
    response_species,
    "FULL_DYNAMIC",
    initial_settings
  )

  beta_dynamic <- beta_table_one_species(
    dynamic_fit$model,
    response_species,
    "FULL_DYNAMIC"
  )

  beta_dynamic$effect_type <- "environment"
  beta_dynamic$effect_type[beta_dynamic$predictor %in% same_year_names] <-
    "same_year_other_species"
  beta_dynamic$effect_type[beta_dynamic$predictor == lag1_own_name] <-
    "lag1_own_species"
  beta_dynamic$effect_type[beta_dynamic$predictor %in% lag1_other_names] <-
    "lag1_other_species"

  beta_dynamic$source_species <- NA_character_

  for (i in seq_along(other_species)) {
    beta_dynamic$source_species[
      beta_dynamic$predictor == same_year_names[i]
    ] <- other_species[i]

    beta_dynamic$source_species[
      beta_dynamic$predictor == lag1_other_names[i]
    ] <- other_species[i]
  }

  beta_dynamic$source_species[
    beta_dynamic$predictor == lag1_own_name
  ] <- response_species

  beta_dynamic$temporal_relation <- ifelse(
    beta_dynamic$effect_type == "same_year_other_species",
    "same_year",
    ifelse(
      beta_dynamic$effect_type %in% c("lag1_own_species", "lag1_other_species"),
      "previous_year",
      "environment"
    )
  )

  beta_dynamic$interpretation <- ifelse(
    beta_dynamic$effect_type == "same_year_other_species",
    "contemporaneous association; not causal",
    ifelse(
      beta_dynamic$effect_type == "lag1_own_species",
      "within-species previous-year association",
      ifelse(
        beta_dynamic$effect_type == "lag1_other_species",
        "cross-species previous-year association",
        "locked environmental predictor"
      )
    )
  )

  dynamic_effects <- beta_dynamic[
    beta_dynamic$effect_type != "environment" &
      beta_dynamic$predictor != "(Intercept)",
    , drop = FALSE
  ]

  dynamic_effects$supported_95 <-
    dynamic_effects$posterior_support >= support_threshold
  dynamic_effects$strongly_supported_975 <-
    dynamic_effects$posterior_support >= strong_support_threshold

  all_beta[[response_species]] <- beta_dynamic
  all_dynamic_beta[[response_species]] <- dynamic_effects

  fit_baseline <- evaluate_explanatory_fit(
    baseline_fit$model,
    response_species,
    "BASELINE_MATCHED",
    14001L + 100L * match(response_species, target_species)
  )

  fit_dynamic <- evaluate_explanatory_fit(
    dynamic_fit$model,
    response_species,
    "FULL_DYNAMIC",
    15001L + 100L * match(response_species, target_species)
  )

  fit_pair <- rbind(fit_baseline, fit_dynamic)

  metric_value <- function(table, model_name, metric) {
    if (!metric %in% names(table)) return(NA_real_)
    as.numeric(table[table$model == model_name, metric][1])
  }

  comparison <- data.frame(
    species = response_species,
    n_matched = n_matched,
    baseline_SR2 = metric_value(fit_pair, "BASELINE_MATCHED", "SR2"),
    dynamic_SR2 = metric_value(fit_pair, "FULL_DYNAMIC", "SR2"),
    delta_SR2 =
      metric_value(fit_pair, "FULL_DYNAMIC", "SR2") -
      metric_value(fit_pair, "BASELINE_MATCHED", "SR2"),
    baseline_RMSE = metric_value(fit_pair, "BASELINE_MATCHED", "RMSE"),
    dynamic_RMSE = metric_value(fit_pair, "FULL_DYNAMIC", "RMSE"),
    delta_RMSE =
      metric_value(fit_pair, "FULL_DYNAMIC", "RMSE") -
      metric_value(fit_pair, "BASELINE_MATCHED", "RMSE"),
    stringsAsFactors = FALSE
  )

  all_fit[[response_species]] <- list(fit = fit_pair, comparison = comparison)

  # Variance partitioning of dynamic model.
  covariates <- dynamic_fit$model$covNames
  vp_labels <- rep(NA_character_, length(covariates))
  vp_labels[covariates %in% c("(Intercept)", "Intercept")] <- "Intercept"
  vp_labels[covariates %in% variables_kept] <- "environment_weather"
  vp_labels[covariates %in% same_year_names] <- "same_year_other_species"
  vp_labels[covariates == lag1_own_name] <- "lag1_own_species"
  vp_labels[covariates %in% lag1_other_names] <- "lag1_other_species"

  if (anyNA(vp_labels)) {
    stop(
      response_species,
      ": VP labels missing for: ",
      paste(covariates[is.na(vp_labels)], collapse = ", ")
    )
  }

  vp_group_names <- unique(vp_labels)
  vp_group <- match(vp_labels, vp_group_names)

  vp_result <- computeVariancePartitioning(
    dynamic_fit$model,
    group = vp_group,
    groupnames = vp_group_names
  )

  vp <- as.matrix(vp_result$vals)

  if (nrow(vp) == 1L) {
    vp_values <- as.numeric(vp[1, ])
    vp_names <- colnames(vp)
  } else if (ncol(vp) == 1L) {
    vp_values <- as.numeric(vp[, 1])
    vp_names <- rownames(vp)
  } else {
    stop(response_species, ": unexpected VP dimensions.")
  }

  vp_table <- data.frame(
    species = response_species,
    variance_group = vp_names,
    variance_proportion = vp_values,
    variance_percent = 100 * vp_values,
    stringsAsFactors = FALSE
  )

  all_vp[[response_species]] <- vp_table

  convergence_species <- rbind(
    baseline_fit$diagnostics$summary,
    dynamic_fit$diagnostics$summary
  )
  all_convergence[[response_species]] <- convergence_species

  write_csv2(
    dynamic_effects,
    file.path(
      result_dir,
      paste0(safe_name(response_species), "__S5_dynamic_abundance_effects.csv2")
    )
  )

  write_csv2(
    comparison,
    file.path(
      result_dir,
      paste0(safe_name(response_species), "__S5_model_comparison.csv2")
    )
  )

  write_csv2(
    vp_table,
    file.path(
      result_dir,
      paste0(safe_name(response_species), "__S5_variance_partitioning.csv2")
    )
  )

  species_results[[response_species]] <- list(
    matched_rows = which(matched_rows),
    dynamic_predictors = dynamic_names,
    same_year_predictors = same_year_names,
    lag1_own_predictor = lag1_own_name,
    lag1_other_predictors = lag1_other_names,
    baseline_fit = baseline_fit,
    dynamic_fit = dynamic_fit,
    beta_dynamic = beta_dynamic,
    dynamic_effects = dynamic_effects,
    model_comparison = comparison,
    variance_partitioning = vp_table
  )

  rm(baseline_template, full_template, baseline_fit, dynamic_fit)
  gc()
}

#===============================================================================
# 7. COMBINED RESULTS
#===============================================================================

sample_summary_all <- do.call(rbind, sample_summary)
dynamic_effects_all <- do.call(rbind, all_dynamic_beta)
beta_all <- do.call(rbind, all_beta)
fit_all <- do.call(rbind, lapply(all_fit, function(x) x$fit))
comparison_all <- do.call(rbind, lapply(all_fit, function(x) x$comparison))
vp_all <- do.call(rbind, all_vp)
convergence_all <- do.call(rbind, all_convergence)

rownames(sample_summary_all) <- NULL
rownames(dynamic_effects_all) <- NULL
rownames(beta_all) <- NULL
rownames(fit_all) <- NULL
rownames(comparison_all) <- NULL
rownames(vp_all) <- NULL
rownames(convergence_all) <- NULL

interaction_summary <- dynamic_effects_all[
  , c(
    "species",
    "source_species",
    "effect_type",
    "temporal_relation",
    "posterior_mean",
    "lower_95_CI",
    "upper_95_CI",
    "posterior_support",
    "direction",
    "supported_95",
    "strongly_supported_975",
    "interpretation"
  ),
  drop = FALSE
]
names(interaction_summary)[names(interaction_summary) == "species"] <-
  "response_species"

write_csv2(sample_summary_all, file.path(result_dir, "S5_sample_summary.csv2"))
write_csv2(
  dynamic_effects_all,
  file.path(result_dir, "S5_ALL_SPECIES_dynamic_abundance_effects.csv2")
)
write_csv2(
  interaction_summary,
  file.path(result_dir, "S5_DIRECTIONAL_SPECIES_RELATIONSHIPS.csv2")
)
write_csv2(beta_all, file.path(result_dir, "S5_ALL_SPECIES_full_dynamic_beta.csv2"))
write_csv2(fit_all, file.path(result_dir, "S5_ALL_SPECIES_explanatory_fit.csv2"))
write_csv2(
  comparison_all,
  file.path(result_dir, "S5_ALL_SPECIES_baseline_vs_dynamic.csv2")
)
write_csv2(
  vp_all,
  file.path(result_dir, "S5_ALL_SPECIES_variance_partitioning.csv2")
)
write_csv2(
  convergence_all,
  file.path(result_dir, "S5_ALL_SPECIES_convergence_summary.csv2")
)

#===============================================================================
# 8. SAVE MASTER RESULTS
#===============================================================================

S5_RESULTS <- list(
  analysis =
    "same-year and exact previous-year species abundance dependencies after final species-specific environmental Hmsc models",
  source_S4 = s4_result_file,
  source_S3 = s3_result_file,
  target_species = target_species,
  locked_weather_variables = locked_weather_variables,
  selected_environment_variables = selected_environment_variables,
  variables_kept = variables_kept,
  abundance_predictor_definition = "z(log1p(count / exp(Loff)))",
  lag_definition =
    "exact previous calendar year at the same site; no nearest-year substitution",
  same_year_interpretation =
    "contemporaneous conditional association; not causal",
  previous_year_interpretation =
    "directional temporal association conditional on environmental and abundance predictors",
  matched_sample_comparison = TRUE,
  support_threshold = support_threshold,
  strong_support_threshold = strong_support_threshold,
  convergence_policy = convergence_rules,
  sample_summary = sample_summary_all,
  dynamic_effects = dynamic_effects_all,
  directional_relationships = interaction_summary,
  explanatory_fit = fit_all,
  baseline_vs_dynamic = comparison_all,
  variance_partitioning = vp_all,
  convergence_summary = convergence_all,
  species_results = species_results,
  session_info = capture.output(sessionInfo())
)

saveRDS(
  S5_RESULTS,
  file.path(result_dir, "S5_SPECIES_ABUNDANCE_DEPENDENCIES_RESULTS.rds")
)

writeLines(
  S5_RESULTS$session_info,
  file.path(result_dir, "sessionInfo.txt")
)

writeLines(
  c(
    "S5_SPECIES_ABUNDANCE_DEPENDENCIES_COMPLETE",
    paste0("species=", paste(target_species, collapse = "|")),
    "lag1=exact_previous_calendar_year_same_site",
    "same_year_other_species=TRUE",
    "lag1_own_species=TRUE",
    "lag1_other_species=TRUE",
    "abundance_predictor=z(log1p(count/exp(Loff)))",
    "baseline_and_dynamic_samples_matched=TRUE",
    "V_blocks_inference=FALSE"
  ),
  complete_file
)

#===============================================================================
# 9. CONSOLE SUMMARY
#===============================================================================

cat("\n========================================================\n")
cat("S5 SPECIES ABUNDANCE DEPENDENCIES COMPLETE\n")
cat("========================================================\n")

cat("\nMATCHED SAMPLE SIZE\n")
print(sample_summary_all, row.names = FALSE)

cat("\nBASELINE vs FULL DYNAMIC MODEL\n")
print(comparison_all, row.names = FALSE)

cat(
  "\nDYNAMIC EFFECTS WITH POSTERIOR SUPPORT >= ",
  support_threshold,
  "\n",
  sep = ""
)
print(
  interaction_summary[
    interaction_summary$posterior_support >= support_threshold,
    , drop = FALSE
  ],
  row.names = FALSE
)

cat("\nALL DIRECTIONAL RELATIONSHIPS\n")
print(interaction_summary, row.names = FALSE)

cat("\nVARIANCE PARTITIONING\n")
print(vp_all, row.names = FALSE)

cat(
  "\nIMPORTANT: same-year cross-species effects are contemporaneous ",
  "associations, not causal effects.\n",
  sep = ""
)
cat(
  "Lag1 uses only the exact previous calendar year at the same site.\n"
)
cat("\nResults:\n", result_dir, "\n")
cat("========================================================\n")
