#========================================================
# HMSC VUOSITASOLLA: sään ja bufferikohtaisten ympäristömuuttujien
# yhtenäinen hierarkkinen valinta sekä varianssiositus
# Havaintomalli: lognormally overdispersed Poisson vuotuisille lukumäärille
#
# Kohdelajit:
#   - Epirrita autumnata
#   - Operophtera fagata
#   - Operophtera brumata
#
# Menetelmä:
#   1. sääryhmien vertailu aineistonsisäisellä explanatory SR2:lla
#   2. valittujen sääryhmien sisäinen backward-karsinta
#   3. jokaiselle ympäristöryhmälle yhden bufferin valinta yhteisillä riveillä
#   4. valittujen ympäristöryhmien selittävä forward-valinta
#   5. valittujen ympäristömuuttujien ryhmäsuojattu backward-karsinta
#   6. pitkä lopullinen MCMC
#   7. explanatory mallinsopivuus, beta-parametrit ja variance partitioning
#   8. site- ja year-satunnaistasot
#   9. valinnainen herkkyysmalli ilman Epirrita autumnataa
#
# TÄRKEÄÄ:
# - Tämä versio tekee vain selittävän analyysin eikä käytä ristiinvalidointia.
# - Muuttujavalinta tähtää havaittujen runsauserojen selittämiseen,
#   ei uusien vuosien tai uusien paikkojen ennustamiseen.
# - REF- ja CAND-mallit sovitetaan aina samoille havaintoriveille.
# - Analyysiyksikkö on paikkavuosi, ei yksittäinen pyyntijakso.
# - Vaste on vuotuinen kokonaislukumäärä (total_count).
# - Vaihteleva pyyntiponnistus huomioidaan Loff-offsetilla:
#   log(total_effort_days / annual_index_standard_days).
# - Kaikki saman vuoden havaitut pyyntijaksot sisällytetään; lentokäyrää tai splineja ei käytetä.
# - Tuloksia tulkitaan ehdollisina yhteyksinä, ei automaattisesti kausaalisina vaikutuksina.
#========================================================

# Yksi skripti: säävalinta + bufferikohtainen ympäristövalinta + loppumalli
set.seed(1)

script_revision <- "S1_S2_a_ANNUAL_PRIMARY_EXPLANATORY_LOGNORMAL_POISSON_NO_SPLINES_2026-08-17"

# Korjattu versio: get_metrics() käyttää .env$evaluation-suodatusta
# ja metriikkataulukoille tehdään kattavat yksikäsitteisyys- ja rakennevarmistukset.

library(Hmsc)
library(dplyr)
library(tidyr)
library(coda)

#========================================================
# 1. Asetukset
#========================================================

base_dir <- "E:/EIFFEL uusi/EIFFELgis/buffer_outputs/nearly_constant_environment"

data_file <- file.path(
  base_dir,
  "model_data_environment_nearly_constant_years_filled.csv"
)

modelDir <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "HMSC_ANNUAL_PRIMARY_EXPLANATORY_LOGNORMAL_POISSON_v1"
)

dir.create(modelDir, recursive = TRUE, showWarnings = FALSE)

effort_source_variable <- "interval_days"
buffer_column <- "buffer_m"
analysis_version <- "annual_weather_environment_one_buffer_lognormal_poisson_no_splines_v1"

# Vasteena käytetään vuotuista kokonaislukumäärää. Pyyntiponnistus lisätään
# Hmsc-mallin lineaariseen prediktoriin Loff-offsetina. Jakamalla ponnistus
# seitsemällä mallin odotusarvo voidaan tulkita seitsemän pyyntivuorokauden
# odotetuksi saaliiksi, kun muut muuttujat pidetään samoina.
annual_index_standard_days <- 7
min_intervals_per_site_year_species <- 4L
min_effort_days_per_site_year_species <- 28

# Sama oletus kuin alkuperäisessä viikkorutiinissa (pivot_wider(values_fill=0)):
# jos kohdelajilta puuttuu rivi muuten kelvollisesta pyyntijaksosta, se tulkitaan
# nollahavainnoksi. Vaihda FALSEksi vain, jos puuttuva rivi tarkoittaa, ettei
# kyseistä lajia arvioitu lainkaan.
missing_sample_species_means_zero <- TRUE

# Lognormal Poisson estimoi Poisson-lukumäärien ylimääräisen hajonnan. Sama
# jakauma pidetään valinta-, vahvistus-, loppu- ja herkkyysmalleissa.
hmsc_distribution <- "lognormal poisson"

# Poikkeavat vuosisummat tulostetaan ennen mallinnusta. Ensimmäisellä ajolla
# skripti pysähtyy tarkoituksella niiden tarkistamiseen. Kun olet varmistanut
# lähdeaineistosta, että suuret arvot eivät ole duplikaatteja tai syöttövirheitä,
# vaihda tämä TRUEksi.
extreme_annual_counts_verified <- TRUE
n_extreme_site_years_to_show <- 20L

cat("HMSC-jakauma:", hmsc_distribution, "\n")
cat("Vaste: vuotuinen kokonaislukumäärä\n")
cat("Offset: log(total_effort_days /", annual_index_standard_days, ")\n")
cat("Uusi tuloshakemisto:", modelDir, "\n")

target_species_patterns <- c(
  Epirrita_autumnata = "epirritaautumnata",
  Operophtera_fagata = "operophterafagata",
  Operophtera_brumata = "operophterabrumata"
)

#--------------------------------------------------------
# MCMC-asetukset
#--------------------------------------------------------

# Nopea muuttujien seulonta
selection_samples   <- 100
selection_transient <- 100
selection_thin      <- 5
selection_chains    <- 2
selection_parallel  <- 2

# Forward-valinnan ehdokkaan vahvistus
confirm_samples   <- 300
confirm_transient <- 300
confirm_thin      <- 5
confirm_chains    <- 2
confirm_parallel  <- 2

# Lopullinen selittävä malli. Näitä voi kasvattaa myöhemmin, jos
# konvergenssidiagnostiikka sitä edellyttää.
final_samples   <- 5000
final_transient <- 10000
final_thin      <- 20
final_chains    <- 4
final_parallel  <- 4

# Mallinsopivuus ja posterior predictive -tarkistus eivät tarvitse kaikkia
# pitkän MCMC-ajon näytteitä. Tämä rajoittaa ennustearrayssa käytettävän muistin.
max_prediction_draws <- 1000L

# Tekninen testi ennen varsinaista sovitusta.
run_quick_test  <- TRUE
quick_samples   <- 2
quick_transient <- 2
quick_thin      <- 1
quick_chains    <- 1

#--------------------------------------------------------
# Selittävän muuttujavalinnan kriteerit
#--------------------------------------------------------

# Ryhmä hyväksytään yhteisötasolla, kun lajien explanatory SR2:n
# keskimääräinen muutos on vähintään tämä.
min_community_delta_explanatory_SR2 <- 0.002

