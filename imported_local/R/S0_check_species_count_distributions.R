#========================================================
# Kohdelajien runsausjakaumien diagnostinen vertailu
#
# Tarkoitus:
# - arvioida erikseen kunkin lajin lukumääräaineistolle sopivaa jakaumaa
# - verrata Poisson-, NB1-, NB2-, COM-Poisson- ja generalized Poisson -malleja
# - verrata lisäksi nollainflatoituja Poisson-, NB1- ja NB2-malleja
# - huomioida pyydyksen pyyntiaika offsetina: offset(log(interval_days))
# - huomioida paikan ja viikon toistomittaukset satunnaisvaikutuksina
#
# Tämä skripti EI valitse sää- tai ympäristömuuttujia eikä muuta HMSC-aineistoa.
#========================================================

set.seed(1)

#========================================================
# 1. Paketointi ja asetukset
#========================================================

required_packages <- c(
  "dplyr",
  "tidyr",
  "ggplot2",
  "glmmTMB",
  "DHARMa"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0) {
  stop(
    "Asenna ensin puuttuvat paketit: ",
    paste(missing_packages, collapse = ", "),
    "\nEsimerkiksi: install.packages(c(",
    paste(sprintf('"%s"', missing_packages), collapse = ", "),
    "))"
  )
}

library(dplyr)
library(tidyr)
library(ggplot2)
library(glmmTMB)
library(DHARMa)

base_dir <- "E:/EIFFEL uusi/EIFFELgis/buffer_outputs/nearly_constant_environment"

data_file <- file.path(
  base_dir,
  "model_data_environment_nearly_constant_years_filled.csv"
)

output_dir <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "species_distribution_diagnostics"
)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# DHARMa-simulaatioiden määrä. Suurenna esimerkiksi arvoon 1000 lopulliseen tarkistukseen.
n_dharma_simulations <- 200

# TRUE = sovita myös nollainflatoidut mallit.
fit_zero_inflated_models <- TRUE
fit_compois <- FALSE  # COM-Poisson on erittäin hidas suurilla aineistoilla

# TRUE = tallenna kaikki sovitetut mallit RDS-tiedostoina.
save_fitted_models <- TRUE

#========================================================
# 2. Apufunktiot
#========================================================

