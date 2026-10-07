#===============================================================================
# S3: NESTED / OUTER CROSS-VALIDATION PREDICTIVE HMSC
#===============================================================================
#
# TARKOITUS
# ---------
# Tämä on lopullinen ennustekyvyn arviointi S1/S2-valintaketjun jälkeen.
# Testiyksiköt eivät osallistu mihinkään muuttujavalinnan vaiheeseen.
#
# Jokaisessa OUTER-foldissa:
#   1. erotetaan outer TRAIN ja outer TEST
#   2. säämuuttujat valitaan uudelleen vain TRAIN-aineistossa
#      - ryhmien forward-valinta
#      - ryhmäsuojattu backward-valinta
#      - valinta perustuu TRAIN-aineiston sisäiseen year-blocked CV:hen
#   3. ympäristömuuttujat valitaan uudelleen vain TRAIN-aineistossa
#      - yksi bufferi / ekologinen ryhmä samoilla riveillä
#      - yksi kiinteä ympäristövertailupaneeli
#      - forward-valinta
#      - ryhmäsuojattu backward-valinta
#      - kaikki valinnat perustuvat TRAIN-aineiston sisäiseen year-blocked CV:hen
#   4. lopulliset WEATHER_ONLY ja WEATHER_PLUS_ENVIRONMENT sovitetaan TRAIN-riveille
#   5. ennustetaan kokonaan käyttämättömät TEST-rivit
#
# OUTER-arvioinnit:
#   - outer_year: kokonaiset vuodet jätetään pois (PÄÄTULOS)
#   - outer_site: kokonaiset paikat jätetään pois (TOISSIJAINEN TULOS)
#
# TÄRKEÄÄ:
#   - outer TEST ei vaikuta korrelaatiokarsintaan, saatavuusvalintoihin,
#     muuttujavalintaan eikä standardointiin.
#   - standardointi lasketaan aina vain kyseisen mallin TRAIN-riveistä.
#   - Loff annetaan eksplisiittisesti predict()-kutsuun.
#   - uusien year/site-random-level-yksiköiden ennusteessa käytetään
#     predictEtaMean = TRUE, jolloin uuden yksikön random effect käyttää
#     posterior predictive -jakauman arvioitua keskiarvoa.
#   - Poisson/lognormal Poisson -ennusteen piste-estimaatti on posteriorimediaani,
#     mikä vastaa Hmsc::evaluateModelFit()-funktion Poisson-logiikkaa.
#
# Skripti EI käytä S1/S2:ssa lopulta valittuja muuttujia outer-foldien valintaan.
# Se käyttää vain S1/S2a:n tallentamaa vuosiaineistoa ja alkuperäisiä kandidaatti-
# ryhmiä. Näin outer-testin tulos arvioi koko valintaputken ennustekykyä.
#===============================================================================

gc()
set.seed(20260818)

#===============================================================================
# 1. KÄYTTÄJÄN ASETUKSET
#===============================================================================

primary_output_dir <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1"
)

primary_rdata_file <- file.path(
  primary_output_dir,
  "HMSC_annual_three_species_weather_environment_buffers_results.RData"
)

output_root <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v1"
)

dir.create(output_root, recursive = TRUE, showWarnings = FALSE)

# TRUE = jatka olemassa olevista foldi- ja mallikohtaisista checkpoint-tiedostoista.
resume_from_checkpoints <- TRUE

# Ensisijainen arviointi: ennustaminen uusiin vuosiin.
run_outer_year_cv <- TRUE
outer_year_nfolds <- 5L
outer_year_seed <- 20260818L

# Toissijainen arviointi: ennustaminen uusille paikoille.
run_outer_site_cv <- TRUE
outer_site_nfolds <- 5L
outer_site_seed <- 20260819L

# Sisäinen muuttujavalinta tehdään aina vuosilohkoilla.
inner_year_nfolds <- 4L
inner_seed_base <- 20260900L

# Testausta varten voi ajaa vain tietyt outer-foldit, esim. c(1L).
# NULL = aja kaikki foldit.
outer_fold_subset <- NULL

#--------------------------------------------------------
# Muuttujavalinnan kriteerit: samat periaatteet kuin S1/S2:ssa
#--------------------------------------------------------

weather_correlation_limit <- 0.80
environment_correlation_limit <- 0.90

max_selected_weather_groups <- 5L
max_selected_environment_groups <- 4L
minimum_variables_per_selected_group <- 1L

min_community_delta_SR2 <- 0.002
min_strong_species_delta_SR2 <- 0.010
max_harm_to_other_species <- 0.010
minimum_nonnegative_species <- 2L
max_backward_mean_loss <- 0.001
delta_tolerance <- 1e-8

# Ympäristöbufferien ja kiinteän paneelin saatavuusrajat.
minimum_samples <- 500L
minimum_sites <- 20L
minimum_years <- 3L
minimum_buffer_fraction_of_best <- 0.80
minimum_common_fraction_of_best <- 0.60
confirm_top_n <- 2L

#--------------------------------------------------------
# MCMC
#--------------------------------------------------------

MCMC <- list(
  screen = list(
    samples = 100L,
    transient = 100L,
    thin = 5L,
    chains = 2L,
    parallel = 2L
  ),
  confirm = list(
    samples = 300L,
    transient = 300L,
    thin = 5L,
    chains = 2L,
    parallel = 2L
  ),
  outer_final = list(
    # Tämä vastaa pitkän päämallin tarkkuutta.
    samples = 5000L,
    transient = 10000L,
    thin = 20L,
    chains = 4L,
    parallel = 4L
  )
)

# Ennusteisiin käytettävien posterioriarvontojen yläraja.
max_prediction_draws <- 1000L

# Hmsc-asetukset.
hmsc_distribution <- "lognormal poisson"
annual_index_standard_days <- 7

#===============================================================================
# 2. PAKETIT
#===============================================================================

required_packages <- c("Hmsc", "dplyr", "tidyr", "coda")
missing_packages <- required_packages[!vapply(
  required_packages,
  requireNamespace,
  quietly = TRUE,
  FUN.VALUE = logical(1)
)]

if (length(missing_packages) > 0L) {
  stop("Asenna puuttuvat paketit: ", paste(missing_packages, collapse = ", "))
}

suppressPackageStartupMessages({
  library(Hmsc)
  library(dplyr)
  library(tidyr)
  library(coda)
})

#===============================================================================
# 3. LATAA S1/S2a:N VUOSIAINEISTO JA ALKUPERÄISET KANDIDAATIT
#===============================================================================

if (!file.exists(primary_rdata_file)) {
  stop("Predictive S1/S2a -RData-tiedostoa ei löydy: ", primary_rdata_file)
}

primary_env <- new.env(parent = emptyenv())
loaded_primary_objects <- load(primary_rdata_file, envir = primary_env)

required_primary_objects <- c(
  "target_species",
  "Y_annual_all",
  "Loff_annual_all",
  "sample_metadata",
  "X_sample",
  "weather_groups",
  "environment_groups_buffered",
  "environment_candidate_table"
)

missing_primary_objects <- setdiff(required_primary_objects, loaded_primary_objects)
if (length(missing_primary_objects) > 0L) {
  stop(
    "S1/S2a-RData-tiedostosta puuttuvat objektit: ",
    paste(missing_primary_objects, collapse = ", ")
  )
}

for (object_name in required_primary_objects) {
  assign(object_name, get(object_name, envir = primary_env), envir = .GlobalEnv)
}
rm(primary_env)

# Yhteinen rivijärjestys.
base_ids <- Reduce(
  intersect,
  list(
    rownames(Y_annual_all),
    rownames(Loff_annual_all),
    as.character(sample_metadata$sample_id),
    as.character(X_sample$sample_id)
  )
)
base_ids <- rownames(Y_annual_all)[rownames(Y_annual_all) %in% base_ids]

if (length(base_ids) == 0L) stop("Yhteisiä vuosirivejä ei löytynyt.")

Y_annual_all <- Y_annual_all[base_ids, , drop = FALSE]
Loff_annual_all <- Loff_annual_all[base_ids, , drop = FALSE]
sample_metadata <- sample_metadata %>%
  filter(.data$sample_id %in% base_ids) %>%
  arrange(match(.data$sample_id, base_ids))
X_sample <- X_sample %>%
  filter(.data$sample_id %in% base_ids) %>%
  arrange(match(.data$sample_id, base_ids))

if (!identical(as.character(sample_metadata$sample_id), base_ids) ||
    !identical(as.character(X_sample$sample_id), base_ids)) {
  stop("Vuosiaineiston rivijärjestys ei täsmää.")
}

storage.mode(Y_annual_all) <- "numeric"
storage.mode(Loff_annual_all) <- "numeric"
dimnames(Loff_annual_all) <- dimnames(Y_annual_all)

all_site_levels <- sort(unique(as.character(sample_metadata$site)))
all_year_levels <- sort(unique(as.character(sample_metadata$year)))

#===============================================================================
# 4. YLEISET APUFUNKTIOT
#===============================================================================

safe_name <- function(x) {
  gsub("[^A-Za-z0-9_]+", "_", as.character(x))
}

strip_buffer_suffix <- function(x) {
  sub("__b.+m$", "", as.character(x))
}

write_csv2 <- function(x, path) {
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  if (ncol(x) == 0L) x <- data.frame(status = "no_rows")
  write.table(
    x,
    file = path,
    sep = ";",
    dec = ",",
    row.names = FALSE,
    col.names = TRUE,
    quote = TRUE,
    na = ""
  )
}

