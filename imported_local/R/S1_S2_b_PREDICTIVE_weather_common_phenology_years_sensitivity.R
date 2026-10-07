#========================================================
# HMSC VUOSITASOLLA: ENNUSTAVAN säävalinnan herkkyys yhteisille fenologiavuosille
#
# JATKAA SUORAAN TIEDOSTOSTA:
#   HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1/
#   HMSC_annual_three_species_weather_environment_buffers_results.RData
#
# Tämä skripti EI aja S1_S2_a-pääanalyysiä uudelleen. Se:
#   1. lataa pääanalyysin valmiit vuosiaineisto- ja valintaobjektit
#   2. tarkistaa päämallin posterior predictive -tilan
#   3. tunnistaa vuodet, joilla kasvukauden fenologia on riittävän kattava
#   4. valitsee sääryhmät ja säämuuttujat uudelleen vain näillä vuosilla year-blocked CV:llä
#   5. sovittaa alkuperäisen ja uudelleen valitun säämallin samoille riveille
#   6. raportoi valintojen vakauden, predictive CV -metriikat, PPC:n,
#      beta-parametrit, konvergenssin ja varianssiosituksen
#
# TÄRKEÄÄ:
# - Analyysiyksikkö on paikkavuosi.
# - Vaste on vuotuinen kokonaislukumäärä.
# - Havaintomalli on lognormal Poisson.
# - Pyyntiponnistus on Loff = log(total_effort_days / 7).
# - Splineja ei käytetä.
# - Tämä on ennustava herkkyysanalyysi: muuttujavalinta perustuu year-blocked ristiinvalidointiin.
# - Päämallin nykyinen PPC vaatii tarkistusta. Herkkyysanalyysi ei yksin
#   ratkaise havaintomallin mahdollista puutteellisuutta.
#========================================================

set.seed(2)

#========================================================
# 1. KÄYTTÄJÄN ASETUKSET
#========================================================

primary_output_dir <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1"
)

primary_rdata_file <- file.path(
  primary_output_dir,
  "HMSC_annual_three_species_weather_environment_buffers_results.RData"
)

primary_results_file <- file.path(
  primary_output_dir,
  "PRIMARY_ANNUAL_RESULTS.rds"
)

sensitivity_output_dir <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "HMSC_ANNUAL_PREDICTIVE_COMMON_PHENOLOGY_YEARS_SENSITIVITY_v1"
)