make_numeric <- function(x) {
  if (is.numeric(x)) return(x)
  x <- trimws(as.character(x))
  x[x %in% c("", "NA", "NaN", "NULL")] <- NA_character_
  x <- gsub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

normalize_species_name <- function(x) {
  gsub("[^a-z]", "", tolower(trimws(as.character(x))))
}

target_species_patterns <- c(
  Epirrita_autumnata = "epirritaautumnata",
  Operophtera_fagata = "operophterafagata",
  Operophtera_brumata = "operophterabrumata"
)

match_target_species <- function(species_names) {
  normalized <- normalize_species_name(species_names)
  
  matched <- vapply(
    target_species_patterns,
    function(pattern) {
      hit <- species_names[normalized == pattern]
      if (length(hit) == 1L) hit else NA_character_
    },
    character(1)
  )
  
  if (anyNA(matched)) {
    stop(
      "Kaikkia kohdelajeja ei löytynyt yksikäsitteisesti. Aineiston lajit: ",
      paste(species_names, collapse = ", ")
    )
  }
  
  unname(matched)
}

safe_name <- function(x) {
  gsub("[^A-Za-z0-9_]+", "_", x)
}

safe_p_value <- function(test_object) {
  if (is.null(test_object)) return(NA_real_)
  p <- tryCatch(test_object$p.value, error = function(e) NA_real_)
  if (length(p) == 0L) NA_real_ else as.numeric(p[1])
}

safe_statistic <- function(test_object) {
  if (is.null(test_object)) return(NA_real_)
  z <- tryCatch(test_object$statistic, error = function(e) NA_real_)
  if (length(z) == 0L) NA_real_ else as.numeric(z[1])
}

#========================================================
# 3. Lue aineisto ja muodosta yksi rivi per näyte ja laji
#========================================================

if (!file.exists(data_file)) {
  stop("Aineistotiedostoa ei löytynyt: ", data_file)
}

dat <- read.csv(
  data_file,
  sep = ",",
  dec = ".",
  header = TRUE,
  stringsAsFactors = FALSE,
  check.names = FALSE
)

required_columns <- c(
  "sample_id", "site", "year", "week",
  "start_DateN", "end_DateN", "interval_days",
  "species", "count"
)

missing_columns <- setdiff(required_columns, names(dat))
if (length(missing_columns) > 0) {
  stop(
    "Aineistosta puuttuvat sarakkeet: ",
    paste(missing_columns, collapse = ", ")
  )
}

dat <- dat %>%
  mutate(
    sample_id = as.character(sample_id),
    site = factor(as.character(site)),
    year = factor(as.character(year)),
    week = factor(as.character(week)),
    start_DateN = as.Date(start_DateN),
    end_DateN = as.Date(end_DateN),
    interval_days = make_numeric(interval_days),
    species = as.character(species),
    count = make_numeric(count)
  )

if (any(dat$count < 0, na.rm = TRUE)) {
  stop("count sisältää negatiivisia arvoja.")
}

if (any(dat$interval_days <= 0, na.rm = TRUE)) {
  stop("interval_days sisältää nollia tai negatiivisia arvoja.")
}

target_species <- match_target_species(unique(dat$species))

sample_metadata <- dat %>%
  select(
    sample_id, site, year, week,
    start_DateN, end_DateN, interval_days
  ) %>%
  distinct(sample_id, .keep_all = TRUE)

count_wide <- dat %>%
  filter(species %in% target_species) %>%
  group_by(sample_id, species) %>%
  summarise(
    count = if (all(is.na(count))) NA_real_ else sum(count, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  complete(
    sample_id = sample_metadata$sample_id,
    species = target_species,
    fill = list(count = 0)
  ) %>%
  left_join(sample_metadata, by = "sample_id") %>%
  filter(
    is.finite(count),
    is.finite(interval_days),
    interval_days > 0,
    !is.na(site),
    !is.na(week)
  ) %>%
  mutate(
    species = factor(species, levels = target_species),
    site = droplevels(site),
    week = droplevels(week),
    log_effort = log(interval_days)
  )

#========================================================
# 4. Kuvaile raaka-aineiston jakaumat
#========================================================

raw_summary <- count_wide %>%
  group_by(species) %>%
  summarise(
    n = n(),
    total_count = sum(count),
    mean_count = mean(count),
    variance_count = var(count),
    variance_mean_ratio = variance_count / mean_count,
    median_count = median(count),
    q90 = unname(quantile(count, 0.90)),
    q95 = unname(quantile(count, 0.95)),
    q99 = unname(quantile(count, 0.99)),
    maximum = max(count),
    zero_n = sum(count == 0),
    zero_proportion = mean(count == 0),
    positive_n = sum(count > 0),
    .groups = "drop"
  )

write.table(
  raw_summary,
  file = file.path(output_dir, "raw_count_distribution_summary.txt"),
  sep = ";",
  dec = ".",
  row.names = FALSE
)

print(raw_summary)

for (sp in target_species) {
  sp_data <- count_wide %>% filter(species == sp)
  sp_safe <- safe_name(sp)
  
  p_linear <- ggplot(sp_data, aes(x = count)) +
    geom_histogram(bins = 60) +
    labs(
      title = paste("Havaittu runsaus:", sp),
      x = "Lukumäärä näytteessä",
      y = "Näytteiden määrä"
    ) +
    theme_bw()
  
  ggsave(
    file.path(output_dir, paste0(sp_safe, "_histogram_linear.pdf")),
    p_linear,
    width = 8,
    height = 6
  )
  
  p_log <- ggplot(sp_data, aes(x = log10(count + 1))) +
    geom_histogram(bins = 60) +
    labs(
      title = paste("Havaittu runsaus log10-asteikolla:", sp),
      x = "log10(lukumäärä + 1)",
      y = "Näytteiden määrä"
    ) +
    theme_bw()
  
  ggsave(
    file.path(output_dir, paste0(sp_safe, "_histogram_log10.pdf")),
    p_log,
    width = 8,
    height = 6
  )
}

#========================================================
# 5. Malliperheet
#========================================================

model_definitions <- list(
  poisson = list(
    family = poisson(link = "log"),
    ziformula = ~ 0
  ),
  nbinom1 = list(
    family = nbinom1(link = "log"),
    ziformula = ~ 0
  ),
  nbinom2 = list(
    family = nbinom2(link = "log"),
    ziformula = ~ 0
  ),
  genpois = list(
    family = genpois(link = "log"),
    ziformula = ~ 0
  )
)

if (fit_compois) {
  model_definitions$compois <- list(
    family = compois(link = "log"),
    ziformula = ~ 0
  )
}

if (fit_zero_inflated_models) {
  model_definitions <- c(
    model_definitions,
    list(
      zero_inflated_poisson = list(
        family = poisson(link = "log"),
        ziformula = ~ 1
      ),
      zero_inflated_nbinom1 = list(
        family = nbinom1(link = "log"),
        ziformula = ~ 1
      ),
      zero_inflated_nbinom2 = list(
        family = nbinom2(link = "log"),
        ziformula = ~ 1
      )
    )
  )
}

# Satunnaisvaikutukset vastaavat HMSC-rakennetta mahdollisimman läheisesti.
# Vuotta ei lisätä satunnaisvaikutukseksi, koska HMSC-mallissa ovat site ja week.
model_formula <- count ~ 1 + offset(log_effort) + (1 | site) + (1 | week)

#========================================================
# 6. Sovita mallit ja tee DHARMa-diagnostiikka
#========================================================

all_model_comparisons <- list()
all_dharma_results <- list()
all_failures <- list()

for (sp in target_species) {
  cat("\n========================================================\n")
  cat("Laji:", sp, "\n")
  cat("========================================================\n")
  
  sp_data <- count_wide %>%
    filter(species == sp) %>%
    droplevels()
  
  sp_safe <- safe_name(sp)
  fitted_models <- list()
  comparison_rows <- list()
  dharma_rows <- list()
  
  for (model_name in names(model_definitions)) {
    definition <- model_definitions[[model_name]]
    
    cat("Sovitetaan:", model_name, "\n")
    
    warnings_seen <- character(0)
    
    fitted <- tryCatch(
      withCallingHandlers(
        glmmTMB(
          formula = model_formula,
          ziformula = definition$ziformula,
          family = definition$family,
          data = sp_data
        ),
        warning = function(w) {
          warnings_seen <<- unique(c(warnings_seen, conditionMessage(w)))
          invokeRestart("muffleWarning")
        }
      ),
      error = function(e) e
    )
    
    if (inherits(fitted, "error")) {
      all_failures[[paste(sp, model_name, sep = "__")]] <- data.frame(
        species = sp,
        model = model_name,
        error = conditionMessage(fitted),
        warnings = paste(warnings_seen, collapse = " | "),
        stringsAsFactors = FALSE
      )
      next
    }
    
    fitted_models[[model_name]] <- fitted
    
    pd_hessian <- tryCatch(
      isTRUE(fitted$sdr$pdHess),
      error = function(e) FALSE
    )
    
    convergence_code <- tryCatch(
      fitted$fit$convergence,
      error = function(e) NA_integer_
    )
    
    log_likelihood <- tryCatch(
      as.numeric(logLik(fitted)),
      error = function(e) NA_real_
    )
    
    n_parameters <- tryCatch(
      attr(logLik(fitted), "df"),
      error = function(e) NA_real_
    )
    
    comparison_rows[[model_name]] <- data.frame(
      species = sp,
      model = model_name,
      n = nrow(sp_data),
      logLik = log_likelihood,
      n_parameters = n_parameters,
      AIC = tryCatch(AIC(fitted), error = function(e) NA_real_),
      BIC = tryCatch(BIC(fitted), error = function(e) NA_real_),
      convergence_code = convergence_code,
      positive_definite_Hessian = pd_hessian,
      warnings = paste(warnings_seen, collapse = " | "),
      stringsAsFactors = FALSE
    )
    
    simulation <- tryCatch(
      simulateResiduals(
        fittedModel = fitted,
        n = n_dharma_simulations,
        refit = FALSE,
        plot = FALSE
      ),
      error = function(e) e
    )
    
    if (inherits(simulation, "error")) {
      dharma_rows[[model_name]] <- data.frame(
        species = sp,
        model = model_name,
        uniformity_p = NA_real_,
        dispersion_statistic = NA_real_,
        dispersion_p = NA_real_,
        zero_inflation_statistic = NA_real_,
        zero_inflation_p = NA_real_,
        outlier_p = NA_real_,
        dharma_error = conditionMessage(simulation),
        stringsAsFactors = FALSE
      )
      next
    }
    
    uniformity_test <- tryCatch(testUniformity(simulation, plot = FALSE), error = function(e) NULL)
    dispersion_test <- tryCatch(testDispersion(simulation, plot = FALSE), error = function(e) NULL)
    zero_test <- tryCatch(testZeroInflation(simulation, plot = FALSE), error = function(e) NULL)
    outlier_test <- tryCatch(
      suppressWarnings(testOutliers(simulation, plot = FALSE, type = "binomial")),
      error = function(e) NULL
    )
    
    dharma_rows[[model_name]] <- data.frame(
      species = sp,
      model = model_name,
      uniformity_p = safe_p_value(uniformity_test),
      dispersion_statistic = safe_statistic(dispersion_test),
      dispersion_p = safe_p_value(dispersion_test),
      zero_inflation_statistic = safe_statistic(zero_test),
      zero_inflation_p = safe_p_value(zero_test),
      outlier_p = safe_p_value(outlier_test),
      dharma_error = "",
      stringsAsFactors = FALSE
    )
    
    pdf(
      file.path(output_dir, paste0(sp_safe, "_", model_name, "_DHARMa.pdf")),
      width = 11,
      height = 8
    )
    plot(simulation)
    dev.off()
    
    if (save_fitted_models) {
      saveRDS(
        fitted,
        file.path(output_dir, paste0(sp_safe, "_", model_name, "_model.rds"))
      )
    }
  }
  
  comparison_table <- bind_rows(comparison_rows) %>%
    arrange(AIC) %>%
    mutate(
      delta_AIC = AIC - min(AIC, na.rm = TRUE),
      Akaike_weight = {
        relative_likelihood <- exp(-0.5 * delta_AIC)
        relative_likelihood / sum(relative_likelihood, na.rm = TRUE)
      },
      AIC_rank = row_number()
    )
  
  dharma_table <- bind_rows(dharma_rows)
  
  combined_table <- comparison_table %>%
    left_join(dharma_table, by = c("species", "model")) %>%
    mutate(
      convergence_ok = convergence_code == 0 & positive_definite_Hessian,
      residual_tests_ok =
        uniformity_p >= 0.05 &
        dispersion_p >= 0.05 &
        zero_inflation_p >= 0.05 &
        outlier_p >= 0.05,
      acceptable_candidate = convergence_ok & residual_tests_ok
    ) %>%
    arrange(AIC)
  
  write.table(
    combined_table,
    file = file.path(output_dir, paste0(sp_safe, "_distribution_comparison.txt")),
    sep = ";",
    dec = ".",
    row.names = FALSE
  )
  
  print(combined_table)
  
  all_model_comparisons[[sp]] <- combined_table
  all_dharma_results[[sp]] <- dharma_table
  
  # Vertaa sisäkkäisiä Poisson- ja nollainflatoituja malleja vain suuntaa-antavasti.
  # AIC ja DHARMa ovat tässä ensisijaiset, koska jakaumaperheet eivät kaikki ole sisäkkäisiä.
  if (length(fitted_models) > 0 && save_fitted_models) {
    saveRDS(
      fitted_models,
      file.path(output_dir, paste0(sp_safe, "_all_fitted_models.rds"))
    )
  }
  
  rm(fitted_models)
  gc()
}

#========================================================
# 7. Yhteenveto kaikista lajeista
#========================================================

comparison_all <- bind_rows(all_model_comparisons) %>%
  group_by(species) %>%
  arrange(AIC, .by_group = TRUE) %>%
  mutate(AIC_rank = row_number()) %>%
  ungroup()

write.table(
  comparison_all,
  file = file.path(output_dir, "all_species_distribution_comparison.txt"),
  sep = ";",
  dec = ".",
  row.names = FALSE
)

best_by_AIC <- comparison_all %>%
  filter(AIC_rank == 1) %>%
  select(
    species, model, AIC, delta_AIC, Akaike_weight,
    convergence_ok, residual_tests_ok, acceptable_candidate,
    uniformity_p, dispersion_p, zero_inflation_p, outlier_p
  )

best_acceptable <- comparison_all %>%
  filter(acceptable_candidate) %>%
  group_by(species) %>%
  slice_min(AIC, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(
    species, model, AIC, delta_AIC, Akaike_weight,
    convergence_ok, residual_tests_ok,
    uniformity_p, dispersion_p, zero_inflation_p, outlier_p
  )

write.table(
  best_by_AIC,
  file = file.path(output_dir, "best_distribution_by_AIC.txt"),
  sep = ";",
  dec = ".",
  row.names = FALSE
)

write.table(
  best_acceptable,
  file = file.path(output_dir, "best_distribution_passing_DHARMa.txt"),
  sep = ";",
  dec = ".",
  row.names = FALSE
)

if (length(all_failures) > 0) {
  failure_table <- bind_rows(all_failures)
  write.table(
    failure_table,
    file = file.path(output_dir, "failed_distribution_models.txt"),
    sep = ";",
    dec = ".",
    row.names = FALSE
  )
}

cat("\n========================================================\n")
cat("JAKAUMADIAGNOSTIIKKA VALMIS\n")
cat("Tuloshakemisto:", output_dir, "\n")
cat("\nParas jakauma AIC:n perusteella:\n")
print(best_by_AIC)
cat("\nParas jakauma, joka läpäisi kaikki DHARMa-testit:\n")
print(best_acceptable)
cat("========================================================\n")

#========================================================
# Tulkinta
#========================================================
# Älä valitse jakaumaa vain pienimmän AIC:n perusteella.
# Hyvän kandidaatin pitäisi:
# 1) konvergoida ja saada positive_definite_Hessian = TRUE,
# 2) olla AIC:n perusteella kilpailukykyinen,
# 3) läpäistä DHARMa-testit ainakin kohtuullisesti,
# 4) tuottaa järkevän näköiset residuaalikuvaajat.
#
# Erityisesti Epirrita autumnata:
# - Poisson hylätään, jos dispersion_p < 0.05 tai dispersion_statistic >> 1.
# - NB2 sopii usein massaesiintymiin paremmin kuin NB1, koska sen varianssi
#   kasvaa keskiarvon neliön mukana.
# - COM-Poisson tai generalized Poisson voi auttaa, jos NB-mallitkaan eivät
#   kuvaa dispersion rakennetta.
# - Nollainflatoitu malli on perusteltu vain, jos se parantaa AIC:tä JA
#   tavallisen mallin DHARMa zero-inflation-testi osoittaa ylimääräisiä nollia.
#========================================================

#========================================================
# JATKO EDELLISELLE JAKAUMADIAGNOSTIIKKASKRIPTILLE
# Massaesiintymien, ääriarvojen ja runsauden keskittymisen analyysi
#========================================================
#
# Aja tämä skripti samassa R-istunnossa heti skriptin
# check_species_count_distributions_fast.R jälkeen.
#
# Skripti käyttää jo olemassa olevia objekteja:
#   count_wide, target_species, output_dir
#
# Se ei lue alkuperäistä aineistoa uudelleen.
#========================================================

required_objects <- c("count_wide", "target_species", "output_dir")
missing_objects <- required_objects[!vapply(required_objects, exists, logical(1), inherits = TRUE)]

if (length(missing_objects) > 0) {
  stop(
    "Seuraavat edellisen skriptin objektit puuttuvat: ",
    paste(missing_objects, collapse = ", "),
    ". Aja ensin check_species_count_distributions_fast.R samassa R-istunnossa."
  )
}

required_packages <- c("dplyr", "tidyr", "ggplot2")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing_packages) > 0) {
  stop(
    "Asenna ensin puuttuvat paketit: ",
    paste(missing_packages, collapse = ", ")
  )
}

library(dplyr)
library(tidyr)
library(ggplot2)

#--------------------------------------------------------
# 1. Asetukset
#--------------------------------------------------------

extreme_output_dir <- file.path(output_dir, "extreme_abundance_analysis")
dir.create(extreme_output_dir, recursive = TRUE, showWarnings = FALSE)

# Biologisesti helposti tulkittavat absoluuttiset rajat.
abundance_thresholds <- c(1, 10, 50, 100, 500, 1000, 5000, 10000)

# Otososuudet, joiden hallitsevuutta tarkastellaan.
top_proportions <- c(0.001, 0.005, 0.01, 0.05, 0.10, 0.20)

# Empiiriset kvantiilirajat massaesiintymien luokitteluun.
outbreak_quantiles <- c(0.90, 0.95, 0.99, 0.995, 0.999)

# Varmista keskeiset muuttujat.
needed_columns <- c("species", "count")
missing_columns <- setdiff(needed_columns, names(count_wide))
if (length(missing_columns) > 0) {
  stop("count_wide-objektista puuttuvat sarakkeet: ", paste(missing_columns, collapse = ", "))
}

count_extreme <- count_wide %>%
  mutate(
    species = as.character(species),
    count = as.numeric(count)
  ) %>%
  filter(species %in% target_species, is.finite(count), count >= 0)

if (nrow(count_extreme) == 0) stop("Analyysiin ei jäänyt havaintoja.")

safe_name_local <- function(x) gsub("[^A-Za-z0-9_]+", "_", x)

#--------------------------------------------------------
# 2. Apufunktiot
#--------------------------------------------------------

gini_coefficient <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & x >= 0]
  n <- length(x)
  if (n == 0 || sum(x) == 0) return(NA_real_)
  x <- sort(x)
  (2 * sum(seq_len(n) * x) / (n * sum(x))) - (n + 1) / n
}