make_grouped_folds <- function(metadata, block, nfolds, seed) {
  if (!block %in% names(metadata)) stop("Lohkomuuttuja puuttuu: ", block)
  block_values <- as.character(metadata[[block]])
  unique_blocks <- unique(block_values)
  unique_blocks <- unique_blocks[!is.na(unique_blocks)]

  if (length(unique_blocks) < 2L) {
    stop("CV tarvitsee vähintään kaksi erillistä ", block, "-yksikköä.")
  }

  nfolds <- min(as.integer(nfolds), length(unique_blocks))
  if (nfolds < 2L) stop("CV-foldien määrä jäi alle kahden.")

  block_table <- data.frame(
    block_value = unique_blocks,
    stringsAsFactors = FALSE
  )
  block_table$n <- vapply(
    block_table$block_value,
    function(z) sum(block_values == z, na.rm = TRUE),
    integer(1)
  )

  set.seed(seed)
  block_table <- block_table[
    order(-block_table$n, runif(nrow(block_table))),
    ,
    drop = FALSE
  ]

  fold_load <- rep(0L, nfolds)
  block_table$fold <- NA_integer_
  for (i in seq_len(nrow(block_table))) {
    f <- which.min(fold_load)
    block_table$fold[i] <- f
    fold_load[f] <- fold_load[f] + block_table$n[i]
  }

  fold_lookup <- setNames(block_table$fold, block_table$block_value)
  partition <- as.integer(fold_lookup[block_values])

  attr(partition, "block_table") <- block_table
  partition
}

complete_ids <- function(variables, within_ids = base_ids) {
  variables <- unique(as.character(variables))
  missing_variables <- setdiff(variables, names(X_sample))
  if (length(missing_variables) > 0L) {
    stop("Selittäjiä puuttuu X_sample-taulusta: ", paste(missing_variables, collapse = ", "))
  }

  x_rows <- match(within_ids, X_sample$sample_id)
  y_rows <- match(within_ids, rownames(Y_annual_all))
  o_rows <- match(within_ids, rownames(Loff_annual_all))

  valid <- !is.na(x_rows) & !is.na(y_rows) & !is.na(o_rows)
  if (length(variables) > 0L) {
    ok_x <- rep(FALSE, length(within_ids))
    ok_x[valid] <- apply(
      as.matrix(X_sample[x_rows[valid], variables, drop = FALSE]),
      1,
      function(z) all(is.finite(z))
    )
    valid <- valid & ok_x
  }

  ok_y <- rep(FALSE, length(within_ids))
  ok_o <- rep(FALSE, length(within_ids))
  valid_idx <- which(valid)
  if (length(valid_idx) > 0L) {
    ok_y[valid_idx] <- rowSums(
      is.finite(Y_annual_all[y_rows[valid_idx], , drop = FALSE])
    ) > 0L
    ok_o[valid_idx] <- apply(
      Loff_annual_all[o_rows[valid_idx], , drop = FALSE],
      1,
      function(z) all(is.finite(z))
    )
  }

  within_ids[valid & ok_y & ok_o]
}

coverage_row <- function(ids, label = NA_character_) {
  md <- sample_metadata[match(ids, sample_metadata$sample_id), , drop = FALSE]
  data.frame(
    label = label,
    n_site_years = length(ids),
    n_sites = dplyr::n_distinct(md$site),
    n_years = dplyr::n_distinct(md$year),
    first_year = if (nrow(md)) min(md$year, na.rm = TRUE) else NA_real_,
    last_year = if (nrow(md)) max(md$year, na.rm = TRUE) else NA_real_,
    stringsAsFactors = FALSE
  )
}

meets_coverage <- function(ids) {
  x <- coverage_row(ids)
  x$n_site_years >= minimum_samples &&
    x$n_sites >= minimum_sites &&
    x$n_years >= minimum_years
}

variables_vary <- function(variables, ids) {
  if (length(variables) == 0L) return(TRUE)
  rows <- match(ids, X_sample$sample_id)
  if (anyNA(rows)) return(FALSE)
  all(vapply(
    variables,
    function(v) {
      z <- X_sample[[v]][rows]
      z <- z[is.finite(z)]
      length(z) > 1L && length(unique(z)) > 1L
    },
    logical(1)
  ))
}

remove_zero_variance_names <- function(dat, variables) {
  variables <- intersect(variables, names(dat))
  keep <- vapply(
    variables,
    function(v) {
      z <- dat[[v]]
      z <- z[is.finite(z)]
      length(z) > 1L && length(unique(z)) > 1L
    },
    logical(1)
  )
  list(kept = variables[keep], removed = variables[!keep])
}

remove_high_correlations <- function(
    dat,
    variables,
    protected_variables = character(0),
    limit = 0.80
) {
  variables <- intersect(unique(variables), names(dat))
  zv <- remove_zero_variance_names(dat, variables)
  kept <- zv$kept
  removed <- zv$removed
  protected_variables <- intersect(protected_variables, kept)

  if (length(kept) <= 1L) return(list(kept = kept, removed = removed))

  cor_mat <- suppressWarnings(cor(dat[, kept, drop = FALSE], use = "pairwise.complete.obs"))

  repeat {
    current <- abs(cor_mat[kept, kept, drop = FALSE])
    diag(current) <- 0
    if (!any(current > limit, na.rm = TRUE)) break

    pairs <- which(current > limit, arr.ind = TRUE)
    pairs <- pairs[pairs[, 1] < pairs[, 2], , drop = FALSE]
    if (nrow(pairs) == 0L) break

    pair_names <- lapply(seq_len(nrow(pairs)), function(i) rownames(current)[pairs[i, ]])
    eligible <- which(vapply(
      pair_names,
      function(z) length(setdiff(z, protected_variables)) > 0L,
      logical(1)
    ))
    if (length(eligible) == 0L) break

    pair <- pair_names[[eligible[1]]]
    removable <- setdiff(pair, protected_variables)
    if (length(removable) == 1L) {
      drop_variable <- removable
    } else {
      mean_cor <- rowMeans(current[removable, , drop = FALSE], na.rm = TRUE)
      drop_variable <- names(which.max(mean_cor))[1]
    }

    kept <- setdiff(kept, drop_variable)
    removed <- unique(c(removed, drop_variable))
    if (length(kept) <= 1L) break
  }

  list(kept = kept, removed = removed)
}

signed_spearman_r2 <- function(observed, predicted) {
  keep <- is.finite(observed) & is.finite(predicted)
  observed <- observed[keep]
  predicted <- predicted[keep]
  if (length(observed) < 3L || length(unique(observed)) < 2L ||
      length(unique(predicted)) < 2L) return(NA_real_)
  r <- suppressWarnings(cor(observed, predicted, method = "spearman"))
  if (!is.finite(r)) return(NA_real_)
  sign(r) * r^2
}

auc_rank <- function(observed, probability) {
  keep <- is.finite(observed) & is.finite(probability)
  observed <- observed[keep]
  probability <- probability[keep]
  n_positive <- sum(observed == 1)
  n_negative <- sum(observed == 0)
  if (n_positive == 0L || n_negative == 0L) return(NA_real_)
  ranks <- rank(probability, ties.method = "average")
  (sum(ranks[observed == 1]) - n_positive * (n_positive + 1) / 2) /
    (n_positive * n_negative)
}

metrics_from_point_predictions <- function(prediction_rows) {
  prediction_rows %>%
    group_by(.data$evaluation, .data$model_type, .data$species) %>%
    group_modify(function(.x, .y) {
      observed <- .x$observed
      predicted <- .x$predicted_median
      presence_probability <- .x$presence_probability
      observed_occurrence <- as.numeric(observed > 0)
      conditional <- is.finite(observed) & observed > 0 & is.finite(predicted)
      data.frame(
        n = sum(is.finite(observed) & is.finite(predicted)),
        RMSE = sqrt(mean((observed - predicted)^2, na.rm = TRUE)),
        SR2 = signed_spearman_r2(observed, predicted),
        O.RMSE = sqrt(mean((observed_occurrence - presence_probability)^2, na.rm = TRUE)),
        O.AUC = auc_rank(observed_occurrence, presence_probability),
        O.TjurR2 = if (
          any(observed_occurrence == 1, na.rm = TRUE) &&
          any(observed_occurrence == 0, na.rm = TRUE)
        ) {
          mean(presence_probability[observed_occurrence == 1], na.rm = TRUE) -
            mean(presence_probability[observed_occurrence == 0], na.rm = TRUE)
        } else {
          NA_real_
        },
        C.RMSE = if (sum(conditional) > 0L) {
          sqrt(mean((observed[conditional] - predicted[conditional])^2, na.rm = TRUE))
        } else {
          NA_real_
        },
        C.SR2 = if (sum(conditional) >= 3L) {
          signed_spearman_r2(observed[conditional], predicted[conditional])
        } else {
          NA_real_
        },
        stringsAsFactors = FALSE
      )
    }) %>%
    ungroup()
}

