#===============================================================================
# S1/S2 C+D VUOSITASOLLA: YKSI BUFFERI / EKOLOGINEN RYHMA
#                         JA YMPARISTOVALINTA YHTEISILLA RIVEILLA
#
# TAMA TIEDOSTO LIITETAAN SUORAAN TIEDOSTON
# S1_S2_b_HMSC_annual_common_phenology_years_sensitivity_STANDALONE.R
# PERAAN SAMAAN R-AJOON.
#
# Se ei lue tai source()-kutsu muita R-skripteja. Edellinen vaihe tuo samaan
# R-istuntoon vuosimallin Hmsc-apufunktiot. Tama vaihe lukee uudelleen vain
# paavuosimallin valmiin RData-tiedoston, jotta ymparistovalinta kayttaa koko
# vuosiaineistoa eika fenologiaherkkyysanalyysin ajallisesti rajattua aineistoa.
#
# Menetelma:
#   1. lukitse paamallissa valitut saamuuttujat
#   2. vertaa kunkin ekologisen ryhman buffereita samoilla paikkavuosilla
#   3. valitse yksi bufferi jokaista vertailukelpoista ryhmaa kohti
#   4. muodosta yksi kiintea paikkavuosipaneeli kaikille ymparistoryhmille
#   5. tee ryhmien forward-valinta ja ryhmasuojattu backward-valinta
#   6. sovita lopulliset WEATHER_ONLY- ja WEATHER_PLUS_ENVIRONMENT-mallit
#      samoille riveille
#   7. tallenna explanatory-metriikat, PPC, beta-parametrit,
#      varianssiositus, konvergenssi ja WAIC
#
# TARKEA OFFSET-KORJAUS:
#   - Hmsc:n computePredictedValues()-funktiota ei kayteta tassa skriptissa.
#   - Kaikki explanatory-ennusteet lasketaan eksplisiittisesti komennolla
#       predict(model, Loff = model$Loff, expected = TRUE)
#   - Posterior predictive -tarkistus lasketaan komennolla
#       predict(model, Loff = model$Loff, expected = FALSE)
#   - Offset lisataan siis lineaariseen ennustimeen ennen Poisson-arvontaa.
#     Toteutuneita lukumaaria ei kerrota offsetilla jalkeenpain.
#
# Vaste: vuotuinen kokonaislukumaara
# Jakauma: lognormal Poisson
# Offset: Loff = log(total_effort_days / 7)
# Satunnaistasot: site ja year
# Splineja: ei
# Ristiinvalidointia: ei
#===============================================================================

gc()
set.seed(3)

#===============================================================================
# 1. KAYTTAJAN ASETUKSET
#===============================================================================

primary_output_dir <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "HMSC_ANNUAL_PRIMARY_EXPLANATORY_LOGNORMAL_POISSON_v1"
)

primary_rdata_file <- file.path(
  primary_output_dir,
  "HMSC_annual_three_species_weather_environment_buffers_results.RData"
)

phenology_sensitivity_file <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "HMSC_ANNUAL_COMMON_PHENOLOGY_YEARS_SENSITIVITY_v1",
  "SENSITIVITY_ANNUAL_COMMON_PHENOLOGY_RESULTS.rds"
)

output_root <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "HMSC_ANNUAL_ONE_BUFFER_MATCHED_ENVIRONMENT_SELECTION_v2_OFFSET_CORRECTED"
)

# Skripti ei poista tai korvaa aikaisempia tuloksia. Jos kansio on jo
# ei-tyhja, vaihda versionumeroa output_root-polussa.
stop_if_output_exists <- TRUE

# Aikaisemman paamallin PPC on voitu laskea ilman eksplisiittista offsetia.
# TRUE sallii taman skriptin offset-korjatun ymparistovalinnan jatkumisen,
# vaikka aikaisempaa PPC:ta ei voida varmistaa offset-tietoiseksi.
allow_environment_selection_despite_primary_ppc_failure <- TRUE

# Saatavuusrajat perustuvat vain selittajiin, eivat vasteeseen.
minimum_samples <- 500L
minimum_sites <- 20L
minimum_years <- 3L
minimum_buffer_fraction_of_best <- 0.80
minimum_common_fraction_of_best <- 0.60

# Selittavan valinnan kriteerit.
max_selected_environment_groups <- 4L
confirm_top_n <- 2L
min_community_delta_SR2 <- 0.002
min_strong_species_delta_SR2 <- 0.010
max_harm_to_other_species <- 0.010
minimum_nonnegative_species <- 2L
max_backward_mean_loss <- 0.001
minimum_variables_per_selected_group <- 1L
delta_tolerance <- 1e-8

# Valinta-ajot ja lopullinen pitka ajo.
MCMC <- list(
  screen = list(
    samples = 100L, transient = 100L, thin = 5L,
    chains = 2L, parallel = 2L
  ),
  confirm = list(
    samples = 300L, transient = 300L, thin = 5L,
    chains = 2L, parallel = 2L
  ),
  final = list(
    samples = 5000L, transient = 10000L, thin = 20L,
    chains = 4L, parallel = 4L
  )
)

run_availability_sensitivity <- TRUE

# Ennustamiseen kaytetaan enintaan tama maara posteriorinaytteita.
# Tama ei muuta sovitettua posterioria, vaan rajoittaa vain arvioinnin muistia.
max_prediction_draws <- 1000L

#===============================================================================
# 2. EDELLISEN VAIHEEN JA APUFUNKTOIDEN TARKISTUS
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
# 2A. C+D-VAIHEEN TARVITSEMAT APUFUNKTIOT
#===============================================================================

# Tee mallien ja tiedostojen nimistä turvallisia
safe_name <- function(x) {
  gsub("[^A-Za-z0-9_]+", "_", as.character(x))
}

# Poista bufferisuffiksi, esim.
# "forest_pct__b500m" -> "forest_pct"
strip_buffer_suffix <- function(x) {
  sub("__b.+m$", "", as.character(x))
}

# Fenologiaherkkyyden tulos otetaan ensisijaisesti samasta R-istunnosta.
if (exists("SENSITIVITY_RESULTS", inherits = FALSE)) {
  phenology_sensitivity_result <- get(
    "SENSITIVITY_RESULTS",
    envir = .GlobalEnv,
    inherits = FALSE
  )
} else if (file.exists(phenology_sensitivity_file)) {
  phenology_sensitivity_result <- readRDS(phenology_sensitivity_file)
} else {
  stop(
    "Fenologiaherkkyysvaiheen tulosta ei ole R-istunnossa eika tiedostossa: ",
    phenology_sensitivity_file
  )
}

if (!file.exists(primary_rdata_file)) {
  stop("Paavuosimallin RData-tiedostoa ei loydy: ", primary_rdata_file)
}

#===============================================================================
# 3. TULOSHAKEMISTOT
#===============================================================================

if (
  dir.exists(output_root) &&
  length(list.files(output_root, all.files = FALSE, no.. = TRUE)) > 0L &&
  stop_if_output_exists
) {
  stop(
    "Tuloshakemisto sisaltaa jo tiedostoja: ", output_root,
    "\nVaihda output_root-polun versionumeroa. Mitakaan ei poistettu."
  )
}

diagnostic_dir <- file.path(output_root, "01_data_and_availability")
buffer_dir <- file.path(output_root, "02_buffer_selection")
selection_dir <- file.path(output_root, "03_environment_selection")
final_dir <- file.path(output_root, "04_final_models")
sensitivity_dir <- file.path(output_root, "05_availability_sensitivity")

for (directory in c(
  diagnostic_dir,
  buffer_dir,
  selection_dir,
  final_dir,
  sensitivity_dir
)) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
}