lorenz_table <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & x >= 0]
  x <- sort(x)
  n <- length(x)
  
  if (n == 0) {
    return(data.frame(sample_share = numeric(0), abundance_share = numeric(0)))
  }
  
  total <- sum(x)
  abundance_share <- if (total > 0) cumsum(x) / total else rep(0, n)
  
  bind_rows(
    data.frame(sample_share = 0, abundance_share = 0),
    data.frame(sample_share = seq_len(n) / n, abundance_share = abundance_share)
  )
}

top_share_summary <- function(x, proportions = top_proportions) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & x >= 0]
  n <- length(x)
  total <- sum(x)
  x_desc <- sort(x, decreasing = TRUE)
  
  bind_rows(lapply(proportions, function(p) {
    n_top <- max(1L, ceiling(n * p))
    top_total <- sum(x_desc[seq_len(n_top)])
    data.frame(
      top_sample_proportion = p,
      top_sample_percent = 100 * p,
      n_top_samples = n_top,
      abundance_in_top_samples = top_total,
      share_of_total_abundance = if (total > 0) top_total / total else NA_real_,
      percent_of_total_abundance = if (total > 0) 100 * top_total / total else NA_real_
    )
  }))
}

threshold_summary <- function(x, thresholds = abundance_thresholds) {
  x <- as.numeric(x)
  x <- x[is.finite(x) & x >= 0]
  n <- length(x)
  total <- sum(x)
  
  bind_rows(lapply(thresholds, function(threshold) {
    hit <- x >= threshold
    abundance_hit <- sum(x[hit])
    data.frame(
      threshold = threshold,
      n_samples_at_or_above = sum(hit),
      sample_proportion = mean(hit),
      sample_percent = 100 * mean(hit),
      abundance_at_or_above = abundance_hit,
      share_of_total_abundance = if (total > 0) abundance_hit / total else NA_real_,
      percent_of_total_abundance = if (total > 0) 100 * abundance_hit / total else NA_real_
    )
  }))
}