summarize_delta <- function(reference_metrics, candidate_metrics) {
  ref <- reference_metrics %>%
    select(.data$species, reference_SR2 = .data$SR2, reference_RMSE = .data$RMSE)
  cand <- candidate_metrics %>%
    select(.data$species, candidate_SR2 = .data$SR2, candidate_RMSE = .data$RMSE)

  delta <- inner_join(ref, cand, by = "species", relationship = "one-to-one") %>%
    mutate(
      delta_SR2 = .data$candidate_SR2 - .data$reference_SR2,
      delta_RMSE = .data$candidate_RMSE - .data$reference_RMSE
    )

  values <- delta$delta_SR2[is.finite(delta$delta_SR2)]
  summary <- if (length(values) > 0L) {
    list(
      mean = mean(values),
      median = median(values),
      minimum = min(values),
      maximum = max(values),
      n_positive = sum(values > delta_tolerance),
      n_nonnegative = sum(values >= -delta_tolerance)
    )
  } else {
    list(
      mean = NA_real_, median = NA_real_, minimum = NA_real_, maximum = NA_real_,
      n_positive = 0L, n_nonnegative = 0L
    )
  }
  list(delta = delta, summary = summary)
}

accept_addition <- function(summary) {
  community <-
    is.finite(summary$mean) &&
    is.finite(summary$median) &&
    summary$mean >= min_community_delta_SR2 &&
    summary$median > delta_tolerance &&
    summary$n_nonnegative >= minimum_nonnegative_species

  strong_species <-
    is.finite(summary$maximum) &&
    is.finite(summary$minimum) &&
    is.finite(summary$mean) &&
    summary$maximum >= min_strong_species_delta_SR2 &&
    summary$minimum >= -max_harm_to_other_species &&
    summary$mean >= min_community_delta_SR2

  list(
    accepted = community || strong_species,
    community_support = community,
    strong_species_support = strong_species
  )
}

accept_removal <- function(summary) {
  is.finite(summary$mean) &&
    summary$mean >= -max_backward_mean_loss &&
    summary$minimum >= -max_harm_to_other_species &&
    summary$n_nonnegative >= minimum_nonnegative_species
}

#===============================================================================
# 5. HMSC: TRAIN-SOVITUS JA AIDOSTI UUDEN DATAN ENNUSTE
#===============================================================================

posterior_subset <- function(model, maximum_draws) {
  post <- poolMcmcChains(model$postList, start = 1L, thin = 1L)
  if (length(post) > maximum_draws) {
    keep <- unique(round(seq(1, length(post), length.out = maximum_draws)))
    post <- post[keep]
  }
  post
}

fit_train_model <- function(variables, train_ids, mcmc, seed) {
  set.seed(seed)
  variables <- unique(as.character(variables))
  train_ids <- complete_ids(variables, train_ids)
  if (length(train_ids) < 20L) stop("TRAIN-rivejä jäi alle 20.")

  md <- sample_metadata[match(train_ids, sample_metadata$sample_id), , drop = FALSE]
  x_raw <- X_sample[match(train_ids, X_sample$sample_id), c("sample_id", variables), drop = FALSE]

  zv <- remove_zero_variance_names(x_raw, variables)
  kept <- zv$kept

  if (length(kept) > 0L) {
    train_means <- vapply(x_raw[, kept, drop = FALSE], mean, numeric(1), na.rm = TRUE)
    train_sds <- vapply(x_raw[, kept, drop = FALSE], sd, numeric(1), na.rm = TRUE)
    valid_scale <- is.finite(train_sds) & train_sds > 0
    kept <- kept[valid_scale]
    train_means <- train_means[kept]
    train_sds <- train_sds[kept]
  } else {
    train_means <- numeric(0)
    train_sds <- numeric(0)
  }

  if (length(kept) > 0L) {
    x_scaled <- as.data.frame(lapply(kept, function(v) {
      (x_raw[[v]] - train_means[[v]]) / train_sds[[v]]
    }))
    names(x_scaled) <- kept
    x_formula <- reformulate(kept)
  } else {
    x_scaled <- data.frame(intercept_helper = rep(0, nrow(x_raw)))
    x_formula <- ~ 1
  }
  rownames(x_scaled) <- train_ids

  y_train <- Y_annual_all[train_ids, , drop = FALSE]
  loff_train <- Loff_annual_all[train_ids, , drop = FALSE]

  study_design <- data.frame(
    site = factor(as.character(md$site), levels = all_site_levels),
    year = factor(as.character(md$year), levels = all_year_levels)
  )
  rownames(study_design) <- train_ids

  ran_levels <- list(
    site = HmscRandomLevel(units = all_site_levels),
    year = HmscRandomLevel(units = all_year_levels)
  )

  model <- Hmsc(
    Y = y_train,
    distr = rep(hmsc_distribution, ncol(y_train)),
    Loff = loff_train,
    XData = x_scaled,
    XScale = FALSE,
    YScale = FALSE,
    XFormula = x_formula,
    studyDesign = study_design,
    ranLevels = ran_levels
  )

  model <- sampleMcmc(
    model,
    samples = mcmc$samples,
    transient = mcmc$transient,
    thin = mcmc$thin,
    nChains = mcmc$chains,
    nParallel = mcmc$parallel,
    verbose = 0
  )

  list(
    model = model,
    variables = kept,
    means = train_means,
    sds = train_sds,
    train_ids = train_ids,
    ran_levels = ran_levels
  )
}

predict_new_data <- function(fit, test_ids, seed, evaluation, model_type) {
  variables <- fit$variables
  test_ids <- complete_ids(variables, test_ids)
  if (length(test_ids) == 0L) {
    return(data.frame())
  }

  md <- sample_metadata[match(test_ids, sample_metadata$sample_id), , drop = FALSE]
  x_raw <- X_sample[match(test_ids, X_sample$sample_id), c("sample_id", variables), drop = FALSE]

  if (length(variables) > 0L) {
    x_scaled <- as.data.frame(lapply(variables, function(v) {
      (x_raw[[v]] - fit$means[[v]]) / fit$sds[[v]]
    }))
    names(x_scaled) <- variables
  } else {
    x_scaled <- data.frame(intercept_helper = rep(0, nrow(x_raw)))
  }
  rownames(x_scaled) <- test_ids

  y_test <- Y_annual_all[test_ids, , drop = FALSE]
  loff_test <- Loff_annual_all[test_ids, , drop = FALSE]
  study_design_test <- data.frame(
    site = factor(as.character(md$site), levels = all_site_levels),
    year = factor(as.character(md$year), levels = all_year_levels)
  )
  rownames(study_design_test) <- test_ids

  post <- posterior_subset(fit$model, max_prediction_draws)
  set.seed(seed)
  pred_list <- predict(
    fit$model,
    post = post,
    XData = x_scaled,
    Loff = loff_test,
    studyDesign = study_design_test,
    ranLevels = fit$ran_levels,
    expected = FALSE,
    predictEtaMean = TRUE,
    nParallel = 1L
  )
  pred <- simplify2array(pred_list)

  expected_dim <- c(nrow(y_test), ncol(y_test), length(post))
  if (!identical(as.integer(dim(pred)), as.integer(expected_dim))) {
    stop(
      "TEST-ennusteen dimensiot eivät täsmää. Saatiin ",
      paste(dim(pred), collapse = "x"),
      ", odotettiin ", paste(expected_dim, collapse = "x")
    )
  }

  point <- apply(pred, c(1, 2), median, na.rm = TRUE)
  presence_probability <- 1 - apply(pred == 0, c(1, 2), mean, na.rm = TRUE)

  rows <- vector("list", ncol(y_test))
  for (j in seq_len(ncol(y_test))) {
    rows[[j]] <- data.frame(
      evaluation = evaluation,
      model_type = model_type,
      sample_id = test_ids,
      site = as.character(md$site),
      year = as.character(md$year),
      species = colnames(y_test)[j],
      observed = as.numeric(y_test[, j]),
      predicted_median = as.numeric(point[, j]),
      presence_probability = as.numeric(presence_probability[, j]),
      stringsAsFactors = FALSE
    )
  }

  bind_rows(rows)
}

#===============================================================================
# 6. SISÄINEN YEAR-BLOCKED CV MUUTTUJAVALINTAA VARTEN
#===============================================================================

run_inner_cv_model <- function(
    variables,
    matched_ids,
    partition,
    mcmc,
    seed,
    cache_file,
    model_type = "candidate"
) {
  if (resume_from_checkpoints && file.exists(cache_file)) {
    return(readRDS(cache_file))
  }

  md <- sample_metadata[match(matched_ids, sample_metadata$sample_id), , drop = FALSE]
  folds <- sort(unique(partition))
  prediction_blocks <- list()

  for (fold in folds) {
    validation_ids <- matched_ids[partition == fold]
    training_ids <- matched_ids[partition != fold]

    if (length(training_ids) < 20L || length(validation_ids) == 0L) next

    fit <- fit_train_model(
      variables = variables,
      train_ids = training_ids,
      mcmc = mcmc,
      seed = seed + fold * 1000L
    )

    pred <- predict_new_data(
      fit = fit,
      test_ids = validation_ids,
      seed = seed + fold * 1000L + 1L,
      evaluation = "inner_cv_year",
      model_type = model_type
    )
    prediction_blocks[[as.character(fold)]] <- pred

    rm(fit)
    gc()
  }

  predictions <- bind_rows(prediction_blocks)
  if (nrow(predictions) == 0L) stop("Inner-CV ei tuottanut ennusteita.")

  metrics <- metrics_from_point_predictions(predictions)
  result <- list(predictions = predictions, metrics = metrics)
  saveRDS(result, cache_file)
  result
}