# Vaihtoehtoinen lajikohtainen hyväksyntä: vähintään yhden lajin
# explanatory SR2 paranee selvästi.
min_strong_species_delta_explanatory_SR2 <- 0.010

# Muut lajit eivät saa heikentyä tätä enempää.
max_allowed_harm_other_species <- 0.01

# Backward-karsinnassa muuttujan poistamisen sallittu
# keskimääräinen explanatory SR2 -menetys.
max_allowed_backward_mean_loss <- 0.001

# Vähintään kahden kolmesta lajista pitää olla heikkenemättä.
minimum_nonnegative_species <- 2L
species_delta_tolerance <- 1e-8


#--------------------------------------------------------
# Muut rajat
#--------------------------------------------------------

weather_correlation_limit <- 0.80
environment_correlation_limit <- 0.90
minimum_variables_per_selected_group <- 1L
min_sample_proportion <- 0.79
max_selected_weather_groups <- 5
max_selected_environment_groups <- 4
stop_when_no_improvement <- TRUE

# Valinnainen lisäajo. FALSE pitää päätyönkulun yhtenä lopullisena mallina.
# Vaihda TRUEksi vain, jos kahden lajin herkkyysmalli halutaan erikseen.
run_without_autumnata_sensitivity <- FALSE
posterior_support_threshold <- 0.95

cat("Sään korrelaatiokynnys:", weather_correlation_limit, "\n")
cat("Ympäristön korrelaatiokynnys:", environment_correlation_limit, "\n")
cat("Yhteisötason vähimmäis-DeltaSR2:", min_community_delta_explanatory_SR2, "\n")

#========================================================
# 2. Biologiset muuttujaryhmät
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
# 3. Apufunktiot
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
    "delta_explanatory_SR2_",
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
    min_community_delta_explanatory_SR2 &&
    delta_summary$median >
    species_delta_tolerance &&
    delta_summary$n_nonnegative >=
    minimum_nonnegative_species
  
  strong_species_support <-
    is.finite(delta_summary$maximum) &&
    is.finite(delta_summary$minimum) &&
    is.finite(delta_summary$mean) &&
    delta_summary$maximum >=
    min_strong_species_delta_explanatory_SR2 &&
    delta_summary$minimum >=
    -max_allowed_harm_other_species &&
    delta_summary$mean >=
    min_community_delta_explanatory_SR2
  
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

fit_pair_explanatory <- function(
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
    cv_specs = list()
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
    cv_specs = list()
  )
  
  comparison <- compare_fitted_results(
    reference,
    candidate,
    "explanatory"
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
        mean_delta_explanatory_SR2 = NA_real_,
        median_delta_explanatory_SR2 = NA_real_,
        min_delta_explanatory_SR2 = NA_real_,
        max_delta_explanatory_SR2 = NA_real_,
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
      fit_pair_explanatory(
        prefix = paste0(
          phase, "_EXPLANATORY_", sprintf("%02d", step), "_",
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
        mean_delta_explanatory_SR2 = NA_real_,
        median_delta_explanatory_SR2 = NA_real_,
        min_delta_explanatory_SR2 = NA_real_,
        max_delta_explanatory_SR2 = NA_real_,
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
      mean_delta_explanatory_SR2 = ds$mean,
      median_delta_explanatory_SR2 = ds$median,
      min_delta_explanatory_SR2 = ds$minimum,
      max_delta_explanatory_SR2 = ds$maximum,
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
          phase, "_explanatory_step_", sprintf("%02d", step), ".txt"
        )
      ),
      sep = ";",
      row.names = FALSE
    )
  }
  
  bind_rows(rows) %>%
    arrange(
      desc(accepted),
      desc(mean_delta_explanatory_SR2),
      desc(max_delta_explanatory_SR2),
      desc(n_samples)
    )
}