#--------------------------------------------------------
# 3. Lajikohtaiset yhteenvedot
#--------------------------------------------------------

basic_extreme_summary <- count_extreme %>%
  group_by(species) %>%
  summarise(
    n = n(),
    total_count = sum(count),
    mean_count = mean(count),
    variance_count = var(count),
    variance_mean_ratio = variance_count / mean_count,
    sd_count = sd(count),
    coefficient_of_variation = sd_count / mean_count,
    median = median(count),
    q75 = quantile(count, 0.75, names = FALSE),
    q90 = quantile(count, 0.90, names = FALSE),
    q95 = quantile(count, 0.95, names = FALSE),
    q99 = quantile(count, 0.99, names = FALSE),
    q995 = quantile(count, 0.995, names = FALSE),
    q999 = quantile(count, 0.999, names = FALSE),
    maximum = max(count),
    zero_n = sum(count == 0),
    zero_proportion = mean(count == 0),
    positive_n = sum(count > 0),
    gini = gini_coefficient(count),
    .groups = "drop"
  )

write.table(
  basic_extreme_summary,
  file = file.path(extreme_output_dir, "extreme_abundance_basic_summary.txt"),
  sep = ";", dec = ".", row.names = FALSE
)

all_thresholds <- list()
all_top_shares <- list()
all_lorenz <- list()
all_quantile_limits <- list()