inner_cv_compare <- function(
    reference_variables,
    candidate_variables,
    within_ids,
    mcmc,
    seed,
    cache_dir,
    label
) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  all_variables <- unique(c(reference_variables, candidate_variables))
  matched_ids <- complete_ids(all_variables, within_ids)
  if (!meets_coverage(matched_ids)) {
    return(list(status = "insufficient_coverage", n_samples = length(matched_ids)))
  }

  md <- sample_metadata[match(matched_ids, sample_metadata$sample_id), , drop = FALSE]
  n_years <- dplyr::n_distinct(md$year)
  if (n_years < 2L) {
    return(list(status = "insufficient_years", n_samples = length(matched_ids)))
  }

  partition <- make_grouped_folds(
    md,
    block = "year",
    nfolds = min(inner_year_nfolds, n_years),
    seed = seed
  )

  reference <- run_inner_cv_model(
    variables = reference_variables,
    matched_ids = matched_ids,
    partition = partition,
    mcmc = mcmc,
    seed = seed + 10L,
    cache_file = file.path(cache_dir, paste0(safe_name(label), "_REF.rds")),
    model_type = "reference"
  )

  candidate <- run_inner_cv_model(
    variables = candidate_variables,
    matched_ids = matched_ids,
    partition = partition,
    mcmc = mcmc,
    seed = seed + 20L,
    cache_file = file.path(cache_dir, paste0(safe_name(label), "_CAND.rds")),
    model_type = "candidate"
  )

  comparison <- summarize_delta(reference$metrics, candidate$metrics)
  list(
    status = "fitted",
    n_samples = length(matched_ids),
    matched_ids = matched_ids,
    partition = partition,
    reference = reference,
    candidate = candidate,
    comparison = comparison
  )
}

comparison_summary_row <- function(pair, label) {
  if (!identical(pair$status, "fitted")) {
    return(data.frame(
      label = label,
      status = pair$status,
      n_samples = pair$n_samples,
      mean_delta_SR2 = NA_real_,
      median_delta_SR2 = NA_real_,
      min_delta_SR2 = NA_real_,
      max_delta_SR2 = NA_real_,
      n_nonnegative_species = NA_integer_,
      stringsAsFactors = FALSE
    ))
  }
  s <- pair$comparison$summary
  data.frame(
    label = label,
    status = "fitted",
    n_samples = pair$n_samples,
    mean_delta_SR2 = s$mean,
    median_delta_SR2 = s$median,
    min_delta_SR2 = s$minimum,
    max_delta_SR2 = s$maximum,
    n_nonnegative_species = s$n_nonnegative,
    stringsAsFactors = FALSE
  )
}

#===============================================================================
# 7. SÄÄMUUTTUJIEN NESTED-VALINTA OUTER-TRAINISSA
#===============================================================================

select_weather_in_outer_train <- function(train_ids, fold_dir, seed_base) {
  weather_dir <- file.path(fold_dir, "01_weather_selection")
  dir.create(weather_dir, recursive = TRUE, showWarnings = FALSE)

  available_groups <- lapply(weather_groups, function(x) intersect(x, names(X_sample)))
  available_groups <- available_groups[lengths(available_groups) > 0L]

  selected_groups <- character(0)
  selected_variables <- character(0)
  remaining_groups <- names(available_groups)
  forward_log <- list()

  x_train <- X_sample[match(train_ids, X_sample$sample_id), , drop = FALSE]

  for (step in seq_len(max_selected_weather_groups)) {
    if (length(remaining_groups) == 0L) break
    rows <- list()

    for (g in remaining_groups) {
      raw_variables <- unique(c(selected_variables, available_groups[[g]]))
      corr <- remove_high_correlations(
        x_train,
        raw_variables,
        protected_variables = selected_variables,
        limit = weather_correlation_limit
      )
      candidate_variables <- corr$kept
      reference_variables <- intersect(selected_variables, candidate_variables)

      pair <- tryCatch(
        inner_cv_compare(
          reference_variables = reference_variables,
          candidate_variables = candidate_variables,
          within_ids = train_ids,
          mcmc = MCMC$screen,
          seed = seed_base + step * 10000L + match(g, remaining_groups) * 100L,
          cache_dir = file.path(weather_dir, "cache"),
          label = paste0("WEATHER_STEP_", step, "_", g, "_SCREEN")
        ),
        error = function(e) list(status = paste0("failed: ", conditionMessage(e)), n_samples = 0L)
      )

      row <- comparison_summary_row(pair, g)
      if (identical(pair$status, "fitted")) {
        decision <- accept_addition(pair$comparison$summary)
        row$accepted <- decision$accepted
        row$community_support <- decision$community_support
        row$strong_species_support <- decision$strong_species_support
      } else {
        row$accepted <- FALSE
        row$community_support <- FALSE
        row$strong_species_support <- FALSE
      }
      row$candidate_group <- g
      row$variables_after_correlation <- paste(candidate_variables, collapse = "|")
      row$removed_by_correlation <- paste(corr$removed, collapse = "|")
      rows[[g]] <- row
    }

    table <- bind_rows(rows) %>%
      arrange(desc(.data$accepted), desc(.data$mean_delta_SR2), desc(.data$max_delta_SR2))
    table$step <- step
    forward_log[[paste0("step_", step, "_screen")]] <- table
    write_csv2(table, file.path(weather_dir, paste0("weather_forward_step_", step, "_screen.csv2")))

    accepted <- table %>% filter(.data$accepted, is.finite(.data$mean_delta_SR2))
    if (nrow(accepted) == 0L) break

    chosen <- NULL
    for (i in seq_len(nrow(accepted))) {
      g <- accepted$candidate_group[i]
      candidate_variables <- strsplit(accepted$variables_after_correlation[i], "\\|")[[1]]
      candidate_variables <- candidate_variables[nzchar(candidate_variables)]
      reference_variables <- intersect(selected_variables, candidate_variables)

      pair <- tryCatch(
        inner_cv_compare(
          reference_variables = reference_variables,
          candidate_variables = candidate_variables,
          within_ids = train_ids,
          mcmc = MCMC$confirm,
          seed = seed_base + 500000L + step * 10000L + i * 100L,
          cache_dir = file.path(weather_dir, "cache"),
          label = paste0("WEATHER_STEP_", step, "_", g, "_CONFIRM")
        ),
        error = function(e) list(status = paste0("failed: ", conditionMessage(e)), n_samples = 0L)
      )

      confirm_row <- comparison_summary_row(pair, g)
      if (identical(pair$status, "fitted")) {
        decision <- accept_addition(pair$comparison$summary)
        confirm_row$accepted <- decision$accepted
        confirm_row$community_support <- decision$community_support
        confirm_row$strong_species_support <- decision$strong_species_support
      } else {
        confirm_row$accepted <- FALSE
        confirm_row$community_support <- FALSE
        confirm_row$strong_species_support <- FALSE
      }
      confirm_row$candidate_group <- g
      confirm_row$variables_after_correlation <- paste(candidate_variables, collapse = "|")
      confirm_row$step <- step
      forward_log[[paste0("step_", step, "_confirm_", safe_name(g))]] <- confirm_row
      write_csv2(confirm_row, file.path(weather_dir, paste0("weather_forward_step_", step, "_", safe_name(g), "_confirm.csv2")))

      if (isTRUE(confirm_row$accepted[1])) {
        chosen <- list(group = g, variables = candidate_variables)
        break
      }
    }

    if (is.null(chosen)) break
    selected_groups <- c(selected_groups, chosen$group)
    selected_variables <- chosen$variables
    remaining_groups <- setdiff(remaining_groups, chosen$group)
  }

  #------------------------------
  # Backward-karsinta
  #------------------------------
  current_variables <- selected_variables
  backward_log <- list()
  backward_step <- 0L

  group_for_variable <- function(v) {
    hit <- selected_groups[vapply(
      selected_groups,
      function(g) v %in% available_groups[[g]],
      logical(1)
    )]
    if (length(hit) == 0L) NA_character_ else hit[1]
  }

  group_guard <- function(v, vars) {
    g <- group_for_variable(v)
    if (is.na(g)) return(TRUE)
    in_group <- vars[vapply(vars, function(z) identical(group_for_variable(z), g), logical(1))]
    length(setdiff(in_group, v)) >= minimum_variables_per_selected_group
  }

  repeat {
    removable <- current_variables[vapply(current_variables, group_guard, logical(1), vars = current_variables)]
    if (length(removable) == 0L) break
    backward_step <- backward_step + 1L
    rows <- list()

    for (v in removable) {
      pair <- tryCatch(
        inner_cv_compare(
          reference_variables = current_variables,
          candidate_variables = setdiff(current_variables, v),
          within_ids = train_ids,
          mcmc = MCMC$screen,
          seed = seed_base + 1000000L + backward_step * 10000L + match(v, removable) * 100L,
          cache_dir = file.path(weather_dir, "cache"),
          label = paste0("WEATHER_BACKWARD_", backward_step, "_DROP_", v, "_SCREEN")
        ),
        error = function(e) list(status = paste0("failed: ", conditionMessage(e)), n_samples = 0L)
      )
      row <- comparison_summary_row(pair, v)
      row$removed_variable <- v
      row$removal_accepted <- identical(pair$status, "fitted") && accept_removal(pair$comparison$summary)
      rows[[v]] <- row
    }

    table <- bind_rows(rows) %>%
      arrange(desc(.data$removal_accepted), desc(.data$mean_delta_SR2), desc(.data$min_delta_SR2))
    table$step <- backward_step
    backward_log[[paste0("step_", backward_step)]] <- table
    write_csv2(table, file.path(weather_dir, paste0("weather_backward_step_", backward_step, ".csv2")))

    accepted <- table %>% filter(.data$removal_accepted)
    if (nrow(accepted) == 0L) break
    current_variables <- setdiff(current_variables, accepted$removed_variable[1])
  }

  selected_variables <- current_variables
  selected_groups_final <- unique(na.omit(vapply(selected_variables, group_for_variable, character(1))))

  write_csv2(
    data.frame(variable = selected_variables, stringsAsFactors = FALSE),
    file.path(weather_dir, "selected_weather_variables.csv2")
  )
  write_csv2(
    data.frame(group = selected_groups_final, stringsAsFactors = FALSE),
    file.path(weather_dir, "selected_weather_groups.csv2")
  )

  list(
    groups = selected_groups_final,
    variables = selected_variables,
    forward_log = bind_rows(forward_log, .id = "result_block"),
    backward_log = bind_rows(backward_log, .id = "result_block")
  )
}