confirm_explanatory_candidate <- function(
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
  
  pair <- fit_pair_explanatory(
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
      mean_delta_explanatory_SR2 = ds$mean,
      median_delta_explanatory_SR2 = ds$median,
      min_delta_explanatory_SR2 = ds$minimum,
      max_delta_explanatory_SR2 = ds$maximum,
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
  
  explanatory_log <- list()
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
    explanatory_log[[paste0("step_", step)]] <- comparison_table
    
    accepted <- comparison_table %>%
      filter(
        accepted,
        is.finite(mean_delta_explanatory_SR2)
      )
    
    if (nrow(accepted) == 0) break
    
    confirmed_best <- NULL
    
    # Jos paras ehdokas ei läpäise pidempää ajoa, kokeillaan
    # seuraavaa hyväksyttyä ehdokasta eikä valita sitä automaattisesti.
    for (candidate_index in seq_len(nrow(accepted))) {
      candidate_row <- accepted[candidate_index, , drop = FALSE]
      
      confirmed <- tryCatch(
        confirm_explanatory_candidate(
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
      explanatory_log,
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
    explanatory_log = explanatory_log,
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
        fit_pair_explanatory(
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
          mean_delta_explanatory_SR2 = NA_real_,
          min_delta_explanatory_SR2 = NA_real_,
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
        mean_delta_explanatory_SR2 = ds$mean,
        median_delta_explanatory_SR2 = ds$median,
        min_delta_explanatory_SR2 = ds$minimum,
        max_delta_explanatory_SR2 = ds$maximum,
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
      arrange(desc(removable), desc(mean_delta_explanatory_SR2))
    
    log[[paste0("step_", step)]] <- table
    removable_table <- table %>%
      filter(removable) %>%
      arrange(desc(mean_delta_explanatory_SR2))
    
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
      round(removable_table$mean_delta_explanatory_SR2[1], 6),
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
            mean_delta_explanatory_SR2 = NA_real_,
            median_delta_explanatory_SR2 = NA_real_,
            min_delta_explanatory_SR2 = NA_real_,
            max_delta_explanatory_SR2 = NA_real_,
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
          mean_delta_explanatory_SR2 = NA_real_,
          median_delta_explanatory_SR2 = NA_real_,
          min_delta_explanatory_SR2 = NA_real_,
          max_delta_explanatory_SR2 = NA_real_,
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
        fit_pair_explanatory(
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
          mean_delta_explanatory_SR2 = NA_real_,
          median_delta_explanatory_SR2 = NA_real_,
          min_delta_explanatory_SR2 = NA_real_,
          max_delta_explanatory_SR2 = NA_real_,
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
        mean_delta_explanatory_SR2 = ds$mean,
        median_delta_explanatory_SR2 = ds$median,
        min_delta_explanatory_SR2 = ds$minimum,
        max_delta_explanatory_SR2 = ds$maximum,
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
      filter(status == "fitted", is.finite(mean_delta_explanatory_SR2)) %>%
      arrange(
        desc(mean_delta_explanatory_SR2),
        desc(median_delta_explanatory_SR2),
        desc(max_delta_explanatory_SR2),
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
# 4. Lue pitkä bufferiaineisto ja muodosta vuosiaineisto
#========================================================

if (!file.exists(data_file)) {
  stop("Aineistotiedostoa ei löydy: ", data_file)
}

dat <- read.csv(
  data_file,
  sep = ",",
  dec = ".",
  header = TRUE,
  stringsAsFactors = FALSE,
  check.names = FALSE
)

required_cols <- c(
  "sample_id", "site", "year", effort_source_variable,
  "species", "count", buffer_column
)
missing_required <- setdiff(required_cols, names(dat))
if (length(missing_required) > 0L) {
  stop(
    "Aineistosta puuttuvat pakolliset sarakkeet: ",
    paste(missing_required, collapse = ", ")
  )
}

dat <- dat %>%
  mutate(
    sample_id = as.character(sample_id),
    site = as.character(site),
    year = as.integer(as.character(year)),
    species = as.character(species),
    count = make_numeric(count),
    interval_days = make_numeric(.data[[effort_source_variable]]),
    buffer_m = make_numeric(.data[[buffer_column]])
  ) %>%
  arrange(site, year, sample_id, species, buffer_m)

if (any(!is.finite(dat$year))) stop("year sisältää puuttuvia tai virheellisiä arvoja.")
if (any(dat$count < 0, na.rm = TRUE)) stop("count sisältää negatiivisia arvoja.")
if (any(!is.finite(dat$buffer_m))) stop("buffer_m sisältää puuttuvia tai virheellisiä arvoja.")
if (any(!is.finite(dat$interval_days)) || any(dat$interval_days <= 0)) {
  stop("interval_days sisältää puuttuvia, nolla- tai negatiivisia arvoja.")
}

target_species <- match_target_species(unique(dat$species))
dat <- dat %>% filter(species %in% target_species)

cat("Mallinnettavat lajit: ", paste(target_species, collapse = ", "), "\n", sep = "")
cat("Analyysiyksikkö: site-year\n")
cat("Vaste: annual total count\n")
cat("Offset: log(total effort days / ", annual_index_standard_days, ")\n", sep = "")
cat("Spline-termejä: 0\n")

buffer_values <- sort(unique(dat$buffer_m))
cat("Aineistosta löydetyt bufferit (m): ", paste(buffer_values, collapse = ", "), "\n", sep = "")

# Rajaa muuttujalistat vain aineistosta todella löytyviin sarakkeisiin.
weather_groups <- lapply(weather_groups, function(x) intersect(x, names(dat)))
weather_groups <- weather_groups[lengths(weather_groups) > 0L]
if (length(weather_groups) == 0L) {
  stop("Yhtään määritettyä säämuuttujaa ei löytynyt aineistosta.")
}

environment_groups_raw <- lapply(
  environment_groups,
  function(x) intersect(x, names(dat))
)
environment_groups_raw <- environment_groups_raw[lengths(environment_groups_raw) > 0L]
if (length(environment_groups_raw) == 0L) {
  stop("Yhtään määritettyä ympäristömuuttujaa ei löytynyt aineistosta.")
}

all_weather_raw <- unique(unlist(weather_groups, use.names = FALSE))
all_environment_raw <- unique(unlist(environment_groups_raw, use.names = FALSE))
numeric_predictors <- unique(c(all_weather_raw, all_environment_raw))
dat[numeric_predictors] <- lapply(dat[numeric_predictors], make_numeric)

cat("\nAineistosta löytyneet sääryhmät:\n")
for (g in names(weather_groups)) {
  cat("  ", g, ": ", paste(weather_groups[[g]], collapse = ", "), "\n", sep = "")
}
cat("\nAineistosta löytyneet ympäristöryhmät:\n")
for (g in names(environment_groups_raw)) {
  cat("  ", g, ": ", paste(environment_groups_raw[[g]], collapse = ", "), "\n", sep = "")
}

first_consistent <- function(x, variable_name = "muuttuja") {
  z <- x[!is.na(x)]
  if (length(z) == 0L) return(NA)
  uz <- unique(z)
  if (length(uz) > 1L) {
    stop(variable_name, " vaihtelee saman sample_id:n sisällä.")
  }
  uz[1]
}

finite_median_value <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) NA_real_ else median(x)
}

# Näytetason metatieto tarkistaa samalla, että bufferirivien monistus ei
# aiheuta ristiriitaisia site-, year- tai effort-arvoja.
interval_metadata <- dat %>%
  group_by(sample_id) %>%
  summarise(
    site = first_consistent(site, "site"),
    year = first_consistent(year, "year"),
    interval_days = first_consistent(interval_days, "interval_days"),
    .groups = "drop"
  )

# Count saa esiintyä usealla bufferirivillä, mutta arvon on oltava sama.
interval_species_count <- dat %>%
  group_by(sample_id, species) %>%
  summarise(
    n_unique_count = n_distinct(count[is.finite(count)]),
    count = if (all(!is.finite(count))) NA_real_ else first(count[is.finite(count)]),
    .groups = "drop"
  ) %>%
  left_join(interval_metadata, by = "sample_id")

if (any(interval_species_count$n_unique_count > 1L)) {
  bad <- interval_species_count %>% filter(n_unique_count > 1L)
  stop(
    "Saman sample_id–species-yhdistelmän count vaihtelee bufferirivien välillä.\n",
    paste(capture.output(print(head(bad, 20))), collapse = "\n")
  )
}

interval_species_count_observed <- interval_species_count %>%
  mutate(source_species_row_present = TRUE)

if (missing_sample_species_means_zero) {
  interval_species_count <- tidyr::expand_grid(
    sample_id = interval_metadata$sample_id,
    species = target_species
  ) %>%
    left_join(
      interval_species_count_observed %>%
        select(sample_id, species, count, source_species_row_present),
      by = c("sample_id", "species")
    ) %>%
    mutate(
      source_species_row_present = tidyr::replace_na(
        source_species_row_present,
        FALSE
      ),
      count = ifelse(!source_species_row_present, 0, count)
    ) %>%
    left_join(interval_metadata, by = "sample_id")
} else {
  interval_species_count <- interval_species_count %>%
    mutate(source_species_row_present = TRUE) %>%
    select(-n_unique_count)
}

zero_fill_audit <- interval_species_count %>%
  group_by(species) %>%
  summarise(
    n_sample_intervals = n(),
    n_source_rows_present = sum(source_species_row_present),
    n_missing_rows_interpreted_as_zero = sum(!source_species_row_present),
    proportion_rows_interpreted_as_zero = mean(!source_species_row_present),
    n_present_rows_with_missing_count = sum(
      source_species_row_present & !is.finite(count)
    ),
    .groups = "drop"
  )

cat(
  "Puuttuva sample_id–species-rivi tulkitaan nollaksi: ",
  missing_sample_species_means_zero,
  "\n",
  sep = ""
)
cat("Lajirivien nollatäytön tarkistus:\n")
print(zero_fill_audit, row.names = FALSE)
if (any(zero_fill_audit$n_present_rows_with_missing_count > 0L)) {
  warning(
    "Aineistossa on olemassa olevia lajirivejä, joiden count puuttuu. ",
    "Niitä ei muutettu nolliksi, vaan ne jäävät pois kyseisen lajin ",
    "vuosisummaa ja pyyntiponnistusta muodostettaessa."
  )
}

# Kaikki havaitut pyyntijaksot käytetään. Vuosivaste ei sisällä lentoviikkoa,
# spline-kantaa tai aineistosta estimoitua lentoaikaikkunaa.
annual_response_long <- interval_species_count %>%
  filter(is.finite(count)) %>%
  group_by(site, year, species) %>%
  summarise(
    total_count = sum(count),
    total_effort_days = sum(interval_days),
    n_intervals = n(),
    .groups = "drop"
  ) %>%
  mutate(
    annual_index = total_count / total_effort_days * annual_index_standard_days,
    log_annual_index = log1p(annual_index),
    sufficient_coverage =
      n_intervals >= min_intervals_per_site_year_species &
      total_effort_days >= min_effort_days_per_site_year_species
  )

annual_response_used <- annual_response_long %>%
  filter(
    sufficient_coverage,
    is.finite(total_count),
    is.finite(total_effort_days),
    total_effort_days > 0
  )

if (nrow(annual_response_used) == 0L) {
  stop("Vuosivasteeseen ei jäänyt yhtään havaintoa kattavuusrajausten jälkeen.")
}

sample_metadata <- annual_response_used %>%
  distinct(site, year) %>%
  arrange(site, year) %>%
  mutate(sample_id = paste(site, year, sep = "__")) %>%
  select(sample_id, site, year)

if (anyDuplicated(sample_metadata$sample_id)) {
  stop("Paikkavuoden sample_id ei ole yksikäsitteinen.")
}

annual_count_wide <- annual_response_used %>%
  mutate(sample_id = paste(site, year, sep = "__")) %>%
  select(sample_id, species, total_count) %>%
  pivot_wider(names_from = species, values_from = total_count) %>%
  right_join(sample_metadata %>% select(sample_id), by = "sample_id") %>%
  arrange(match(sample_id, sample_metadata$sample_id))

annual_effort_wide <- annual_response_used %>%
  mutate(sample_id = paste(site, year, sep = "__")) %>%
  select(sample_id, species, total_effort_days) %>%
  pivot_wider(names_from = species, values_from = total_effort_days) %>%
  right_join(sample_metadata %>% select(sample_id), by = "sample_id") %>%
  arrange(match(sample_id, sample_metadata$sample_id))

missing_response_species <- setdiff(target_species, names(annual_count_wide))
if (length(missing_response_species) > 0L) {
  stop(
    "Vuosivasteesta puuttuvat kokonaan lajit: ",
    paste(missing_response_species, collapse = ", ")
  )
}

missing_effort_species <- setdiff(target_species, names(annual_effort_wide))
if (length(missing_effort_species) > 0L) {
  stop(
    "Pyyntiponnistusmatriisista puuttuvat kokonaan lajit: ",
    paste(missing_effort_species, collapse = ", ")
  )
}

Y_annual_all <- as.matrix(annual_count_wide[, target_species, drop = FALSE])
storage.mode(Y_annual_all) <- "numeric"
rownames(Y_annual_all) <- annual_count_wide$sample_id

effort_days_annual_all <- as.matrix(
  annual_effort_wide[, target_species, drop = FALSE]
)
storage.mode(effort_days_annual_all) <- "numeric"
rownames(effort_days_annual_all) <- annual_effort_wide$sample_id

if (!identical(dim(Y_annual_all), dim(effort_days_annual_all)) ||
    !identical(rownames(Y_annual_all), rownames(effort_days_annual_all)) ||
    !identical(colnames(Y_annual_all), colnames(effort_days_annual_all))) {
  stop("Vuosittaisten count- ja effort-matriisien rakenne ei täsmää.")
}

finite_y <- is.finite(Y_annual_all)
if (any(Y_annual_all[finite_y] < 0)) {
  stop("Vuosittainen count-vaste sisältää negatiivisia arvoja.")
}
if (any(abs(Y_annual_all[finite_y] - round(Y_annual_all[finite_y])) > 1e-8)) {
  stop(
    "Lognormal Poisson -malli edellyttää kokonaislukumääräistä vastetta, ",
    "mutta vuosivasteessa on ei-kokonaislukuarvoja."
  )
}
Y_annual_all[finite_y] <- round(Y_annual_all[finite_y])

bad_effort <- finite_y &
  (!is.finite(effort_days_annual_all) | effort_days_annual_all <= 0)
if (any(bad_effort)) {
  stop("Ainakin yhdeltä havaintovasteelta puuttuu positiivinen pyyntiponnistus.")
}

# Hmsc vaatii äärellisen offsetin koko Y-matriisin kokoisena. Soluissa, joissa
# Y on NA, offset ei osallistu likelihoodiin; niille käytetään neutraalia nollaa.
Loff_annual_all <- matrix(
  0,
  nrow = nrow(effort_days_annual_all),
  ncol = ncol(effort_days_annual_all),
  dimnames = dimnames(effort_days_annual_all)
)
valid_effort <- is.finite(effort_days_annual_all) & effort_days_annual_all > 0
Loff_annual_all[valid_effort] <- log(
  effort_days_annual_all[valid_effort] / annual_index_standard_days
)

if (ncol(Y_annual_all) != 3L) {
  stop("Vuosittaisessa lajimatriisissa ei ole täsmälleen kolmea kohdelajia.")
}
if (any(rowSums(is.finite(Y_annual_all)) == 0L)) {
  stop("Vuosittaisessa lajimatriisissa on täysin puuttuvia paikkavuosia.")
}
response_variance <- apply(Y_annual_all, 2, var, na.rm = TRUE)
if (any(!is.finite(response_variance) | response_variance <= 0)) {
  stop("Ainakin yhden lajin vuosivasteen varianssi on nolla tai määrittelemätön.")
}

response_distribution <- bind_rows(lapply(target_species, function(sp) {
  d <- annual_response_used %>% filter(species == sp)
  data.frame(
    species = sp,
    n = nrow(d),
    zero_proportion = mean(d$total_count == 0),
    minimum_count = min(d$total_count),
    q05_count = as.numeric(quantile(d$total_count, 0.05, names = FALSE)),
    median_count = median(d$total_count),
    mean_count = mean(d$total_count),
    q95_count = as.numeric(quantile(d$total_count, 0.95, names = FALSE)),
    q99_count = as.numeric(quantile(d$total_count, 0.99, names = FALSE)),
    maximum_count = max(d$total_count),
    variance_to_mean = if (mean(d$total_count) > 0) {
      var(d$total_count) / mean(d$total_count)
    } else {
      NA_real_
    },
    median_effort_days = median(d$total_effort_days),
    minimum_effort_days = min(d$total_effort_days),
    maximum_effort_days = max(d$total_effort_days),
    stringsAsFactors = FALSE
  )
}))

extreme_count_audit <- annual_response_used %>%
  group_by(species) %>%
  arrange(desc(total_count), .by_group = TRUE) %>%
  slice_head(n = n_extreme_site_years_to_show) %>%
  ungroup() %>%
  select(
    species, site, year, total_count, total_effort_days,
    n_intervals, annual_index, log_annual_index
  )

extreme_interval_audit <- interval_species_count %>%
  inner_join(
    extreme_count_audit %>% distinct(species, site, year),
    by = c("species", "site", "year")
  ) %>%
  arrange(species, site, year, desc(count), sample_id) %>%
  select(species, site, year, sample_id, count, interval_days)

extreme_count_flags <- response_distribution %>%
  transmute(
    species,
    q99_count,
    maximum_count,
    maximum_to_q99_ratio = maximum_count / pmax(q99_count, 1),
    flagged = maximum_count > 5 * pmax(q99_count, 1)
  )

cat("\nVuosittaisen count-vasteen jakaumadiagnostiikka:\n")
print(response_distribution, row.names = FALSE)
cat("\nSuurimmat paikkavuosikohtaiset lukumäärät tarkistettaviksi:\n")
print(extreme_count_audit, n = nrow(extreme_count_audit))
cat("\nAutomaattiset yläpäähälytykset:\n")
print(extreme_count_flags, row.names = FALSE)

write.table(
  annual_response_long,
  file = file.path(modelDir, "annual_site_year_species_indices_all.txt"),
  sep = ";", row.names = FALSE
)
write.table(
  response_distribution,
  file = file.path(modelDir, "annual_response_distribution.txt"),
  sep = ";", row.names = FALSE
)
write.table(
  zero_fill_audit,
  file = file.path(modelDir, "annual_zero_fill_audit.txt"),
  sep = ";", row.names = FALSE
)
write.table(
  extreme_count_audit,
  file = file.path(modelDir, "annual_extreme_counts_for_verification.txt"),
  sep = ";", row.names = FALSE
)
write.table(
  extreme_interval_audit,
  file = file.path(modelDir, "annual_extreme_count_intervals_for_verification.txt"),
  sep = ";", row.names = FALSE
)

if (any(extreme_count_flags$flagged) && !extreme_annual_counts_verified) {
  stop(
    "Poikkeavien vuosisummien tarkistus vaaditaan ennen Hmsc-ajoa. ",
    "Tarkista annual_extreme_counts_for_verification.txt ja ",
    "annual_extreme_count_intervals_for_verification.txt. ",
    "Kun arvot on varmistettu lähdeaineistosta, aseta ",
    "extreme_annual_counts_verified <- TRUE ja aja skripti uudelleen."
  )
}

# Sääarvot aggregoidaan ensin kerran pyyntijaksoa kohti ja sitten mediaanina
# paikkavuodelle. Näin laji- ja bufferirivien määrä ei painota mediaania.
weather_interval <- dat %>%
  group_by(sample_id) %>%
  summarise(
    across(all_of(all_weather_raw), finite_median_value),
    .groups = "drop"
  ) %>%
  left_join(interval_metadata, by = "sample_id")

weather_annual <- weather_interval %>%
  group_by(site, year) %>%
  summarise(
    across(all_of(all_weather_raw), finite_median_value),
    .groups = "drop"
  ) %>%
  mutate(sample_id = paste(site, year, sep = "__")) %>%
  select(sample_id, all_of(all_weather_raw))

# Ympäristöarvot aggregoidaan paikkavuosi × bufferi -tasolle ja levitetään
# bufferikohtaisiksi sarakkeiksi: pine_volume -> pine_volume__b500m.
environment_interval <- dat %>%
  group_by(sample_id, buffer_m) %>%
  summarise(
    across(all_of(all_environment_raw), finite_median_value),
    .groups = "drop"
  ) %>%
  left_join(interval_metadata, by = "sample_id")

environment_annual_long <- environment_interval %>%
  group_by(site, year, buffer_m) %>%
  summarise(
    across(all_of(all_environment_raw), finite_median_value),
    .groups = "drop"
  ) %>%
  mutate(
    sample_id = paste(site, year, sep = "__"),
    buffer_key = buffer_key(buffer_m)
  )

environment_wide <- environment_annual_long %>%
  select(sample_id, buffer_key, all_of(all_environment_raw)) %>%
  pivot_wider(
    id_cols = sample_id,
    names_from = buffer_key,
    values_from = all_of(all_environment_raw),
    names_glue = "{.value}__b{buffer_key}m"
  )

buffer_variable_map <- expand.grid(
  original_variable = all_environment_raw,
  buffer_m = buffer_values,
  stringsAsFactors = FALSE
) %>%
  mutate(
    buffer_key = buffer_key(buffer_m),
    model_variable = paste0(original_variable, "__b", safe_name(buffer_key), "m"),
    present_in_wide_data = model_variable %in% names(environment_wide)
  )

write.table(
  buffer_variable_map,
  file = file.path(modelDir, "buffer_variable_name_map.txt"),
  sep = ";", row.names = FALSE
)

X_sample <- sample_metadata %>%
  select(sample_id) %>%
  left_join(weather_annual, by = "sample_id") %>%
  left_join(environment_wide, by = "sample_id")

common_ids <- Reduce(
  intersect,
  list(
    rownames(Y_annual_all),
    rownames(Loff_annual_all),
    sample_metadata$sample_id,
    X_sample$sample_id
  )
)
if (length(common_ids) == 0L) {
  stop("Y-, metadata- ja X-aineistoilla ei ole yhteisiä paikkavuosia.")
}

Y_annual_all <- Y_annual_all[common_ids, , drop = FALSE]
effort_days_annual_all <- effort_days_annual_all[common_ids, , drop = FALSE]
Loff_annual_all <- Loff_annual_all[common_ids, , drop = FALSE]
sample_metadata <- sample_metadata %>%
  filter(sample_id %in% common_ids) %>%
  arrange(match(sample_id, common_ids))
X_sample <- X_sample %>%
  filter(sample_id %in% common_ids) %>%
  arrange(match(sample_id, common_ids))

if (!identical(rownames(Y_annual_all), rownames(Loff_annual_all)) ||
    !identical(colnames(Y_annual_all), colnames(Loff_annual_all)) ||
    !identical(rownames(Y_annual_all), sample_metadata$sample_id) ||
    !identical(rownames(Y_annual_all), X_sample$sample_id)) {
  stop("Vuosittaisen Y-, Loff-, metadata- ja X-aineiston rivijärjestys ei täsmää.")
}

min_required_samples <- ceiling(nrow(X_sample) * min_sample_proportion)

write.table(
  data.frame(
    species = colnames(Y_annual_all),
    n_site_years = colSums(is.finite(Y_annual_all)),
    n_zero_counts = vapply(
      target_species,
      function(sp) sum(
        annual_response_used$species == sp & annual_response_used$total_count == 0
      ),
      integer(1)
    )
  ),
  file = file.path(modelDir, "target_species_annual_summary.txt"),
  sep = ";", row.names = FALSE
)

#========================================================
# 5. Muodosta bufferikohtaiset ympäristökandidaatit
#========================================================

# Muodosta jokaisesta ekologinen ryhmä × bufferi -yhdistelmästä
# oma forward-valinnan kandidaattiryhmä.
environment_groups_buffered <- list()

for (group_name in names(environment_groups_raw)) {
  for (b in buffer_values) {
    candidate_name <- paste0(
      group_name,
      "__buffer_",
      safe_name(buffer_key(b)),
      "m"
    )
    
    requested <- paste0(
      environment_groups_raw[[group_name]],
      buffer_suffix(b)
    )
    
    present <- intersect(requested, names(X_sample))
    present <- remove_zero_variance_names(X_sample, present)$kept
    
    if (length(present) > 0) {
      environment_groups_buffered[[candidate_name]] <- present
    }
  }
}

if (length(environment_groups_buffered) == 0) {
  stop("Yhtään bufferikohtaista ympäristöryhmää ei voitu muodostaa.")
}

environment_candidate_table <- bind_rows(
  lapply(
    names(environment_groups_buffered),
    function(candidate_name) {
      data.frame(
        candidate_group = candidate_name,
        ecological_group = sub("__buffer_.*$", "", candidate_name),
        buffer_m = as.numeric(
          sub(
            "m$",
            "",
            sub("^.*__buffer_", "", candidate_name)
          )
        ),
        variables = paste(
          environment_groups_buffered[[candidate_name]],
          collapse = "|"
        ),
        stringsAsFactors = FALSE
      )
    }
  )
)

write.table(
  environment_candidate_table,
  file = file.path(modelDir, "environment_group_buffer_candidates.txt"),
  sep = ";",
  row.names = FALSE
)

#========================================================
# 6. Sääryhmien forward selection
#========================================================

weather_forward <- forward_select_groups(
  groups = weather_groups,
  phase = "WEATHER",
  max_groups = max_selected_weather_groups,
  base_variables = character(0)
)

selected_weather_groups <- weather_forward$selected_groups
weather_variables_before_backward <- weather_forward$selected_variables

if (length(selected_weather_groups) == 0) {
  message(
    "\nYksikään sääryhmä ei parantanut explanatory SR2:ta. ",
    "Jatketaan ilman säämuuttujia."
  )
  selected_weather_groups <- character(0)
  weather_variables_before_backward <- character(0)
} else {
  message(
    "\nExplanatory SR2:lla valitut sääryhmät: ",
    paste(selected_weather_groups, collapse = ", ")
  )
}

#========================================================
# 7. Säämuuttujien ryhmäsuojattu backward selection
#========================================================

weather_backward <- backward_select_variables(
  initial_variables = weather_variables_before_backward,
  selected_group_names = selected_weather_groups,
  all_groups = weather_groups,
  phase = "WEATHER"
)

selected_weather_variables <- weather_backward$selected_variables

write.table(
  data.frame(variable = selected_weather_variables),
  file = file.path(modelDir, "selected_weather_variables_final.txt"),
  sep = ";",
  row.names = FALSE
)

write.table(
  data.frame(group = selected_weather_groups),
  file = file.path(modelDir, "selected_weather_groups_final.txt"),
  sep = ";",
  row.names = FALSE
)

#========================================================
# 8A. Valitse yksi bufferi jokaiselle ympäristöryhmälle
#========================================================
#
# Saman ekologisen ryhmän kaikki bufferit testataan samoilla havaintoriveillä.
# Tässä valitaan vain ryhmän mittakaava; vasta seuraava forward-vaihe päättää,
# tuoko ekologinen ryhmä lisäselitysvoimaa lukitun sääpohjan päälle.
#========================================================

buffer_selection <- select_one_buffer_per_environment_group(
  groups_buffered = environment_groups_buffered,
  candidate_table = environment_candidate_table,
  base_variables = selected_weather_variables
)

write.table(
  buffer_selection$comparisons,
  file = file.path(modelDir, "buffer_selection_all_groups.txt"),
  sep = ";",
  row.names = FALSE
)
write.table(
  buffer_selection$winners,
  file = file.path(modelDir, "buffer_selection_winners.txt"),
  sep = ";",
  row.names = FALSE
)

environment_groups_one_buffer <- buffer_selection$groups
if (length(environment_groups_one_buffer) == 0L) {
  stop(
    "Yhdellekään ympäristöryhmälle ei voitu valita bufferia. ",
    "Tarkista buffer_selection_all_groups.txt."
  )
}

#========================================================
# 8B. Valitse ympäristöryhmät vain ennalta valituilla buffereilla
#========================================================

environment_forward <- forward_select_groups(
  groups = environment_groups_one_buffer,
  phase = "ENVIRONMENT",
  max_groups = max_selected_environment_groups,
  base_variables = selected_weather_variables
)

selected_environment_groups <- environment_forward$selected_groups

selected_environment_group_buffers <- buffer_selection$winners %>%
  filter(ecological_group %in% selected_environment_groups) %>%
  arrange(match(ecological_group, selected_environment_groups)) %>%
  pull(candidate_group)

environment_variables_before_backward <- setdiff(
  environment_forward$selected_variables,
  selected_weather_variables
)

if (length(selected_environment_groups) == 0) {
  warning(
    "Yksikään ennalta bufferikorjattu ympäristöryhmä ei parantanut ",
    "explanatory SR2:ta."
  )
  selected_environment_variables <- character(0)
  environment_backward_log <- list()
} else {
  message(
    "\nValitut ympäristöryhmät: ",
    paste(selected_environment_groups, collapse = ", ")
  )
  
  environment_group_definitions <- environment_groups_one_buffer[
    selected_environment_groups
  ]
  
  current_environment <- environment_variables_before_backward
  environment_backward_log <- list()
  
  for (step in seq_len(max(0, length(current_environment) - 1))) {
    rows <- list()
    
    for (variable_to_remove in current_environment) {
      guard <- check_group_guard(
        current_environment,
        variable_to_remove,
        environment_group_definitions
      )
      
      full_variables <- unique(c(
        selected_weather_variables,
        current_environment
      ))
      
      reduced_variables <- unique(c(
        selected_weather_variables,
        setdiff(current_environment, variable_to_remove)
      ))
      
      ids <- candidate_sample_ids(full_variables)
      
      pair <- tryCatch(
        fit_pair_explanatory(
          prefix = paste0(
            "ENVIRONMENT_BACKWARD_",
            sprintf("%02d", step),
            "_DROP_",
            safe_name(variable_to_remove)
          ),
          reference_variables = full_variables,
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
          removable = FALSE,
          status = paste0("failed: ", pair$error),
          stringsAsFactors = FALSE
        )
        next
      }
      
      ds <- pair$comparison$summary
      removable <- guard$allowed && accept_removal(ds)
      
      row <- data.frame(
        step = step,
        removed_variable = variable_to_remove,
        mean_delta_explanatory_SR2 = ds$mean,
        median_delta_explanatory_SR2 = ds$median,
        min_delta_explanatory_SR2 = ds$minimum,
        max_delta_explanatory_SR2 = ds$maximum,
        n_species_nonnegative = ds$n_nonnegative,
        group_guard_allows = guard$allowed,
        protected_groups = paste(
          guard$protected_groups,
          collapse = "|"
        ),
        removable = removable,
        status = "fitted",
        stringsAsFactors = FALSE
      )
      
      rows[[variable_to_remove]] <- bind_cols(
        row,
        species_delta_wide(pair$comparison$delta)
      )
    }
    
    table <- bind_rows(rows) %>%
      arrange(desc(removable), desc(mean_delta_explanatory_SR2))
    
    environment_backward_log[[paste0("step_", step)]] <- table
    
    write.table(
      table,
      file = file.path(
        modelDir,
        paste0(
          "ENVIRONMENT_backward_step_",
          sprintf("%02d", step),
          ".txt"
        )
      ),
      sep = ";",
      row.names = FALSE
    )
    
    possible <- table %>%
      filter(removable) %>%
      arrange(desc(mean_delta_explanatory_SR2))
    
    if (nrow(possible) == 0) break
    
    # Poistetaan suoraan alustavan backward-vertailun paras sallittu muuttuja.
    # Erillistä pitkää vahvistusajoa ei tehdä jokaiselle poistolle.
    best_drop <- possible$removed_variable[1]
    
    current_environment <- setdiff(
      current_environment,
      best_drop
    )
    
    message(
      "Ympäristömuuttujien backward-karsinta, askel ", step,
      ": poistettiin ", best_drop,
      " (mean delta SR2 = ",
      round(possible$mean_delta_explanatory_SR2[1], 6),
      ")."
    )
  }
  
  selected_environment_variables <- current_environment
}

selected_environment_table <- data.frame(
  variable = selected_environment_variables,
  original_variable = strip_buffer_suffix(selected_environment_variables),
  buffer_m = suppressWarnings(
    as.numeric(
      sub(
        "m$",
        "",
        sub("^.*__b", "", selected_environment_variables)
      )
    )
  ),
  ecological_group = vapply(
    selected_environment_variables,
    get_environment_group,
    character(1)
  ),
  stringsAsFactors = FALSE
)

selected_environment_group_buffers_final <- environment_candidate_table %>%
  filter(candidate_group %in% selected_environment_group_buffers) %>%
  rowwise() %>%
  mutate(
    n_final_variables = sum(
      selected_environment_table$ecological_group == ecological_group &
        selected_environment_table$buffer_m == buffer_m,
      na.rm = TRUE
    )
  ) %>%
  ungroup() %>%
  filter(n_final_variables > 0)

selected_environment_groups <- unique(
  selected_environment_group_buffers_final$ecological_group
)

write.table(
  selected_environment_table,
  file = file.path(
    modelDir,
    "selected_environment_variables_final.txt"
  ),
  sep = ";",
  row.names = FALSE
)

write.table(
  selected_environment_group_buffers_final,
  file = file.path(
    modelDir,
    "selected_environment_groups_and_buffers_final.txt"
  ),
  sep = ";",
  row.names = FALSE
)

# 9. Lopullinen pitkä malli
#========================================================

final_variables <- unique(c(
  selected_weather_variables,
  selected_environment_variables
))

if (length(final_variables) == 0L) {
  stop(
    "Muuttujavalinta päättyi ilman yhtään sää- tai ympäristömuuttujaa. ",
    "Lopullista vakiotermimallia ei soviteta automaattisesti. Tarkista ",
    "WEATHER_explanatory_selection_all.txt ja ",
    "ENVIRONMENT_explanatory_selection_all.txt."
  )
}

final_ids <- candidate_sample_ids(final_variables)

final_result <- fit_hmsc_model(
  model_name = "FINAL_THREE_SPECIES_ANNUAL",
  variables = final_variables,
  sample_ids = final_ids,
  samples = final_samples,
  transient = final_transient,
  thin = final_thin,
  chains = final_chains,
  parallel = final_parallel,
  cv_specs = list(),
  calculate_vp = TRUE,
  save_fitted = TRUE,
  save_convergence = TRUE
)

#========================================================
# 10. Herkkyysmalli ilman Epirrita autumnataa
#========================================================

autumnata_name <- target_species[
  normalize_species_name(target_species) == "epirritaautumnata"
]

sensitivity_result <- NULL

if (
  run_without_autumnata_sensitivity &&
  length(autumnata_name) == 1
) {
  Y_without_autumnata <- Y_annual_all[
    ,
    setdiff(colnames(Y_annual_all), autumnata_name),
    drop = FALSE
  ]
  Loff_without_autumnata <- Loff_annual_all[
    ,
    colnames(Y_without_autumnata),
    drop = FALSE
  ]
  
  sensitivity_result <- fit_hmsc_model(
    model_name = "ANNUAL_SENSITIVITY_WITHOUT_EPIRRITA_AUTUMNATA",
    variables = final_variables,
    sample_ids = final_ids,
    response_matrix = Y_without_autumnata,
    offset_matrix = Loff_without_autumnata,
    samples = final_samples,
    transient = final_transient,
    thin = final_thin,
    chains = final_chains,
    parallel = final_parallel,
    cv_specs = list(),
    calculate_vp = TRUE,
    save_fitted = TRUE,
    save_convergence = TRUE
  )
}

#========================================================
# 11. Tallenna koko valintapolku
#========================================================

write.table(
  bind_rows(weather_forward$explanatory_log),
  file = file.path(modelDir, "weather_explanatory_selection_all.txt"),
  sep = ";",
  row.names = FALSE
)


write.table(
  bind_rows(weather_backward$log),
  file = file.path(modelDir, "weather_backward_all.txt"),
  sep = ";",
  row.names = FALSE
)

write.table(
  bind_rows(environment_forward$explanatory_log),
  file = file.path(modelDir, "environment_explanatory_selection_all.txt"),
  sep = ";",
  row.names = FALSE
)


save(
  script_revision,
  analysis_version,
  target_species,
  annual_response_long,
  annual_response_used,
  response_distribution,
  zero_fill_audit,
  extreme_count_audit,
  extreme_interval_audit,
  extreme_count_flags,
  Y_annual_all,
  effort_days_annual_all,
  Loff_annual_all,
  sample_metadata,
  X_sample,
  weather_groups,
  environment_groups,
  environment_groups_raw,
  environment_groups_buffered,
  environment_groups_one_buffer,
  buffer_selection,
  buffer_values,
  buffer_variable_map,
  environment_candidate_table,
  selected_weather_groups,
  selected_weather_variables,
  selected_environment_groups,
  selected_environment_group_buffers,
  selected_environment_group_buffers_final,
  selected_environment_table,
  selected_environment_variables,
  final_variables,
  weather_forward,
  weather_backward,
  environment_forward,
  final_result,
  sensitivity_result,
  file = file.path(
    modelDir,
    "HMSC_annual_three_species_weather_environment_buffers_results.RData"
  )
)

#========================================================
# 12. Yksi selkeä tulosobjekti ja esitykseen sopiva yhteenveto
#========================================================

PRIMARY_RESULTS <- list(
  role = "PRIMARY_ANNUAL_EXPLANATORY_HMSC",
  script_revision = script_revision,
  analysis_version = analysis_version,
  response_definition = paste0(
    "annual total_count with Loff = log(total_effort_days / ",
    annual_index_standard_days, ")"
  ),
  distribution = hmsc_distribution,
  offset_definition = paste0(
    "log(total_effort_days / ", annual_index_standard_days, ")"
  ),
  spline_terms = character(0),
  beta_scale = paste(
    "change in log expected count per predictor SD",
    "(YScale=FALSE; predictors scaled explicitly; effort held through Loff)"
  ),
  species = target_species,
  n_samples = final_result$n_samples,
  response_distribution = response_distribution,
  zero_fill_audit = zero_fill_audit,
  extreme_count_audit = extreme_count_audit,
  extreme_interval_audit = extreme_interval_audit,
  extreme_count_flags = extreme_count_flags,
  selected_weather_groups = selected_weather_groups,
  selected_weather_variables = selected_weather_variables,
  buffer_selection = buffer_selection$comparisons,
  selected_buffers = buffer_selection$winners,
  selected_environment_groups = selected_environment_groups,
  selected_environment_variables = selected_environment_table,
  final_variables = final_variables,
  explanatory_metrics = final_result$metrics,
  posterior_predictive_check = final_result$posterior_predictive_check,
  beta_parameters = final_result$beta_table,
  supported_effects_95 = if (is.null(final_result$beta_table)) {
    data.frame()
  } else {
    final_result$beta_table %>%
      filter(
        supported,
        predictor %in% final_variables
      ) %>%
      arrange(species, desc(posterior_support), predictor)
  },
  variance_partitioning = final_result$variance_partitioning,
  without_autumnata_sensitivity = sensitivity_result
)

saveRDS(
  PRIMARY_RESULTS,
  file.path(modelDir, "PRIMARY_ANNUAL_RESULTS.rds")
)

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

presentation_effects <- if (nrow(PRIMARY_RESULTS$supported_effects_95) > 0L) {
  PRIMARY_RESULTS$supported_effects_95 %>%
    select(
      species, predictor, posterior_mean, direction,
      posterior_support
    )
} else {
  data.frame(
    species = character(0), predictor = character(0),
    posterior_mean = numeric(0), direction = character(0),
    posterior_support = numeric(0), stringsAsFactors = FALSE
  )
}

presentation_lines <- c(
  "# Primary analysis: annual explanatory Hmsc model",
  "",
  "## Workflow",
  "",
  paste0("1. The annual response for each species was the total annual count. Trapping effort was included as Loff = log(total effort days / ", annual_index_standard_days, ")."),
  "2. Counts were analysed jointly with a lognormally overdispersed Poisson Hmsc model. Counts were not scaled; continuous predictors were standardised.",
  "3. The sampling unit was a site-year. Site and year were included as random levels; flight-week and spline terms were not used.",
  "4. Weather groups were selected using explanatory SR2, followed by group-protected backward elimination.",
  "5. One spatial buffer was first selected for each environmental group using identical site-years for all buffer candidates within that group.",
  "6. Environmental groups at their selected buffer scales were evaluated on top of the locked weather model, and the final model was fitted with the longer MCMC settings.",
  "7. Species-specific coefficients, posterior support, explanatory SR2, occurrence metrics, posterior predictive checks, convergence diagnostics, and variance partitioning were extracted from the final model.",
  "",
  "## Data and selected variables",
  "",
  paste0("- Species: ", paste(target_species, collapse = ", ")),
  paste0("- Site-years in the final model: ", final_result$n_samples),
  paste0("- Selected weather groups: ", ifelse(length(selected_weather_groups) == 0L, "none", paste(selected_weather_groups, collapse = ", "))),
  paste0("- Selected weather variables: ", ifelse(length(selected_weather_variables) == 0L, "none", paste(selected_weather_variables, collapse = ", "))),
  paste0("- Selected environmental groups: ", ifelse(length(selected_environment_groups) == 0L, "none", paste(selected_environment_groups, collapse = ", "))),
  "",
  "### Selected environmental groups and buffers",
  "",
  markdown_table(selected_environment_group_buffers_final),
  "",
  "## Explanatory model fit by species",
  "",
  markdown_table(final_result$metrics),
  "",
  "## Posterior predictive check",
  "",
  markdown_table(final_result$posterior_predictive_check),
  "",
  "## Ecological effects with posterior support of at least 0.95",
  "",
  markdown_table(presentation_effects),
  "",
  "## Variance partitioning",
  "",
  markdown_table(final_result$variance_partitioning),
  "",
  "## Scope of interpretation",
  "",
  "These results describe within-sample explanatory power and conditional ecological associations. Predictive performance must be evaluated later in a separate cross-validation analysis of the locked model."
)

writeLines(
  presentation_lines,
  file.path(modelDir, "PRESENTATION_ANNUAL_PRIMARY_METHODS_AND_RESULTS.md")
)

cat("\n========================================================\n")
cat("KOKO ANALYYSI VALMIS\n")
cat("Skriptin revisio:", script_revision, "\n")
cat("Lajit:", paste(target_species, collapse = ", "), "\n")
cat("Sääryhmät:", paste(selected_weather_groups, collapse = ", "), "\n")
cat("Säämuuttujia:", length(selected_weather_variables), "\n")
cat(
  "Ympäristöryhmät:",
  ifelse(
    length(selected_environment_groups) == 0,
    "ei yhtään",
    paste(selected_environment_groups, collapse = ", ")
  ),
  "\n"
)
cat("Ympäristömuuttujia:", length(selected_environment_variables), "\n")
cat("Valitut ympäristöryhmät ja bufferit:\n")
print(selected_environment_group_buffers_final)
cat("\nLopullisen vuosimallin explanatory SR2, RMSE ja esiintymismetriikat:\n")
print(final_result$metrics, row.names = FALSE)
cat("\nPosterior predictive -tarkistus:\n")
print(final_result$posterior_predictive_check, row.names = FALSE)
cat("\nVahvasti tuetut ekologiset vaikutukset (posterior support >= ",
    posterior_support_threshold, "):\n", sep = "")
print(PRIMARY_RESULTS$supported_effects_95, row.names = FALSE)
cat("\nVarianssiositus:\n")
print(final_result$variance_partitioning, row.names = FALSE)

writeLines(
  capture.output(sessionInfo()),
  con = file.path(modelDir, "sessionInfo.txt")
)
cat("Tulokset:", modelDir, "\n")
cat("Koonti R:ssä: PRIMARY_RESULTS\n")
cat("Tallennettu koonti: PRIMARY_ANNUAL_RESULTS.rds\n")
cat("Esitysyhteenveto: PRESENTATION_ANNUAL_PRIMARY_METHODS_AND_RESULTS.md\n")
cat("========================================================\n")