for (sp in target_species) {
  sp_data <- count_extreme %>% filter(species == sp)
  sp_safe <- safe_name_local(sp)
  
  threshold_table <- threshold_summary(sp_data$count) %>%
    mutate(species = sp, .before = 1)
  
  top_table <- top_share_summary(sp_data$count) %>%
    mutate(species = sp, .before = 1)
  
  lorenz <- lorenz_table(sp_data$count) %>%
    mutate(species = sp, .before = 1)
  
  quantile_table <- data.frame(
    species = sp,
    quantile_probability = outbreak_quantiles,
    quantile_percent = 100 * outbreak_quantiles,
    abundance_limit = as.numeric(quantile(sp_data$count, outbreak_quantiles, names = FALSE)),
    stringsAsFactors = FALSE
  )
  
  all_thresholds[[sp]] <- threshold_table
  all_top_shares[[sp]] <- top_table
  all_lorenz[[sp]] <- lorenz
  all_quantile_limits[[sp]] <- quantile_table
  
  write.table(
    threshold_table,
    file = file.path(extreme_output_dir, paste0(sp_safe, "_absolute_thresholds.txt")),
    sep = ";", dec = ".", row.names = FALSE
  )
  
  write.table(
    top_table,
    file = file.path(extreme_output_dir, paste0(sp_safe, "_top_sample_shares.txt")),
    sep = ";", dec = ".", row.names = FALSE
  )
  
  write.table(
    quantile_table,
    file = file.path(extreme_output_dir, paste0(sp_safe, "_empirical_outbreak_limits.txt")),
    sep = ";", dec = ".", row.names = FALSE
  )
  
  # Lorenz-käyrä
  p_lorenz <- ggplot(lorenz, aes(x = sample_share, y = abundance_share)) +
    geom_line(linewidth = 0.9) +
    geom_abline(slope = 1, intercept = 0, linetype = 2) +
    coord_equal() +
    labs(
      title = paste0("Lorenz-käyrä: ", sp),
      subtitle = paste0("Gini = ", round(gini_coefficient(sp_data$count), 3)),
      x = "Kumulatiivinen osuus näytteistä",
      y = "Kumulatiivinen osuus yksilöistä"
    ) +
    theme_bw()
  
  ggsave(
    file.path(extreme_output_dir, paste0(sp_safe, "_Lorenz_curve.pdf")),
    p_lorenz, width = 7, height = 7
  )
  
  # CCDF näyttää oikean hännän ilman histogrammin peittymistä.
  ccdf <- sp_data %>%
    arrange(count) %>%
    mutate(
      rank_ascending = row_number(),
      probability_at_or_above = (n() - rank_ascending + 1) / n()
    ) %>%
    filter(count > 0)
  
  p_ccdf <- ggplot(ccdf, aes(x = count, y = probability_at_or_above)) +
    geom_step() +
    scale_x_log10() +
    scale_y_log10() +
    labs(
      title = paste0("Runsauden oikea häntä: ", sp),
      x = "Runsaus (log10-asteikko)",
      y = "P(runsaus ≥ x), log10-asteikko"
    ) +
    theme_bw()
  
  ggsave(
    file.path(extreme_output_dir, paste0(sp_safe, "_CCDF_loglog.pdf")),
    p_ccdf, width = 8, height = 6
  )
  
  # Järjestetyt runsaudet näyttävät kuinka harvat havainnot hallitsevat kokonaismäärää.
  ranked <- sp_data %>%
    arrange(desc(count)) %>%
    mutate(
      abundance_rank = row_number(),
      sample_rank_proportion = abundance_rank / n(),
      cumulative_abundance_share = cumsum(count) / sum(count)
    )
  
  p_rank <- ggplot(ranked, aes(x = sample_rank_proportion, y = count)) +
    geom_line() +
    scale_y_log10() +
    labs(
      title = paste0("Järjestetty runsaus: ", sp),
      x = "Näytteen sijoitus / näytteiden määrä",
      y = "Runsaus (log10-asteikko)"
    ) +
    theme_bw()
  
  ggsave(
    file.path(extreme_output_dir, paste0(sp_safe, "_rank_abundance.pdf")),
    p_rank, width = 8, height = 6
  )
}