#===============================================================================
# 8. YMPÄRISTÖBUFFERIT + FORWARD/BACKWARD OUTER-TRAINISSA
#===============================================================================

build_environment_buffer_sets <- function() {
  registry <- environment_candidate_table %>%
    select(.data$candidate_group, .data$ecological_group, .data$buffer_m) %>%
    distinct() %>%
    filter(.data$candidate_group %in% names(environment_groups_buffered)) %>%
    arrange(.data$ecological_group, .data$buffer_m)

  out <- list()
  for (g in unique(registry$ecological_group)) {
    rows <- registry %>% filter(.data$ecological_group == g)
    raw_sets <- lapply(rows$candidate_group, function(candidate_name) {
      strip_buffer_suffix(environment_groups_buffered[[candidate_name]])
    })
    common_raw <- Reduce(intersect, raw_sets)
    if (length(common_raw) == 0L) next

    out[[g]] <- list()
    for (i in seq_len(nrow(rows))) {
      candidate_name <- rows$candidate_group[i]
      buffer_name <- format(as.numeric(rows$buffer_m[i]), scientific = FALSE, trim = TRUE)
      vars <- environment_groups_buffered[[candidate_name]]
      vars <- vars[strip_buffer_suffix(vars) %in% common_raw]
      vars <- intersect(vars, names(X_sample))
      if (length(vars) > 0L) out[[g]][[buffer_name]] <- vars
    }
    if (length(out[[g]]) == 0L) out[[g]] <- NULL
  }
  out
}

environment_buffer_sets <- build_environment_buffer_sets()