dir.create(
  sensitivity_output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

# Fenologiavuosi hyväksytään, kun vähintään 80 % vuoden paikkavuosista sisältää
# kaikki current_growing_phenology-ryhmän saatavilla olevat muuttujat.
phenology_reference_group <- "current_growing_phenology"
phenology_year_coverage_threshold <- 0.80
minimum_site_years_per_year_for_coverage <- 20L
minimum_eligible_years <- 3L

# TRUE sallii herkkyysanalyysin jatkua, vaikka päämallin PPC vaatii tarkistusta.
# Tulos merkitään tällöin diagnostiseksi eikä vahvistetuksi päämalliksi.
allow_sensitivity_despite_primary_ppc_failure <- TRUE

#--------------------------------------------------------
# Ennustavan herkkyysanalyysin cross-validation
#--------------------------------------------------------
# Muuttujavalinnan ensisijainen tavoite on ennustaa uusia vuosia.
# Kaikki saman vuoden paikkavuodet ovat samassa foldissa. REF- ja CAND-mallit
# käyttävät samoja rivejä, samaa lohkomuuttujaa ja samaa siementä.
selection_primary_evaluation <- "cv_year"
selection_cv_specs <- list(
  cv_year = list(
    block = "year",
    nfolds = 5L,
    seed = 20260818L
  )
)

# Lopullinen matched-sample-vertailu raportoidaan sekä uusille vuosille että
# uusille paikoille. Muuttujavalinta perustuu silti vain cv_year-arviointiin.
final_cv_specs <- list(
  cv_year = list(
    block = "year",
    nfolds = 5L,
    seed = 20260818L
  ),
  cv_site = list(
    block = "site",
    nfolds = 5L,
    seed = 20260819L
  )
)

#--------------------------------------------------------
# MCMC-asetukset
#--------------------------------------------------------

# Sääryhmien nopea seulonta.
selection_samples   <- 100L
selection_transient <- 100L
selection_thin      <- 5L
selection_chains    <- 2L
selection_parallel  <- 2L

# Forward-ehdokkaan vahvistus.
confirm_samples   <- 300L
confirm_transient <- 300L
confirm_thin      <- 5L
confirm_chains    <- 2L
confirm_parallel  <- 2L

# Lopulliset kaksi saman aineiston vertailumallia.
# Asetukset vastaavat vuosipäämallin pitkää ajoa.
final_samples   <- 5000L
final_transient <- 10000L
final_thin      <- 20L
final_chains    <- 4L
final_parallel  <- 4L

# Tekninen smoke-ajo ei ole tarpeen, kun päämalli on jo valmistunut.
run_quick_test  <- FALSE
quick_samples   <- 2L
quick_transient <- 2L
quick_thin      <- 1L
quick_chains    <- 1L

# Ennustearrayssa käytettävien posterioriarvontojen yläraja.
max_prediction_draws <- 1000L

#--------------------------------------------------------
# Sama predictive-valintalogiikka kuin ennustavassa vuosipäämallissa
#--------------------------------------------------------

min_community_delta_predictive_SR2 <- 0.002
min_strong_species_delta_predictive_SR2 <- 0.010
max_allowed_harm_other_species <- 0.01
max_allowed_backward_mean_loss <- 0.001
minimum_nonnegative_species <- 2L
species_delta_tolerance <- 1e-8

weather_correlation_limit <- 0.80
environment_correlation_limit <- 0.90
minimum_variables_per_selected_group <- 1L
min_sample_proportion <- 0.79
max_selected_weather_groups <- 5L
max_selected_environment_groups <- 0L
stop_when_no_improvement <- TRUE
posterior_support_threshold <- 0.95

hmsc_distribution <- "lognormal poisson"
annual_index_standard_days <- 7

# fit_hmsc_model()-funktion käyttämä tuloshakemisto.
modelDir <- sensitivity_output_dir
#========================================================
# 2. KIRJASTOT JA BIOLOGISET MUUTTUJARYHMÄT
#========================================================

suppressPackageStartupMessages({
  library(Hmsc)
  library(dplyr)
  library(tidyr)
  library(coda)
})

# Kaikki seuraavat muuttujaryhmät ja apufunktiot ovat tässä tiedostossa.
# Skripti ei etsi, source()-kutsu eikä tarvitse muita R-skriptejä.

# 2A. BIOLOGISET MUUTTUJARYHMÄT
#========================================================

weather_groups <- list(
  
  current_winter_temperature = c(
    "current_winter_mean_temperature",
    "current_winter_mean_Tmin",
    "current_winter_min_Tmin",
    "current_winter_mean_Tmax",
    "current_winter_days_Tmin_below_minus37",
    "current_winter_cold_exposure_below_minus37"
  ),
  
  current_winter_moisture_snow = c(
    "current_winter_sum_precipitation",
    "current_winter_mean_snow",
    "current_winter_max_snow",
    "current_winter_snowmelt_sum"
  ),
  
  current_spring_temperature = c(
    "current_spring_mean_temperature",
    "current_spring_mean_Tmin",
    "current_spring_min_Tmin",
    "current_spring_mean_Tmax",
    "current_spring_days_above_5",
    "current_spring_days_above_10",
    "current_spring_frost_days",
    "current_spring_GDD5"
  ),
  
  current_spring_moisture_snow = c(
    "current_spring_sum_precipitation",
    "current_spring_mean_snow",
    "current_spring_snow_days",
    "current_spring_snowmelt_sum"
  ),
  
  current_summer_temperature = c(
    "current_summer_mean_temperature",
    "current_summer_mean_Tmin",
    "current_summer_min_Tmin",
    "current_summer_mean_Tmax",
    "current_summer_max_Tmax"
  ),
  
  current_summer_moisture = c(
    "current_summer_sum_precipitation",
    "current_summer_mean_precipitation"
  ),
  
  current_autumn_temperature = c(
    "current_autumn_mean_temperature",
    "current_autumn_mean_Tmin",
    "current_autumn_min_Tmin",
    "current_autumn_mean_Tmax"
  ),
  
  current_autumn_moisture = c(
    "current_autumn_sum_precipitation",
    "current_autumn_mean_precipitation"
  ),
  
  current_season_phenology = c(
    "current_thermal_spring_start_0_doy",
    "current_biological_spring_start_5_doy",
    "current_thermal_summer_start_10_doy",
    "current_thermal_autumn_start_10_doy",
    "current_thermal_winter_start_0_doy",
    "current_biological_winter_start_doy",
    "current_spring_length_days",
    "current_summer_length_days",
    "current_autumn_length_days",
    "current_winter_length_days",
    "current_thermal_spring_start_0_anomaly_days",
    "current_spring_start_anomaly_days",
    "current_summer_start_anomaly_days",
    "current_autumn_start_anomaly_days",
    "current_thermal_winter_start_0_anomaly_days",
    "current_winter_start_anomaly_days",
    "current_winter_length_anomaly_days",
    "current_spring_length_anomaly_days",
    "current_summer_length_anomaly_days",
    "current_autumn_length_anomaly_days"
  ),
  
  current_annual_temperature = c(
    "current_annual_mean_temperature",
    "current_annual_mean_Tmin",
    "current_annual_min_Tmin",
    "current_annual_mean_Tmax",
    "current_annual_max_Tmax",
    "current_annual_GDD_minus5",
    "current_annual_GDD_0",
    "current_annual_GDD_5",
    "current_annual_days_Tmin_below_minus37",
    "current_annual_cold_exposure_below_minus37"
  ),
  
  current_annual_moisture = c(
    "current_annual_sum_precipitation",
    "current_annual_mean_snow",
    "current_annual_max_snow",
    "current_annual_API_mean",
    "current_annual_API_max",
    "current_annual_API_end",
    "current_annual_precipitation_30d_end",
    "current_annual_precipitation_90d_end"
  ),
  
  current_short_term_temperature = c(
    "current_annual_temperature_30d_end",
    "current_annual_temperature_90d_end"
  ),
  
  current_growing_temperature = c(
    "current_growing_mean_temperature",
    "current_growing_mean_Tmin",
    "current_growing_mean_Tmax",
    "current_growing_GDD_minus5",
    "current_growing_GDD_0",
    "current_growing_GDD_5"
  ),
  
  current_growing_moisture = c(
    "current_growing_sum_precipitation"
  ),
  
  current_growing_phenology = c(
    "current_growing_start_doy",
    "current_growing_end_doy",
    "current_growing_n_days"
  ),
  
  lag1_winter_temperature = c(
    "lag1_winter_mean_temperature",
    "lag1_winter_mean_Tmin",
    "lag1_winter_min_Tmin",
    "lag1_winter_mean_Tmax",
    "lag1_winter_days_Tmin_below_minus37",
    "lag1_winter_cold_exposure_below_minus37"
  ),
  
  lag1_winter_moisture_snow = c(
    "lag1_winter_sum_precipitation",
    "lag1_winter_mean_snow",
    "lag1_winter_max_snow",
    "lag1_winter_snowmelt_sum"
  ),
  
  lag1_spring_temperature = c(
    "lag1_spring_mean_temperature",
    "lag1_spring_mean_Tmin",
    "lag1_spring_min_Tmin",
    "lag1_spring_mean_Tmax",
    "lag1_spring_days_above_5",
    "lag1_spring_days_above_10",
    "lag1_spring_frost_days",
    "lag1_spring_GDD5"
  ),
  
  lag1_spring_moisture_snow = c(
    "lag1_spring_sum_precipitation",
    "lag1_spring_mean_snow",
    "lag1_spring_snow_days",
    "lag1_spring_snowmelt_sum"
  ),
  
  lag1_summer_temperature = c(
    "lag1_summer_mean_temperature",
    "lag1_summer_mean_Tmin",
    "lag1_summer_min_Tmin",
    "lag1_summer_mean_Tmax",
    "lag1_summer_max_Tmax"
  ),
  
  lag1_summer_moisture = c(
    "lag1_summer_sum_precipitation",
    "lag1_summer_mean_precipitation"
  ),
  
  lag1_autumn_temperature = c(
    "lag1_autumn_mean_temperature",
    "lag1_autumn_mean_Tmin",
    "lag1_autumn_min_Tmin",
    "lag1_autumn_mean_Tmax"
  ),
  
  lag1_autumn_moisture = c(
    "lag1_autumn_sum_precipitation",
    "lag1_autumn_mean_precipitation"
  ),
  
  lag1_season_phenology = c(
    "lag1_thermal_spring_start_0_doy",
    "lag1_biological_spring_start_5_doy",
    "lag1_thermal_summer_start_10_doy",
    "lag1_thermal_autumn_start_10_doy",
    "lag1_thermal_winter_start_0_doy",
    "lag1_biological_winter_start_doy",
    "lag1_spring_length_days",
    "lag1_summer_length_days",
    "lag1_autumn_length_days",
    "lag1_winter_length_days",
    "lag1_thermal_spring_start_0_anomaly_days",
    "lag1_spring_start_anomaly_days",
    "lag1_summer_start_anomaly_days",
    "lag1_autumn_start_anomaly_days",
    "lag1_thermal_winter_start_0_anomaly_days",
    "lag1_winter_start_anomaly_days",
    "lag1_winter_length_anomaly_days",
    "lag1_spring_length_anomaly_days",
    "lag1_summer_length_anomaly_days",
    "lag1_autumn_length_anomaly_days"
  ),
  
  lag1_annual_temperature = c(
    "lag1_annual_mean_temperature",
    "lag1_annual_mean_Tmin",
    "lag1_annual_min_Tmin",
    "lag1_annual_mean_Tmax",
    "lag1_annual_max_Tmax",
    "lag1_annual_GDD_minus5",
    "lag1_annual_GDD_0",
    "lag1_annual_GDD_5",
    "lag1_annual_days_Tmin_below_minus37",
    "lag1_annual_cold_exposure_below_minus37"
  ),
  
  lag1_annual_moisture = c(
    "lag1_annual_sum_precipitation",
    "lag1_annual_mean_snow",
    "lag1_annual_max_snow",
    "lag1_annual_API_mean",
    "lag1_annual_API_max",
    "lag1_annual_API_end",
    "lag1_annual_precipitation_30d_end",
    "lag1_annual_precipitation_90d_end"
  ),
  
  lag1_short_term_temperature = c(
    "lag1_annual_temperature_30d_end",
    "lag1_annual_temperature_90d_end"
  ),
  
  lag1_growing_temperature = c(
    "lag1_growing_mean_temperature",
    "lag1_growing_mean_Tmin",
    "lag1_growing_mean_Tmax",
    "lag1_growing_GDD_minus5",
    "lag1_growing_GDD_0",
    "lag1_growing_GDD_5"
  ),
  
  lag1_growing_moisture = c(
    "lag1_growing_sum_precipitation"
  ),
  
  lag1_growing_phenology = c(
    "lag1_growing_start_doy",
    "lag1_growing_end_doy",
    "lag1_growing_n_days"
  ),
  
  lag2_winter_temperature = c(
    "lag2_winter_mean_temperature",
    "lag2_winter_mean_Tmin",
    "lag2_winter_min_Tmin",
    "lag2_winter_mean_Tmax",
    "lag2_winter_days_Tmin_below_minus37",
    "lag2_winter_cold_exposure_below_minus37"
  ),
  
  lag2_winter_moisture_snow = c(
    "lag2_winter_sum_precipitation",
    "lag2_winter_mean_snow",
    "lag2_winter_max_snow",
    "lag2_winter_snowmelt_sum"
  ),
  
  lag2_spring_temperature = c(
    "lag2_spring_mean_temperature",
    "lag2_spring_mean_Tmin",
    "lag2_spring_min_Tmin",
    "lag2_spring_mean_Tmax",
    "lag2_spring_days_above_5",
    "lag2_spring_days_above_10",
    "lag2_spring_frost_days",
    "lag2_spring_GDD5"
  ),
  
  lag2_spring_moisture_snow = c(
    "lag2_spring_sum_precipitation",
    "lag2_spring_mean_snow",
    "lag2_spring_snow_days",
    "lag2_spring_snowmelt_sum"
  ),
  
  lag2_summer_temperature = c(
    "lag2_summer_mean_temperature",
    "lag2_summer_mean_Tmin",
    "lag2_summer_min_Tmin",
    "lag2_summer_mean_Tmax",
    "lag2_summer_max_Tmax"
  ),
  
  lag2_summer_moisture = c(
    "lag2_summer_sum_precipitation",
    "lag2_summer_mean_precipitation"
  ),
  
  lag2_autumn_temperature = c(
    "lag2_autumn_mean_temperature",
    "lag2_autumn_mean_Tmin",
    "lag2_autumn_min_Tmin",
    "lag2_autumn_mean_Tmax"
  ),
  
  lag2_autumn_moisture = c(
    "lag2_autumn_sum_precipitation",
    "lag2_autumn_mean_precipitation"
  ),
  
  lag2_season_phenology = c(
    "lag2_thermal_spring_start_0_doy",
    "lag2_biological_spring_start_5_doy",
    "lag2_thermal_summer_start_10_doy",
    "lag2_thermal_autumn_start_10_doy",
    "lag2_thermal_winter_start_0_doy",
    "lag2_biological_winter_start_doy",
    "lag2_spring_length_days",
    "lag2_summer_length_days",
    "lag2_autumn_length_days",
    "lag2_winter_length_days",
    "lag2_thermal_spring_start_0_anomaly_days",
    "lag2_spring_start_anomaly_days",
    "lag2_summer_start_anomaly_days",
    "lag2_autumn_start_anomaly_days",
    "lag2_thermal_winter_start_0_anomaly_days",
    "lag2_winter_start_anomaly_days",
    "lag2_winter_length_anomaly_days",
    "lag2_spring_length_anomaly_days",
    "lag2_summer_length_anomaly_days",
    "lag2_autumn_length_anomaly_days"
  ),
  
  lag2_annual_temperature = c(
    "lag2_annual_mean_temperature",
    "lag2_annual_mean_Tmin",
    "lag2_annual_min_Tmin",
    "lag2_annual_mean_Tmax",
    "lag2_annual_max_Tmax",
    "lag2_annual_GDD_minus5",
    "lag2_annual_GDD_0",
    "lag2_annual_GDD_5",
    "lag2_annual_days_Tmin_below_minus37",
    "lag2_annual_cold_exposure_below_minus37"
  ),
  
  lag2_annual_moisture = c(
    "lag2_annual_sum_precipitation",
    "lag2_annual_mean_snow",
    "lag2_annual_max_snow",
    "lag2_annual_API_mean",
    "lag2_annual_API_max",
    "lag2_annual_API_end",
    "lag2_annual_precipitation_30d_end",
    "lag2_annual_precipitation_90d_end"
  ),
  
  lag2_short_term_temperature = c(
    "lag2_annual_temperature_30d_end",
    "lag2_annual_temperature_90d_end"
  ),
  
  lag2_growing_temperature = c(
    "lag2_growing_mean_temperature",
    "lag2_growing_mean_Tmin",
    "lag2_growing_mean_Tmax",
    "lag2_growing_GDD_minus5",
    "lag2_growing_GDD_0",
    "lag2_growing_GDD_5"
  ),
  
  lag2_growing_moisture = c(
    "lag2_growing_sum_precipitation"
  ),
  
  lag2_growing_phenology = c(
    "lag2_growing_start_doy",
    "lag2_growing_end_doy",
    "lag2_growing_n_days"
  )
)

environment_groups <- list(
  
  DTW_wetness = c(
    "DTW_lt25m_prop", "DTW_lt50m_prop", "DTW_lt100m_prop",
    "DTW_lt250m_prop", "DTW_lt500m_prop", "DTW_mean", "DTW_min",
    "DTW_q10", "DTW_q25", "DTW_sd", "DTW_wetness_exp150_mean",
    "DTW_wetness_exp150_sd", "LocalWetPatchIndex"
  ),
  
  tree_drought_stress = c(
    "HostTreeDroughtStressIndex",
    "SoilDrynessSensitivityIndex"
  ),
  
  soil_moisture_retention = c(
    "OverwinteringSoilBufferIndex",
    "SoilMoistureRetentionIndex",
    "low_soil_retention_lt025_prop",
    "soil_retention_gt05_prop",
    "soil_retention_max",
    "soil_retention_mean",
    "soil_retention_min",
    "soil_retention_sd"
  ),
  
  land_cover = c(
    "clc_built_up_pct", "clc_agriculture_pct",
    "clc_broadleaved_forest_pct", "clc_coniferous_forest_pct",
    "clc_mixed_forest_pct", "clc_shrub_grass_transitional_pct",
    "clc_open_bare_pct", "clc_inland_wetlands_pct",
    "clc_coastal_wetlands_pct", "clc_water_pct"
  ),
  
  forest_amount = c(
    "forest_pct", "forest_cover_pct",
    "total_forest_pct", "clc_forest_total_pct"
  ),
  
  frost = c(
    "frost_n_days20", "frost_cold_sum20", "frost_min_tmin",
    "frost_mean_tmin_below20"
  ),
  
  vegetation_productivity = c(
    "NDVI_mean", "NDVI_median", "NDVI_max"
  ),
  
  conifer_composition = c(
    "havu_mean", "pine_volume", "spruce_volume"
  ),
  
  broadleaf_composition = c(
    "lehti_mean", "birch_volume", "other_broadleaf_volume",
    "broadleaf_canopy_cover"
  ),
  
  forest_structure = c(
    "age", "mean_diameter", "mean_height", "canopy_cover",
    "basal_area", "volume"
  )
)


#========================================================
# 3. HMSC-APUFUNKTIOT
#========================================================

make_numeric <- function(x) {
  if (is.numeric(x)) return(x)
  x <- trimws(as.character(x))
  x[x %in% c("", "NA", "NaN", "NULL")] <- NA_character_
  x <- gsub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

safe_name <- function(x) {
  gsub("[^A-Za-z0-9_]+", "_", x)
}

buffer_key <- function(buffer) {
  format(
    as.numeric(buffer),
    scientific = FALSE,
    trim = TRUE,
    digits = 15
  )
}

buffer_suffix <- function(buffer) {
  paste0("__b", safe_name(buffer_key(buffer)), "m")
}

strip_buffer_suffix <- function(variable) {
  sub("__b[^_]+m$", "", variable)
}

normalize_species_name <- function(x) {
  gsub(
    "[^a-z]",
    "",
    tolower(trimws(as.character(x)))
  )
}

match_target_species <- function(species_names) {
  normalized <- normalize_species_name(species_names)
  
  matched <- vapply(
    target_species_patterns,
    function(pattern) {
      hit <- species_names[normalized == pattern]
      if (length(hit) == 1) hit else NA_character_
    },
    character(1)
  )
  
  if (anyNA(matched)) {
    stop(
      "Kaikkia kolmea kohdelajia ei löytynyt yksikäsitteisesti. Löytyneet lajit: ",
      paste(species_names, collapse = ", "),
      ". Tarkista target_species_patterns."
    )
  }
  
  unname(matched)
}

remove_zero_variance_names <- function(dat, variables) {
  variables <- intersect(variables, names(dat))
  
  keep <- vapply(
    variables,
    function(v) {
      x <- dat[[v]]
      x <- x[is.finite(x)]
      length(x) > 1 && length(unique(x)) > 1
    },
    logical(1)
  )
  
  list(
    kept = variables[keep],
    removed = variables[!keep]
  )
}

remove_high_correlations <- function(
    dat,
    variables,
    protected_variables = character(0),
    limit
) {
  zv <- remove_zero_variance_names(dat, variables)
  kept <- zv$kept
  removed <- zv$removed
  
  if (length(kept) <= 1) {
    return(list(kept = kept, removed = removed))
  }
  
  cor_mat <- suppressWarnings(
    cor(dat[, kept, drop = FALSE], use = "pairwise.complete.obs")
  )
  
  repeat {
    current <- abs(cor_mat[kept, kept, drop = FALSE])
    diag(current) <- 0
    
    if (!any(current > limit, na.rm = TRUE)) break
    
    pairs <- which(current > limit, arr.ind = TRUE)
    pairs <- pairs[pairs[, 1] < pairs[, 2], , drop = FALSE]
    pair_names <- lapply(seq_len(nrow(pairs)), function(i) {
      rownames(current)[pairs[i, ]]
    })
    
    # Pakollisia, jo valittuja muuttujia ei saa poistaa myöhemmän
    # kandidaatin vuoksi. Jos korreloiva pari koostuu kahdesta suojatusta
    # muuttujasta, pari jätetään rauhaan ja etsitään seuraava pari, josta
    # vähintään toinen muuttuja on poistettavissa.
    eligible_pair <- which(vapply(
      pair_names,
      function(z) length(setdiff(z, protected_variables)) > 0L,
      logical(1)
    ))
    if (length(eligible_pair) == 0L) break
    
    pair <- pair_names[[eligible_pair[1]]]
    removable <- setdiff(pair, protected_variables)
    
    if (length(removable) == 1L) {
      drop_variable <- removable
    } else {
      mean_cor <- rowMeans(
        current[removable, , drop = FALSE],
        na.rm = TRUE
      )
      drop_variable <- names(which.max(mean_cor))[1]
    }
    kept <- setdiff(kept, drop_variable)
    removed <- unique(c(removed, drop_variable))
    
    if (length(kept) <= 1) break
  }
  
  list(kept = kept, removed = removed)
}

make_grouped_folds <- function(metadata, block, nfolds, seed = 1) {
  if (!block %in% names(metadata)) {
    stop("CV-lohkomuuttuja puuttuu: ", block)
  }
  
  block_values <- as.character(metadata[[block]])
  n_blocks <- length(unique(block_values))
  if (n_blocks < 2L) {
    stop("CV tarvitsee vähintään kaksi erillistä lohkoa muuttujalle: ", block)
  }
  nfolds <- min(as.integer(nfolds), n_blocks)
  
  block_table <- data.frame(
    block_value = unique(block_values),
    stringsAsFactors = FALSE
  )
  
  block_table$n <- vapply(
    block_table$block_value,
    function(z) sum(block_values == z),
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
  
  fold_lookup <- setNames(
    block_table$fold,
    block_table$block_value
  )
  
  as.integer(fold_lookup[block_values])
}

extract_species_metric <- function(metric, species, metric_name) {
  n_species <- length(species)
  
  if (is.null(metric)) {
    return(rep(NA_real_, n_species))
  }
  
  # Hmsc-versiosta riippuen metriikka voi olla vektori,
  # yhden sarakkeen matriisi tai yhden rivin matriisi.
  if (is.data.frame(metric)) {
    metric <- as.matrix(metric)
  }
  
  if (is.matrix(metric) || is.array(metric)) {
    dims <- dim(metric)
    
    if (length(dims) == 2L && dims[1] == n_species && dims[2] == 1L) {
      metric <- metric[, 1]
    } else if (length(dims) == 2L && dims[1] == 1L && dims[2] == n_species) {
      metric <- metric[1, ]
    } else if (length(metric) == n_species) {
      metric <- as.vector(metric)
    } else {
      stop(
        metric_name,
        "-metriikan rakenne ei vastaa lajimäärää. Lajeja=", n_species,
        ", metriikan dim=", paste(dims, collapse = "x"),
        "."
      )
    }
  }
  
  metric <- as.numeric(metric)
  
  if (length(metric) != n_species) {
    stop(
      metric_name,
      "-metriikassa on ", length(metric),
      " arvoa, mutta lajien määrä on ", n_species,
      "."
    )
  }
  
  metric
}

metric_table <- function(model_name, species, MF, evaluation) {
  species <- as.character(species)
  
  cat("\n--- metric_table diagnostics ---\n")
  cat("Model:", model_name, "\n")
  cat("Evaluation:", evaluation, "\n")
  cat("Species count:", length(species), "\n")
  cat("SR2 count:", length(MF$SR2), "\n")
  print(species)
  print(MF$SR2)
  
  if (length(species) != length(MF$SR2)) {
    stop(
      "Lajien ja SR2-arvojen määrät eroavat: ",
      length(species), " lajia, mutta ",
      length(MF$SR2), " SR2-arvoa."
    )
  }
  
  if (anyDuplicated(species)) {
    stop(
      "Vastematriisin lajien nimet eivät ole yksikäsitteisiä: ",
      paste(unique(species[duplicated(species)]), collapse = ", ")
    )
  }
  
  out <- data.frame(
    model = rep(model_name, length(species)),
    evaluation = rep(evaluation, length(species)),
    species = species,
    RMSE = extract_species_metric(MF$RMSE, species, "RMSE"),
    SR2 = extract_species_metric(MF$SR2, species, "SR2"),
    O.RMSE = extract_species_metric(MF$O.RMSE, species, "O.RMSE"),
    O.AUC = extract_species_metric(MF$O.AUC, species, "O.AUC"),
    O.TjurR2 = extract_species_metric(MF$O.TjurR2, species, "O.TjurR2"),
    C.RMSE = extract_species_metric(MF$C.RMSE, species, "C.RMSE"),
    C.SR2 = extract_species_metric(MF$C.SR2, species, "C.SR2"),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  
  if (
    nrow(out) != length(species) ||
    anyDuplicated(out$species)
  ) {
    stop(
      "Metriikkataulukon muodostaminen epäonnistui: ",
      "lajikohtaiset rivit eivät ole yksikäsitteisiä."
    )
  }
  
  cat("Muodostettu metriikkataulukko:\n")
  print(out)
  
  out
}

metric_summary <- function(metric_data) {
  finite_mean <- function(x) {
    x <- x[is.finite(x)]
    if (length(x) == 0L) NA_real_ else mean(x)
  }
  finite_median <- function(x) {
    x <- x[is.finite(x)]
    if (length(x) == 0L) NA_real_ else median(x)
  }
  metric_data %>%
    group_by(model, evaluation) %>%
    summarise(
      mean_SR2 = finite_mean(SR2),
      median_SR2 = finite_median(SR2),
      mean_RMSE = finite_mean(RMSE),
      median_RMSE = finite_median(RMSE),
      mean_occurrence_AUC = finite_mean(O.AUC),
      median_occurrence_AUC = finite_median(O.AUC),
      mean_conditional_SR2 = finite_mean(C.SR2),
      median_conditional_SR2 = finite_median(C.SR2),
      .groups = "drop"
    )
}

prepare_species_metrics <- function(metric_data, value_name) {
  required <- c("species", "SR2")
  missing_columns <- setdiff(required, names(metric_data))
  
  if (length(missing_columns) > 0) {
    stop(
      "Metriikkataulukosta puuttuvat sarakkeet: ",
      paste(missing_columns, collapse = ", ")
    )
  }
  
  out <- metric_data %>%
    transmute(
      species = as.character(species),
      value = as.numeric(SR2)
    )
  
  duplicate_species <- unique(out$species[duplicated(out$species)])
  
  if (length(duplicate_species) > 0) {
    stop(
      "Samalle lajille löytyi useita SR2-arvoja samassa arvioinnissa: ",
      paste(duplicate_species, collapse = ", "),
      ". Tarkista metric_table() ja arviointityypin suodatus."
    )
  }
  
  names(out)[names(out) == "value"] <- value_name
  out
}

species_delta_table <- function(reference_metrics, candidate_metrics) {
  reference <- prepare_species_metrics(
    reference_metrics,
    "reference_SR2"
  )
  
  candidate <- prepare_species_metrics(
    candidate_metrics,
    "candidate_SR2"
  )
  
  if (!setequal(reference$species, candidate$species)) {
    stop(
      "Referenssi- ja kandidaattimallien lajijoukot eroavat. Referenssi: ",
      paste(reference$species, collapse = ", "),
      "; kandidaatti: ",
      paste(candidate$species, collapse = ", ")
    )
  }
  
  reference %>%
    inner_join(
      candidate,
      by = "species",
      relationship = "one-to-one"
    ) %>%
    arrange(match(species, reference$species)) %>%
    mutate(delta_SR2 = candidate_SR2 - reference_SR2)
}

summarize_species_deltas <- function(delta_table) {
  x <- delta_table$delta_SR2
  x <- x[is.finite(x)]
  
  if (length(x) == 0) {
    return(list(
      mean = NA_real_,
      median = NA_real_,
      minimum = NA_real_,
      maximum = NA_real_,
      n_positive = 0L,
      n_nonnegative = 0L
    ))
  }
  
  list(
    mean = mean(x),
    median = median(x),
    minimum = min(x),
    maximum = max(x),
    n_positive = sum(x > species_delta_tolerance),
    n_nonnegative = sum(x >= -species_delta_tolerance)
  )
}

species_delta_wide <- function(delta_table) {
  if (anyDuplicated(delta_table$species)) {
    stop(
      "species_delta_wide(): sama laji esiintyy useita kertoja: ",
      paste(
        unique(delta_table$species[duplicated(delta_table$species)]),
        collapse = ", "
      )
    )
  }
  
  values <- as.numeric(delta_table$delta_SR2)
  names(values) <- paste0(
    "delta_predictive_SR2_",
    safe_name(delta_table$species)
  )
  
  if (anyDuplicated(names(values))) {
    stop("Lajikohtaisten delta-SR2-sarakkeiden nimet eivät ole yksikäsitteisiä.")
  }
  
  as.data.frame(as.list(values), check.names = FALSE)
}

accept_addition <- function(delta_summary) {
  
  community_support <-
    is.finite(delta_summary$mean) &&
    is.finite(delta_summary$median) &&
    delta_summary$mean >=
    min_community_delta_predictive_SR2 &&
    delta_summary$median >
    species_delta_tolerance &&
    delta_summary$n_nonnegative >=
    minimum_nonnegative_species
  
  strong_species_support <-
    is.finite(delta_summary$maximum) &&
    is.finite(delta_summary$minimum) &&
    is.finite(delta_summary$mean) &&
    delta_summary$maximum >=
    min_strong_species_delta_predictive_SR2 &&
    delta_summary$minimum >=
    -max_allowed_harm_other_species &&
    delta_summary$mean >=
    min_community_delta_predictive_SR2
  
  list(
    accepted =
      community_support || strong_species_support,
    community_support = community_support,
    strong_species_support = strong_species_support
  )
}

accept_removal <- function(delta_summary) {
  # delta = reduced model - full model
  is.finite(delta_summary$mean) &&
    delta_summary$mean >= -max_allowed_backward_mean_loss &&
    delta_summary$minimum >= -max_allowed_harm_other_species &&
    delta_summary$n_nonnegative >= minimum_nonnegative_species
}

group_membership <- function(variables, groups) {
  out <- lapply(groups, function(x) intersect(variables, x))
  out[lengths(out) > 0]
}

check_group_guard <- function(
    current_variables,
    variable_to_remove,
    selected_groups
) {
  before <- group_membership(current_variables, selected_groups)
  after <- group_membership(
    setdiff(current_variables, variable_to_remove),
    selected_groups
  )
  
  protected <- names(before)[
    vapply(
      names(before),
      function(g) {
        variable_to_remove %in% before[[g]] &&
          length(after[[g]]) < minimum_variables_per_selected_group
      },
      logical(1)
    )
  ]
  
  list(
    allowed = length(protected) == 0,
    protected_groups = protected
  )
}

get_environment_group <- function(variable) {
  original_variable <- strip_buffer_suffix(variable)
  hit <- names(environment_groups)[
    vapply(
      environment_groups,
      function(x) original_variable %in% x,
      logical(1)
    )
  ]
  
  if (length(hit) == 0) "environment_other" else hit[1]
}

make_vp_mapping <- function(model_variables) {
  variable_group <- setNames(
    rep(NA_character_, length(model_variables) + 1),
    c("(Intercept)", model_variables)
  )
  
  variable_group["(Intercept)"] <- "Intercept"
  
  weather_in_model <- intersect(
    selected_weather_variables,
    model_variables
  )
  variable_group[weather_in_model] <- "weather"
  
  for (v in intersect(selected_environment_variables, model_variables)) {
    variable_group[v] <- get_environment_group(v)
  }
  
  if (anyNA(variable_group)) {
    stop(
      "Variance partitioning -ryhmä puuttuu muuttujilta: ",
      paste(names(variable_group)[is.na(variable_group)], collapse = ", ")
    )
  }
  
  ordered <- c("(Intercept)", model_variables)
  groupnames <- unique(unname(variable_group[ordered]))
  lookup <- setNames(seq_along(groupnames), groupnames)
  group <- unname(lookup[variable_group[ordered]])
  
  list(
    group = group,
    groupnames = groupnames,
    check = data.frame(
      variable = ordered,
      group_name = unname(variable_group[ordered]),
      group_id = group
    )
  )
}

beta_table_from_model <- function(model_fitted, model_name) {
  if (is.null(model_fitted$postList) || length(model_fitted$postList) == 0L) {
    stop("Mallilta ", model_name, " puuttuvat posteriorinäytteet.")
  }
  
  post_beta <- getPostEstimate(model_fitted, parName = "Beta")
  beta_mean <- as.matrix(post_beta$mean)
  beta_support <- as.matrix(post_beta$support)
  
  predictor_names <- colnames(model_fitted$X)
  if (is.null(predictor_names)) {
    predictor_names <- paste0("predictor_", seq_len(ncol(model_fitted$X)))
  }
  species_names <- colnames(model_fitted$Y)
  if (is.null(species_names)) {
    species_names <- paste0("species_", seq_len(ncol(model_fitted$Y)))
  }
  
  expected_dim <- c(length(predictor_names), length(species_names))
  reverse_dim <- rev(expected_dim)
  
  if (identical(dim(beta_mean), reverse_dim)) beta_mean <- t(beta_mean)
  if (identical(dim(beta_support), reverse_dim)) beta_support <- t(beta_support)
  
  if (!identical(dim(beta_mean), expected_dim) ||
      !identical(dim(beta_support), expected_dim)) {
    stop(
      "Beta-posteriorin dimensio ei vastaa mallia. mean=",
      paste(dim(beta_mean), collapse = "x"),
      ", support=", paste(dim(beta_support), collapse = "x"),
      ", odotettu=", paste(expected_dim, collapse = "x"), "."
    )
  }
  
  out <- bind_rows(lapply(seq_along(predictor_names), function(i) {
    data.frame(
      model = model_name,
      predictor = predictor_names[i],
      species = species_names,
      posterior_mean = as.numeric(beta_mean[i, ]),
      support_positive = as.numeric(beta_support[i, ]),
      support_negative = 1 - as.numeric(beta_support[i, ]),
      stringsAsFactors = FALSE
    )
  })) %>%
    mutate(
      direction = case_when(
        posterior_mean > 0 ~ "positive",
        posterior_mean < 0 ~ "negative",
        TRUE ~ "zero"
      ),
      posterior_support = pmax(support_positive, support_negative),
      supported = posterior_support >= posterior_support_threshold
    )
  
  out
}

variance_partition_tables <- function(VP, model_fitted, model_name) {
  values <- as.matrix(VP$vals)
  
  source_names <- rownames(values)
  if (is.null(source_names)) {
    source_names <- c(
      VP$groupnames,
      paste0("Random: ", model_fitted$rLNames)
    )[seq_len(nrow(values))]
  }
  species_names <- colnames(values)
  if (is.null(species_names)) species_names <- colnames(model_fitted$Y)
  
  rownames(values) <- source_names
  colnames(values) <- species_names
  
  wide <- data.frame(
    model = model_name,
    variance_source = source_names,
    values,
    row.names = NULL,
    check.names = FALSE
  )
  
  long <- wide %>%
    pivot_longer(
      cols = -c(model, variance_source),
      names_to = "species",
      values_to = "variance_proportion"
    )
  
  list(wide = wide, long = long)
}

save_convergence_diagnostics <- function(model_fitted, model_name) {
  coda_objects <- tryCatch(
    convertToCodaObject(model_fitted),
    error = function(e) NULL
  )
  
  if (is.null(coda_objects)) return(invisible(NULL))
  
  for (component in names(coda_objects)) {
    obj <- coda_objects[[component]]
    if (is.null(obj)) next
    
    gelman <- tryCatch(
      gelman.diag(obj, multivariate = FALSE)$psrf,
      error = function(e) NULL
    )
    
    ess <- tryCatch(
      effectiveSize(obj),
      error = function(e) NULL
    )
    
    if (!is.null(gelman)) {
      write.table(
        data.frame(
          parameter = rownames(gelman),
          point_estimate = gelman[, 1],
          upper_CI = gelman[, 2]
        ),
        file = file.path(
          modelDir,
          paste0(model_name, "_", component, "_gelman.txt")
        ),
        sep = ";",
        row.names = FALSE
      )
    }
    
    if (!is.null(ess)) {
      write.table(
        data.frame(
          parameter = names(ess),
          effective_sample_size = as.numeric(ess)
        ),
        file = file.path(
          modelDir,
          paste0(model_name, "_", component, "_ESS.txt")
        ),
        sep = ";",
        row.names = FALSE
      )
    }
  }
}

prediction_thin_for_model <- function(model_fitted, max_draws) {
  chain_lengths <- lengths(model_fitted$postList)
  chain_lengths <- chain_lengths[is.finite(chain_lengths) & chain_lengths > 0]
  if (length(chain_lengths) == 0L) {
    stop("Mallilta puuttuvat posteriorinäytteet ennustamista varten.")
  }
  target_per_chain <- max(1L, floor(max_draws / length(chain_lengths)))
  max(1L, ceiling(max(chain_lengths) / target_per_chain))
}

as_prediction_array <- function(predY, n_rows, n_species) {
  if (!is.array(predY)) predY <- as.array(predY)
  d <- dim(predY)
  if (length(d) != 3L) {
    stop(
      "Ennusteobjektin pitää olla kolmiulotteinen array; saatu dim=",
      paste(d, collapse = "x"), "."
    )
  }
  if (d[1] == n_rows && d[2] == n_species) return(predY)
  
  permutations <- list(
    c(1L, 3L, 2L), c(2L, 1L, 3L), c(2L, 3L, 1L),
    c(3L, 1L, 2L), c(3L, 2L, 1L)
  )
  for (p in permutations) {
    candidate <- aperm(predY, p)
    if (dim(candidate)[1] == n_rows && dim(candidate)[2] == n_species) {
      return(candidate)
    }
  }
  stop(
    "Ennusteobjektin rivejä ja lajeja ei voitu tunnistaa. dim=",
    paste(d, collapse = "x"), ", odotettu=", n_rows, "x", n_species, "xdraws."
  )
}

posterior_predictive_check <- function(predY, Y_observed, model_name) {
  pred_array <- as_prediction_array(
    predY,
    n_rows = nrow(Y_observed),
    n_species = ncol(Y_observed)
  )
  
  interval_summary <- function(x) {
    c(
      q025 = unname(quantile(x, 0.025, na.rm = TRUE)),
      median = unname(median(x, na.rm = TRUE)),
      q975 = unname(quantile(x, 0.975, na.rm = TRUE))
    )
  }
  ppc_p_two_sided <- function(simulated, observed) {
    min(
      1,
      2 * min(
        mean(simulated <= observed, na.rm = TRUE),
        mean(simulated >= observed, na.rm = TRUE)
      )
    )
  }
  
  rows <- lapply(seq_len(ncol(Y_observed)), function(j) {
    observed <- Y_observed[, j]
    keep <- is.finite(observed)
    observed <- observed[keep]
    simulated <- matrix(
      pred_array[keep, j, , drop = FALSE],
      nrow = sum(keep),
      ncol = dim(pred_array)[3]
    )
    
    simulated_zero <- colMeans(simulated == 0, na.rm = TRUE)
    simulated_mean <- colMeans(simulated, na.rm = TRUE)
    simulated_q95 <- apply(
      simulated, 2, quantile, probs = 0.95, na.rm = TRUE, names = FALSE
    )
    simulated_maximum <- apply(simulated, 2, max, na.rm = TRUE)
    
    zero_interval <- interval_summary(simulated_zero)
    mean_interval <- interval_summary(simulated_mean)
    q95_interval <- interval_summary(simulated_q95)
    maximum_interval <- interval_summary(simulated_maximum)
    
    observed_zero <- mean(observed == 0)
    observed_mean <- mean(observed)
    observed_q95 <- unname(quantile(observed, 0.95))
    observed_maximum <- max(observed)
    
    data.frame(
      model = model_name,
      species = colnames(Y_observed)[j],
      n = length(observed),
      posterior_predictive_draws = ncol(simulated),
      observed_zero_proportion = observed_zero,
      predicted_zero_q025 = zero_interval["q025"],
      predicted_zero_median = zero_interval["median"],
      predicted_zero_q975 = zero_interval["q975"],
      zero_covered_95 = observed_zero >= zero_interval["q025"] &&
        observed_zero <= zero_interval["q975"],
      zero_ppc_p = ppc_p_two_sided(simulated_zero, observed_zero),
      observed_mean = observed_mean,
      predicted_mean_q025 = mean_interval["q025"],
      predicted_mean_median = mean_interval["median"],
      predicted_mean_q975 = mean_interval["q975"],
      mean_covered_95 = observed_mean >= mean_interval["q025"] &&
        observed_mean <= mean_interval["q975"],
      mean_ppc_p = ppc_p_two_sided(simulated_mean, observed_mean),
      observed_q95 = observed_q95,
      predicted_q95_q025 = q95_interval["q025"],
      predicted_q95_median = q95_interval["median"],
      predicted_q95_q975 = q95_interval["q975"],
      q95_covered_95 = observed_q95 >= q95_interval["q025"] &&
        observed_q95 <= q95_interval["q975"],
      q95_ppc_p = ppc_p_two_sided(simulated_q95, observed_q95),
      observed_maximum = observed_maximum,
      predicted_maximum_q025 = maximum_interval["q025"],
      predicted_maximum_median = maximum_interval["median"],
      predicted_maximum_q975 = maximum_interval["q975"],
      maximum_covered_95 = observed_maximum >= maximum_interval["q025"] &&
        observed_maximum <= maximum_interval["q975"],
      maximum_ppc_p = ppc_p_two_sided(simulated_maximum, observed_maximum),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  })
  
  bind_rows(rows) %>%
    mutate(
      ppc_status = ifelse(
        zero_covered_95 & mean_covered_95 & q95_covered_95 & maximum_covered_95,
        "OK",
        "REQUIRES_REVIEW"
      )
    )
}

fit_hmsc_model <- function(
    model_name,
    variables,
    sample_ids,
    response_matrix = Y_annual_all,
    offset_matrix = Loff_annual_all,
    samples,
    transient,
    thin,
    chains,
    parallel,
    cv_specs = list(),
    calculate_vp = FALSE,
    save_fitted = FALSE,
    save_convergence = FALSE
) {
  # Vaste on vuotuinen kokonaislukumäärä. Pyyntiponnistus huomioidaan
  # Loff-offsetilla; lentoviikko- tai spline-termejä ei käytetä.
  variables <- unique(variables)
  variables <- intersect(variables, names(X_sample))
  
  metadata_model <- sample_metadata %>%
    filter(sample_id %in% sample_ids) %>%
    arrange(match(sample_id, sample_ids))
  
  X_raw <- X_sample %>%
    filter(sample_id %in% sample_ids) %>%
    arrange(match(sample_id, sample_ids)) %>%
    select(sample_id, all_of(variables))
  
  if (!identical(X_raw$sample_id, metadata_model$sample_id)) {
    stop("X- ja metadata-rivien järjestys ei täsmää mallissa: ", model_name)
  }
  
  baseline_variables <- character(0)
  model_variables <- variables
  
  finite_rows <- if (length(model_variables) == 0L) {
    rep(TRUE, nrow(X_raw))
  } else {
    apply(
      as.matrix(X_raw[, model_variables, drop = FALSE]),
      1,
      function(z) all(is.finite(z))
    )
  }
  
  X_raw <- X_raw[finite_rows, , drop = FALSE]
  metadata_model <- metadata_model[finite_rows, , drop = FALSE]
  
  if (nrow(X_raw) < 20) stop("Malliin jäi alle 20 havaintoa.")
  
  zv <- remove_zero_variance_names(X_raw, model_variables)
  variables_kept <- zv$kept
  
  if (length(variables_kept) == 0L) {
    # Hmsc tarvitsee XData-objektin myös vakiotermimallille. Apusarake ei
    # sisälly kaavaan eikä siten tule malliparametriksi.
    X_scaled <- data.frame(intercept_helper = rep(0, nrow(X_raw)))
    X_formula <- ~ 1
  } else {
    X_model <- X_raw[, variables_kept, drop = FALSE]
    X_scaled <- as.data.frame(scale(X_model))
    X_formula <- reformulate(variables_kept)
    if (any(!is.finite(as.matrix(X_scaled)))) {
      stop("Standardoinnin jälkeen jäi NA/Inf-arvoja.")
    }
  }
  
  rownames(X_scaled) <- X_raw$sample_id
  
  Y_model <- response_matrix[
    X_raw$sample_id,
    ,
    drop = FALSE
  ]
  
  Loff_model <- offset_matrix[
    X_raw$sample_id,
    colnames(Y_model),
    drop = FALSE
  ]
  
  if (!identical(dim(Y_model), dim(Loff_model))) {
    stop("Y- ja Loff-matriisien dimensiot eroavat mallissa: ", model_name)
  }
  if (!identical(rownames(Y_model), rownames(Loff_model)) ||
      !identical(colnames(Y_model), colnames(Loff_model))) {
    stop("Y- ja Loff-matriisien nimet tai rivijärjestys eroavat mallissa: ", model_name)
  }
  if (any(!is.finite(Loff_model))) {
    stop("Loff sisältää NA/Inf-arvoja mallissa: ", model_name)
  }
  finite_y <- is.finite(Y_model)
  if (any(Y_model[finite_y] < 0)) {
    stop("Count-vaste sisältää negatiivisia arvoja mallissa: ", model_name)
  }
  if (any(abs(Y_model[finite_y] - round(Y_model[finite_y])) > 1e-8)) {
    stop("Lognormal Poisson -vaste sisältää ei-kokonaislukuarvoja mallissa: ", model_name)
  }
  Y_model[finite_y] <- round(Y_model[finite_y])
  
  # Sivusto kuvaa pysyviä paikkojen välisiä eroja ja vuosi kaikkia saman
  # vuoden paikkahavaintoja yhdistävää vuosittaista vaihtelua.
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
    # X_model standardoidaan yllä eksplisiittisesti. Estetään Hmsc:aa
    # standardoimasta samoja muuttujia toistamiseen.
    XScale = FALSE,
    # Lukumäärävastetta ei standardoida.
    YScale = FALSE,
    XFormula = X_formula,
    studyDesign = studyDesign,
    ranLevels = list(
      site = HmscRandomLevel(units = levels(studyDesign$site)),
      year = HmscRandomLevel(units = levels(studyDesign$year))
    )
  )
  
  if (run_quick_test) {
    quick_model <- sampleMcmc(
      model_unfitted,
      samples = quick_samples,
      transient = quick_transient,
      thin = quick_thin,
      nChains = quick_chains,
      verbose = 0
    )
    rm(quick_model)
    gc()
  }
  
  cat(
    "\n", model_name,
    ": n=", nrow(Y_model),
    ", predictors=", ncol(X_scaled),
    ", samples=", samples,
    ", chains=", chains, "\n",
    sep = ""
  )
  
  model_fitted <- sampleMcmc(
    model_unfitted,
    samples = samples,
    transient = transient,
    thin = thin,
    nChains = chains,
    nParallel = parallel,
    verbose = 100
  )
  
  model_checkpoint_file <- file.path(
    modelDir,
    paste0(model_name, "_Hmsc_model.rds")
  )
  if (save_fitted) {
    # Tallenna kallis posteriori heti. Myöhempi metriikka-, beta- tai
    # variance partitioning -virhe ei tällöin hukkaa onnistunutta sovitusta.
    saveRDS(model_fitted, model_checkpoint_file)
    cat("Hmsc-sovite tallennettu:", model_checkpoint_file, "\n")
  }
  
  all_metrics <- list()
  
  prediction_thin <- prediction_thin_for_model(
    model_fitted,
    max_draws = max_prediction_draws
  )
  cat(
    "Ennusteiden posterioriohennus:", prediction_thin,
    "(enintään noin", max_prediction_draws, "arvontaa)\n"
  )
  
  pred_explanatory <- computePredictedValues(
    model_fitted,
    start = 1,
    thin = prediction_thin,
    expected = FALSE
  )
  
  MF_explanatory <- evaluateModelFit(
    hM = model_fitted,
    predY = pred_explanatory
  )
  
  all_metrics[["explanatory"]] <- metric_table(
    model_name,
    colnames(Y_model),
    MF_explanatory,
    "explanatory"
  )
  
  ppc_table <- NULL
  ppc_error <- NA_character_
  if (save_fitted) {
    ppc_table <- tryCatch(
      posterior_predictive_check(
        predY = pred_explanatory,
        Y_observed = Y_model,
        model_name = model_name
      ),
      error = function(e) {
        ppc_error <<- conditionMessage(e)
        warning("Posterior predictive -tarkistus epäonnistui: ", ppc_error)
        NULL
      }
    )
    if (!is.null(ppc_table)) {
      write.table(
        ppc_table,
        file = file.path(
          modelDir,
          paste0(model_name, "_posterior_predictive_check.txt")
        ),
        sep = ";",
        row.names = FALSE
      )
      cat("\nPosterior predictive -tarkistus:\n")
      print(ppc_table, row.names = FALSE)
    }
  }
  
  cv_partitions <- list()
  
  if (length(cv_specs) > 0) {
    for (cv_name in names(cv_specs)) {
      spec <- cv_specs[[cv_name]]
      
      partition <- make_grouped_folds(
        metadata = metadata_model,
        block = spec$block,
        nfolds = spec$nfolds,
        seed = spec$seed
      )
      
      cv_partitions[[cv_name]] <- partition
      
      pred_cv <- computePredictedValues(
        model_fitted,
        partition = partition,
        start = 1,
        thin = prediction_thin,
        expected = FALSE,
        nParallel = parallel,
        verbose = 100
      )
      
      MF_cv <- evaluateModelFit(
        hM = model_fitted,
        predY = pred_cv
      )
      
      cat("\n========================\n")
      cat("CV diagnostics\n")
      cat("Model:", model_name, "\n")
      cat("Evaluation:", cv_name, "\n")
      cat("Species:", paste(colnames(Y_model), collapse = ", "), "\n")
      cat("Fold counts:",
          paste(names(table(partition)), as.integer(table(partition)),
                sep = "=", collapse = ", "), "\n")
      cat("========================\n")
      
      print(MF_cv)
      str(MF_cv)
      print(names(MF_cv))
      
      if (is.null(MF_cv$SR2)) {
        stop("CV-arvioinnista puuttuu SR2: ", model_name, " / ", cv_name)
      }
      
      if (length(MF_cv$SR2) != ncol(Y_model)) {
        stop(
          "CV-SR2-arvojen määrä ei vastaa lajimäärää mallissa ",
          model_name, " / ", cv_name,
          ": SR2-arvoja=", length(MF_cv$SR2),
          ", lajeja=", ncol(Y_model)
        )
      }
      all_metrics[[cv_name]] <- metric_table(
        model_name,
        colnames(Y_model),
        MF_cv,
        cv_name
      )
      
      rm(pred_cv)
      gc()
    }
  }
  
  metrics <- bind_rows(all_metrics)
  
  required_metric_columns <- c("model", "evaluation", "species", "RMSE", "SR2")
  missing_metric_columns <- setdiff(required_metric_columns, names(metrics))
  
  if (length(missing_metric_columns) > 0) {
    stop(
      "Yhdistetystä metriikkataulukosta puuttuvat sarakkeet: ",
      paste(missing_metric_columns, collapse = ", ")
    )
  }
  
  duplicate_metric_key <- duplicated(metrics[c("model", "evaluation", "species")])
  
  if (any(duplicate_metric_key)) {
    duplicate_rows <- metrics[
      duplicate_metric_key,
      c("model", "evaluation", "species"),
      drop = FALSE
    ]
    stop(
      "Yhdistetyssä metriikkataulukossa on duplikaattiavaimia:\n",
      paste(capture.output(print(duplicate_rows)), collapse = "\n")
    )
  }
  
  expected_evaluations <- c("explanatory", names(cv_specs))
  missing_evaluations <- setdiff(expected_evaluations, unique(metrics$evaluation))
  
  if (length(missing_evaluations) > 0) {
    stop(
      "Mallilta ", model_name,
      " puuttuvat arvioinnit: ",
      paste(missing_evaluations, collapse = ", ")
    )
  }
  
  evaluation_counts <- metrics %>%
    count(.data$evaluation, name = "n_rows")
  
  if (any(evaluation_counts$n_rows != ncol(Y_model))) {
    stop(
      "Mallin ", model_name,
      " arvioinneissa ei ole täsmälleen yhtä riviä lajia kohti:\n",
      paste(capture.output(print(evaluation_counts)), collapse = "\n")
    )
  }
  
  cat("\n--- Combined metrics diagnostics ---\n")
  cat("Model:", model_name, "\n")
  print(evaluation_counts)
  print(metrics)
  
  summary_table <- metric_summary(metrics)
  
  beta_table <- NULL
  beta_error <- NA_character_
  if (save_fitted) {
    beta_table <- tryCatch(
      beta_table_from_model(model_fitted, model_name),
      error = function(e) {
        beta_error <<- conditionMessage(e)
        warning("Beta-taulukon muodostaminen epäonnistui: ", beta_error)
        NULL
      }
    )
    if (!is.null(beta_table)) {
      write.table(
        beta_table,
        file = file.path(modelDir, paste0(model_name, "_beta_posterior.txt")),
        sep = ";",
        row.names = FALSE
      )
      write.table(
        beta_table %>% filter(supported, predictor != "(Intercept)"),
        file = file.path(modelDir, paste0(model_name, "_supported_effects_95.txt")),
        sep = ";",
        row.names = FALSE
      )
    }
  }
  
  VP <- NULL
  VP_table <- NULL
  VP_table_long <- NULL
  vp_mapping <- NULL
  vp_error <- NA_character_
  
  if (calculate_vp) {
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
      warning("Variance partitioning epäonnistui: ", vp_error)
      NULL
    })
    
    if (!is.null(vp_result)) {
      VP <- vp_result$VP
      VP_table <- vp_result$wide
      VP_table_long <- vp_result$long
      
      write.table(
        VP_table,
        file = file.path(
          modelDir,
          paste0(model_name, "_variance_partitioning.txt")
        ),
        sep = ";",
        row.names = FALSE
      )
      write.table(
        VP_table_long,
        file = file.path(
          modelDir,
          paste0(model_name, "_variance_partitioning_long.txt")
        ),
        sep = ";",
        row.names = FALSE
      )
      
      pdf(
        file.path(
          modelDir,
          paste0(model_name, "_variance_partitioning.pdf")
        ),
        width = 12,
        height = max(7, 0.35 * ncol(Y_model))
      )
      plotVariancePartitioning(model_fitted, VP = VP)
      dev.off()
    }
    
    write.table(
      vp_mapping$check,
      file = file.path(
        modelDir,
        paste0(model_name, "_variance_partitioning_groups.txt")
      ),
      sep = ";",
      row.names = FALSE
    )
  }
  
  write.table(
    metrics,
    file = file.path(
      modelDir,
      paste0(model_name, "_performance_by_species.txt")
    ),
    sep = ";",
    row.names = FALSE
  )
  
  write.table(
    summary_table,
    file = file.path(
      modelDir,
      paste0(model_name, "_performance_summary.txt")
    ),
    sep = ";",
    row.names = FALSE
  )
  
  if (save_convergence) {
    save_convergence_diagnostics(model_fitted, model_name)
  }
  
  fitted_file <- file.path(
    modelDir,
    paste0(model_name, "_fitted.RData")
  )
  
  if (save_fitted) {
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
      beta_table,
      beta_error,
      ppc_table,
      ppc_error,
      cv_partitions,
      VP,
      VP_table,
      VP_table_long,
      vp_mapping,
      vp_error,
      file = fitted_file
    )
  }
  
  list(
    status = "fitted",
    model_name = model_name,
    variables = setdiff(variables_kept, baseline_variables),
    sample_ids = X_raw$sample_id,
    n_samples = nrow(Y_model),
    metrics = metrics,
    summary = summary_table,
    beta_table = beta_table,
    posterior_predictive_check = ppc_table,
    variance_partitioning = VP_table_long,
    model_checkpoint_file = model_checkpoint_file,
    fitted_file = fitted_file
  )
}

get_metrics <- function(result, evaluation) {
  if (is.null(result$metrics) || !is.data.frame(result$metrics)) {
    stop(
      "Mallin ", result$model_name,
      " metrics-objekti puuttuu tai ei ole data.frame."
    )
  }
  
  required <- c("model", "evaluation", "species", "RMSE", "SR2")
  missing_columns <- setdiff(required, names(result$metrics))
  
  if (length(missing_columns) > 0) {
    stop(
      "Mallin ", result$model_name,
      " metriikkataulukosta puuttuvat sarakkeet: ",
      paste(missing_columns, collapse = ", ")
    )
  }
  
  available_evaluations <- unique(as.character(result$metrics$evaluation))
  
  cat("\n--- get_metrics diagnostics ---\n")
  cat("Model:", result$model_name, "\n")
  cat("Requested evaluation:", evaluation, "\n")
  cat("Available evaluations:",
      paste(available_evaluations, collapse = ", "), "\n")
  
  # TÄRKEÄ KORJAUS:
  # dplyr-data-maskissa paljas 'evaluation' viittasi sarakkeeseen itseensä.
  # .env$evaluation pakottaa käyttämään funktion argumenttia.
  out <- result$metrics %>%
    filter(.data$evaluation == .env$evaluation)
  
  cat("Rows after filtering:", nrow(out), "\n")
  print(out)
  
  if (nrow(out) == 0) {
    stop(
      "Mallille ", result$model_name,
      " ei löytynyt arviointia: ", evaluation,
      ". Saatavilla: ", paste(available_evaluations, collapse = ", ")
    )
  }
  
  expected_species <- unique(as.character(result$metrics$species))
  
  if (nrow(out) != length(expected_species)) {
    stop(
      "Mallin ", result$model_name,
      " arvioinnissa ", evaluation,
      " rivejä on ", nrow(out),
      ", mutta yksikäsitteisiä lajeja koko metriikkataulukossa on ",
      length(expected_species), "."
    )
  }
  
  duplicate_key <- duplicated(out[c("model", "evaluation", "species")])
  
  if (any(duplicate_key)) {
    duplicate_rows <- out[duplicate_key, c("model", "evaluation", "species"), drop = FALSE]
    stop(
      "Sama model-evaluation-species-yhdistelmä esiintyy useita kertoja:\n",
      paste(capture.output(print(duplicate_rows)), collapse = "\n")
    )
  }
  
  duplicate_species <- unique(out$species[duplicated(out$species)])
  
  if (length(duplicate_species) > 0) {
    stop(
      "Mallin ", result$model_name,
      " arvioinnissa ", evaluation,
      " sama laji esiintyy useita kertoja: ",
      paste(duplicate_species, collapse = ", ")
    )
  }
  
  if (anyNA(out$species) || any(trimws(out$species) == "")) {
    stop(
      "Mallin ", result$model_name,
      " arvioinnissa ", evaluation,
      " on puuttuva tai tyhjä lajinimi."
    )
  }
  
  if (any(!is.finite(out$SR2))) {
    stop(
      "Mallin ", result$model_name,
      " arvioinnissa ", evaluation,
      " on puuttuva SR2. Lognormal Poisson -Hmsc-mallin pitää palauttaa MF$SR2 ",
      "jokaiselle lajille; valintaa ei jatketa NA-arvoilla."
    )
  }
  
  out
}

compare_fitted_results <- function(
    reference_result,
    candidate_result,
    evaluation
) {
  reference <- get_metrics(reference_result, evaluation)
  candidate <- get_metrics(candidate_result, evaluation)
  delta <- species_delta_table(reference, candidate)
  list(
    delta = delta,
    summary = summarize_species_deltas(delta)
  )
}

fit_pair_predictive <- function(
    prefix,
    reference_variables,
    candidate_variables,
    matched_ids,
    samples,
    transient,
    thin,
    chains,
    parallel
) {
  reference <- fit_hmsc_model(
    model_name = paste0(prefix, "_REF"),
    variables = reference_variables,
    sample_ids = matched_ids,
    samples = samples,
    transient = transient,
    thin = thin,
    chains = chains,
    parallel = parallel,
    cv_specs = selection_cv_specs
  )
  
  candidate <- fit_hmsc_model(
    model_name = paste0(prefix, "_CAND"),
    variables = candidate_variables,
    sample_ids = matched_ids,
    samples = samples,
    transient = transient,
    thin = thin,
    chains = chains,
    parallel = parallel,
    cv_specs = selection_cv_specs
  )
  
  comparison <- compare_fitted_results(
    reference,
    candidate,
    selection_primary_evaluation
  )
  
  list(
    reference = reference,
    candidate = candidate,
    comparison = comparison
  )
}

candidate_sample_ids <- function(variables) {
  needed <- unique(variables)
  rows <- if (length(needed) == 0L) {
    rep(TRUE, nrow(X_sample))
  } else {
    complete.cases(X_sample[, needed, drop = FALSE])
  }
  X_sample$sample_id[rows]
}

evaluate_group_candidates <- function(
    step,
    selected_variables,
    remaining_groups,
    available_groups,
    phase
) {
  rows <- list()
  
  correlation_limit_phase <- if (grepl("^WEATHER", phase)) {
    weather_correlation_limit
  } else {
    environment_correlation_limit
  }
  
  for (group_name in remaining_groups) {
    raw_variables <- unique(c(
      selected_variables,
      available_groups[[group_name]]
    ))
    
    # Korrelaatiokarsinta käyttää pairwise-havaintoja koko X-aineistosta.
    # Complete-case-rivit määritetään vasta karsinnan jälkeen, jotta jo
    # poistettu, huonosti kattava muuttuja ei pienennä mallia tarpeettomasti.
    corr <- remove_high_correlations(
      X_sample,
      raw_variables,
      protected_variables = selected_variables,
      limit = correlation_limit_phase
    )
    
    candidate_variables <- corr$kept
    reference_variables <- intersect(
      selected_variables,
      candidate_variables
    )
    ids <- candidate_sample_ids(candidate_variables)
    
    if (length(ids) < min_required_samples) {
      rows[[group_name]] <- data.frame(
        step = step,
        candidate_group = group_name,
        n_samples = length(ids),
        mean_delta_predictive_SR2 = NA_real_,
        median_delta_predictive_SR2 = NA_real_,
        min_delta_predictive_SR2 = NA_real_,
        max_delta_predictive_SR2 = NA_real_,
        n_species_nonnegative = NA_integer_,
        community_support = FALSE,
        strong_species_support = FALSE,
        accepted = FALSE,
        variables_after_correlation = paste(candidate_variables, collapse = "|"),
        removed_by_correlation = paste(corr$removed, collapse = "|"),
        status = "too_many_missing"
      )
      next
    }
    
    pair <- tryCatch(
      fit_pair_predictive(
        prefix = paste0(
          phase, "_PREDICTIVE_", sprintf("%02d", step), "_",
          safe_name(group_name)
        ),
        reference_variables = reference_variables,
        candidate_variables = candidate_variables,
        matched_ids = ids,
        samples = selection_samples,
        transient = selection_transient,
        thin = selection_thin,
        chains = selection_chains,
        parallel = selection_parallel
      ),
      error = function(e) {
        list(status = "failed", error = conditionMessage(e))
      }
    )
    
    if (!is.null(pair$status) && pair$status == "failed") {
      rows[[group_name]] <- data.frame(
        step = step,
        candidate_group = group_name,
        n_samples = length(ids),
        mean_delta_predictive_SR2 = NA_real_,
        median_delta_predictive_SR2 = NA_real_,
        min_delta_predictive_SR2 = NA_real_,
        max_delta_predictive_SR2 = NA_real_,
        n_species_nonnegative = NA_integer_,
        community_support = FALSE,
        strong_species_support = FALSE,
        accepted = FALSE,
        variables_after_correlation = paste(candidate_variables, collapse = "|"),
        removed_by_correlation = paste(corr$removed, collapse = "|"),
        status = paste0("failed: ", pair$error)
      )
      next
    }
    
    ds <- pair$comparison$summary
    decision <- accept_addition(ds)
    
    row <- data.frame(
      step = step,
      candidate_group = group_name,
      n_samples = length(ids),
      mean_delta_predictive_SR2 = ds$mean,
      median_delta_predictive_SR2 = ds$median,
      min_delta_predictive_SR2 = ds$minimum,
      max_delta_predictive_SR2 = ds$maximum,
      n_species_nonnegative = ds$n_nonnegative,
      community_support = decision$community_support,
      strong_species_support = decision$strong_species_support,
      accepted = decision$accepted,
      variables_after_correlation = paste(candidate_variables, collapse = "|"),
      removed_by_correlation = paste(corr$removed, collapse = "|"),
      status = "fitted"
    )
    
    rows[[group_name]] <- bind_cols(
      row,
      species_delta_wide(pair$comparison$delta)
    )
    
    write.table(
      bind_rows(rows),
      file = file.path(
        modelDir,
        paste0(
          phase, "_predictive_step_", sprintf("%02d", step), ".txt"
        )
      ),
      sep = ";",
      row.names = FALSE
    )
  }
  
  bind_rows(rows) %>%
    arrange(
      desc(accepted),
      desc(mean_delta_predictive_SR2),
      desc(max_delta_predictive_SR2),
      desc(n_samples)
    )
}

confirm_predictive_candidate <- function(
    best_row,
    selected_variables,
    phase,
    step
) {
  group_name <- best_row$candidate_group
  candidate_variables <- strsplit(
    best_row$variables_after_correlation,
    "\\|"
  )[[1]]
  reference_variables <- intersect(selected_variables, candidate_variables)
  ids <- candidate_sample_ids(candidate_variables)
  
  pair <- fit_pair_predictive(
    prefix = paste0(
      phase, "_CONFIRM_", sprintf("%02d", step), "_", safe_name(group_name)
    ),
    reference_variables = reference_variables,
    candidate_variables = candidate_variables,
    matched_ids = ids,
    samples = confirm_samples,
    transient = confirm_transient,
    thin = confirm_thin,
    chains = confirm_chains,
    parallel = confirm_parallel
  )
  
  ds <- pair$comparison$summary
  decision <- accept_addition(ds)
  
  bind_cols(
    data.frame(
      step = step,
      candidate_group = group_name,
      n_samples = length(ids),
      mean_delta_predictive_SR2 = ds$mean,
      median_delta_predictive_SR2 = ds$median,
      min_delta_predictive_SR2 = ds$minimum,
      max_delta_predictive_SR2 = ds$maximum,
      n_species_nonnegative = ds$n_nonnegative,
      community_support = decision$community_support,
      strong_species_support = decision$strong_species_support,
      accepted = decision$accepted,
      variables_after_correlation = best_row$variables_after_correlation,
      removed_by_correlation = best_row$removed_by_correlation,
      status = "confirmed"
    ),
    species_delta_wide(pair$comparison$delta)
  )
}

forward_select_groups <- function(
    groups,
    phase,
    max_groups,
    base_variables = character(0)
) {
  available_groups <- lapply(
    groups,
    function(x) intersect(x, names(X_sample))
  )
  available_groups <- available_groups[lengths(available_groups) > 0]
  
  selected_groups <- character(0)
  selected_variables <- unique(base_variables)
  remaining_groups <- names(available_groups)
  
  predictive_log <- list()
  selected_path <- list()
  
  for (step in seq_len(max_groups)) {
    if (length(remaining_groups) == 0) break
    
    comparison_table <- evaluate_group_candidates(
      step,
      selected_variables,
      remaining_groups,
      available_groups,
      phase
    )
    predictive_log[[paste0("step_", step)]] <- comparison_table
    
    accepted <- comparison_table %>%
      filter(
        accepted,
        is.finite(mean_delta_predictive_SR2)
      )
    
    if (nrow(accepted) == 0) break
    
    confirmed_best <- NULL
    
    # Jos paras ehdokas ei läpäise pidempää ajoa, kokeillaan
    # seuraavaa hyväksyttyä ehdokasta eikä valita sitä automaattisesti.
    for (candidate_index in seq_len(nrow(accepted))) {
      candidate_row <- accepted[candidate_index, , drop = FALSE]
      
      confirmed <- tryCatch(
        confirm_predictive_candidate(
          candidate_row,
          selected_variables,
          phase,
          step
        ),
        error = function(e) {
          message(
            "Varmistus epäonnistui ryhmälle ",
            candidate_row$candidate_group,
            ": ",
            conditionMessage(e)
          )
          NULL
        }
      )
      
      if (!is.null(confirmed) && isTRUE(confirmed$accepted[1])) {
        confirmed_best <- confirmed
        break
      }
    }
    
    if (is.null(confirmed_best)) break
    
    best <- confirmed_best
    selected_group <- best$candidate_group
    selected_groups <- c(selected_groups, selected_group)
    selected_variables <- strsplit(
      best$variables_after_correlation,
      "\\|"
    )[[1]]
    
    remaining_groups <- setdiff(remaining_groups, selected_group)
    selected_path[[paste0("step_", step)]] <- best
    
    save(
      selected_groups,
      selected_variables,
      remaining_groups,
      predictive_log,
      selected_path,
      file = file.path(
        modelDir,
        paste0(phase, "_forward_progress.RData")
      )
    )
    
    write.table(
      bind_rows(selected_path),
      file = file.path(
        modelDir,
        paste0(phase, "_selected_path.txt")
      ),
      sep = ";",
      row.names = FALSE
    )
  }
  
  list(
    selected_groups = selected_groups,
    selected_variables = selected_variables,
    available_groups = available_groups,
    predictive_log = predictive_log,
    selected_path = selected_path
  )
}

backward_select_variables <- function(
    initial_variables,
    selected_group_names,
    all_groups,
    phase
) {
  current_variables <- initial_variables
  selected_group_definitions <- all_groups[selected_group_names]
  log <- list()
  
  for (step in seq_len(max(0, length(initial_variables) - 1))) {
    rows <- list()
    
    for (variable_to_remove in current_variables) {
      guard <- check_group_guard(
        current_variables,
        variable_to_remove,
        selected_group_definitions
      )
      
      reduced_variables <- setdiff(
        current_variables,
        variable_to_remove
      )
      
      ids <- candidate_sample_ids(current_variables)
      
      pair <- tryCatch(
        fit_pair_predictive(
          prefix = paste0(
            phase, "_BACKWARD_", sprintf("%02d", step), "_DROP_",
            safe_name(variable_to_remove)
          ),
          reference_variables = current_variables,
          candidate_variables = reduced_variables,
          matched_ids = ids,
          samples = selection_samples,
          transient = selection_transient,
          thin = selection_thin,
          chains = selection_chains,
          parallel = selection_parallel
        ),
        error = function(e) {
          list(status = "failed", error = conditionMessage(e))
        }
      )
      
      if (!is.null(pair$status) && pair$status == "failed") {
        rows[[variable_to_remove]] <- data.frame(
          step = step,
          removed_variable = variable_to_remove,
          mean_delta_predictive_SR2 = NA_real_,
          min_delta_predictive_SR2 = NA_real_,
          n_species_nonnegative = NA_integer_,
          group_guard_allows = guard$allowed,
          protected_groups = paste(
            guard$protected_groups,
            collapse = "|"
          ),
          removable = FALSE,
          status = paste0("failed: ", pair$error)
        )
        next
      }
      
      ds <- pair$comparison$summary
      removable <- guard$allowed && accept_removal(ds)
      
      row <- data.frame(
        step = step,
        removed_variable = variable_to_remove,
        mean_delta_predictive_SR2 = ds$mean,
        median_delta_predictive_SR2 = ds$median,
        min_delta_predictive_SR2 = ds$minimum,
        max_delta_predictive_SR2 = ds$maximum,
        n_species_nonnegative = ds$n_nonnegative,
        group_guard_allows = guard$allowed,
        protected_groups = paste(
          guard$protected_groups,
          collapse = "|"
        ),
        removable = removable,
        status = "fitted"
      )
      
      rows[[variable_to_remove]] <- bind_cols(
        row,
        species_delta_wide(pair$comparison$delta)
      )
      
      write.table(
        bind_rows(rows),
        file = file.path(
          modelDir,
          paste0(
            phase, "_backward_step_", sprintf("%02d", step), ".txt"
          )
        ),
        sep = ";",
        row.names = FALSE
      )
    }
    
    table <- bind_rows(rows) %>%
      arrange(desc(removable), desc(mean_delta_predictive_SR2))
    
    log[[paste0("step_", step)]] <- table
    removable_table <- table %>%
      filter(removable) %>%
      arrange(desc(mean_delta_predictive_SR2))
    
    if (nrow(removable_table) == 0) break
    
    # Poistetaan suoraan alustavan backward-vertailun paras muuttuja.
    # Erillistä pitkää vahvistusajoa ei tehdä jokaiselle poistolle.
    best_drop <- removable_table$removed_variable[1]
    
    current_variables <- setdiff(
      current_variables,
      best_drop
    )
    
    message(
      "Backward-karsinta, vaihe ", phase,
      ", askel ", step,
      ": poistettiin ", best_drop,
      " (mean delta SR2 = ",
      round(removable_table$mean_delta_predictive_SR2[1], 6),
      ")."
    )
    
    save(
      current_variables,
      log,
      file = file.path(
        modelDir,
        paste0(phase, "_backward_progress.RData")
      )
    )
  }
  
  list(
    selected_variables = current_variables,
    log = log
  )
}

select_one_buffer_per_environment_group <- function(
    groups_buffered,
    candidate_table,
    base_variables
) {
  comparison_rows <- list()
  winner_rows <- list()
  selected_groups <- list()
  
  ecological_groups <- unique(candidate_table$ecological_group)
  
  for (ecological_group in ecological_groups) {
    candidate_names <- candidate_table %>%
      filter(.data$ecological_group == .env$ecological_group) %>%
      arrange(buffer_m) %>%
      pull(candidate_group)
    candidate_names <- intersect(candidate_names, names(groups_buffered))
    if (length(candidate_names) == 0L) next
    
    # Kaikki saman ekologisen ryhmän bufferit arvioidaan samoilla riveillä.
    all_buffer_variables <- unique(unlist(
      groups_buffered[candidate_names],
      use.names = FALSE
    ))
    common_ids <- candidate_sample_ids(unique(c(
      base_variables,
      all_buffer_variables
    )))
    
    if (length(common_ids) < min_required_samples) {
      comparison_rows[[ecological_group]] <- bind_rows(lapply(
        candidate_names,
        function(candidate_name) {
          buffer_value <- candidate_table$buffer_m[
            match(candidate_name, candidate_table$candidate_group)
          ]
          data.frame(
            ecological_group = ecological_group,
            candidate_group = candidate_name,
            buffer_m = buffer_value,
            n_samples = length(common_ids),
            mean_delta_predictive_SR2 = NA_real_,
            median_delta_predictive_SR2 = NA_real_,
            min_delta_predictive_SR2 = NA_real_,
            max_delta_predictive_SR2 = NA_real_,
            n_species_nonnegative = NA_integer_,
            selected_buffer = FALSE,
            variables_after_correlation = NA_character_,
            removed_by_correlation = NA_character_,
            status = "insufficient_common_rows",
            stringsAsFactors = FALSE
          )
        }
      ))
      next
    }
    
    matched_data <- X_sample[
      match(common_ids, X_sample$sample_id),
      ,
      drop = FALSE
    ]
    group_rows <- list()
    
    for (candidate_name in candidate_names) {
      buffer_value <- candidate_table$buffer_m[
        match(candidate_name, candidate_table$candidate_group)
      ]
      raw_variables <- unique(c(
        base_variables,
        groups_buffered[[candidate_name]]
      ))
      corr <- remove_high_correlations(
        matched_data,
        raw_variables,
        protected_variables = base_variables,
        limit = environment_correlation_limit
      )
      candidate_variables <- corr$kept
      reference_variables <- intersect(base_variables, candidate_variables)
      new_environment_variables <- setdiff(
        candidate_variables,
        reference_variables
      )
      
      if (length(new_environment_variables) == 0L) {
        group_rows[[candidate_name]] <- data.frame(
          ecological_group = ecological_group,
          candidate_group = candidate_name,
          buffer_m = buffer_value,
          n_samples = length(common_ids),
          mean_delta_predictive_SR2 = NA_real_,
          median_delta_predictive_SR2 = NA_real_,
          min_delta_predictive_SR2 = NA_real_,
          max_delta_predictive_SR2 = NA_real_,
          n_species_nonnegative = NA_integer_,
          selected_buffer = FALSE,
          variables_after_correlation = "",
          removed_by_correlation = paste(corr$removed, collapse = "|"),
          status = "no_environment_variables_after_correlation",
          stringsAsFactors = FALSE
        )
        next
      }
      
      pair <- tryCatch(
        fit_pair_predictive(
          prefix = paste0(
            "BUFFER_SCALE_", safe_name(ecological_group), "_",
            safe_name(buffer_value), "m"
          ),
          reference_variables = reference_variables,
          candidate_variables = candidate_variables,
          matched_ids = common_ids,
          samples = selection_samples,
          transient = selection_transient,
          thin = selection_thin,
          chains = selection_chains,
          parallel = selection_parallel
        ),
        error = function(e) list(status = "failed", error = conditionMessage(e))
      )
      
      if (!is.null(pair$status) && identical(pair$status, "failed")) {
        group_rows[[candidate_name]] <- data.frame(
          ecological_group = ecological_group,
          candidate_group = candidate_name,
          buffer_m = buffer_value,
          n_samples = length(common_ids),
          mean_delta_predictive_SR2 = NA_real_,
          median_delta_predictive_SR2 = NA_real_,
          min_delta_predictive_SR2 = NA_real_,
          max_delta_predictive_SR2 = NA_real_,
          n_species_nonnegative = NA_integer_,
          selected_buffer = FALSE,
          variables_after_correlation = paste(
            new_environment_variables,
            collapse = "|"
          ),
          removed_by_correlation = paste(corr$removed, collapse = "|"),
          status = paste0("failed: ", pair$error),
          stringsAsFactors = FALSE
        )
        next
      }
      
      ds <- pair$comparison$summary
      row <- data.frame(
        ecological_group = ecological_group,
        candidate_group = candidate_name,
        buffer_m = buffer_value,
        n_samples = length(common_ids),
        mean_delta_predictive_SR2 = ds$mean,
        median_delta_predictive_SR2 = ds$median,
        min_delta_predictive_SR2 = ds$minimum,
        max_delta_predictive_SR2 = ds$maximum,
        n_species_nonnegative = ds$n_nonnegative,
        selected_buffer = FALSE,
        variables_after_correlation = paste(
          new_environment_variables,
          collapse = "|"
        ),
        removed_by_correlation = paste(corr$removed, collapse = "|"),
        status = "fitted",
        stringsAsFactors = FALSE
      )
      group_rows[[candidate_name]] <- bind_cols(
        row,
        species_delta_wide(pair$comparison$delta)
      )
    }
    
    group_table <- bind_rows(group_rows)
    valid <- group_table %>%
      filter(status == "fitted", is.finite(mean_delta_predictive_SR2)) %>%
      arrange(
        desc(mean_delta_predictive_SR2),
        desc(median_delta_predictive_SR2),
        desc(max_delta_predictive_SR2),
        buffer_m
      )
    
    if (nrow(valid) > 0L) {
      winner_name <- valid$candidate_group[1]
      group_table$selected_buffer[
        group_table$candidate_group == winner_name
      ] <- TRUE
      winner <- group_table[
        group_table$candidate_group == winner_name,
        ,
        drop = FALSE
      ]
      winner_rows[[ecological_group]] <- winner
      selected_groups[[ecological_group]] <- strsplit(
        winner$variables_after_correlation[1],
        "\\|"
      )[[1]]
    }
    
    comparison_rows[[ecological_group]] <- group_table
  }
  
  list(
    comparisons = bind_rows(comparison_rows),
    winners = bind_rows(winner_rows),
    groups = selected_groups
  )
}

#========================================================

# 4. LATAA PÄÄANALYYSIN VALMIIT OBJEKTIT
#========================================================

if (!file.exists(primary_rdata_file)) {
  stop("Pääanalyysin RData-tiedostoa ei löydy: ", primary_rdata_file)
}

if (!file.exists(primary_results_file)) {
  stop("Pääanalyysin RDS-koontia ei löydy: ", primary_results_file)
}

primary_env <- new.env(parent = globalenv())
loaded_objects <- load(primary_rdata_file, envir = primary_env)
PRIMARY_RESULTS <- readRDS(primary_results_file)

required_primary_objects <- c(
  "target_species",
  "Y_annual_all",
  "Loff_annual_all",
  "sample_metadata",
  "X_sample",
  "weather_groups",
  "selected_weather_groups",
  "selected_weather_variables",
  "selected_environment_variables",
  "final_result"
)

missing_primary_objects <- setdiff(required_primary_objects, loaded_objects)

if (length(missing_primary_objects) > 0L) {
  stop(
    "Pääanalyysin RData-tiedostosta puuttuvat objektit: ",
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

# Säilytä pääanalyysin valinnat ennen kuin herkkyysanalyysin valinnat
# kirjoitetaan samoihin globaalien muuttujien nimiin.
primary_selected_weather_groups <- selected_weather_groups
primary_selected_weather_variables <- selected_weather_variables
primary_selected_environment_variables <- selected_environment_variables
primary_final_result <- final_result

if (is.data.frame(primary_selected_environment_variables)) {
  primary_selected_environment_variables <- if (
    "variable" %in% names(primary_selected_environment_variables)
  ) {
    primary_selected_environment_variables$variable
  } else {
    character(0)
  }
}

primary_selected_environment_variables <- unique(
  as.character(primary_selected_environment_variables)
)
primary_selected_environment_variables <-
  primary_selected_environment_variables[
    nzchar(primary_selected_environment_variables)
  ]

#========================================================
# 5. PÄÄMALLIN PPC-PORTTI
#========================================================

primary_ppc <- PRIMARY_RESULTS$posterior_predictive_check

primary_ppc_ok <-
  !is.null(primary_ppc) &&
  is.data.frame(primary_ppc) &&
  nrow(primary_ppc) > 0L &&
  "ppc_status" %in% names(primary_ppc) &&
  all(primary_ppc$ppc_status == "OK")

if (!primary_ppc_ok) {
  ppc_message <- paste(
    "Päävuosimallin posterior predictive -tarkistus ei ole hyväksytty.",
    "Fenologiavuosien herkkyysanalyysi voidaan tehdä diagnostisena vertailuna,",
    "mutta se ei vahvista nykyistä havaintomallia."
  )
  
  if (!allow_sensitivity_despite_primary_ppc_failure) {
    stop(ppc_message)
  }
  
  warning(ppc_message)
}

analysis_status <- if (primary_ppc_ok) {
  "PRIMARY_PPC_OK"
} else {
  "DIAGNOSTIC_ONLY_PRIMARY_PPC_REQUIRES_REVIEW"
}

primary_ppc_for_export <- if (is.null(primary_ppc)) {
  data.frame(status = "primary_ppc_missing", stringsAsFactors = FALSE)
} else {
  as.data.frame(primary_ppc)
}

write.table(
  primary_ppc_for_export,
  file = file.path(modelDir, "primary_model_posterior_predictive_check.txt"),
  sep = ";",
  row.names = FALSE
)

#========================================================
# 6. TARKISTA LADATTUJEN VUOSIOBJEKTIEN RAKENNE
#========================================================

if (!identical(rownames(Y_annual_all), rownames(Loff_annual_all)) ||
    !identical(colnames(Y_annual_all), colnames(Loff_annual_all))) {
  stop("Pääanalyysistä ladattujen Y- ja Loff-matriisien nimet eivät täsmää.")
}

required_sample_columns <- c("sample_id", "site", "year")

if (!all(required_sample_columns %in% names(sample_metadata))) {
  stop(
    "sample_metadata-taulusta puuttuu: ",
    paste(setdiff(required_sample_columns, names(sample_metadata)), collapse = ", ")
  )
}

if (!"sample_id" %in% names(X_sample)) {
  stop("X_sample-taulusta puuttuu sample_id.")
}

common_order <- Reduce(
  intersect,
  list(
    rownames(Y_annual_all),
    rownames(Loff_annual_all),
    sample_metadata$sample_id,
    X_sample$sample_id
  )
)

if (length(common_order) == 0L) {
  stop("Ladatuilla vuosimallin objekteilla ei ole yhteisiä sample_id-rivejä.")
}

common_order <- rownames(Y_annual_all)[
  rownames(Y_annual_all) %in% common_order
]

Y_annual_all <- Y_annual_all[common_order, , drop = FALSE]
Loff_annual_all <- Loff_annual_all[common_order, , drop = FALSE]
sample_metadata <- sample_metadata %>%
  filter(sample_id %in% common_order) %>%
  arrange(match(sample_id, common_order))
X_sample <- X_sample %>%
  filter(sample_id %in% common_order) %>%
  arrange(match(sample_id, common_order))

if (!identical(sample_metadata$sample_id, common_order) ||
    !identical(X_sample$sample_id, common_order)) {
  stop("Vuosiaineiston rivijärjestyksen yhdenmukaistaminen epäonnistui.")
}

#========================================================
# 7. TUNNISTA YHTEISET FENOLOGIAVUODET
#========================================================

if (!phenology_reference_group %in% names(weather_groups)) {
  stop(
    "Fenologian vertailuryhmää ei löydy weather_groups-listasta: ",
    phenology_reference_group
  )
}

phenology_variables <- intersect(
  weather_groups[[phenology_reference_group]],
  names(X_sample)
)

if (length(phenology_variables) == 0L) {
  stop(
    "Fenologiaryhmästä ei löytynyt yhtään X_sample-taulussa olevaa muuttujaa: ",
    phenology_reference_group
  )
}

base_response_ok <- rowSums(is.finite(Y_annual_all)) > 0L

coverage_data <- sample_metadata %>%
  select(sample_id, site, year) %>%
  left_join(
    X_sample %>% select(sample_id, all_of(phenology_variables)),
    by = "sample_id"
  ) %>%
  mutate(
    base_response_ok = base_response_ok[
      match(sample_id, rownames(Y_annual_all))
    ],
    phenology_complete = complete.cases(
      across(all_of(phenology_variables))
    )
  ) %>%
  filter(base_response_ok)

phenology_availability_by_year <- coverage_data %>%
  group_by(year) %>%
  summarise(
    n_site_years = n(),
    n_sites = n_distinct(site),
    n_phenology_complete = sum(phenology_complete),
    phenology_coverage = n_phenology_complete / n_site_years,
    eligible_year =
      n_site_years >= minimum_site_years_per_year_for_coverage &
      phenology_coverage >= phenology_year_coverage_threshold,
    .groups = "drop"
  ) %>%
  arrange(year)

eligible_phenology_years <- phenology_availability_by_year %>%
  filter(eligible_year) %>%
  pull(year) %>%
  sort()

if (length(eligible_phenology_years) < minimum_eligible_years) {
  stop(
    "Käyttökelpoisia fenologiavuosia löytyi vain ",
    length(eligible_phenology_years),
    ". Tarvitaan vähintään ", minimum_eligible_years,
    ". Tarkista phenology_availability_by_year.txt."
  )
}

write.table(
  phenology_availability_by_year,
  file = file.path(modelDir, "phenology_availability_by_year.txt"),
  sep = ";",
  row.names = FALSE
)

write.table(
  data.frame(year = eligible_phenology_years),
  file = file.path(modelDir, "eligible_phenology_years.txt"),
  sep = ";",
  row.names = FALSE
)

cat("\nFenologiaryhmä:", phenology_reference_group, "\n")
cat("Fenologiamuuttujat:", paste(phenology_variables, collapse = ", "), "\n")
cat("Hyväksytyt vuodet:", paste(eligible_phenology_years, collapse = ", "), "\n")

#========================================================
# 8. RAJAA KAIKKI MALLIOBJEKTIT SAMAAN AJANJAKSOON
#========================================================

common_period_ids <- sample_metadata %>%
  filter(year %in% eligible_phenology_years) %>%
  pull(sample_id)

common_period_ids <- common_order[common_order %in% common_period_ids]

if (length(common_period_ids) < 100L) {
  stop(
    "Yhteisille fenologiavuosille jäi vain ",
    length(common_period_ids),
    " paikkavuotta."
  )
}

Y_annual_all <- Y_annual_all[common_period_ids, , drop = FALSE]
Loff_annual_all <- Loff_annual_all[common_period_ids, , drop = FALSE]
sample_metadata <- sample_metadata %>%
  filter(sample_id %in% common_period_ids) %>%
  arrange(match(sample_id, common_period_ids))
X_sample <- X_sample %>%
  filter(sample_id %in% common_period_ids) %>%
  arrange(match(sample_id, common_period_ids))

if (!identical(sample_metadata$sample_id, common_period_ids) ||
    !identical(X_sample$sample_id, common_period_ids)) {
  stop("Fenologiavuosille rajattujen objektien rivijärjestys ei täsmää.")
}

min_required_samples <- ceiling(nrow(X_sample) * min_sample_proportion)

common_period_summary <- data.frame(
  first_year = min(sample_metadata$year),
  last_year = max(sample_metadata$year),
  n_eligible_years = length(eligible_phenology_years),
  n_site_years_before_complete_case = nrow(X_sample),
  n_sites = n_distinct(sample_metadata$site),
  minimum_required_samples = min_required_samples,
  phenology_coverage_threshold = phenology_year_coverage_threshold,
  primary_ppc_ok = primary_ppc_ok,
  analysis_status = analysis_status,
  stringsAsFactors = FALSE
)

write.table(
  common_period_summary,
  file = file.path(modelDir, "common_phenology_period_summary.txt"),
  sep = ";",
  row.names = FALSE
)

#========================================================
# 9. VALITSE SÄÄRYHMÄT UUDELLEEN YHTEISELLÄ AJANJAKSOLLA
#========================================================

weather_forward_common_period <- forward_select_groups(
  groups = weather_groups,
  phase = "WEATHER_ANNUAL_COMMON_PHENOLOGY",
  max_groups = max_selected_weather_groups,
  base_variables = character(0)
)

sensitivity_selected_weather_groups <-
  weather_forward_common_period$selected_groups

weather_variables_before_backward <-
  weather_forward_common_period$selected_variables

if (length(sensitivity_selected_weather_groups) == 0L) {
  sensitivity_selected_weather_variables <- character(0)
  weather_backward_common_period <- list(
    selected_variables = character(0),
    log = list()
  )
} else {
  weather_backward_common_period <- backward_select_variables(
    initial_variables = weather_variables_before_backward,
    selected_group_names = sensitivity_selected_weather_groups,
    all_groups = weather_groups,
    phase = "WEATHER_ANNUAL_COMMON_PHENOLOGY"
  )
  
  sensitivity_selected_weather_variables <-
    weather_backward_common_period$selected_variables
}

write.table(
  data.frame(group = sensitivity_selected_weather_groups),
  file = file.path(
    modelDir,
    "selected_weather_groups_common_phenology_years.txt"
  ),
  sep = ";",
  row.names = FALSE
)

write.table(
  data.frame(variable = sensitivity_selected_weather_variables),
  file = file.path(
    modelDir,
    "selected_weather_variables_common_phenology_years.txt"
  ),
  sep = ";",
  row.names = FALSE
)

write_optional_table <- function(x, file) {
  x <- as.data.frame(x)
  if (ncol(x) == 0L) {
    x <- data.frame(status = "no_rows", stringsAsFactors = FALSE)
  }
  write.table(x, file = file, sep = ";", row.names = FALSE)
}

write_optional_table(
  bind_rows(weather_forward_common_period$predictive_log),
  file.path(
    modelDir,
    "weather_selection_all_common_phenology_years.txt"
  )
)

write_optional_table(
  bind_rows(weather_backward_common_period$log),
  file.path(
    modelDir,
    "weather_backward_all_common_phenology_years.txt"
  )
)

#========================================================
# 10. MUODOSTA VERTAILUKELPOINEN MATCHED-SAMPLE-AINEISTO
#========================================================

missing_primary_weather_variables <- setdiff(
  primary_selected_weather_variables,
  names(X_sample)
)

if (length(missing_primary_weather_variables) > 0L) {
  stop(
    "Päämallin valituista säämuuttujista puuttuvat X_sample-taulusta: ",
    paste(missing_primary_weather_variables, collapse = ", ")
  )
}

# Pääanalyysissä ympäristömuuttujia ei valittu. Jos myöhempi pääajo sisältää
# ympäristömuuttujia, ne lukitaan molempiin vertailumalleihin.
locked_environment_variables <- intersect(
  primary_selected_environment_variables,
  names(X_sample)
)

original_common_period_variables <- unique(c(
  primary_selected_weather_variables,
  locked_environment_variables
))

reselected_common_period_variables <- unique(c(
  sensitivity_selected_weather_variables,
  locked_environment_variables
))

matched_variable_union <- unique(c(
  original_common_period_variables,
  reselected_common_period_variables
))

matched_common_ids <- candidate_sample_ids(matched_variable_union)

if (length(matched_common_ids) < min_required_samples) {
  stop(
    "Alkuperäisen ja uudelleen valitun mallin yhteisille complete-case-riveille jäi ",
    length(matched_common_ids),
    " paikkavuotta, mutta vähimmäisraja on ", min_required_samples, "."
  )
}

# Varianssiosituksessa kaikki kummassakin mallissa esiintyvät säämuuttujat
# tunnistetaan sääryhmään ja lukitut ympäristömuuttujat ympäristöryhmiinsä.
selected_weather_variables <- unique(c(
  primary_selected_weather_variables,
  sensitivity_selected_weather_variables
))
selected_environment_variables <- locked_environment_variables

#========================================================
# 11. SOVITA KAKSI PITKÄÄ MALLIA TÄSMÄLLEEN SAMOILLE RIVEILLE
#========================================================

cat("\nSovitetaan alkuperäinen säävalinta yhteisille riveille.\n")

original_weather_common_period_result <- fit_hmsc_model(
  model_name = "ANNUAL_COMMON_PERIOD_ORIGINAL_WEATHER",
  variables = original_common_period_variables,
  sample_ids = matched_common_ids,
  samples = final_samples,
  transient = final_transient,
  thin = final_thin,
  chains = final_chains,
  parallel = final_parallel,
  cv_specs = final_cv_specs,
  calculate_vp = TRUE,
  save_fitted = TRUE,
  save_convergence = TRUE
)

identical_weather_variable_sets <- setequal(
  original_common_period_variables,
  reselected_common_period_variables
)

if (identical_weather_variable_sets) {
  cat("Valitut muuttujat ovat samat; toista pitkää mallia ei soviteta.\n")
  reselected_weather_common_period_result <-
    original_weather_common_period_result
} else {
  cat("\nSovitetaan uudelleen valittu säämalli samoille riveille.\n")
  
  reselected_weather_common_period_result <- fit_hmsc_model(
    model_name = "ANNUAL_COMMON_PERIOD_RESELECTED_WEATHER",
    variables = reselected_common_period_variables,
    sample_ids = matched_common_ids,
    samples = final_samples,
    transient = final_transient,
    thin = final_thin,
    chains = final_chains,
    parallel = final_parallel,
    cv_specs = final_cv_specs,
    calculate_vp = TRUE,
    save_fitted = TRUE,
    save_convergence = TRUE
  )
}

#========================================================
# 12. VERTAA VALINTOJA JA ENNUSTAVIA CV-METRIIKOITA
#========================================================

group_items <- union(
  primary_selected_weather_groups,
  sensitivity_selected_weather_groups
)

variable_items <- union(
  primary_selected_weather_variables,
  sensitivity_selected_weather_variables
)

selection_comparison <- bind_rows(
  data.frame(
    item_type = rep("group", length(group_items)),
    item = group_items,
    stringsAsFactors = FALSE
  ),
  data.frame(
    item_type = rep("variable", length(variable_items)),
    item = variable_items,
    stringsAsFactors = FALSE
  )
) %>%
  mutate(
    selected_full_period = ifelse(
      item_type == "group",
      item %in% primary_selected_weather_groups,
      item %in% primary_selected_weather_variables
    ),
    selected_common_phenology_years = ifelse(
      item_type == "group",
      item %in% sensitivity_selected_weather_groups,
      item %in% sensitivity_selected_weather_variables
    ),
    same_selection =
      selected_full_period == selected_common_phenology_years
  ) %>%
  arrange(item_type, desc(same_selection), item)

compare_final_cv_metrics <- function(evaluation_name) {
  original_metrics <- original_weather_common_period_result$metrics %>%
    filter(.data$evaluation == .env$evaluation_name) %>%
    select(
      species,
      original_RMSE = RMSE,
      original_SR2 = SR2,
      original_O_RMSE = O.RMSE,
      original_O_AUC = O.AUC,
      original_O_TjurR2 = O.TjurR2,
      original_C_RMSE = C.RMSE,
      original_C_SR2 = C.SR2
    )
  
  reselected_metrics <- reselected_weather_common_period_result$metrics %>%
    filter(.data$evaluation == .env$evaluation_name) %>%
    select(
      species,
      reselected_RMSE = RMSE,
      reselected_SR2 = SR2,
      reselected_O_RMSE = O.RMSE,
      reselected_O_AUC = O.AUC,
      reselected_O_TjurR2 = O.TjurR2,
      reselected_C_RMSE = C.RMSE,
      reselected_C_SR2 = C.SR2
    )
  
  original_metrics %>%
    inner_join(reselected_metrics, by = "species") %>%
    mutate(
      evaluation = evaluation_name,
      delta_SR2 = reselected_SR2 - original_SR2,
      delta_RMSE = reselected_RMSE - original_RMSE,
      delta_O_AUC = reselected_O_AUC - original_O_AUC,
      delta_O_TjurR2 = reselected_O_TjurR2 - original_O_TjurR2,
      delta_C_SR2 = reselected_C_SR2 - original_C_SR2
    ) %>%
    select(evaluation, everything())
}

matched_predictive_comparison <- bind_rows(
  compare_final_cv_metrics("cv_year"),
  compare_final_cv_metrics("cv_site")
)

write.table(
  selection_comparison,
  file = file.path(
    modelDir,
    "comparison_full_vs_common_phenology_years_selection.txt"
  ),
  sep = ";",
  row.names = FALSE
)

write.table(
  matched_predictive_comparison,
  file = file.path(
    modelDir,
    "matched_original_vs_reselected_predictive_metrics.txt"
  ),
  sep = ";",
  row.names = FALSE
)

#========================================================
# 13. KOONTIOBJEKTI JA TALLENNUS
#========================================================

SENSITIVITY_RESULTS <- list(
  role = "ANNUAL_PREDICTIVE_COMMON_PHENOLOGY_YEARS_WEATHER_SENSITIVITY",
  analysis_status = analysis_status,
  primary_ppc_ok = primary_ppc_ok,
  primary_posterior_predictive_check = primary_ppc,
  response_definition = paste0(
    "annual total_count with Loff = log(total_effort_days / ",
    annual_index_standard_days,
    ")"
  ),
  distribution = hmsc_distribution,
  spline_terms = character(0),
  cross_validated = TRUE,
  selection_primary_evaluation = selection_primary_evaluation,
  selection_cv_specs = selection_cv_specs,
  final_cv_specs = final_cv_specs,
  phenology_reference_group = phenology_reference_group,
  phenology_variables = phenology_variables,
  availability_by_year = phenology_availability_by_year,
  eligible_years = eligible_phenology_years,
  common_period_summary = common_period_summary,
  matched_sample_ids = matched_common_ids,
  n_matched_site_years = length(matched_common_ids),
  primary_selected_weather_groups = primary_selected_weather_groups,
  primary_selected_weather_variables = primary_selected_weather_variables,
  sensitivity_selected_weather_groups =
    sensitivity_selected_weather_groups,
  sensitivity_selected_weather_variables =
    sensitivity_selected_weather_variables,
  identical_weather_variable_sets = identical_weather_variable_sets,
  locked_environment_variables = locked_environment_variables,
  selection_comparison = selection_comparison,
  weather_forward = weather_forward_common_period,
  weather_backward = weather_backward_common_period,
  original_weather_common_period =
    original_weather_common_period_result,
  reselected_weather_common_period =
    reselected_weather_common_period_result,
  matched_predictive_comparison = matched_predictive_comparison
)

saveRDS(
  SENSITIVITY_RESULTS,
  file.path(modelDir, "SENSITIVITY_ANNUAL_COMMON_PHENOLOGY_RESULTS.rds")
)

save(
  analysis_status,
  primary_ppc_ok,
  selection_primary_evaluation,
  selection_cv_specs,
  final_cv_specs,
  phenology_reference_group,
  phenology_variables,
  phenology_availability_by_year,
  eligible_phenology_years,
  common_period_summary,
  matched_common_ids,
  primary_selected_weather_groups,
  primary_selected_weather_variables,
  sensitivity_selected_weather_groups,
  sensitivity_selected_weather_variables,
  identical_weather_variable_sets,
  locked_environment_variables,
  selection_comparison,
  weather_forward_common_period,
  weather_backward_common_period,
  original_weather_common_period_result,
  reselected_weather_common_period_result,
  matched_predictive_comparison,
  file = file.path(
    modelDir,
    "HMSC_annual_common_phenology_years_sensitivity_results.RData"
  )
)

#========================================================
# 14. ENGLANNINKIELINEN ESITYSYHTEENVETO
#========================================================

markdown_table <- function(x, digits = 3L) {
  if (is.null(x) || nrow(as.data.frame(x)) == 0L) return("No rows.")
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  x[] <- lapply(x, function(z) {
    if (is.numeric(z)) {
      format(round(z, digits), trim = TRUE, scientific = FALSE)
    } else {
      as.character(z)
    }
  })
  x[] <- lapply(x, function(z) gsub("\\|", "/", z))
  c(
    paste0("| ", paste(names(x), collapse = " | "), " |"),
    paste0("| ", paste(rep("---", ncol(x)), collapse = " | "), " |"),
    apply(
      x,
      1,
      function(z) paste0("| ", paste(z, collapse = " | "), " |")
    )
  )
}

presentation_lines <- c(
  "# Annual predictive Hmsc sensitivity to common phenology years",
  "",
  "## Role and scope",
  "",
  "This is a predictive sensitivity analysis. Weather selection is repeated within the common-phenology period using year-blocked cross-validation, while the full-period primary predictive selection is kept as the reference.",
  paste0("Primary-model PPC status: **", analysis_status, "**."),
  "",
  "## Common phenology period",
  "",
  paste0("- Reference group: ", phenology_reference_group),
  paste0("- Variables: ", paste(phenology_variables, collapse = ", ")),
  paste0("- Eligible years: ", paste(eligible_phenology_years, collapse = ", ")),
  paste0("- Matched site-years in the final comparison: ", length(matched_common_ids)),
  paste0(
    "- Original and reselected predictor sets identical: ",
    identical_weather_variable_sets
  ),
  "",
  "## Weather-selection stability",
  "",
  paste0("- Full-period groups: ", ifelse(
    length(primary_selected_weather_groups) == 0L,
    "none",
    paste(primary_selected_weather_groups, collapse = ", ")
  )),
  paste0("- Common-period groups: ", ifelse(
    length(sensitivity_selected_weather_groups) == 0L,
    "none",
    paste(sensitivity_selected_weather_groups, collapse = ", ")
  )),
  "",
  markdown_table(selection_comparison),
  "",
  "## Matched-sample predictive comparison",
  "",
  "Both models below were evaluated on exactly the same common-period site-years. The table reports both year-blocked and site-blocked cross-validation. Variable selection itself uses cv_year; positive delta SR2 favours the common-period reselected weather model.",
  "",
  markdown_table(matched_predictive_comparison),
  "",
  "## Posterior predictive checks",
  "",
  "### Original weather selection on common-period rows",
  "",
  markdown_table(
    original_weather_common_period_result$posterior_predictive_check
  ),
  "",
  "### Reselected weather model on common-period rows",
  "",
  markdown_table(
    reselected_weather_common_period_result$posterior_predictive_check
  ),
  "",
  "## Interpretation",
  "",
  "Stable selections and small cross-validated changes support temporal robustness of predictive weather selection. PPC remains a separate observation-model diagnostic and should be reviewed independently of predictive CV performance."
)

writeLines(
  presentation_lines,
  file.path(
    modelDir,
    "PRESENTATION_ANNUAL_COMMON_PHENOLOGY_SENSITIVITY.md"
  )
)

writeLines(
  capture.output(sessionInfo()),
  con = file.path(modelDir, "sessionInfo.txt")
)

#========================================================
# 15. KONSOLIKOONTI
#========================================================

cat("\n========================================================\n")
cat("ANNUAL COMMON-PHENOLOGY-YEARS SENSITIVITY COMPLETE\n")
cat("========================================================\n")
cat("Status:", analysis_status, "\n")
cat("Päämallin PPC hyväksytty:", primary_ppc_ok, "\n")
cat("Fenologiavuodet:", paste(eligible_phenology_years, collapse = ", "), "\n")
cat("Vertailun paikkavuosia:", length(matched_common_ids), "\n")
cat("\nKoko ajanjakson sääryhmät:\n")
print(primary_selected_weather_groups)
cat("\nYhteisten fenologiavuosien sääryhmät:\n")
print(sensitivity_selected_weather_groups)
cat("\nValintojen vertailu:\n")
print(selection_comparison, row.names = FALSE)
cat("\nMatched-sample predictive comparison:\n")
print(matched_predictive_comparison, row.names = FALSE)
cat("\nAlkuperäisen säävalinnan PPC yhteisellä ajanjaksolla:\n")
print(
  original_weather_common_period_result$posterior_predictive_check,
  row.names = FALSE
)
cat("\nUudelleen valitun säämallin PPC yhteisellä ajanjaksolla:\n")
print(
  reselected_weather_common_period_result$posterior_predictive_check,
  row.names = FALSE
)
cat("\nTulokset:", modelDir, "\n")
cat("R-koonti: SENSITIVITY_RESULTS\n")
cat("========================================================\n")