thresholds_all <- bind_rows(all_thresholds)
top_shares_all <- bind_rows(all_top_shares)
lorenz_all <- bind_rows(all_lorenz)
quantile_limits_all <- bind_rows(all_quantile_limits)

write.table(
  thresholds_all,
  file = file.path(extreme_output_dir, "all_species_absolute_thresholds.txt"),
  sep = ";", dec = ".", row.names = FALSE
)

write.table(
  top_shares_all,
  file = file.path(extreme_output_dir, "all_species_top_sample_shares.txt"),
  sep = ";", dec = ".", row.names = FALSE
)

write.table(
  quantile_limits_all,
  file = file.path(extreme_output_dir, "all_species_empirical_outbreak_limits.txt"),
  sep = ";", dec = ".", row.names = FALSE
)

# Yhteinen Lorenz-kuva.
p_lorenz_all <- ggplot(lorenz_all, aes(x = sample_share, y = abundance_share, linetype = species)) +
  geom_line(linewidth = 0.9) +
  geom_abline(slope = 1, intercept = 0, linetype = 2) +
  coord_equal() +
  labs(
    title = "Runsauden keskittyminen lajeittain",
    x = "Kumulatiivinen osuus näytteistä",
    y = "Kumulatiivinen osuus yksilöistä",
    linetype = "Laji"
  ) +
  theme_bw()