select_environment_in_outer_train <- function(train_ids, weather_variables, fold_dir, seed_base) {
  env_dir <- file.path(fold_dir, "02_environment_selection")
  buffer_dir <- file.path(env_dir, "01_buffers")
  selection_dir <- file.path(env_dir, "02_groups")
  dir.create(buffer_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(selection_dir, recursive = TRUE, showWarnings = FALSE)

  weather_ids <- complete_ids(weather_variables, train_ids)
  if (!meets_coverage(weather_ids)) {
    return(list(
      groups = character(0), variables = character(0), selected_buffers = list(),
      primary_ids = weather_ids, status = "weather_panel_insufficient"
    ))
  }

  selected_buffers <- list()
  buffer_summary <- list()
  buffer_counter <- 0L

  #------------------------------
  # 8A. yksi bufferi / ekologinen ryhmä
  #------------------------------
  for (g in names(environment_buffer_sets)) {
    candidates <- environment_buffer_sets[[g]]
    individual_ids <- lapply(candidates, function(vars) {
      complete_ids(c(weather_variables, vars), weather_ids)
    })
    individual_n <- vapply(individual_ids, length, integer(1))
    if (length(individual_n) == 0L) next
    best_n <- max(individual_n)

    eligible <- names(individual_ids)[
      individual_n >= max(minimum_samples, ceiling(minimum_buffer_fraction_of_best * best_n))
    ]
    eligible <- eligible[vapply(individual_ids[eligible], meets_coverage, logical(1))]
    eligible <- eligible[vapply(
      eligible,
      function(b) variables_vary(candidates[[b]], individual_ids[[b]]),
      logical(1)
    )]
    if (length(eligible) == 0L) next

    all_vars <- unique(c(
      weather_variables,
      unlist(candidates[eligible], use.names = FALSE)
    ))
    common_ids <- complete_ids(all_vars, weather_ids)
    common_threshold <- max(
      minimum_samples,
      ceiling(minimum_common_fraction_of_best * best_n)
    )
    if (!meets_coverage(common_ids) || length(common_ids) < common_threshold) next

    screen_rows <- list()
    for (b in eligible) {
      buffer_counter <- buffer_counter + 1L
      pair <- tryCatch(
        inner_cv_compare(
          reference_variables = weather_variables,
          candidate_variables = unique(c(weather_variables, candidates[[b]])),
          within_ids = common_ids,
          mcmc = MCMC$screen,
          seed = seed_base + 2000000L + buffer_counter * 100L,
          cache_dir = file.path(buffer_dir, "cache"),
          label = paste0("BUFFER_", g, "_", b, "_SCREEN")
        ),
        error = function(e) list(status = paste0("failed: ", conditionMessage(e)), n_samples = 0L)
      )
      row <- comparison_summary_row(pair, paste0(g, "_", b))
      row$ecological_group <- g
      row$buffer_m <- as.numeric(b)
      row$stage <- "screen"
      screen_rows[[b]] <- row
    }

    screen_table <- bind_rows(screen_rows) %>%
      filter(.data$status == "fitted", is.finite(.data$mean_delta_SR2)) %>%
      arrange(desc(.data$mean_delta_SR2), desc(.data$min_delta_SR2), .data$buffer_m)
    if (nrow(screen_table) == 0L) next

    top_buffers <- as.character(head(screen_table$buffer_m, confirm_top_n))
    confirm_rows <- list()
    for (b in top_buffers) {
      buffer_counter <- buffer_counter + 1L
      pair <- tryCatch(
        inner_cv_compare(
          reference_variables = weather_variables,
          candidate_variables = unique(c(weather_variables, candidates[[b]])),
          within_ids = common_ids,
          mcmc = MCMC$confirm,
          seed = seed_base + 2500000L + buffer_counter * 100L,
          cache_dir = file.path(buffer_dir, "cache"),
          label = paste0("BUFFER_", g, "_", b, "_CONFIRM")
        ),
        error = function(e) list(status = paste0("failed: ", conditionMessage(e)), n_samples = 0L)
      )
      row <- comparison_summary_row(pair, paste0(g, "_", b))
      row$ecological_group <- g
      row$buffer_m <- as.numeric(b)
      row$stage <- "confirm"
      confirm_rows[[b]] <- row
    }

    confirm_table <- bind_rows(confirm_rows) %>%
      filter(.data$status == "fitted", is.finite(.data$mean_delta_SR2)) %>%
      arrange(desc(.data$mean_delta_SR2), desc(.data$min_delta_SR2), .data$buffer_m)
    if (nrow(confirm_table) == 0L) next

    chosen <- as.character(confirm_table$buffer_m[1])
    selected_buffers[[g]] <- list(
      buffer_m = as.numeric(chosen),
      variables = candidates[[chosen]],
      individual_ids = individual_ids[[chosen]]
    )
    buffer_summary[[g]] <- bind_rows(screen_table, confirm_table)
  }

  buffer_summary_table <- bind_rows(buffer_summary)
  write_csv2(buffer_summary_table, file.path(buffer_dir, "buffer_selection_summary.csv2"))

  if (length(selected_buffers) == 0L) {
    return(list(
      groups = character(0), variables = character(0), selected_buffers = list(),
      primary_ids = weather_ids, buffer_summary = buffer_summary_table,
      status = "no_environment_buffer_selected"
    ))
  }

  #------------------------------
  # 8B. yksi kiinteä ympäristövertailupaneeli
  #------------------------------
  primary_groups <- names(selected_buffers)
  group_individual_ids <- lapply(primary_groups, function(g) {
    complete_ids(c(weather_variables, selected_buffers[[g]]$variables), weather_ids)
  })
  names(group_individual_ids) <- primary_groups

  basic_ok <- vapply(group_individual_ids, meets_coverage, logical(1))
  primary_groups <- primary_groups[basic_ok]
  if (length(primary_groups) == 0L) {
    return(list(
      groups = character(0), variables = character(0), selected_buffers = selected_buffers,
      primary_ids = weather_ids, buffer_summary = buffer_summary_table,
      status = "no_environment_group_with_sufficient_availability"
    ))
  }

  get_primary_ids <- function(groups) {
    vars <- unique(c(
      weather_variables,
      unlist(lapply(groups, function(g) selected_buffers[[g]]$variables), use.names = FALSE)
    ))
    complete_ids(vars, weather_ids)
  }

  panel_valid <- function(groups, ids) {
    if (length(groups) == 0L || !meets_coverage(ids)) return(FALSE)
    individual_n <- vapply(group_individual_ids[groups], length, integer(1))
    required_n <- max(
      minimum_samples,
      ceiling(minimum_common_fraction_of_best * max(individual_n))
    )
    if (length(ids) < required_n) return(FALSE)
    all(vapply(groups, function(g) variables_vary(selected_buffers[[g]]$variables, ids), logical(1)))
  }

  exclusions <- list()
  repeat {
    primary_ids <- get_primary_ids(primary_groups)
    if (panel_valid(primary_groups, primary_ids)) break
    if (length(primary_groups) == 1L) {
      primary_groups <- character(0)
      primary_ids <- weather_ids
      break
    }

    recovered_n <- vapply(
      primary_groups,
      function(drop_group) length(get_primary_ids(setdiff(primary_groups, drop_group))),
      integer(1)
    )
    individual_n <- vapply(group_individual_ids[primary_groups], length, integer(1))
    drop_order <- order(-recovered_n, individual_n, primary_groups)
    drop_group <- primary_groups[drop_order[1]]
    exclusions[[drop_group]] <- data.frame(
      ecological_group = drop_group,
      reason = "removed_to_create_comparable_primary_panel",
      stringsAsFactors = FALSE
    )
    primary_groups <- setdiff(primary_groups, drop_group)
  }

  write_csv2(bind_rows(exclusions), file.path(selection_dir, "groups_excluded_by_availability.csv2"))

  if (length(primary_groups) == 0L) {
    return(list(
      groups = character(0), variables = character(0), selected_buffers = selected_buffers,
      primary_ids = weather_ids, buffer_summary = buffer_summary_table,
      status = "environment_common_panel_failed"
    ))
  }

  write_csv2(coverage_row(primary_ids, "environment_primary_panel"),
             file.path(selection_dir, "primary_environment_panel.csv2"))

  #------------------------------
  # 8C. ympäristöryhmien forward-valinta
  #------------------------------
  selected_groups <- character(0)
  selected_env_variables <- character(0)
  remaining_groups <- primary_groups
  forward_log <- list()
  step <- 0L

  while (length(remaining_groups) > 0L && length(selected_groups) < max_selected_environment_groups) {
    step <- step + 1L
    base_variables <- unique(c(weather_variables, selected_env_variables))
    rows <- list()

    for (g in remaining_groups) {
      candidate_variables <- unique(c(base_variables, selected_buffers[[g]]$variables))
      pair <- tryCatch(
        inner_cv_compare(
          reference_variables = base_variables,
          candidate_variables = candidate_variables,
          within_ids = primary_ids,
          mcmc = MCMC$screen,
          seed = seed_base + 3000000L + step * 10000L + match(g, remaining_groups) * 100L,
          cache_dir = file.path(selection_dir, "cache"),
          label = paste0("ENV_FORWARD_", step, "_", g, "_SCREEN")
        ),
        error = function(e) list(status = paste0("failed: ", conditionMessage(e)), n_samples = 0L)
      )
      row <- comparison_summary_row(pair, g)
      row$ecological_group <- g
      row$accepted <- identical(pair$status, "fitted") && accept_addition(pair$comparison$summary)$accepted
      row$stage <- "screen"
      rows[[g]] <- row
    }

    table <- bind_rows(rows) %>%
      arrange(desc(.data$accepted), desc(.data$mean_delta_SR2), desc(.data$min_delta_SR2))
    table$step <- step
    forward_log[[paste0("step_", step, "_screen")]] <- table
    write_csv2(table, file.path(selection_dir, paste0("environment_forward_step_", step, "_screen.csv2")))

    accepted <- table %>% filter(.data$accepted)
    if (nrow(accepted) == 0L) break

    top_groups <- head(accepted$ecological_group, confirm_top_n)
    confirm_rows <- list()
    for (g in top_groups) {
      candidate_variables <- unique(c(base_variables, selected_buffers[[g]]$variables))
      pair <- tryCatch(
        inner_cv_compare(
          reference_variables = base_variables,
          candidate_variables = candidate_variables,
          within_ids = primary_ids,
          mcmc = MCMC$confirm,
          seed = seed_base + 3500000L + step * 10000L + match(g, top_groups) * 100L,
          cache_dir = file.path(selection_dir, "cache"),
          label = paste0("ENV_FORWARD_", step, "_", g, "_CONFIRM")
        ),
        error = function(e) list(status = paste0("failed: ", conditionMessage(e)), n_samples = 0L)
      )
      row <- comparison_summary_row(pair, g)
      row$ecological_group <- g
      row$accepted <- identical(pair$status, "fitted") && accept_addition(pair$comparison$summary)$accepted
      row$stage <- "confirm"
      confirm_rows[[g]] <- row
    }

    confirm_table <- bind_rows(confirm_rows) %>%
      arrange(desc(.data$accepted), desc(.data$mean_delta_SR2), desc(.data$min_delta_SR2))
    confirm_table$step <- step
    forward_log[[paste0("step_", step, "_confirm")]] <- confirm_table
    write_csv2(confirm_table, file.path(selection_dir, paste0("environment_forward_step_", step, "_confirm.csv2")))

    confirmed <- confirm_table %>% filter(.data$accepted)
    if (nrow(confirmed) == 0L) break

    chosen <- confirmed$ecological_group[1]
    selected_groups <- c(selected_groups, chosen)
    selected_env_variables <- unique(c(selected_env_variables, selected_buffers[[chosen]]$variables))
    remaining_groups <- setdiff(remaining_groups, chosen)
  }

  #------------------------------
  # 8D. ryhmäsuojattu backward
  #------------------------------
  current_variables <- selected_env_variables
  backward_log <- list()
  backward_step <- 0L

  variable_group <- function(v) {
    hit <- names(selected_buffers)[vapply(
      selected_buffers,
      function(definition) v %in% definition$variables,
      logical(1)
    )]
    if (length(hit) == 0L) NA_character_ else hit[1]
  }

  guard_allows <- function(v, vars) {
    g <- variable_group(v)
    in_group <- vars[vapply(vars, function(z) identical(variable_group(z), g), logical(1))]
    length(setdiff(in_group, v)) >= minimum_variables_per_selected_group
  }

  repeat {
    removable <- current_variables[vapply(current_variables, guard_allows, logical(1), vars = current_variables)]
    if (length(removable) == 0L) break
    backward_step <- backward_step + 1L
    full_variables <- unique(c(weather_variables, current_variables))
    rows <- list()

    for (v in removable) {
      pair <- tryCatch(
        inner_cv_compare(
          reference_variables = full_variables,
          candidate_variables = unique(c(weather_variables, setdiff(current_variables, v))),
          within_ids = primary_ids,
          mcmc = MCMC$screen,
          seed = seed_base + 4000000L + backward_step * 10000L + match(v, removable) * 100L,
          cache_dir = file.path(selection_dir, "cache"),
          label = paste0("ENV_BACKWARD_", backward_step, "_DROP_", v, "_SCREEN")
        ),
        error = function(e) list(status = paste0("failed: ", conditionMessage(e)), n_samples = 0L)
      )
      row <- comparison_summary_row(pair, v)
      row$removed_variable <- v
      row$ecological_group <- variable_group(v)
      row$removal_accepted <- identical(pair$status, "fitted") && accept_removal(pair$comparison$summary)
      row$stage <- "screen"
      rows[[v]] <- row
    }

    table <- bind_rows(rows) %>%
      arrange(desc(.data$removal_accepted), desc(.data$mean_delta_SR2), desc(.data$min_delta_SR2))
    table$step <- backward_step
    backward_log[[paste0("step_", backward_step, "_screen")]] <- table
    write_csv2(table, file.path(selection_dir, paste0("environment_backward_step_", backward_step, "_screen.csv2")))

    accepted <- table %>% filter(.data$removal_accepted)
    if (nrow(accepted) == 0L) break
    chosen_remove <- accepted$removed_variable[1]

    # Vahvista valittu poisto pidemmällä ajolla.
    pair <- tryCatch(
      inner_cv_compare(
        reference_variables = full_variables,
        candidate_variables = unique(c(weather_variables, setdiff(current_variables, chosen_remove))),
        within_ids = primary_ids,
        mcmc = MCMC$confirm,
        seed = seed_base + 4500000L + backward_step * 10000L,
        cache_dir = file.path(selection_dir, "cache"),
        label = paste0("ENV_BACKWARD_", backward_step, "_DROP_", chosen_remove, "_CONFIRM")
      ),
      error = function(e) list(status = paste0("failed: ", conditionMessage(e)), n_samples = 0L)
    )
    confirm_row <- comparison_summary_row(pair, chosen_remove)
    confirm_row$removed_variable <- chosen_remove
    confirm_row$ecological_group <- variable_group(chosen_remove)
    confirm_row$removal_accepted <- identical(pair$status, "fitted") && accept_removal(pair$comparison$summary)
    confirm_row$stage <- "confirm"
    confirm_row$step <- backward_step
    backward_log[[paste0("step_", backward_step, "_confirm")]] <- confirm_row
    write_csv2(confirm_row, file.path(selection_dir, paste0("environment_backward_step_", backward_step, "_confirm.csv2")))

    if (!isTRUE(confirm_row$removal_accepted[1])) break
    current_variables <- setdiff(current_variables, chosen_remove)
  }

  selected_env_variables <- current_variables
  selected_groups_final <- unique(na.omit(vapply(selected_env_variables, variable_group, character(1))))

  selected_buffer_table <- bind_rows(lapply(names(selected_buffers), function(g) {
    data.frame(
      ecological_group = g,
      buffer_m = selected_buffers[[g]]$buffer_m,
      variables = paste(selected_buffers[[g]]$variables, collapse = "|"),
      selected_final = g %in% selected_groups_final,
      stringsAsFactors = FALSE
    )
  }))

  write_csv2(selected_buffer_table, file.path(env_dir, "selected_environment_buffers.csv2"))
  write_csv2(data.frame(group = selected_groups_final), file.path(env_dir, "selected_environment_groups.csv2"))
  write_csv2(data.frame(variable = selected_env_variables), file.path(env_dir, "selected_environment_variables.csv2"))

  list(
    groups = selected_groups_final,
    variables = selected_env_variables,
    selected_buffers = selected_buffers,
    selected_buffer_table = selected_buffer_table,
    primary_ids = primary_ids,
    buffer_summary = buffer_summary_table,
    forward_log = bind_rows(forward_log, .id = "result_block"),
    backward_log = bind_rows(backward_log, .id = "result_block"),
    status = if (length(selected_groups_final)) "environment_selected" else "no_environment_selected"
  )
}

#===============================================================================
# 9. YHDEN OUTER-FOLDIN KOKO PIPELINE
#===============================================================================

run_outer_fold <- function(
    scheme,
    fold,
    outer_train_ids,
    outer_test_ids,
    fold_dir,
    seed_base
) {
  dir.create(fold_dir, recursive = TRUE, showWarnings = FALSE)
  checkpoint <- file.path(fold_dir, "OUTER_FOLD_COMPLETE.rds")
  if (resume_from_checkpoints && file.exists(checkpoint)) {
    message("Luetaan valmis outer-fold checkpoint: ", checkpoint)
    return(readRDS(checkpoint))
  }

  cat("\n============================================================\n")
  cat("S3 OUTER ", scheme, " FOLD ", fold, "\n", sep = "")
  cat("TRAIN n = ", length(outer_train_ids), "; TEST n = ", length(outer_test_ids), "\n", sep = "")
  cat("============================================================\n")

  # 1) säävalinta vain outer TRAINissa
  weather <- select_weather_in_outer_train(
    train_ids = outer_train_ids,
    fold_dir = fold_dir,
    seed_base = seed_base + 10000000L
  )

  if (length(weather$variables) == 0L) {
    warning("Outer-foldissa ei valittu yhtään säämuuttujaa; jatketaan intercept-mallilla.")
  }

  # 2) ympäristövalinta vain outer TRAINissa
  environment <- select_environment_in_outer_train(
    train_ids = outer_train_ids,
    weather_variables = weather$variables,
    fold_dir = fold_dir,
    seed_base = seed_base + 20000000L
  )

  final_weather_variables <- weather$variables
  final_environment_variables <- environment$variables
  final_all_variables <- unique(c(final_weather_variables, final_environment_variables))

  # Matched outer TRAIN/TEST: molemmat loppumallit arvioidaan samoilla riveillä.
  final_train_ids <- complete_ids(final_all_variables, outer_train_ids)
  final_test_ids <- complete_ids(final_all_variables, outer_test_ids)

  coverage <- bind_rows(
    coverage_row(outer_train_ids, "outer_train_all"),
    coverage_row(final_train_ids, "outer_train_final_complete"),
    coverage_row(outer_test_ids, "outer_test_all"),
    coverage_row(final_test_ids, "outer_test_final_complete")
  )
  coverage$scheme <- scheme
  coverage$outer_fold <- fold
  write_csv2(coverage, file.path(fold_dir, "outer_fold_coverage.csv2"))

  if (length(final_train_ids) < 20L || length(final_test_ids) == 0L) {
    stop("Outer-foldin lopullinen matched TRAIN/TEST-paneeli on liian pieni.")
  }

  # 3) WEATHER_ONLY samoilla matched-riveillä
  fit_weather <- fit_train_model(
    variables = final_weather_variables,
    train_ids = final_train_ids,
    mcmc = MCMC$outer_final,
    seed = seed_base + 30000000L
  )
  pred_weather <- predict_new_data(
    fit_weather,
    test_ids = final_test_ids,
    seed = seed_base + 30000001L,
    evaluation = paste0("outer_", scheme),
    model_type = "WEATHER_ONLY"
  )

  # 4) WEATHER_PLUS_ENVIRONMENT samoilla matched-riveillä
  if (length(final_environment_variables) > 0L) {
    fit_full <- fit_train_model(
      variables = final_all_variables,
      train_ids = final_train_ids,
      mcmc = MCMC$outer_final,
      seed = seed_base + 40000000L
    )
    pred_full <- predict_new_data(
      fit_full,
      test_ids = final_test_ids,
      seed = seed_base + 40000001L,
      evaluation = paste0("outer_", scheme),
      model_type = "WEATHER_PLUS_ENVIRONMENT"
    )
    rm(fit_full)
  } else {
    pred_full <- pred_weather
    pred_full$model_type <- "WEATHER_PLUS_ENVIRONMENT"
  }
  rm(fit_weather)
  gc()

  predictions <- bind_rows(pred_weather, pred_full)
  predictions$outer_fold <- fold
  predictions$scheme <- scheme
  metrics <- metrics_from_point_predictions(predictions)
  metrics$outer_fold <- fold
  metrics$scheme <- scheme

  write_csv2(predictions, file.path(fold_dir, "outer_test_predictions.csv2"))
  write_csv2(metrics, file.path(fold_dir, "outer_test_metrics.csv2"))

  selected_weather_table <- data.frame(
    scheme = rep(scheme, length(weather$groups)),
    outer_fold = rep(fold, length(weather$groups)),
    group = weather$groups,
    stringsAsFactors = FALSE
  )
  selected_weather_var_table <- data.frame(
    scheme = rep(scheme, length(weather$variables)),
    outer_fold = rep(fold, length(weather$variables)),
    variable = weather$variables,
    stringsAsFactors = FALSE
  )
  selected_env_table <- data.frame(
    scheme = rep(scheme, length(environment$groups)),
    outer_fold = rep(fold, length(environment$groups)),
    group = environment$groups,
    stringsAsFactors = FALSE
  )
  selected_env_var_table <- data.frame(
    scheme = rep(scheme, length(environment$variables)),
    outer_fold = rep(fold, length(environment$variables)),
    variable = environment$variables,
    stringsAsFactors = FALSE
  )

  result <- list(
    scheme = scheme,
    outer_fold = fold,
    outer_train_ids = outer_train_ids,
    outer_test_ids = outer_test_ids,
    final_train_ids = final_train_ids,
    final_test_ids = final_test_ids,
    coverage = coverage,
    weather = weather,
    environment = environment,
    selected_weather_groups = selected_weather_table,
    selected_weather_variables = selected_weather_var_table,
    selected_environment_groups = selected_env_table,
    selected_environment_variables = selected_env_var_table,
    predictions = predictions,
    metrics = metrics
  )

  saveRDS(result, checkpoint)
  result
}

#===============================================================================
# 10. OUTER-CV AJURI
#===============================================================================

run_outer_scheme <- function(scheme, block, nfolds, seed) {
  scheme_dir <- file.path(output_root, paste0("outer_", scheme))
  dir.create(scheme_dir, recursive = TRUE, showWarnings = FALSE)

  md <- sample_metadata[match(base_ids, sample_metadata$sample_id), , drop = FALSE]
  partition <- make_grouped_folds(md, block = block, nfolds = nfolds, seed = seed)
  block_table <- attr(partition, "block_table")
  write_csv2(block_table, file.path(scheme_dir, "outer_partition_blocks.csv2"))

  folds <- sort(unique(partition))
  if (!is.null(outer_fold_subset)) {
    folds <- intersect(folds, as.integer(outer_fold_subset))
  }

  results <- list()
  for (fold in folds) {
    train_ids <- base_ids[partition != fold]
    test_ids <- base_ids[partition == fold]
    fold_dir <- file.path(scheme_dir, paste0("fold_", sprintf("%02d", fold)))

    scheme_offset <- if (identical(scheme, "site")) 100000000L else 0L
    fold_seed_base <- as.integer((seed %% 100000L) + scheme_offset + fold * 10000000L)

    result <- run_outer_fold(
      scheme = scheme,
      fold = fold,
      outer_train_ids = train_ids,
      outer_test_ids = test_ids,
      fold_dir = fold_dir,
      seed_base = fold_seed_base
    )
    results[[as.character(fold)]] <- result

    # Välitallennus jokaisen foldin jälkeen.
    saveRDS(results, file.path(scheme_dir, "outer_scheme_progress.rds"))
    gc()
  }

  results
}

#===============================================================================
# 11. AJA OUTER YEAR JA OUTER SITE
#===============================================================================

outer_year_results <- NULL
outer_site_results <- NULL

if (run_outer_year_cv) {
  outer_year_results <- run_outer_scheme(
    scheme = "year",
    block = "year",
    nfolds = outer_year_nfolds,
    seed = outer_year_seed
  )
}

if (run_outer_site_cv) {
  outer_site_results <- run_outer_scheme(
    scheme = "site",
    block = "site",
    nfolds = outer_site_nfolds,
    seed = outer_site_seed
  )
}

#===============================================================================
# 12. YHDISTÄ OUTER-TULOKSET
#===============================================================================

all_results <- c(
  if (!is.null(outer_year_results)) outer_year_results else list(),
  if (!is.null(outer_site_results)) outer_site_results else list()
)

if (length(all_results) == 0L) stop("Yhtään outer-foldia ei ajettu.")

all_predictions <- bind_rows(lapply(all_results, `[[`, "predictions"))
all_fold_metrics <- bind_rows(lapply(all_results, `[[`, "metrics"))
all_coverage <- bind_rows(lapply(all_results, `[[`, "coverage"))
all_weather_groups <- bind_rows(lapply(all_results, `[[`, "selected_weather_groups"))
all_weather_variables <- bind_rows(lapply(all_results, `[[`, "selected_weather_variables"))
all_environment_groups <- bind_rows(lapply(all_results, `[[`, "selected_environment_groups"))
all_environment_variables <- bind_rows(lapply(all_results, `[[`, "selected_environment_variables"))

# Pooled outer metrics: jokainen havainto on ennustettu mallilla, joka ei nähnyt
# kyseistä outer-testiyksikköä missään valinta- tai sovitusvaiheessa.
# evaluation on yksikäsitteisesti outer_year tai outer_site, joten pooled-metriikat
# voidaan laskea suoraan kaikista outer-testien riviennusteista.
pooled_outer_metrics <- metrics_from_point_predictions(all_predictions) %>%
  mutate(
    scheme = sub("^outer_", "", .data$evaluation),
    .before = 1
  )

# Foldikohtainen keskiarvo ja hajonta.
fold_metric_summary <- all_fold_metrics %>%
  group_by(.data$scheme, .data$model_type, .data$species) %>%
  summarise(
    n_folds = n_distinct(.data$outer_fold),
    mean_RMSE = mean(.data$RMSE, na.rm = TRUE),
    sd_RMSE = sd(.data$RMSE, na.rm = TRUE),
    mean_SR2 = mean(.data$SR2, na.rm = TRUE),
    sd_SR2 = sd(.data$SR2, na.rm = TRUE),
    mean_O_AUC = mean(.data$O.AUC, na.rm = TRUE),
    sd_O_AUC = sd(.data$O.AUC, na.rm = TRUE),
    .groups = "drop"
  )

# WEATHER_PLUS_ENVIRONMENT - WEATHER_ONLY pooled delta.
pooled_environment_delta <- pooled_outer_metrics %>%
  select(.data$scheme, .data$species, .data$model_type, .data$RMSE, .data$SR2, .data$O.AUC) %>%
  pivot_wider(
    names_from = .data$model_type,
    values_from = c(.data$RMSE, .data$SR2, .data$O.AUC)
  ) %>%
  mutate(
    delta_SR2_environment = .data$SR2_WEATHER_PLUS_ENVIRONMENT - .data$SR2_WEATHER_ONLY,
    delta_RMSE_environment = .data$RMSE_WEATHER_PLUS_ENVIRONMENT - .data$RMSE_WEATHER_ONLY,
    delta_O_AUC_environment = .data$O.AUC_WEATHER_PLUS_ENVIRONMENT - .data$O.AUC_WEATHER_ONLY
  )

scheme_fold_counts <- bind_rows(lapply(all_results, function(z) {
  data.frame(scheme = z$scheme, outer_fold = z$outer_fold, stringsAsFactors = FALSE)
})) %>%
  distinct(.data$scheme, .data$outer_fold) %>%
  count(.data$scheme, name = "n_outer_folds_run")

selection_frequency <- function(x, item_col) {
  if (nrow(x) == 0L) return(data.frame())
  tmp <- x %>%
    transmute(
      scheme = as.character(.data$scheme),
      item = as.character(.data[[item_col]])
    ) %>%
    filter(!is.na(.data$item), nzchar(.data$item)) %>%
    count(.data$scheme, .data$item, name = "n_outer_folds_selected") %>%
    left_join(scheme_fold_counts, by = "scheme") %>%
    mutate(
      selection_frequency = .data$n_outer_folds_selected / .data$n_outer_folds_run
    )
  names(tmp)[names(tmp) == "item"] <- item_col
  tmp
}

weather_group_stability <- selection_frequency(all_weather_groups, "group")
weather_variable_stability <- selection_frequency(all_weather_variables, "variable")
environment_group_stability <- selection_frequency(all_environment_groups, "group")
environment_variable_stability <- selection_frequency(all_environment_variables, "variable")

#===============================================================================
# 13. TALLENNA LOPPUTULOKSET
#===============================================================================

write_csv2(all_predictions, file.path(output_root, "S3_all_outer_test_predictions.csv2"))
write_csv2(all_fold_metrics, file.path(output_root, "S3_outer_fold_metrics.csv2"))
write_csv2(pooled_outer_metrics, file.path(output_root, "S3_POOLED_OUTER_PREDICTIVE_METRICS.csv2"))
write_csv2(fold_metric_summary, file.path(output_root, "S3_outer_fold_metric_summary.csv2"))
write_csv2(pooled_environment_delta, file.path(output_root, "S3_environment_incremental_predictive_value.csv2"))
write_csv2(all_coverage, file.path(output_root, "S3_outer_coverage.csv2"))
write_csv2(weather_group_stability, file.path(output_root, "S3_weather_group_selection_stability.csv2"))
write_csv2(weather_variable_stability, file.path(output_root, "S3_weather_variable_selection_stability.csv2"))
write_csv2(environment_group_stability, file.path(output_root, "S3_environment_group_selection_stability.csv2"))
write_csv2(environment_variable_stability, file.path(output_root, "S3_environment_variable_selection_stability.csv2"))

S3_RESULTS <- list(
  role = "NESTED_OUTER_CROSS_VALIDATION_OF_FULL_PREDICTIVE_SELECTION_PIPELINE",
  primary_result = "outer_year",
  secondary_result = "outer_site",
  response_definition = paste0(
    "annual total_count with Loff = log(total_effort_days / ",
    annual_index_standard_days,
    ")"
  ),
  distribution = hmsc_distribution,
  outer_year_nfolds = outer_year_nfolds,
  outer_site_nfolds = outer_site_nfolds,
  inner_year_nfolds = inner_year_nfolds,
  outer_year_results = outer_year_results,
  outer_site_results = outer_site_results,
  pooled_outer_metrics = pooled_outer_metrics,
  fold_metric_summary = fold_metric_summary,
  environment_incremental_predictive_value = pooled_environment_delta,
  coverage = all_coverage,
  weather_group_stability = weather_group_stability,
  weather_variable_stability = weather_variable_stability,
  environment_group_stability = environment_group_stability,
  environment_variable_stability = environment_variable_stability
)

saveRDS(S3_RESULTS, file.path(output_root, "S3_NESTED_OUTER_CV_RESULTS.rds"))

#===============================================================================
# 14. ENGLANNINKIELINEN MENETELMÄ- JA TULOSRUNKO
#===============================================================================

markdown_table <- function(x, digits = 3L) {
  if (is.null(x) || nrow(as.data.frame(x)) == 0L) return("No rows.")
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  x[] <- lapply(x, function(z) {
    if (is.numeric(z)) format(round(z, digits), trim = TRUE, scientific = FALSE) else as.character(z)
  })
  x[] <- lapply(x, function(z) gsub("\\|", "/", z))
  c(
    paste0("| ", paste(names(x), collapse = " | "), " |"),
    paste0("| ", paste(rep("---", ncol(x)), collapse = " | "), " |"),
    apply(x, 1, function(z) paste0("| ", paste(z, collapse = " | "), " |"))
  )
}

presentation_lines <- c(
  "# S3 nested outer cross-validation of the predictive Hmsc workflow",
  "",
  "## Purpose",
  "",
  "Predictive performance was evaluated with an outer cross-validation layer that was completely separated from predictor selection.",
  "Within every outer training set, weather and environmental predictors were reselected from the original candidate sets using inner year-blocked cross-validation. The held-out outer observations were not used for correlation filtering, availability decisions, predictor selection, scaling, or model fitting.",
  "",
  "## Primary predictive target",
  "",
  "The primary evaluation is outer-year cross-validation, where complete years are held out. This estimates predictive performance for years not used anywhere in model construction.",
  "",
  "## Secondary predictive target",
  "",
  "Outer-site cross-validation holds out complete sites and evaluates transferability to sites not used anywhere in model construction.",
  "",
  "## Final outer-test performance",
  "",
  markdown_table(pooled_outer_metrics),
  "",
  "## Incremental predictive value of environmental predictors",
  "",
  "Positive delta SR2 and negative delta RMSE favour WEATHER_PLUS_ENVIRONMENT over WEATHER_ONLY on the same outer-test observations.",
  "",
  markdown_table(pooled_environment_delta),
  "",
  "## Predictor-selection stability across outer folds",
  "",
  "### Weather groups",
  "",
  markdown_table(weather_group_stability),
  "",
  "### Environmental groups",
  "",
  markdown_table(environment_group_stability)
)

writeLines(
  unlist(presentation_lines),
  con = file.path(output_root, "S3_PRESENTATION_NESTED_OUTER_CV.md")
)

writeLines(
  capture.output(sessionInfo()),
  con = file.path(output_root, "sessionInfo.txt")
)

#===============================================================================
# 15. KONSOLIKOONTI
#===============================================================================

cat("\n========================================================\n")
cat("S3 NESTED OUTER CROSS-VALIDATION COMPLETE\n")
cat("========================================================\n")
cat("Päätulos: outer_year\n")
cat("Toissijainen: outer_site\n")
cat("\nPOOLED OUTER METRICS:\n")
print(pooled_outer_metrics, row.names = FALSE)
cat("\nENVIRONMENT INCREMENTAL PREDICTIVE VALUE:\n")
print(pooled_environment_delta, row.names = FALSE)
cat("\nTulokset:", output_root, "\n")
#===============================================================================