write_csv2 <- function(x, path) {
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  if (ncol(x) == 0L) {
    x <- data.frame(status = "no_rows", stringsAsFactors = FALSE)
  }
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

#===============================================================================
# 4. PALAUTA KOKO PAAVUOSIMALLIN AINEISTO
#===============================================================================

primary_env <- new.env(parent = globalenv())
loaded_primary_objects <- load(primary_rdata_file, envir = primary_env)

required_primary_objects <- c(
  "target_species",
  "Y_annual_all",
  "Loff_annual_all",
  "sample_metadata",
  "X_sample",
  "weather_groups",
  "environment_groups",
  "environment_groups_buffered",
  "environment_candidate_table",
  "selected_weather_groups",
  "selected_weather_variables",
  "final_result"
)

missing_primary_objects <- setdiff(
  required_primary_objects,
  loaded_primary_objects
)

if (length(missing_primary_objects) > 0L) {
  stop(
    "Paavuosimallin RData-tiedostosta puuttuvat objektit: ",
    paste(missing_primary_objects, collapse = ", ")
  )
}

for (object_name in required_primary_objects) {
  assign(
    object_name,
    get(object_name, envir = primary_env),
    envir = .GlobalEnv
  )
}

locked_weather_groups <- unique(as.character(selected_weather_groups))
locked_weather_variables <- unique(as.character(selected_weather_variables))
locked_weather_variables <- locked_weather_variables[
  !is.na(locked_weather_variables) & nzchar(locked_weather_variables)
]

if (length(locked_weather_variables) == 0L) {
  stop("Paavuosimallista ei loytynyt lukittuja saamuuttujia.")
}

# Fenologia-analyysi on herkkyystarkistus. Se ei automaattisesti korvaa
# paamallissa lukittua saavalintaa.
phenology_selection_same <- isTRUE(
  phenology_sensitivity_result$identical_weather_variable_sets
)

primary_ppc <- final_result$posterior_predictive_check
primary_offset_evaluation_used <- isTRUE(
  final_result$offset_prediction_used
)
primary_ppc_ok <-
  primary_offset_evaluation_used &&
  !is.null(primary_ppc) &&
  is.data.frame(primary_ppc) &&
  nrow(primary_ppc) > 0L &&
  "ppc_status" %in% names(primary_ppc) &&
  all(primary_ppc$ppc_status == "OK")

if (!primary_ppc_ok) {
  ppc_message <- paste(
    "Aikaisemman paavuosimallin posterior predictive -tarkistusta ei voida",
    "vahvistaa eksplisiittisesti offset-tietoiseksi. Tama skripti laskee",
    "kaikki uudet bufferi-, ymparisto- ja loppumallivertailut oikein",
    "predict(..., Loff = model$Loff) -ennusteilla. Lukittu saavalinta on",
    "silti aikaisemman vaiheen syote, kunnes myos saavalinta ajetaan",
    "offset-korjatulla arvioinnilla."
  )
  if (!allow_environment_selection_despite_primary_ppc_failure) {
    stop(ppc_message)
  }
  warning(ppc_message)
}

analysis_status <- if (primary_ppc_ok) {
  "OFFSET_CORRECTED_ENVIRONMENT_SELECTION_PRIMARY_INPUT_VERIFIED"
} else {
  "OFFSET_CORRECTED_ENVIRONMENT_SELECTION_LOCKED_WEATHER_INPUT_NOT_REVALIDATED"
}

# Palauta koko aineiston rivijarjestys. Edellinen vaihe rajasi samannimiset
# globaalit objektit yhteisille fenologiavuosille.
common_ids <- Reduce(
  intersect,
  list(
    rownames(Y_annual_all),
    rownames(Loff_annual_all),
    as.character(sample_metadata$sample_id),
    as.character(X_sample$sample_id)
  )
)

common_ids <- rownames(Y_annual_all)[rownames(Y_annual_all) %in% common_ids]

if (length(common_ids) == 0L) {
  stop("Paavuosimallin vuosimatriiseilla ei ole yhteisia sample_id-riveja.")
}

Y_annual_all <- Y_annual_all[common_ids, , drop = FALSE]
Loff_annual_all <- Loff_annual_all[common_ids, , drop = FALSE]
sample_metadata <- sample_metadata %>%
  filter(sample_id %in% common_ids) %>%
  arrange(match(sample_id, common_ids))
X_sample <- X_sample %>%
  filter(sample_id %in% common_ids) %>%
  arrange(match(sample_id, common_ids))

if (
  !identical(sample_metadata$sample_id, common_ids) ||
  !identical(X_sample$sample_id, common_ids)
) {
  stop("Koko vuosiaineiston rivijarjestyksen palautus epaonnistui.")
}

if (!identical(dim(Y_annual_all), dim(Loff_annual_all))) {
  stop("Koko vuosiaineiston Y- ja Loff-matriisien mitat eivat tasmaa.")
}
if (is.null(colnames(Loff_annual_all))) {
  colnames(Loff_annual_all) <- colnames(Y_annual_all)
}
if (is.null(colnames(Loff_annual_all))) {
  stop("Loff-matriisilta puuttuvat lajien sarakenimet.")
}

offset_multiplier <- exp(Loff_annual_all)
offset_diagnostic <- bind_rows(lapply(seq_len(ncol(offset_multiplier)), function(j) {
  values <- offset_multiplier[, j]
  data.frame(
    species = colnames(Loff_annual_all)[j],
    minimum = min(values, na.rm = TRUE),
    q25 = unname(quantile(values, 0.25, na.rm = TRUE)),
    median = median(values, na.rm = TRUE),
    mean = mean(values, na.rm = TRUE),
    q75 = unname(quantile(values, 0.75, na.rm = TRUE)),
    maximum = max(values, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}))
write_csv2(
  offset_diagnostic,
  file.path(diagnostic_dir, "effort_offset_multiplier_summary.csv2")
)

missing_locked_weather <- setdiff(locked_weather_variables, names(X_sample))
if (length(missing_locked_weather) > 0L) {
  stop(
    "Lukittuja saamuuttujia puuttuu X_sample-taulusta: ",
    paste(missing_locked_weather, collapse = ", ")
  )
}

selected_weather_variables <- locked_weather_variables
selected_environment_variables <- character(0)
hmsc_distribution <- "lognormal poisson"
annual_index_standard_days <- 7
run_quick_test <- FALSE

# fit_hmsc_model() kirjoittaa tuloksensa kulloisenkin vaiheen hakemistoon.
modelDir <- buffer_dir

#===============================================================================
# 5. VERTAILU- JA SAATAVUUSAPUFUNKTIOT
#===============================================================================

complete_ids <- function(
    variables,
    within_ids = as.character(X_sample$sample_id)
) {
  variables <- unique(as.character(variables))
  missing_variables <- setdiff(variables, names(X_sample))
  if (length(missing_variables) > 0L) {
    stop(
      "Selittajasarakkeita puuttuu X_sample-taulusta: ",
      paste(missing_variables, collapse = ", ")
    )
  }
  
  rows <- match(within_ids, X_sample$sample_id)
  valid <- !is.na(rows)
  
  if (length(variables) > 0L) {
    predictor_ok <- rep(FALSE, length(rows))
    predictor_ok[valid] <- apply(
      as.matrix(X_sample[rows[valid], variables, drop = FALSE]),
      1,
      function(z) all(is.finite(z))
    )
    valid <- valid & predictor_ok
  }
  
  y_rows <- match(within_ids, rownames(Y_annual_all))
  offset_rows <- match(within_ids, rownames(Loff_annual_all))
  matrix_ok <- !is.na(y_rows) & !is.na(offset_rows)
  matrix_ok[matrix_ok] <-
    rowSums(is.finite(Y_annual_all[y_rows[matrix_ok], , drop = FALSE])) > 0L &
    apply(
      Loff_annual_all[offset_rows[matrix_ok], , drop = FALSE],
      1,
      function(z) all(is.finite(z))
    )
  
  within_ids[valid & matrix_ok]
}

coverage_row <- function(ids, label = NA_character_) {
  metadata <- sample_metadata[
    match(ids, sample_metadata$sample_id),
    ,
    drop = FALSE
  ]
  data.frame(
    label = label,
    n_site_years = length(ids),
    n_sites = dplyr::n_distinct(metadata$site),
    n_years = dplyr::n_distinct(metadata$year),
    first_year = if (nrow(metadata)) min(metadata$year) else NA_real_,
    last_year = if (nrow(metadata)) max(metadata$year) else NA_real_,
    stringsAsFactors = FALSE
  )
}

meets_coverage <- function(ids) {
  coverage <- coverage_row(ids)
  coverage$n_site_years >= minimum_samples &&
    coverage$n_sites >= minimum_sites &&
    coverage$n_years >= minimum_years
}

variables_vary <- function(variables, ids) {
  rows <- match(ids, X_sample$sample_id)
  if (anyNA(rows)) return(FALSE)
  all(vapply(
    variables,
    function(variable) {
      z <- X_sample[[variable]][rows]
      z <- z[is.finite(z)]
      length(z) > 1L && length(unique(z)) > 1L
    },
    logical(1)
  ))
}

remove_zero_variance_names_cd <- function(data, variables) {
  kept <- variables[vapply(
    variables,
    function(variable) {
      z <- data[[variable]]
      z <- z[is.finite(z)]
      length(z) > 1L && length(unique(z)) > 1L
    },
    logical(1)
  )]
  list(kept = kept, removed = setdiff(variables, kept))
}

prediction_posterior_cd <- function(model, maximum_draws) {
  if (length(model$postList) == 0L) {
    stop("Mallissa ei ole posteriorinaytteita.")
  }
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

predict_array_offset_cd <- function(model, post, expected, seed) {
  if (is.null(model$Loff)) {
    stop("Hmsc-mallista puuttuu Loff; arviointia ei jatketa.")
  }
  if (!identical(dim(model$Loff), dim(model$Y))) {
    stop("Hmsc-mallin Loff- ja Y-matriisien mitat eivat tasmaa.")
  }
  set.seed(seed)
  predicted_list <- predict(
    model,
    post = post,
    Loff = model$Loff,
    expected = expected,
    nParallel = 1L
  )
  predicted <- simplify2array(predicted_list)
  expected_dimensions <- c(nrow(model$Y), ncol(model$Y), length(post))
  if (!identical(as.integer(dim(predicted)), as.integer(expected_dimensions))) {
    stop(
      "Offset-ennusteen mitat ovat virheelliset. Saatiin ",
      paste(dim(predicted), collapse = " x "),
      ", odotettiin ", paste(expected_dimensions, collapse = " x "), "."
    )
  }
  predicted
}

auc_rank_cd <- function(observed, probability) {
  keep <- is.finite(observed) & is.finite(probability)
  observed <- observed[keep]
  probability <- probability[keep]
  n_positive <- sum(observed == 1)
  n_negative <- sum(observed == 0)
  if (n_positive == 0L || n_negative == 0L) return(NA_real_)
  ranks <- rank(probability, ties.method = "average")
  (
    sum(ranks[observed == 1]) -
      n_positive * (n_positive + 1) / 2
  ) / (n_positive * n_negative)
}

occurrence_metrics_cd <- function(Y, predicted_realized) {
  presence_probability <- 1 - apply(
    predicted_realized == 0,
    c(1, 2),
    mean,
    na.rm = TRUE
  )
  bind_rows(lapply(seq_len(ncol(Y)), function(species_index) {
    observed <- as.numeric(Y[, species_index] > 0)
    probability <- presence_probability[, species_index]
    positive <- observed == 1
    negative <- observed == 0
    data.frame(
      species = colnames(Y)[species_index],
      O.RMSE = sqrt(mean((observed - probability)^2, na.rm = TRUE)),
      O.AUC = auc_rank_cd(observed, probability),
      O.TjurR2 = if (
        any(positive, na.rm = TRUE) &&
        any(negative, na.rm = TRUE)
      ) {
        mean(probability[positive], na.rm = TRUE) -
          mean(probability[negative], na.rm = TRUE)
      } else {
        NA_real_
      },
      stringsAsFactors = FALSE
    )
  }))
}

metric_value_cd <- function(model_fit, metric, n_species) {
  value <- model_fit[[metric]]
  if (is.null(value) || length(value) != n_species) {
    rep(NA_real_, n_species)
  } else {
    as.numeric(value)
  }
}

metric_table_offset_cd <- function(
    model_name,
    species_names,
    model_fit,
    occurrence_metrics = NULL
) {
  n_species <- length(species_names)
  result <- data.frame(
    model = model_name,
    evaluation = "explanatory_offset_corrected",
    species = species_names,
    RMSE = metric_value_cd(model_fit, "RMSE", n_species),
    SR2 = metric_value_cd(model_fit, "SR2", n_species),
    O.RMSE = NA_real_,
    O.AUC = NA_real_,
    O.TjurR2 = NA_real_,
    C.RMSE = metric_value_cd(model_fit, "C.RMSE", n_species),
    C.SR2 = metric_value_cd(model_fit, "C.SR2", n_species),
    stringsAsFactors = FALSE
  )
  if (!is.null(occurrence_metrics) && nrow(occurrence_metrics) > 0L) {
    occurrence_metrics <- occurrence_metrics[
      match(result$species, occurrence_metrics$species),
      ,
      drop = FALSE
    ]
    result$O.RMSE <- occurrence_metrics$O.RMSE
    result$O.AUC <- occurrence_metrics$O.AUC
    result$O.TjurR2 <- occurrence_metrics$O.TjurR2
  }
  result
}

metric_summary_cd <- function(metrics) {
  metric_names <- intersect(
    c("RMSE", "SR2", "O.RMSE", "O.AUC", "O.TjurR2", "C.RMSE", "C.SR2"),
    names(metrics)
  )
  bind_rows(lapply(metric_names, function(metric_name) {
    values <- metrics[[metric_name]]
    values <- values[is.finite(values)]
    data.frame(
      metric = metric_name,
      mean = if (length(values)) mean(values) else NA_real_,
      median = if (length(values)) median(values) else NA_real_,
      minimum = if (length(values)) min(values) else NA_real_,
      maximum = if (length(values)) max(values) else NA_real_,
      stringsAsFactors = FALSE
    )
  }))
}

ppc_interval_cd <- function(draws, observed) {
  draws <- draws[is.finite(draws)]
  if (!length(draws) || !is.finite(observed)) {
    return(c(q025 = NA_real_, median = NA_real_, q975 = NA_real_,
             covered = NA_real_, p_value = NA_real_))
  }
  interval <- quantile(draws, c(0.025, 0.5, 0.975), na.rm = TRUE)
  p_value <- min(
    1,
    2 * min(mean(draws <= observed), mean(draws >= observed))
  )
  c(
    q025 = unname(interval[1]),
    median = unname(interval[2]),
    q975 = unname(interval[3]),
    covered = as.numeric(observed >= interval[1] && observed <= interval[3]),
    p_value = p_value
  )
}

posterior_predictive_check_offset_cd <- function(
    model_name,
    Y,
    predicted_realized
) {
  bind_rows(lapply(seq_len(ncol(Y)), function(species_index) {
    predicted_species <- predicted_realized[
      , species_index, , drop = FALSE
    ]
    draw_mean <- apply(predicted_species, 3, mean, na.rm = TRUE)
    draw_zero <- apply(
      predicted_species, 3,
      function(z) mean(z == 0, na.rm = TRUE)
    )
    draw_q95 <- apply(
      predicted_species, 3,
      function(z) unname(quantile(z, 0.95, na.rm = TRUE))
    )
    draw_q99 <- apply(
      predicted_species, 3,
      function(z) unname(quantile(z, 0.99, na.rm = TRUE))
    )
    draw_maximum <- apply(predicted_species, 3, max, na.rm = TRUE)
    observed <- Y[, species_index]
    observed_mean <- mean(observed, na.rm = TRUE)
    observed_zero <- mean(observed == 0, na.rm = TRUE)
    observed_q95 <- unname(quantile(observed, 0.95, na.rm = TRUE))
    observed_q99 <- unname(quantile(observed, 0.99, na.rm = TRUE))
    observed_maximum <- max(observed, na.rm = TRUE)
    mean_check <- ppc_interval_cd(draw_mean, observed_mean)
    zero_check <- ppc_interval_cd(draw_zero, observed_zero)
    q95_check <- ppc_interval_cd(draw_q95, observed_q95)
    q99_check <- ppc_interval_cd(draw_q99, observed_q99)
    maximum_check <- ppc_interval_cd(draw_maximum, observed_maximum)
    core_ok <- isTRUE(all(c(
      mean_check["covered"],
      zero_check["covered"],
      q95_check["covered"]
    ) == 1))
    central_and_zero_ok <- isTRUE(all(c(
      zero_check["covered"],
      q95_check["covered"]
    ) == 1))
    tail_ok <- isTRUE(all(c(
      q99_check["covered"],
      maximum_check["covered"]
    ) == 1))
    ppc_status <- if (core_ok && tail_ok) {
      "OK"
    } else if (central_and_zero_ok && (!core_ok || !tail_ok)) {
      "UPPER_TAIL_REQUIRES_REVIEW"
    } else {
      "REQUIRES_REVIEW"
    }
    data.frame(
      model = model_name,
      species = colnames(Y)[species_index],
      n = sum(is.finite(observed)),
      posterior_predictive_draws = dim(predicted_realized)[3],
      observed_mean = observed_mean,
      predicted_mean_q025 = mean_check["q025"],
      predicted_mean_median = mean_check["median"],
      predicted_mean_q975 = mean_check["q975"],
      mean_covered_95 = as.logical(mean_check["covered"]),
      mean_ppc_p = mean_check["p_value"],
      observed_zero_proportion = observed_zero,
      predicted_zero_q025 = zero_check["q025"],
      predicted_zero_median = zero_check["median"],
      predicted_zero_q975 = zero_check["q975"],
      zero_covered_95 = as.logical(zero_check["covered"]),
      zero_ppc_p = zero_check["p_value"],
      observed_q95 = observed_q95,
      predicted_q95_q025 = q95_check["q025"],
      predicted_q95_median = q95_check["median"],
      predicted_q95_q975 = q95_check["q975"],
      q95_covered_95 = as.logical(q95_check["covered"]),
      q95_ppc_p = q95_check["p_value"],
      observed_q99 = observed_q99,
      predicted_q99_q025 = q99_check["q025"],
      predicted_q99_median = q99_check["median"],
      predicted_q99_q975 = q99_check["q975"],
      q99_covered_95 = as.logical(q99_check["covered"]),
      q99_ppc_p = q99_check["p_value"],
      observed_maximum = observed_maximum,
      predicted_maximum_q025 = maximum_check["q025"],
      predicted_maximum_median = maximum_check["median"],
      predicted_maximum_q975 = maximum_check["q975"],
      maximum_covered_95 = as.logical(maximum_check["covered"]),
      maximum_ppc_p = maximum_check["p_value"],
      ppc_status = ppc_status,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  }))
}

fit_hmsc_model_offset_cd <- function(
    model_name,
    variables,
    sample_ids,
    response_matrix,
    offset_matrix,
    mcmc,
    seed,
    final_model = FALSE,
    calculate_vp = FALSE
) {
  set.seed(seed)
  variables <- unique(as.character(variables))
  missing_variables <- setdiff(variables, names(X_sample))
  if (length(missing_variables) > 0L) {
    stop(
      "Mallin selittajia puuttuu X_sample-taulusta: ",
      paste(missing_variables, collapse = ", ")
    )
  }
  metadata_model <- sample_metadata %>%
    filter(.data$sample_id %in% sample_ids) %>%
    arrange(match(.data$sample_id, sample_ids))
  X_raw <- X_sample %>%
    filter(.data$sample_id %in% sample_ids) %>%
    arrange(match(.data$sample_id, sample_ids)) %>%
    select(sample_id, all_of(variables))
  if (
    !identical(as.character(metadata_model$sample_id), sample_ids) ||
    !identical(as.character(X_raw$sample_id), sample_ids)
  ) {
    stop("X-, metadata- tai sample_id-rivijarjestys ei tasmaa: ", model_name)
  }
  response_rows <- match(sample_ids, rownames(response_matrix))
  offset_rows <- match(sample_ids, rownames(offset_matrix))
  if (anyNA(response_rows) || anyNA(offset_rows)) {
    stop("Vaste- tai offset-riveja puuttuu mallista: ", model_name)
  }
  predictor_finite <- if (length(variables)) {
    apply(
      as.matrix(X_raw[, variables, drop = FALSE]),
      1,
      function(z) all(is.finite(z))
    )
  } else {
    rep(TRUE, nrow(X_raw))
  }
  response_finite <- rowSums(
    is.finite(response_matrix[response_rows, , drop = FALSE])
  ) > 0L
  offset_finite <- apply(
    offset_matrix[offset_rows, , drop = FALSE],
    1,
    function(z) all(is.finite(z))
  )
  keep_rows <- predictor_finite & response_finite & offset_finite
  X_raw <- X_raw[keep_rows, , drop = FALSE]
  metadata_model <- metadata_model[keep_rows, , drop = FALSE]
  if (nrow(X_raw) < 20L) stop("Malliin jai alle 20 havaintoa: ", model_name)
  zero_variance <- remove_zero_variance_names_cd(X_raw, variables)
  variables_kept <- zero_variance$kept
  if (length(variables_kept)) {
    X_scaled <- as.data.frame(scale(X_raw[, variables_kept, drop = FALSE]))
    names(X_scaled) <- variables_kept
    X_formula <- reformulate(variables_kept)
  } else {
    X_scaled <- data.frame(intercept_helper = rep(0, nrow(X_raw)))
    X_formula <- ~ 1
  }
  if (any(!is.finite(as.matrix(X_scaled)))) {
    stop("Selittajien standardoinnin jalkeen jai NA/Inf-arvoja: ", model_name)
  }
  rownames(X_scaled) <- X_raw$sample_id
  Y_model <- response_matrix[X_raw$sample_id, , drop = FALSE]
  Loff_model <- offset_matrix[X_raw$sample_id, , drop = FALSE]
  storage.mode(Y_model) <- "numeric"
  storage.mode(Loff_model) <- "numeric"
  dimnames(Loff_model) <- dimnames(Y_model)
  if (any(Y_model < 0, na.rm = TRUE)) {
    stop("Poisson-vasteessa on negatiivisia arvoja: ", model_name)
  }
  studyDesign <- data.frame(
    site = factor(metadata_model$site),
    year = factor(metadata_model$year)
  )
  rownames(studyDesign) <- metadata_model$sample_id
  model_unfitted <- Hmsc(
    Y = Y_model,
    distr = rep(hmsc_distribution, ncol(Y_model)),
    Loff = Loff_model,
    XData = X_scaled,
    XScale = FALSE,
    YScale = FALSE,
    XFormula = X_formula,
    studyDesign = studyDesign,
    ranLevels = list(
      site = HmscRandomLevel(units = levels(studyDesign$site)),
      year = HmscRandomLevel(units = levels(studyDesign$year))
    )
  )
  if (isTRUE(run_quick_test)) {
    quick_model <- sampleMcmc(
      model_unfitted,
      samples = quick_samples,
      transient = quick_transient,
      thin = quick_thin,
      nChains = quick_chains,
      nParallel = 1L,
      verbose = 0
    )
    rm(quick_model)
    gc()
  }
  cat(
    "\n", model_name,
    ": n=", nrow(Y_model),
    ", predictors=", length(variables_kept),
    ", samples=", mcmc$samples,
    ", chains=", mcmc$chains,
    ", explicit_offset_predictions=TRUE\n",
    sep = ""
  )
  model_fitted <- sampleMcmc(
    model_unfitted,
    samples = mcmc$samples,
    transient = mcmc$transient,
    thin = mcmc$thin,
    nChains = mcmc$chains,
    nParallel = mcmc$parallel,
    verbose = 100
  )
  if (is.null(model_fitted$Loff)) {
    stop("Sovitetusta mallista katosi Loff: ", model_name)
  }
  model_checkpoint_file <- file.path(
    modelDir,
    paste0(model_name, "_Hmsc_model.rds")
  )
  if (final_model) {
    saveRDS(model_fitted, model_checkpoint_file)
    cat("Hmsc-sovite tallennettu:", model_checkpoint_file, "\n")
  }
  prediction_post <- prediction_posterior_cd(
    model_fitted,
    max_prediction_draws
  )
  pred_expected_offset <- predict_array_offset_cd(
    model_fitted,
    prediction_post,
    expected = TRUE,
    seed = seed + 100000L
  )
  explanatory_fit <- evaluateModelFit(
    hM = model_fitted,
    predY = pred_expected_offset
  )
  pred_realized_offset <- NULL
  occurrence_metrics <- NULL
  posterior_predictive_check <- data.frame()
  if (final_model) {
    pred_realized_offset <- predict_array_offset_cd(
      model_fitted,
      prediction_post,
      expected = FALSE,
      seed = seed + 200000L
    )
    occurrence_metrics <- occurrence_metrics_cd(
      Y_model,
      pred_realized_offset
    )
    posterior_predictive_check <- posterior_predictive_check_offset_cd(
      model_name,
      Y_model,
      pred_realized_offset
    )
  }
  metrics <- metric_table_offset_cd(
    model_name,
    colnames(Y_model),
    explanatory_fit,
    occurrence_metrics
  )
  summary_table <- metric_summary_cd(metrics)
  write_csv2(
    metrics,
    file.path(modelDir, paste0(model_name, "_performance_by_species.csv2"))
  )
  write_csv2(
    summary_table,
    file.path(modelDir, paste0(model_name, "_performance_summary.csv2"))
  )
  if (final_model) {
    write_csv2(
      occurrence_metrics,
      file.path(modelDir, paste0(model_name, "_occurrence_metrics.csv2"))
    )
    write_csv2(
      posterior_predictive_check,
      file.path(modelDir, paste0(model_name, "_PPC_offset_corrected.csv2"))
    )
  }
  beta_table <- NULL
  beta_error <- NA_character_
  if (final_model && exists("beta_table_from_model", mode = "function")) {
    beta_table <- tryCatch(
      beta_table_from_model(model_fitted, model_name),
      error = function(e) {
        beta_error <<- conditionMessage(e)
        warning("Beta-taulukon muodostaminen epaonnistui: ", beta_error)
        NULL
      }
    )
    if (!is.null(beta_table)) {
      write_csv2(
        beta_table,
        file.path(modelDir, paste0(model_name, "_beta_posterior.csv2"))
      )
    }
  }
  VP <- NULL
  VP_table <- NULL
  VP_table_long <- NULL
  vp_mapping <- NULL
  vp_error <- NA_character_
  if (
    calculate_vp &&
    exists("make_vp_mapping", mode = "function") &&
    exists("variance_partition_tables", mode = "function")
  ) {
    vp_mapping <- make_vp_mapping(names(X_scaled))
    vp_result <- tryCatch({
      VP <- computeVariancePartitioning(
        model_fitted,
        group = vp_mapping$group,
        groupnames = vp_mapping$groupnames
      )
      vp_tables <- variance_partition_tables(VP, model_fitted, model_name)
      list(VP = VP, wide = vp_tables$wide, long = vp_tables$long)
    }, error = function(e) {
      vp_error <<- conditionMessage(e)
      warning("Varianssiositus epaonnistui: ", vp_error)
      NULL
    })
    if (!is.null(vp_result)) {
      VP <- vp_result$VP
      VP_table <- vp_result$wide
      VP_table_long <- vp_result$long
      write_csv2(
        VP_table_long,
        file.path(modelDir, paste0(model_name, "_variance_partitioning.csv2"))
      )
    }
  }
  if (
    final_model &&
    exists("save_convergence_diagnostics", mode = "function")
  ) {
    save_convergence_diagnostics(model_fitted, model_name)
  }
  fitted_file <- if (final_model) {
    file.path(modelDir, paste0(model_name, "_fitted.RData"))
  } else {
    NA_character_
  }
  if (final_model) {
    offset_prediction_used <- TRUE
    prediction_draws_used <- length(prediction_post)
    save(
      model_unfitted,
      model_fitted,
      X_raw,
      X_scaled,
      Y_model,
      Loff_model,
      metadata_model,
      studyDesign,
      variables_kept,
      metrics,
      summary_table,
      occurrence_metrics,
      posterior_predictive_check,
      beta_table,
      beta_error,
      VP,
      VP_table,
      VP_table_long,
      vp_mapping,
      vp_error,
      offset_prediction_used,
      prediction_draws_used,
      file = fitted_file
    )
  }
  rm(pred_expected_offset)
  if (!is.null(pred_realized_offset)) rm(pred_realized_offset)
  gc()
  list(
    status = "fitted",
    model_name = model_name,
    variables = variables_kept,
    sample_ids = X_raw$sample_id,
    n_samples = nrow(Y_model),
    metrics = metrics,
    summary = summary_table,
    occurrence_metrics = occurrence_metrics,
    posterior_predictive_check = posterior_predictive_check,
    variance_partitioning = VP_table_long,
    beta_table = beta_table,
    model_checkpoint_file = if (final_model) model_checkpoint_file else NA_character_,
    fitted_file = fitted_file,
    offset_prediction_used = TRUE,
    prediction_draws_used = length(prediction_post)
  )
}

fit_once <- function(model_name, variables, ids, mcmc, seed,
                     final_model = FALSE, calculate_vp = FALSE) {
  fit_hmsc_model_offset_cd(
    model_name = model_name,
    variables = variables,
    sample_ids = ids,
    response_matrix = Y_annual_all,
    offset_matrix = Loff_annual_all,
    mcmc = mcmc,
    seed = seed,
    final_model = final_model,
    calculate_vp = calculate_vp
  )
}

compare_fitted_results_cd <- function(reference, candidate) {
  required_columns <- c("species", "SR2")
  for (result in list(reference = reference, candidate = candidate)) {
    missing_columns <- setdiff(required_columns, names(result$metrics))
    if (length(missing_columns) > 0L) {
      stop(
        "Offset-korjatusta metriikkataulukosta puuttuvat sarakkeet: ",
        paste(missing_columns, collapse = ", ")
      )
    }
  }
  reference_metrics <- reference$metrics %>%
    filter(.data$evaluation == "explanatory_offset_corrected") %>%
    transmute(
      species = as.character(.data$species),
      reference_SR2 = as.numeric(.data$SR2)
    )
  candidate_metrics <- candidate$metrics %>%
    filter(.data$evaluation == "explanatory_offset_corrected") %>%
    transmute(
      species = as.character(.data$species),
      candidate_SR2 = as.numeric(.data$SR2)
    )
  if (
    anyDuplicated(reference_metrics$species) ||
    anyDuplicated(candidate_metrics$species) ||
    !setequal(reference_metrics$species, candidate_metrics$species)
  ) {
    stop("Referenssi- ja kandidaattimallien lajikohtaiset SR2-rivit eivat tasmaa.")
  }
  delta <- reference_metrics %>%
    inner_join(candidate_metrics, by = "species", relationship = "one-to-one") %>%
    arrange(match(.data$species, reference_metrics$species)) %>%
    mutate(delta_SR2 = .data$candidate_SR2 - .data$reference_SR2)
  values <- delta$delta_SR2[is.finite(delta$delta_SR2)]
  summary <- if (length(values)) {
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
      mean = NA_real_, median = NA_real_, minimum = NA_real_,
      maximum = NA_real_, n_positive = 0L, n_nonnegative = 0L
    )
  }
  list(delta = delta, summary = summary)
}

comparison_result <- function(reference, candidate, comparison_name) {
  comparison <- compare_fitted_results_cd(reference, candidate)
  summary <- comparison$summary
  summary_table <- data.frame(
    comparison = comparison_name,
    mean_delta_SR2 = summary$mean,
    median_delta_SR2 = summary$median,
    min_delta_SR2 = summary$minimum,
    max_delta_SR2 = summary$maximum,
    n_nonnegative_species = summary$n_nonnegative,
    stringsAsFactors = FALSE
  )
  species_table <- comparison$delta %>%
    mutate(comparison = comparison_name, .before = 1)
  list(
    comparison = comparison,
    summary = summary_table,
    species = species_table
  )
}

accept_addition_cd <- function(summary_row) {
  community <-
    is.finite(summary_row$mean_delta_SR2) &&
    is.finite(summary_row$median_delta_SR2) &&
    summary_row$mean_delta_SR2 >= min_community_delta_SR2 &&
    summary_row$median_delta_SR2 > delta_tolerance &&
    summary_row$n_nonnegative_species >= minimum_nonnegative_species
  
  strong_species <-
    is.finite(summary_row$max_delta_SR2) &&
    is.finite(summary_row$min_delta_SR2) &&
    summary_row$max_delta_SR2 >= min_strong_species_delta_SR2 &&
    summary_row$min_delta_SR2 >= -max_harm_to_other_species &&
    summary_row$mean_delta_SR2 >= min_community_delta_SR2
  
  community || strong_species
}

accept_removal_cd <- function(summary_row) {
  is.finite(summary_row$mean_delta_SR2) &&
    summary_row$mean_delta_SR2 >= -max_backward_mean_loss &&
    summary_row$min_delta_SR2 >= -max_harm_to_other_species &&
    summary_row$n_nonnegative_species >= minimum_nonnegative_species
}

#===============================================================================
# 6. MUODOSTA VERTAILUKELPOISET BUFFERIKANDIDAATIT
#===============================================================================

candidate_registry <- environment_candidate_table %>%
  select(candidate_group, ecological_group, buffer_m) %>%
  distinct() %>%
  filter(candidate_group %in% names(environment_groups_buffered)) %>%
  arrange(ecological_group, buffer_m)

if (nrow(candidate_registry) == 0L) {
  stop("Paavuosimallista ei loytynyt bufferikohtaisia ymparistokandidaatteja.")
}

group_buffer_variables <- list()
candidate_variable_registry <- list()

for (ecological_group in unique(candidate_registry$ecological_group)) {
  group_rows <- candidate_registry %>%
    filter(.data$ecological_group == .env$ecological_group)
  
  raw_sets <- lapply(group_rows$candidate_group, function(candidate_group) {
    strip_buffer_suffix(environment_groups_buffered[[candidate_group]])
  })
  common_raw_variables <- Reduce(intersect, raw_sets)
  
  if (length(common_raw_variables) == 0L) next
  
  for (row_index in seq_len(nrow(group_rows))) {
    candidate_group <- group_rows$candidate_group[row_index]
    buffer_m <- group_rows$buffer_m[row_index]
    variables <- environment_groups_buffered[[candidate_group]]
    variables <- variables[
      strip_buffer_suffix(variables) %in% common_raw_variables
    ]
    variables <- intersect(variables, names(X_sample))
    if (length(variables) == 0L) next
    
    buffer_name <- format(
      as.numeric(buffer_m),
      scientific = FALSE,
      trim = TRUE
    )
    group_buffer_variables[[ecological_group]][[buffer_name]] <- variables
    candidate_variable_registry[[length(candidate_variable_registry) + 1L]] <-
      data.frame(
        ecological_group = ecological_group,
        buffer_m = as.numeric(buffer_m),
        n_common_raw_variables = length(common_raw_variables),
        variables = paste(variables, collapse = "|"),
        stringsAsFactors = FALSE
      )
  }
}

candidate_variable_registry <- bind_rows(candidate_variable_registry)
write_csv2(
  candidate_variable_registry,
  file.path(diagnostic_dir, "environment_buffer_candidate_variables.csv2")
)

if (length(group_buffer_variables) == 0L) {
  stop("Yhtaan vertailukelpoista ekologinen ryhma x bufferi -kandidaattia ei jaanyt.")
}

weather_ids <- complete_ids(locked_weather_variables)
if (!meets_coverage(weather_ids)) {
  stop("Lukittu saamalli ei tayta saatavuuden vahimmaisrajoja.")
}

availability_rows <- list()
availability_index <- 0L

for (ecological_group in names(group_buffer_variables)) {
  for (buffer_name in names(group_buffer_variables[[ecological_group]])) {
    variables <- group_buffer_variables[[ecological_group]][[buffer_name]]
    ids <- complete_ids(c(locked_weather_variables, variables), weather_ids)
    
    for (year_value in sort(unique(sample_metadata$year))) {
      weather_year_ids <- intersect(
        weather_ids,
        sample_metadata$sample_id[sample_metadata$year == year_value]
      )
      complete_year_ids <- intersect(ids, weather_year_ids)
      availability_index <- availability_index + 1L
      availability_rows[[availability_index]] <- data.frame(
        ecological_group = ecological_group,
        buffer_m = as.numeric(buffer_name),
        year = year_value,
        weather_complete_n = length(weather_year_ids),
        environment_complete_n = length(complete_year_ids),
        environment_complete_sites = dplyr::n_distinct(
          sample_metadata$site[
            match(complete_year_ids, sample_metadata$sample_id)
          ]
        ),
        proportion_of_weather_rows = if (length(weather_year_ids)) {
          length(complete_year_ids) / length(weather_year_ids)
        } else {
          NA_real_
        },
        stringsAsFactors = FALSE
      )
    }
  }
}

availability_by_year <- bind_rows(availability_rows)
write_csv2(
  availability_by_year,
  file.path(diagnostic_dir, "availability_by_group_buffer_year.csv2")
)

#===============================================================================
# 7. VALITSE YKSI BUFFERI JOKAISELLE VERTAILUKELPOISELLE RYHMALLE
#===============================================================================

modelDir <- buffer_dir
selected_group_buffers <- list()
buffer_selection_summary_blocks <- list()
buffer_selection_species_blocks <- list()
buffer_panel_blocks <- list()
buffer_counter <- 0L

for (ecological_group in names(group_buffer_variables)) {
  cat("\n========================================================\n")
  cat("BUFFERIVALINTA: ", ecological_group, "\n", sep = "")
  cat("========================================================\n")
  
  candidates <- group_buffer_variables[[ecological_group]]
  individual_ids <- lapply(candidates, function(variables) {
    complete_ids(c(locked_weather_variables, variables), weather_ids)
  })
  individual_n <- vapply(individual_ids, length, integer(1))
  best_n <- max(individual_n)
  
  eligible_buffers <- names(individual_ids)[
    individual_n >= max(
      minimum_samples,
      ceiling(minimum_buffer_fraction_of_best * best_n)
    )
  ]
  eligible_buffers <- eligible_buffers[vapply(
    individual_ids[eligible_buffers],
    meets_coverage,
    logical(1)
  )]
  eligible_buffers <- eligible_buffers[vapply(
    eligible_buffers,
    function(buffer_name) {
      variables_vary(
        candidates[[buffer_name]],
        individual_ids[[buffer_name]]
      )
    },
    logical(1)
  )]
  
  if (length(eligible_buffers) == 0L) {
    buffer_panel_blocks[[ecological_group]] <- data.frame(
      ecological_group = ecological_group,
      status = "no_eligible_buffer",
      n_candidate_buffers = length(candidates),
      n_eligible_buffers = 0L,
      common_n = 0L,
      stringsAsFactors = FALSE
    )
    next
  }
  
  repeat {
    common_variables <- unique(c(
      locked_weather_variables,
      unlist(candidates[eligible_buffers], use.names = FALSE)
    ))
    buffer_common_ids <- complete_ids(common_variables, weather_ids)
    varying <- vapply(
      eligible_buffers,
      function(buffer_name) {
        variables_vary(candidates[[buffer_name]], buffer_common_ids)
      },
      logical(1)
    )
    if (all(varying)) break
    eligible_buffers <- eligible_buffers[varying]
    if (length(eligible_buffers) == 0L) break
  }
  
  if (length(eligible_buffers) == 0L) {
    buffer_panel_blocks[[ecological_group]] <- data.frame(
      ecological_group = ecological_group,
      status = "zero_variance_on_common_panel",
      n_candidate_buffers = length(candidates),
      n_eligible_buffers = 0L,
      common_n = 0L,
      stringsAsFactors = FALSE
    )
    next
  }
  
  common_threshold <- max(
    minimum_samples,
    ceiling(minimum_common_fraction_of_best * best_n)
  )
  comparable <-
    meets_coverage(buffer_common_ids) &&
    length(buffer_common_ids) >= common_threshold
  
  panel_coverage <- coverage_row(
    buffer_common_ids,
    paste0("buffer_", ecological_group)
  )
  buffer_panel_blocks[[ecological_group]] <- cbind(
    data.frame(
      ecological_group = ecological_group,
      status = if (comparable) "comparable" else "common_panel_too_small",
      n_candidate_buffers = length(candidates),
      n_eligible_buffers = length(eligible_buffers),
      best_individual_n = best_n,
      common_threshold = common_threshold,
      stringsAsFactors = FALSE
    ),
    panel_coverage[, setdiff(names(panel_coverage), "label"), drop = FALSE]
  )
  
  if (!comparable) next
  
  buffer_counter <- buffer_counter + 1L
  screen_reference <- fit_once(
    paste0("BUFFER_", safe_name(ecological_group), "_SCREEN_REF"),
    locked_weather_variables,
    buffer_common_ids,
    MCMC$screen,
    seed = 1000L + buffer_counter * 100L
  )
  
  screen_rows <- list()
  species_rows <- list()
  
  for (buffer_name in eligible_buffers) {
    buffer_counter <- buffer_counter + 1L
    candidate <- fit_once(
      paste0(
        "BUFFER_", safe_name(ecological_group), "_",
        safe_name(buffer_name), "m_SCREEN"
      ),
      unique(c(locked_weather_variables, candidates[[buffer_name]])),
      buffer_common_ids,
      MCMC$screen,
      seed = 1000L + buffer_counter * 10L
    )
    comparison <- comparison_result(
      screen_reference,
      candidate,
      paste0(ecological_group, "_", buffer_name, "m_screen")
    )
    screen_rows[[buffer_name]] <- comparison$summary %>%
      mutate(
        ecological_group = ecological_group,
        buffer_m = as.numeric(buffer_name),
        n_samples = length(buffer_common_ids),
        stage = "screen",
        .before = 1
      )
    species_rows[[paste0("screen_", buffer_name)]] <-
      comparison$species %>%
      mutate(
        ecological_group = ecological_group,
        buffer_m = as.numeric(buffer_name),
        stage = "screen",
        .before = 1
      )
    rm(candidate)
    gc()
  }
  
  screen_table <- bind_rows(screen_rows) %>%
    filter(is.finite(mean_delta_SR2)) %>%
    arrange(desc(mean_delta_SR2), desc(min_delta_SR2), buffer_m)
  
  if (nrow(screen_table) == 0L) next
  
  top_buffers <- as.character(head(screen_table$buffer_m, confirm_top_n))
  confirm_reference <- fit_once(
    paste0("BUFFER_", safe_name(ecological_group), "_CONFIRM_REF"),
    locked_weather_variables,
    buffer_common_ids,
    MCMC$confirm,
    seed = 2000L + buffer_counter * 100L
  )
  
  confirm_rows <- list()
  for (buffer_name in top_buffers) {
    buffer_counter <- buffer_counter + 1L
    candidate <- fit_once(
      paste0(
        "BUFFER_", safe_name(ecological_group), "_",
        safe_name(buffer_name), "m_CONFIRM"
      ),
      unique(c(locked_weather_variables, candidates[[buffer_name]])),
      buffer_common_ids,
      MCMC$confirm,
      seed = 2000L + buffer_counter * 10L
    )
    comparison <- comparison_result(
      confirm_reference,
      candidate,
      paste0(ecological_group, "_", buffer_name, "m_confirm")
    )
    confirm_rows[[buffer_name]] <- comparison$summary %>%
      mutate(
        ecological_group = ecological_group,
        buffer_m = as.numeric(buffer_name),
        n_samples = length(buffer_common_ids),
        stage = "confirm",
        .before = 1
      )
    species_rows[[paste0("confirm_", buffer_name)]] <-
      comparison$species %>%
      mutate(
        ecological_group = ecological_group,
        buffer_m = as.numeric(buffer_name),
        stage = "confirm",
        .before = 1
      )
    rm(candidate)
    gc()
  }
  
  confirm_table <- bind_rows(confirm_rows) %>%
    filter(is.finite(mean_delta_SR2)) %>%
    arrange(desc(mean_delta_SR2), desc(min_delta_SR2), buffer_m)
  
  if (nrow(confirm_table) == 0L) next
  
  chosen_buffer <- as.character(confirm_table$buffer_m[1])
  selected_group_buffers[[ecological_group]] <- list(
    buffer_m = as.numeric(chosen_buffer),
    variables = candidates[[chosen_buffer]],
    buffer_comparison_sample_ids = buffer_common_ids
  )
  
  buffer_selection_summary_blocks[[ecological_group]] <- bind_rows(
    screen_table,
    confirm_table
  )
  buffer_selection_species_blocks[[ecological_group]] <- bind_rows(
    species_rows
  )
  
  rm(screen_reference, confirm_reference)
  gc()
}

buffer_selection_summary <- bind_rows(buffer_selection_summary_blocks)
buffer_selection_species <- bind_rows(buffer_selection_species_blocks)
buffer_panel_registry <- bind_rows(buffer_panel_blocks)

write_csv2(
  buffer_selection_summary,
  file.path(buffer_dir, "buffer_selection_summary.csv2")
)
write_csv2(
  buffer_selection_species,
  file.path(buffer_dir, "buffer_selection_by_species.csv2")
)
write_csv2(
  buffer_panel_registry,
  file.path(buffer_dir, "buffer_comparison_panels.csv2")
)

if (length(selected_group_buffers) == 0L) {
  stop("Yhdellakaan ekologisella ryhmalla ei ollut vertailukelpoista bufferipaneelia.")
}

selected_buffer_table <- bind_rows(lapply(
  names(selected_group_buffers),
  function(ecological_group) {
    data.frame(
      ecological_group = ecological_group,
      selected_buffer_m = selected_group_buffers[[ecological_group]]$buffer_m,
      variables = paste(
        selected_group_buffers[[ecological_group]]$variables,
        collapse = "|"
      ),
      stringsAsFactors = FALSE
    )
  }
))

write_csv2(
  selected_buffer_table,
  file.path(buffer_dir, "selected_one_buffer_per_group.csv2")
)

#===============================================================================
# 8. MUODOSTA YKSI KIINTEA YMPARISTOVALINNAN PANEELI
#===============================================================================

primary_groups <- names(selected_group_buffers)
group_individual_ids <- lapply(primary_groups, function(ecological_group) {
  complete_ids(
    c(
      locked_weather_variables,
      selected_group_buffers[[ecological_group]]$variables
    ),
    weather_ids
  )
})
names(group_individual_ids) <- primary_groups

basic_ok <- vapply(group_individual_ids, meets_coverage, logical(1))

initially_excluded_groups <- primary_groups[!basic_ok]

availability_exclusions <- data.frame(
  ecological_group = initially_excluded_groups,
  reason = rep(
    "insufficient_individual_availability",
    length(initially_excluded_groups)
  ),
  stringsAsFactors = FALSE
)

primary_groups <- primary_groups[basic_ok]

if (length(primary_groups) == 0L) {
  stop("Yksikaan bufferivalittu ryhma ei tayta ymparistovalinnan saatavuusrajoja.")
}

get_primary_ids <- function(groups) {
  variables <- unique(c(
    locked_weather_variables,
    unlist(
      lapply(groups, function(ecological_group) {
        selected_group_buffers[[ecological_group]]$variables
      }),
      use.names = FALSE
    )
  ))
  complete_ids(variables, weather_ids)
}

primary_panel_is_valid <- function(groups, ids) {
  if (length(groups) == 0L || !meets_coverage(ids)) return(FALSE)
  individual_n <- vapply(
    group_individual_ids[groups],
    length,
    integer(1)
  )
  required_n <- max(
    minimum_samples,
    ceiling(minimum_common_fraction_of_best * max(individual_n))
  )
  if (length(ids) < required_n) return(FALSE)
  all(vapply(
    groups,
    function(ecological_group) {
      variables_vary(
        selected_group_buffers[[ecological_group]]$variables,
        ids
      )
    },
    logical(1)
  ))
}

repeat {
  primary_ids <- get_primary_ids(primary_groups)
  if (primary_panel_is_valid(primary_groups, primary_ids)) break
  if (length(primary_groups) == 1L) {
    stop("Yhdenkin ryhman kiintea vertailupaneeli on liian pieni tai vakioinen.")
  }
  
  recovered_n <- vapply(
    primary_groups,
    function(drop_group) {
      length(get_primary_ids(setdiff(primary_groups, drop_group)))
    },
    integer(1)
  )
  individual_n <- vapply(
    group_individual_ids[primary_groups],
    length,
    integer(1)
  )
  nonvarying <- primary_groups[!vapply(
    primary_groups,
    function(ecological_group) {
      variables_vary(
        selected_group_buffers[[ecological_group]]$variables,
        primary_ids
      )
    },
    logical(1)
  )]
  
  if (length(nonvarying) > 0L) {
    drop_group <- nonvarying[order(
      individual_n[nonvarying],
      -recovered_n[nonvarying],
      nonvarying
    )[1]]
    exclusion_reason <- "zero_variance_on_primary_common_panel"
  } else {
    drop_order <- order(-recovered_n, individual_n, primary_groups)
    drop_group <- primary_groups[drop_order[1]]
    exclusion_reason <- "removed_to_create_comparable_primary_panel"
  }
  
  availability_exclusions <- bind_rows(
    availability_exclusions,
    data.frame(
      ecological_group = drop_group,
      reason = exclusion_reason,
      n_before = length(primary_ids),
      n_after_removal = recovered_n[drop_group],
      stringsAsFactors = FALSE
    )
  )
  primary_groups <- setdiff(primary_groups, drop_group)
}

primary_panel <- coverage_row(
  primary_ids,
  "primary_environment_selection_panel"
)
primary_panel$groups_compared <- paste(primary_groups, collapse = "|")

write_csv2(
  primary_panel,
  file.path(selection_dir, "primary_comparison_panel.csv2")
)
write_csv2(
  availability_exclusions,
  file.path(selection_dir, "groups_excluded_by_availability.csv2")
)
write_csv2(
  data.frame(sample_id = primary_ids),
  file.path(selection_dir, "primary_comparison_sample_ids.csv2")
)

#===============================================================================
# 9. YMPARISTORYHMIEN FORWARD-VALINTA KIINTEALLA PANEELILLA
#===============================================================================

modelDir <- selection_dir
selected_groups <- character(0)
selected_environment_variables <- character(0)
remaining_groups <- primary_groups
forward_summary_blocks <- list()
forward_species_blocks <- list()
forward_step <- 0L

while (
  length(remaining_groups) > 0L &&
  length(selected_groups) < max_selected_environment_groups
) {
  forward_step <- forward_step + 1L
  cat("\nYMPARISTON FORWARD-VAIHE ", forward_step, "\n", sep = "")
  
  base_variables <- unique(c(
    locked_weather_variables,
    selected_environment_variables
  ))
  reference <- fit_once(
    paste0("ENV_FORWARD_", forward_step, "_SCREEN_REF"),
    base_variables,
    primary_ids,
    MCMC$screen,
    seed = 3000L + forward_step * 100L
  )
  
  screen_rows <- list()
  screen_species <- list()
  
  for (ecological_group in remaining_groups) {
    candidate <- fit_once(
      paste0(
        "ENV_FORWARD_", forward_step, "_",
        safe_name(ecological_group), "_SCREEN"
      ),
      unique(c(
        base_variables,
        selected_group_buffers[[ecological_group]]$variables
      )),
      primary_ids,
      MCMC$screen,
      seed = 3000L + forward_step * 100L +
        match(ecological_group, remaining_groups)
    )
    comparison <- comparison_result(
      reference,
      candidate,
      paste0("forward_", forward_step, "_", ecological_group)
    )
    row <- comparison$summary %>%
      mutate(
        step = forward_step,
        ecological_group = ecological_group,
        n_samples = length(primary_ids),
        stage = "screen",
        .before = 1
      )
    row$accepted <- accept_addition_cd(row)
    screen_rows[[ecological_group]] <- row
    screen_species[[ecological_group]] <- comparison$species %>%
      mutate(
        step = forward_step,
        ecological_group = ecological_group,
        stage = "screen",
        .before = 1
      )
    rm(candidate)
    gc()
  }
  
  ranking <- bind_rows(screen_rows) %>%
    arrange(desc(accepted), desc(mean_delta_SR2), desc(min_delta_SR2))
  forward_summary_blocks[[paste0("step_", forward_step, "_screen")]] <- ranking
  forward_species_blocks[[paste0("step_", forward_step, "_screen")]] <-
    bind_rows(screen_species)
  
  accepted_groups <- ranking$ecological_group[ranking$accepted]
  if (length(accepted_groups) == 0L) {
    rm(reference)
    gc()
    break
  }
  
  top_groups <- head(accepted_groups, confirm_top_n)
  confirm_reference <- fit_once(
    paste0("ENV_FORWARD_", forward_step, "_CONFIRM_REF"),
    base_variables,
    primary_ids,
    MCMC$confirm,
    seed = 4000L + forward_step * 100L
  )
  
  confirm_rows <- list()
  for (ecological_group in top_groups) {
    candidate <- fit_once(
      paste0(
        "ENV_FORWARD_", forward_step, "_",
        safe_name(ecological_group), "_CONFIRM"
      ),
      unique(c(
        base_variables,
        selected_group_buffers[[ecological_group]]$variables
      )),
      primary_ids,
      MCMC$confirm,
      seed = 4000L + forward_step * 100L +
        match(ecological_group, top_groups)
    )
    comparison <- comparison_result(
      confirm_reference,
      candidate,
      paste0("forward_confirm_", forward_step, "_", ecological_group)
    )
    row <- comparison$summary %>%
      mutate(
        step = forward_step,
        ecological_group = ecological_group,
        n_samples = length(primary_ids),
        stage = "confirm",
        .before = 1
      )
    row$accepted <- accept_addition_cd(row)
    confirm_rows[[ecological_group]] <- row
    forward_species_blocks[[paste0(
      "step_", forward_step, "_confirm_", ecological_group
    )]] <- comparison$species %>%
      mutate(
        step = forward_step,
        ecological_group = ecological_group,
        stage = "confirm",
        .before = 1
      )
    rm(candidate)
    gc()
  }
  
  confirmed <- bind_rows(confirm_rows) %>%
    arrange(desc(accepted), desc(mean_delta_SR2), desc(min_delta_SR2))
  forward_summary_blocks[[paste0("step_", forward_step, "_confirm")]] <-
    confirmed
  
  confirmed_accepted <- confirmed$ecological_group[confirmed$accepted]
  if (length(confirmed_accepted) == 0L) {
    rm(reference, confirm_reference)
    gc()
    break
  }
  
  chosen_group <- confirmed_accepted[1]
  selected_groups <- c(selected_groups, chosen_group)
  selected_environment_variables <- unique(c(
    selected_environment_variables,
    selected_group_buffers[[chosen_group]]$variables
  ))
  remaining_groups <- setdiff(remaining_groups, chosen_group)
  
  rm(reference, confirm_reference)
  gc()
}

forward_summary_table <- bind_rows(
  forward_summary_blocks,
  .id = "result_block"
)
forward_species_table <- bind_rows(
  forward_species_blocks,
  .id = "result_block"
)

write_csv2(
  forward_summary_table,
  file.path(selection_dir, "forward_group_selection_summary.csv2")
)
write_csv2(
  forward_species_table,
  file.path(selection_dir, "forward_group_selection_by_species.csv2")
)

# Nolla valittua ryhmaa on sallittu tieteellinen tulos.
forward_selection_status <- if (length(selected_groups) > 0L) {
  "ENVIRONMENT_GROUPS_SELECTED"
} else {
  "NO_ENVIRONMENT_GROUP_PASSED_CONFIRMED_SELECTION"
}

#===============================================================================
# 10. RYHMASUOJATTU BACKWARD-VALINTA SAMALLA PANEELILLA
#===============================================================================

current_variables <- selected_environment_variables
backward_summary_blocks <- list()
backward_species_blocks <- list()
backward_step <- 0L

variable_group <- function(variable) {
  hits <- names(selected_group_buffers)[vapply(
    selected_group_buffers,
    function(definition) variable %in% definition$variables,
    logical(1)
  )]
  if (length(hits) == 0L) NA_character_ else hits[1]
}

group_guard_allows <- function(remove_variable, variables) {
  ecological_group <- variable_group(remove_variable)
  remaining_in_group <- setdiff(
    variables[vapply(variables, variable_group, character(1)) == ecological_group],
    remove_variable
  )
  length(remaining_in_group) >= minimum_variables_per_selected_group
}

repeat {
  removable <- current_variables[vapply(
    current_variables,
    group_guard_allows,
    logical(1),
    variables = current_variables
  )]
  if (length(removable) == 0L) break
  
  backward_step <- backward_step + 1L
  full_variables <- unique(c(
    locked_weather_variables,
    current_variables
  ))
  full_fit <- fit_once(
    paste0("ENV_BACKWARD_", backward_step, "_SCREEN_FULL"),
    full_variables,
    primary_ids,
    MCMC$screen,
    seed = 5000L + backward_step * 100L
  )
  
  removal_rows <- list()
  removal_species <- list()
  
  for (remove_variable in removable) {
    reduced_variables <- unique(c(
      locked_weather_variables,
      setdiff(current_variables, remove_variable)
    ))
    reduced_fit <- fit_once(
      paste0(
        "ENV_BACKWARD_", backward_step, "_DROP_",
        safe_name(remove_variable), "_SCREEN"
      ),
      reduced_variables,
      primary_ids,
      MCMC$screen,
      seed = 5000L + backward_step * 100L +
        match(remove_variable, removable)
    )
    comparison <- comparison_result(
      full_fit,
      reduced_fit,
      paste0("drop_", remove_variable)
    )
    row <- comparison$summary %>%
      mutate(
        step = backward_step,
        removed_variable = remove_variable,
        ecological_group = variable_group(remove_variable),
        n_samples = length(primary_ids),
        stage = "screen",
        .before = 1
      )
    row$removal_accepted <- accept_removal_cd(row)
    removal_rows[[remove_variable]] <- row
    removal_species[[remove_variable]] <- comparison$species %>%
      mutate(
        step = backward_step,
        removed_variable = remove_variable,
        stage = "screen",
        .before = 1
      )
    rm(reduced_fit)
    gc()
  }
  
  ranking <- bind_rows(removal_rows) %>%
    arrange(
      desc(removal_accepted),
      desc(mean_delta_SR2),
      desc(min_delta_SR2)
    )
  backward_summary_blocks[[paste0("step_", backward_step, "_screen")]] <-
    ranking
  backward_species_blocks[[paste0("step_", backward_step, "_screen")]] <-
    bind_rows(removal_species)
  
  accepted_variables <- ranking$removed_variable[ranking$removal_accepted]
  rm(full_fit)
  gc()
  if (length(accepted_variables) == 0L) break
  
  chosen_remove <- accepted_variables[1]
  confirm_full <- fit_once(
    paste0("ENV_BACKWARD_", backward_step, "_CONFIRM_FULL"),
    full_variables,
    primary_ids,
    MCMC$confirm,
    seed = 6000L + backward_step * 100L
  )
  confirm_reduced <- fit_once(
    paste0(
      "ENV_BACKWARD_", backward_step, "_DROP_",
      safe_name(chosen_remove), "_CONFIRM"
    ),
    unique(c(
      locked_weather_variables,
      setdiff(current_variables, chosen_remove)
    )),
    primary_ids,
    MCMC$confirm,
    seed = 6001L + backward_step * 100L
  )
  confirmation <- comparison_result(
    confirm_full,
    confirm_reduced,
    paste0("confirm_drop_", chosen_remove)
  )
  confirmation_row <- confirmation$summary %>%
    mutate(
      step = backward_step,
      removed_variable = chosen_remove,
      ecological_group = variable_group(chosen_remove),
      n_samples = length(primary_ids),
      stage = "confirm",
      .before = 1
    )
  confirmation_row$removal_accepted <- accept_removal_cd(confirmation_row)
  backward_summary_blocks[[paste0("step_", backward_step, "_confirm")]] <-
    confirmation_row
  backward_species_blocks[[paste0("step_", backward_step, "_confirm")]] <-
    confirmation$species %>%
    mutate(
      step = backward_step,
      removed_variable = chosen_remove,
      stage = "confirm",
      .before = 1
    )
  
  rm(confirm_full, confirm_reduced)
  gc()
  
  if (!confirmation_row$removal_accepted[1]) break
  current_variables <- setdiff(current_variables, chosen_remove)
}

selected_environment_variables <- current_variables
selected_groups_final <- unique(vapply(
  selected_environment_variables,
  variable_group,
  character(1)
))
selected_groups_final <- selected_groups_final[
  !is.na(selected_groups_final) & nzchar(selected_groups_final)
]

backward_summary_table <- bind_rows(
  backward_summary_blocks,
  .id = "result_block"
)
backward_species_table <- bind_rows(
  backward_species_blocks,
  .id = "result_block"
)

write_csv2(
  backward_summary_table,
  file.path(selection_dir, "backward_variable_selection_summary.csv2")
)
write_csv2(
  backward_species_table,
  file.path(selection_dir, "backward_variable_selection_by_species.csv2")
)

selected_environment_table <- if (length(selected_environment_variables)) {
  bind_rows(lapply(selected_environment_variables, function(variable) {
    ecological_group <- variable_group(variable)
    data.frame(
      ecological_group = ecological_group,
      raw_variable = strip_buffer_suffix(variable),
      selected_buffer_m = selected_group_buffers[[ecological_group]]$buffer_m,
      model_variable = variable,
      stringsAsFactors = FALSE
    )
  }))
} else {
  data.frame(
    ecological_group = character(0),
    raw_variable = character(0),
    selected_buffer_m = numeric(0),
    model_variable = character(0),
    stringsAsFactors = FALSE
  )
}

write_csv2(
  selected_environment_table,
  file.path(selection_dir, "selected_environment_variables_final.csv2")
)

#===============================================================================
# 11. LOPULLISET PITKAT MATCHED-SAMPLE-MALLIT
#===============================================================================

final_ids <- complete_ids(
  c(locked_weather_variables, selected_environment_variables),
  weather_ids
)
if (!meets_coverage(final_ids)) {
  stop("Lopullinen matched-sample-aineisto ei tayta saatavuusrajoja.")
}

final_coverage <- coverage_row(final_ids, "final_matched_sample")
write_csv2(
  final_coverage,
  file.path(final_dir, "final_matched_sample_coverage.csv2")
)
write_csv2(
  data.frame(sample_id = final_ids),
  file.path(final_dir, "final_matched_sample_ids.csv2")
)

# Varianssiosituksen ryhmittely kayttaa naita globaaleja valintoja.
selected_weather_variables <- locked_weather_variables
selected_environment_variables <- current_variables
modelDir <- final_dir

final_weather_only <- fit_once(
  "FINAL_ANNUAL_WEATHER_ONLY_MATCHED",
  locked_weather_variables,
  final_ids,
  MCMC$final,
  seed = 7000L,
  final_model = TRUE,
  calculate_vp = TRUE
)

if (length(selected_environment_variables) > 0L) {
  final_weather_plus_environment <- fit_once(
    "FINAL_ANNUAL_WEATHER_PLUS_ENVIRONMENT_MATCHED",
    unique(c(
      locked_weather_variables,
      selected_environment_variables
    )),
    final_ids,
    MCMC$final,
    seed = 7001L,
    final_model = TRUE,
    calculate_vp = TRUE
  )
} else {
  cat(
    "\nYhtaan ymparistoryhmaa ei valittu. Toista identtista pitkaa mallia ",
    "ei soviteta.\n",
    sep = ""
  )
  final_weather_plus_environment <- final_weather_only
}

final_comparison <- comparison_result(
  final_weather_only,
  final_weather_plus_environment,
  "FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED"
)

write_csv2(
  final_weather_only$metrics,
  file.path(final_dir, "FINAL_WEATHER_ONLY_MATCHED_metrics.csv2")
)
write_csv2(
  final_weather_plus_environment$metrics,
  file.path(final_dir, "FINAL_WEATHER_PLUS_ENVIRONMENT_MATCHED_metrics.csv2")
)
write_csv2(
  final_comparison$species,
  file.path(final_dir, "final_matched_comparison_by_species.csv2")
)
write_csv2(
  final_comparison$summary,
  file.path(final_dir, "final_matched_comparison_summary.csv2")
)
write_csv2(
  final_weather_only$posterior_predictive_check,
  file.path(final_dir, "FINAL_WEATHER_ONLY_MATCHED_PPC.csv2")
)
write_csv2(
  final_weather_plus_environment$posterior_predictive_check,
  file.path(final_dir, "FINAL_WEATHER_PLUS_ENVIRONMENT_MATCHED_PPC.csv2")
)
write_csv2(
  final_weather_only$occurrence_metrics,
  file.path(final_dir, "FINAL_WEATHER_ONLY_MATCHED_occurrence_metrics.csv2")
)
write_csv2(
  final_weather_plus_environment$occurrence_metrics,
  file.path(
    final_dir,
    "FINAL_WEATHER_PLUS_ENVIRONMENT_MATCHED_occurrence_metrics.csv2"
  )
)

final_ppc_statuses <- unique(c(
  as.character(final_weather_only$posterior_predictive_check$ppc_status),
  as.character(
    final_weather_plus_environment$posterior_predictive_check$ppc_status
  )
))
final_ppc_statuses <- final_ppc_statuses[
  !is.na(final_ppc_statuses) & nzchar(final_ppc_statuses)
]

if (length(final_ppc_statuses) == 0L) {
  analysis_status <- paste0(analysis_status, "__FINAL_PPC_MISSING")
} else if (any(final_ppc_statuses == "REQUIRES_REVIEW")) {
  analysis_status <- paste0(analysis_status, "__FINAL_PPC_REQUIRES_REVIEW")
} else if (any(final_ppc_statuses == "UPPER_TAIL_REQUIRES_REVIEW")) {
  analysis_status <- paste0(analysis_status, "__FINAL_UPPER_TAIL_REQUIRES_REVIEW")
} else {
  analysis_status <- paste0(analysis_status, "__FINAL_PPC_OK")
}

compute_result_waic <- function(result) {
  if (
    is.null(result$fitted_file) ||
    length(result$fitted_file) != 1L ||
    is.na(result$fitted_file) ||
    !file.exists(result$fitted_file)
  ) {
    return(structure(NA_real_, error = "fitted model file missing"))
  }
  fitted_environment <- new.env(parent = globalenv())
  load(result$fitted_file, envir = fitted_environment)
  if (!exists("model_fitted", envir = fitted_environment, inherits = FALSE)) {
    return(structure(NA_real_, error = "model_fitted missing"))
  }
  tryCatch(
    computeWAIC(get("model_fitted", envir = fitted_environment)),
    error = function(e) structure(NA_real_, error = conditionMessage(e))
  )
}

final_weather_only_WAIC <- compute_result_waic(final_weather_only)
final_weather_plus_environment_WAIC <- if (
  length(selected_environment_variables) > 0L
) {
  compute_result_waic(final_weather_plus_environment)
} else {
  final_weather_only_WAIC
}

writeLines(
  capture.output(print(final_weather_only_WAIC)),
  file.path(final_dir, "FINAL_WEATHER_ONLY_MATCHED_WAIC.txt")
)
writeLines(
  capture.output(print(final_weather_plus_environment_WAIC)),
  file.path(final_dir, "FINAL_WEATHER_PLUS_ENVIRONMENT_MATCHED_WAIC.txt")
)

#===============================================================================
# 12. SAATAVUUSHERKKYYS ERI RIVEILLA, EI RYHMIEN RANKINGIIN
#===============================================================================

availability_sensitivity_summary <- data.frame()
availability_sensitivity_species <- data.frame()

if (run_availability_sensitivity) {
  
  modelDir <- sensitivity_dir
  
  sensitivity_summary_blocks <- list()
  sensitivity_species_blocks <- list()
  sensitivity_status_blocks <- list()
  
  if (length(selected_group_buffers) == 0L) {
    
    message(
      "Saatavuusherkkyyttä ei ajettu: ",
      "valittuja ympäristöryhmiä ei ollut."
    )
    
  } else {
    
    group_names <- names(selected_group_buffers)
    
    if (
      is.null(group_names) ||
      length(group_names) != length(selected_group_buffers) ||
      any(is.na(group_names)) ||
      any(!nzchar(group_names))
    ) {
      stop(
        "selected_group_buffers-listan kaikilla alkioilla ",
        "pitää olla ekologisen ryhmän nimi."
      )
    }
    
    for (group_index in seq_along(selected_group_buffers)) {
      
      #---------------------------------------------------
      # Kiinnitä ryhmän tiedot ennen mutate()-kutsuja.
      # Näin dplyr ei sekoita silmukan nimeä taulukkosarakkeeseen.
      #---------------------------------------------------
      
      current_group <- group_names[group_index]
      current_group_spec <- selected_group_buffers[[current_group]]
      
      current_variables <- unique(
        as.character(current_group_spec$variables)
      )
      current_variables <- current_variables[
        !is.na(current_variables) &
          nzchar(current_variables)
      ]
      
      current_buffer_m <- current_group_spec$buffer_m
      
      if (
        is.null(current_buffer_m) ||
        length(current_buffer_m) != 1L ||
        !is.finite(as.numeric(current_buffer_m))
      ) {
        
        warning(
          "Saatavuusherkkyys ohitettiin ryhmältä ",
          current_group,
          ": valittu bufferikoko puuttuu tai ei ole yksikäsitteinen."
        )
        
        sensitivity_status_blocks[[current_group]] <- data.frame(
          ecological_group = current_group,
          selected_buffer_m = NA_real_,
          status = "skipped_invalid_buffer",
          message = "Selected buffer was missing or non-unique.",
          stringsAsFactors = FALSE
        )
        
        next
      }
      
      current_buffer_m <- as.numeric(current_buffer_m)
      
      if (length(current_variables) == 0L) {
        
        warning(
          "Saatavuusherkkyys ohitettiin ryhmältä ",
          current_group,
          ": ryhmällä ei ole ympäristömuuttujia."
        )
        
        sensitivity_status_blocks[[current_group]] <- data.frame(
          ecological_group = current_group,
          selected_buffer_m = current_buffer_m,
          status = "skipped_no_variables",
          message = "The selected group contained no variables.",
          stringsAsFactors = FALSE
        )
        
        next
      }
      
      #---------------------------------------------------
      # Ryhmän mahdollisimman suuri complete-case-aineisto
      #---------------------------------------------------
      
      current_ids <- complete_ids(
        c(
          locked_weather_variables,
          current_variables
        ),
        weather_ids
      )
      
      if (!isTRUE(meets_coverage(current_ids))) {
        
        warning(
          "Saatavuusherkkyys ohitettiin ryhmältä ",
          current_group,
          ": aineiston kattavuus ei täytä vähimmäisrajoja."
        )
        
        current_coverage <- coverage_row(
          current_ids,
          paste0("availability_", current_group)
        )
        
        sensitivity_status_blocks[[current_group]] <- data.frame(
          ecological_group = current_group,
          selected_buffer_m = current_buffer_m,
          status = "skipped_insufficient_coverage",
          message = "Coverage limits were not met.",
          n_site_years = current_coverage$n_site_years,
          n_sites = current_coverage$n_sites,
          n_years = current_coverage$n_years,
          stringsAsFactors = FALSE
        )
        
        next
      }
      
      cat(
        "\nSaatavuusherkkyys:",
        current_group,
        "| bufferi:",
        current_buffer_m,
        "m | paikkavuosia:",
        length(current_ids),
        "\n"
      )
      
      #---------------------------------------------------
      # WEATHER_ONLY-vertailumalli
      #---------------------------------------------------
      
      reference <- fit_once(
        model_name = paste0(
          "AVAIL_",
          safe_name(current_group),
          "_REF"
        ),
        variables = locked_weather_variables,
        ids = current_ids,
        mcmc = MCMC$confirm,
        seed = 8000L + group_index * 10L
      )
      
      #---------------------------------------------------
      # WEATHER_PLUS_ONE_ENVIRONMENT_GROUP
      #---------------------------------------------------
      
      candidate <- fit_once(
        model_name = paste0(
          "AVAIL_",
          safe_name(current_group),
          "_CAND"
        ),
        variables = unique(c(
          locked_weather_variables,
          current_variables
        )),
        ids = current_ids,
        mcmc = MCMC$confirm,
        seed = 8001L + group_index * 10L
      )
      
      #---------------------------------------------------
      # Explanatory SR2 -vertailu
      #---------------------------------------------------
      
      comparison <- comparison_result(
        reference = reference,
        candidate = candidate,
        comparison_name = paste0(
          "availability_",
          current_group
        )
      )
      
      current_coverage <- coverage_row(
        current_ids,
        paste0("availability_", current_group)
      )
      
      #---------------------------------------------------
      # Yhteisötason yhteenveto
      #---------------------------------------------------
      
      sensitivity_summary_blocks[[current_group]] <- cbind(
        comparison$summary %>%
          mutate(
            ecological_group = .env$current_group,
            selected_buffer_m = .env$current_buffer_m,
            .before = 1
          ),
        current_coverage[, c(
          "n_site_years",
          "n_sites",
          "n_years",
          "first_year",
          "last_year"
        ), drop = FALSE]
      )
      
      #---------------------------------------------------
      # Lajikohtaiset tulokset
      #---------------------------------------------------
      
      sensitivity_species_blocks[[current_group]] <-
        comparison$species %>%
        mutate(
          ecological_group = .env$current_group,
          selected_buffer_m = .env$current_buffer_m,
          .before = 1
        )
      
      sensitivity_status_blocks[[current_group]] <- data.frame(
        ecological_group = current_group,
        selected_buffer_m = current_buffer_m,
        status = "completed",
        message = "",
        n_site_years = current_coverage$n_site_years,
        n_sites = current_coverage$n_sites,
        n_years = current_coverage$n_years,
        stringsAsFactors = FALSE
      )
      
      rm(
        reference,
        candidate,
        comparison,
        current_coverage
      )
      
      gc()
    }
  }
  
  #-------------------------------------------------------
  # Yhdistä ryhmäkohtaiset tulokset
  #-------------------------------------------------------
  
  availability_sensitivity_summary <- bind_rows(
    sensitivity_summary_blocks
  )
  
  availability_sensitivity_species <- bind_rows(
    sensitivity_species_blocks
  )
  
  availability_sensitivity_status <- bind_rows(
    sensitivity_status_blocks
  )
  
  #-------------------------------------------------------
  # Tallenna tulokset
  #-------------------------------------------------------
  
  write_csv2(
    availability_sensitivity_summary,
    file.path(
      sensitivity_dir,
      "group_specific_sensitivity_summary.csv2"
    )
  )
  
  write_csv2(
    availability_sensitivity_species,
    file.path(
      sensitivity_dir,
      "group_specific_sensitivity_by_species.csv2"
    )
  )
  
  write_csv2(
    availability_sensitivity_status,
    file.path(
      sensitivity_dir,
      "group_specific_sensitivity_status.csv2"
    )
  )
  
  writeLines(
    c(
      "These group-specific matched pairs use different maximum available rows.",
      "They describe data-availability sensitivity only.",
      "Do not rank ecological groups using these delta SR2 values.",
      "Buffer and environmental-group selection must be based on the fixed matched panel."
    ),
    file.path(
      sensitivity_dir,
      "INTERPRETATION.txt"
    )
  )
  
  #-------------------------------------------------------
  # Tulosta yhteenveto R-konsoliin
  #-------------------------------------------------------
  
  cat("\n========================================================\n")
  cat("AVAILABILITY SENSITIVITY COMPLETE\n")
  cat("========================================================\n")
  
  cat("\nAnalysis status by environmental group:\n")
  print(
    availability_sensitivity_status,
    row.names = FALSE
  )
  
  cat("\nCommunity-level sensitivity results:\n")
  print(
    availability_sensitivity_summary,
    row.names = FALSE
  )
  
  cat("\nSpecies-level sensitivity results:\n")
  print(
    availability_sensitivity_species,
    row.names = FALSE
  )
  
  cat(
    "\nThese results must not be used to rank environmental groups,\n",
    "because the groups can contain different site-year observations.\n",
    sep = ""
  )
  
} else {
  
  availability_sensitivity_status <- data.frame(
    status = "not_run",
    message = "run_availability_sensitivity was FALSE.",
    stringsAsFactors = FALSE
  )
  
  cat(
    "\nSaatavuusherkkyyttä ei ajettu, koska ",
    "run_availability_sensitivity = FALSE.\n",
    sep = ""
  )
}
#===============================================================================
# 13. YKSI KOONTIOBJEKTI JA ENGLANNINKIELINEN ESITYSYHTEENVETO
#===============================================================================

analysis_results <- list(
  role = "ANNUAL_ONE_BUFFER_MATCHED_ENVIRONMENT_SELECTION",
  analysis_status = analysis_status,
  design = list(
    analysis_type = "explanatory",
    response = "annual total count",
    distribution = "lognormal poisson",
    effort_offset = "log(total_effort_days / 7)",
    offset_prediction_method =
      "predict(model, Loff = model$Loff, expected = TRUE/FALSE)",
    selection_metric = "offset-corrected explanatory SR2",
    occurrence_metrics =
      "posterior probability of Y > 0 from offset-corrected realized draws",
    random_levels = c("site", "year"),
    spline_terms = character(0),
    predictive_cross_validation = FALSE,
    weather_selection = "locked from annual primary model",
    phenology_sensitivity_used_as = "diagnostic sensitivity only",
    buffer_rule = "one buffer per ecological group",
    buffer_comparisons = "matched rows within ecological group",
    environment_selection = "one fixed common site-year panel"
  ),
  input_files = list(
    primary_rdata_file = primary_rdata_file,
    phenology_sensitivity_file = phenology_sensitivity_file
  ),
  primary_ppc_ok = primary_ppc_ok,
  primary_offset_evaluation_used = primary_offset_evaluation_used,
  legacy_primary_posterior_predictive_check = primary_ppc,
  phenology_sensitivity_status =
    phenology_sensitivity_result$analysis_status,
  phenology_selection_same = phenology_selection_same,
  locked_weather_groups = locked_weather_groups,
  locked_weather_variables = locked_weather_variables,
  offset_multiplier_summary = offset_diagnostic,
  availability_by_year = availability_by_year,
  buffer_panel_registry = buffer_panel_registry,
  buffer_selection_summary = buffer_selection_summary,
  selected_group_buffers = selected_group_buffers,
  primary_groups = primary_groups,
  primary_sample_ids = primary_ids,
  primary_panel = primary_panel,
  availability_exclusions = availability_exclusions,
  forward_selection_status = forward_selection_status,
  forward_summary = forward_summary_table,
  backward_summary = backward_summary_table,
  selected_environment_groups = selected_groups_final,
  selected_environment_variables = selected_environment_table,
  final_sample_ids = final_ids,
  final_coverage = final_coverage,
  final_weather_only = final_weather_only,
  final_weather_plus_environment = final_weather_plus_environment,
  final_offset_prediction_used = all(c(
    isTRUE(final_weather_only$offset_prediction_used),
    isTRUE(final_weather_plus_environment$offset_prediction_used)
  )),
  final_ppc_statuses = final_ppc_statuses,
  final_comparison_by_species = final_comparison$species,
  final_comparison_summary = final_comparison$summary,
  final_weather_only_WAIC = final_weather_only_WAIC,
  final_weather_plus_environment_WAIC =
    final_weather_plus_environment_WAIC,
  availability_sensitivity_summary = availability_sensitivity_summary,
  availability_sensitivity_species = availability_sensitivity_species,
  session_info = capture.output(sessionInfo())
)

saveRDS(
  analysis_results,
  file.path(output_root, "HMSC_annual_one_buffer_matched_results.rds")
)

writeLines(
  analysis_results$session_info,
  file.path(output_root, "sessionInfo.txt")
)

markdown_table <- function(x, digits = 3L) {
  if (is.null(x) || nrow(as.data.frame(x)) == 0L) return("No rows.")
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  x[] <- lapply(x, function(value) {
    if (is.numeric(value)) {
      format(round(value, digits), trim = TRUE, scientific = FALSE)
    } else {
      as.character(value)
    }
  })
  x[] <- lapply(x, function(value) gsub("\\|", "/", value))
  c(
    paste0("| ", paste(names(x), collapse = " | "), " |"),
    paste0("| ", paste(rep("---", ncol(x)), collapse = " | "), " |"),
    apply(
      x,
      1,
      function(value) paste0("| ", paste(value, collapse = " | "), " |")
    )
  )
}

presentation_lines <- c(
  "# Annual matched environmental selection",
  "",
  "## Model structure",
  "",
  "- Response: annual total count.",
  "- Observation model: lognormal Poisson.",
  "- Effort offset: log(total effort days / 7).",
  "- Every model comparison uses predict(..., Loff = model$Loff).",
  "- Count SR2 and RMSE use expected offset-corrected count predictions.",
  "- Occurrence metrics use posterior P(Y > 0) from realized draws.",
  "- Random levels: site and year.",
  "- No flight-week splines and no predictive cross-validation.",
  paste0("- Analysis status: **", analysis_status, "**."),
  "",
  "### Effort offset multiplier",
  "",
  markdown_table(offset_diagnostic),
  "",
  "## Locked weather model",
  "",
  paste0(
    "- Earlier weather-selection evaluation explicitly offset-corrected: ",
    primary_offset_evaluation_used
  ),
  paste0("- Weather groups: ", paste(locked_weather_groups, collapse = ", ")),
  paste0("- Weather variables: ", paste(locked_weather_variables, collapse = ", ")),
  paste0(
    "- Phenology-period and primary predictor sets identical: ",
    phenology_selection_same
  ),
  "",
  "## One selected buffer per comparable ecological group",
  "",
  markdown_table(selected_buffer_table),
  "",
  "## Final environmental selection",
  "",
  paste0("- Forward-selection status: ", forward_selection_status),
  markdown_table(selected_environment_table),
  "",
  "## Final matched explanatory comparison",
  "",
  markdown_table(final_comparison$species),
  "",
  markdown_table(final_comparison$summary),
  "",
  "## Posterior predictive checks",
  "",
  "### Weather-only model",
  "",
  markdown_table(final_weather_only$posterior_predictive_check),
  "",
  "### Weather plus environment model",
  "",
  markdown_table(final_weather_plus_environment$posterior_predictive_check),
  "",
  "## Occurrence metrics",
  "",
  "### Weather-only model",
  "",
  markdown_table(final_weather_only$occurrence_metrics),
  "",
  "### Weather plus environment model",
  "",
  markdown_table(final_weather_plus_environment$occurrence_metrics),
  "",
  "## Interpretation",
  "",
  "Buffer candidates were compared on matched rows within each ecological group. Environmental groups were then compared on one fixed site-year panel. All comparisons used an explicit effort offset in prediction. UPPER_TAIL_REQUIRES_REVIEW means that the model describes zeros and the central distribution but not the most extreme outbreak years."
)

writeLines(
  presentation_lines,
  file.path(output_root, "PRESENTATION_ANNUAL_MATCHED_ENVIRONMENT.md")
)

#===============================================================================
# 14. KONSOLIKOONTI
#===============================================================================

cat("\n========================================================\n")
cat("ANNUAL ONE-BUFFER MATCHED ENVIRONMENT ANALYSIS COMPLETE\n")
cat("========================================================\n")
cat("Status:", analysis_status, "\n")
cat("Aikaisemman paamallin arviointi offset-tietoinen:",
    primary_offset_evaluation_used, "\n")
cat("Aikaisemman paamallin PPC hyvaksytty:", primary_ppc_ok, "\n")
cat("Fenologiaherkkyyden valinta identtinen:", phenology_selection_same, "\n")
cat("\nPyyntiponnistuksen offset-kertoimet exp(Loff):\n")
print(offset_diagnostic, row.names = FALSE)
cat("\nLukitut saamuuttujat:\n")
print(locked_weather_variables)
cat("\nValittu yksi bufferi vertailukelpoista ryhmaa kohti:\n")
print(selected_buffer_table, row.names = FALSE)
cat("\nForward-valinnan tila:", forward_selection_status, "\n")
cat("\nLopulliset ymparistomuuttujat:\n")
print(selected_environment_table, row.names = FALSE)
cat("\nLopullinen matched-sample-kattavuus:\n")
print(final_coverage, row.names = FALSE)
cat("\nWeather-only vs weather-plus-environment:\n")
print(final_comparison$species, row.names = FALSE)
print(final_comparison$summary, row.names = FALSE)
cat("\nWeather-only PPC:\n")
print(final_weather_only$posterior_predictive_check, row.names = FALSE)
cat("\nWeather-only occurrence metrics:\n")
print(final_weather_only$occurrence_metrics, row.names = FALSE)
cat("\nWeather-plus-environment PPC:\n")
print(
  final_weather_plus_environment$posterior_predictive_check,
  row.names = FALSE
)
cat("\nWeather-plus-environment occurrence metrics:\n")
print(
  final_weather_plus_environment$occurrence_metrics,
  row.names = FALSE
)
cat("\nTulokset:", output_root, "\n")
cat("R-koonti: analysis_results\n")
cat("========================================================\n")