ggsave(
  file.path(extreme_output_dir, "all_species_Lorenz_curves.pdf"),
  p_lorenz_all, width = 8, height = 7
)

#--------------------------------------------------------
# 4. Massaesiintymäluokat myöhempää kaksiosaista mallia varten
#--------------------------------------------------------

# Jokaiselle lajille omat empiiriset rajat. Luokittelu ei muuta alkuperäistä countia.
outbreak_cutoffs <- count_extreme %>%
  group_by(species) %>%
  summarise(
    cutoff_q95 = quantile(count, 0.95, names = FALSE),
    cutoff_q99 = quantile(count, 0.99, names = FALSE),
    cutoff_q995 = quantile(count, 0.995, names = FALSE),
    cutoff_q999 = quantile(count, 0.999, names = FALSE),
    .groups = "drop"
  )

count_outbreak <- count_extreme %>%
  left_join(outbreak_cutoffs, by = "species") %>%
  mutate(
    presence = as.integer(count > 0),
    positive_count = ifelse(count > 0, count, NA_real_),
    outbreak_q95 = as.integer(count >= cutoff_q95 & count > 0),
    outbreak_q99 = as.integer(count >= cutoff_q99 & count > 0),
    outbreak_q995 = as.integer(count >= cutoff_q995 & count > 0),
    outbreak_q999 = as.integer(count >= cutoff_q999 & count > 0),
    abundance_class = case_when(
      count == 0 ~ "zero",
      count < cutoff_q95 ~ "positive_below_q95",
      count < cutoff_q99 ~ "high_q95_to_q99",
      count < cutoff_q995 ~ "outbreak_q99_to_q995",
      count < cutoff_q999 ~ "extreme_q995_to_q999",
      TRUE ~ "most_extreme_q999"
    )
  )

write.table(
  outbreak_cutoffs,
  file = file.path(extreme_output_dir, "species_specific_outbreak_cutoffs.txt"),
  sep = ";", dec = ".", row.names = FALSE
)

write.table(
  count_outbreak,
  file = file.path(extreme_output_dir, "count_data_with_outbreak_classes.txt"),
  sep = ";", dec = ".", row.names = FALSE
)

# Valmiit aineistot kaksiosaiseen mallinnukseen.
presence_data <- count_outbreak
positive_abundance_data <- count_outbreak %>% filter(count > 0)
outbreak_q99_data <- count_outbreak

write.table(
  presence_data,
  file = file.path(extreme_output_dir, "two_part_1_presence_absence_data.txt"),
  sep = ";", dec = ".", row.names = FALSE
)

write.table(
  positive_abundance_data,
  file = file.path(extreme_output_dir, "two_part_2_positive_abundance_data.txt"),
  sep = ";", dec = ".", row.names = FALSE
)

write.table(
  outbreak_q99_data,
  file = file.path(extreme_output_dir, "outbreak_q99_binary_data.txt"),
  sep = ";", dec = ".", row.names = FALSE
)

#--------------------------------------------------------
# 5. Ajallinen ja paikallinen keskittyminen, jos sarakkeet ovat olemassa
#--------------------------------------------------------

summarise_concentration_by <- function(data, grouping_variable, file_stub) {
  if (!grouping_variable %in% names(data)) return(NULL)
  
  summary_data <- data %>%
    group_by(species, .data[[grouping_variable]]) %>%
    summarise(
      n_samples = n(),
      total_count = sum(count),
      mean_count = mean(count),
      maximum = max(count),
      n_outbreak_q99 = sum(outbreak_q99),
      .groups = "drop"
    ) %>%
    group_by(species) %>%
    mutate(
      share_of_species_total = total_count / sum(total_count),
      rank_by_total = rank(-total_count, ties.method = "first")
    ) %>%
    ungroup()
  
  write.table(
    summary_data,
    file = file.path(extreme_output_dir, paste0(file_stub, ".txt")),
    sep = ";", dec = ".", row.names = FALSE
  )
  
  summary_data
}

year_summary <- summarise_concentration_by(count_outbreak, "year", "abundance_concentration_by_year")
site_summary <- summarise_concentration_by(count_outbreak, "site", "abundance_concentration_by_site")
week_summary <- summarise_concentration_by(count_outbreak, "week", "abundance_concentration_by_week")

if (!is.null(year_summary)) {
  p_year <- ggplot(year_summary, aes(x = as.numeric(as.character(year)), y = total_count, linetype = species)) +
    geom_line() +
    geom_point() +
    scale_y_log10() +
    labs(
      title = "Kokonaisrunsaus vuosittain",
      x = "Vuosi",
      y = "Kokonaisrunsaus (log10-asteikko)",
      linetype = "Laji"
    ) +
    theme_bw()
  
  ggsave(
    file.path(extreme_output_dir, "annual_total_abundance_log.pdf"),
    p_year, width = 10, height = 6
  )
}

#--------------------------------------------------------
# 6. Autumnatan ääriarvojen tarkka luettelo
#--------------------------------------------------------

autumnata_name <- target_species[grepl("Epirrita autumnata", target_species, fixed = TRUE)]
if (length(autumnata_name) == 1) {
  autumnata_extremes <- count_outbreak %>%
    filter(species == autumnata_name) %>%
    arrange(desc(count)) %>%
    mutate(
      abundance_rank = row_number(),
      cumulative_count = cumsum(count),
      cumulative_share = cumulative_count / sum(count)
    )
  
  # Ensimmäiset 1 000 havaintoa ovat yleensä riittävä tarkastuslista.
  write.table(
    head(autumnata_extremes, 1000),
    file = file.path(extreme_output_dir, "Epirrita_autumnata_top_1000_observations.txt"),
    sep = ";", dec = ".", row.names = FALSE
  )
}

#--------------------------------------------------------
# 7. Tulosta ydinpäätelmien numerot konsoliin
#--------------------------------------------------------

cat("\n========================================================\n")
cat("MASSAESIINTYMIEN JA ÄÄRIARVOJEN ANALYYSI VALMIS\n")
cat("Tuloshakemisto:", extreme_output_dir, "\n\n")

cat("Perusyhteenveto ja Gini-kertoimet:\n")
print(basic_extreme_summary %>% select(species, n, total_count, mean_count, median, q99, maximum, zero_proportion, gini))

cat("\nYlimmän 1 %:n osuus kaikista yksilöistä:\n")
print(
  top_shares_all %>%
    filter(abs(top_sample_proportion - 0.01) < 1e-12) %>%
    select(species, n_top_samples, percent_of_total_abundance)
)

cat("\nYlimmän 5 %:n osuus kaikista yksilöistä:\n")
print(
  top_shares_all %>%
    filter(abs(top_sample_proportion - 0.05) < 1e-12) %>%
    select(species, n_top_samples, percent_of_total_abundance)
)

cat("\nLajikohtaiset q99-massaesiintymärajat:\n")
print(outbreak_cutoffs %>% select(species, cutoff_q99, cutoff_q995, cutoff_q999))
cat("========================================================\n")