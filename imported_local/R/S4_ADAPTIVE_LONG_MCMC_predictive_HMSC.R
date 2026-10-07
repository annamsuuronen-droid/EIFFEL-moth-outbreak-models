#===============================================================================
# S4: PREDICTIVE HMSC - ADAPTIIVINEN PITKA MCMC-AJO
#===============================================================================
#
# TARKOITUS
#   S1/S2 valitsee lopullisen WEATHER + ENVIRONMENT -mallirakenteen.
#   S3 arvioi koko valintaputken aidon out-of-sample ennustekyvyn nested/outer CV:lla.
#   S4 EI valitse enaa muuttujia eika tee uutta cross-validationia.
#
#   S4 sovittaa koko kaytettavissa olevalle lopulliselle matched-aineistolle
#   lukitun predictive Hmsc -mallin pitkillä MCMC-ajoilla. Ajo pitenee vain,
#   jos posteriorin konvergenssi / Monte Carlo -tarkkuus ei ole riittava.
#
# ADAPTIIVINEN LOGIIKKA
#   1. Aloita 10 000 posteriorinaytteella / ketju.
#   2. Tulosta jokaisen ajon jalkeen konsoliin:
#        - MCMC-asetukset
#        - Beta-posteriorit
#        - komponenttikohtaiset R-hat- ja ESS-yhteenvedot
#        - huonoimmin konvergoivat parametrit
#        - offset-tietoinen mallisovitus
#        - posterior predictive check (PPC)
#        - eksplisiittinen johtopaatos riittavyydesta
#   3. Jos R-hat on huono -> pidennä erityisesti transienttia ja myos ajoa.
#   4. Jos R-hat on kunnossa mutta ESS pieni -> kasvata samples- ja thin-arvoja.
#   5. Jos MCMC on kunnossa mutta PPC huono -> tee korkeintaan yksi pidempi
#      varmistusajo. Jos PPC on edelleen huono, lopeta: pidempi MCMC ei korjaa
#      havaintomallin / mallirakenteen puutetta.
#   6. Kun MCMC ja PPC ovat riittavat, lopeta automaattisesti ja tallenna
#      kyseinen malli S4_FINAL_LONG_HMSC_MODEL.rds-tiedostoon.
#
# TULKINTA
#   - S3:n outer_year/outer_site-metriikat ovat mallin varsinainen predictive
#     validointi. S4:n in-sample fit ja PPC ovat diagnostisia.
#   - S4:n tehtava on varmistaa, etta lopullisen koko aineiston posteriori on
#     riittavan hyvin estimoitu julkaistavia kertoimia, varianssiositusta ja
#     posterioriyhteenvetoja varten.
#
# Vaste: vuotuinen kokonaislukumaara
# Jakauma: lognormal Poisson
# Offset: Loff = log(total_effort_days / 7)
# Satunnaistasot: site ja year
# Splineja: ei
#===============================================================================

gc()
set.seed(20261001)

#===============================================================================
# 1. KAYTTAJAN ASETUKSET
#===============================================================================

primary_output_dir <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1"
)

primary_rdata_file <- file.path(
  primary_output_dir,
  "HMSC_annual_three_species_weather_environment_buffers_results.RData"
)

selection_results_file <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "HMSC_ANNUAL_PREDICTIVE_ONE_BUFFER_MATCHED_ENVIRONMENT_SELECTION_v1",
  "HMSC_annual_predictive_one_buffer_matched_results.rds"
)

s3_results_file <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v1",
  "S3_NESTED_OUTER_CV_RESULTS.rds"
)

output_root <- file.path(
  "E:/EIFFEL uusi/hmsc_outputs",
  "S4_HMSC_ADAPTIVE_LONG_MCMC_PREDICTIVE_v1"
)

dir.create(output_root, recursive = TRUE, showWarnings = FALSE)

# TRUE = jos valmis stage löytyy, lue se levyltä äläkä sovita uudelleen.
resume_from_checkpoints <- TRUE

# TRUE = tallenna jokaisen vaiheen Hmsc-malli. Pitkat mallit voivat olla isoja.
save_all_stage_models <- TRUE

#--------------------------------------------------------
# Ensimmainen pitka ajo
#--------------------------------------------------------
initial_mcmc <- list(
  samples = 10000L,
  transient = 20000L,
  thin = 20L,
  chains = 4L,
  parallel = 4L
)

# Enintaan nain monta adaptiivista pitkaa ajoa.
max_stages <- 4L

# Turvarajat automaattiselle pidentamiselle.
max_samples <- 40000L
max_transient <- 80000L
max_thin <- 80L

# Yksi ylimaarainen vahvistusajo sallitaan, jos MCMC on jo kunnossa mutta PPC
# vaatii tarkistusta. Sen jalkeen pidempaa MCMC:ta ei jatketa PPC:n vuoksi.
max_ppc_confirmation_stages <- 1L

stage_seed_base <- 20261000L

#--------------------------------------------------------
# Konvergenssin riittavyyskriteerit
#--------------------------------------------------------
# Hmsc/coda ei maarita yhtä universaalia rajaa, joten alla olevat ovat
# tarkoituksella konservatiivisia kaytannön kriteereja ja ne voi muuttaa.

rhat_point_target <- 1.05
rhat_upper_target <- 1.10
rhat_point_hard_limit <- 1.10

ess_target <- 400
ess_hard_minimum <- 100
ess_median_target <- 1000

good_parameter_fraction_target <- 0.95

# Kiinteiden vaikutusten Beta-parametrit ovat paatulkinnan kannalta kriittisia.
# Niille vaaditaan tiukempi ehto kuin koko parametrimassalle.
require_beta_strict <- TRUE

# FALSE = valvo paaasiallisesti Beta/Gamma/Omega-komponentteja kuten aiemmissa
# Hmsc-konvergenssikoosteissa. TRUE lisaa myos Lambda-lataukset varsinaiseen
# riittavyysarvioon, mika voi kasvattaa diagnostiikan kokoa ja laskenta-aikaa.
monitor_latent_parameters <- FALSE

#--------------------------------------------------------
# Ennuste- ja PPC-asetukset
#--------------------------------------------------------
max_prediction_draws_intermediate <- 500L
max_prediction_draws_final <- 1000L

# Jos TRUE, PPC on osa lopullista ADEQUATE-paatosta.
require_ppc_for_final_adequacy <- TRUE

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
# 3. YLEISET APUFUNKTIOT
#===============================================================================

safe_name <- function(x) {
  gsub("[^A-Za-z0-9_]+", "_", as.character(x))
}

write_csv2 <- function(x, path) {
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  if (ncol(x) == 0L) {
    x <- data.frame(status = "no_columns", stringsAsFactors = FALSE)
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

finite_quantile <- function(x, p) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  unname(quantile(x, probs = p, na.rm = TRUE, names = FALSE))
}

finite_max <- function(x) {
  x <- x[is.finite(x)]
  if (!length(x)) NA_real_ else max(x)
}

finite_min <- function(x) {
  x <- x[is.finite(x)]
  if (!length(x)) NA_real_ else min(x)
}

finite_median <- function(x) {
  x <- x[is.finite(x)]
  if (!length(x)) NA_real_ else median(x)
}

round_up_int <- function(x) {
  as.integer(max(1, ceiling(x)))
}

same_or_larger <- function(old, new) {
  as.integer(max(as.integer(old), as.integer(new)))
}

#===============================================================================
# 4. LATAA LOPULLINEN MUUTTUJAVALINTA, S3 JA VUOSIAINEISTO
#===============================================================================

if (!file.exists(primary_rdata_file)) {
  stop("Primary RData -tiedostoa ei loydy: ", primary_rdata_file)
}
if (!file.exists(selection_results_file)) {
  stop("Predictive S1/S2 C+D -tulosta ei loydy: ", selection_results_file)
}
if (!file.exists(s3_results_file)) {
  stop(
    "S3 nested outer CV -tulosta ei loydy: ", s3_results_file,
    "\nAja S3 ennen S4:aa."
  )
}

selection_results <- readRDS(selection_results_file)
S3_RESULTS <- readRDS(s3_results_file)

primary_env <- new.env(parent = globalenv())
loaded_primary <- load(primary_rdata_file, envir = primary_env)

required_primary_objects <- c(
  "Y_annual_all",
  "Loff_annual_all",
  "sample_metadata",
  "X_sample"
)
missing_primary <- setdiff(required_primary_objects, loaded_primary)
if (length(missing_primary) > 0L) {
  stop(
    "Primary RData -tiedostosta puuttuvat objektit: ",
    paste(missing_primary, collapse = ", ")
  )
}

Y_annual_all <- get("Y_annual_all", envir = primary_env)
Loff_annual_all <- get("Loff_annual_all", envir = primary_env)
sample_metadata <- get("sample_metadata", envir = primary_env)
X_sample <- get("X_sample", envir = primary_env)

locked_weather_variables <- unique(as.character(
  selection_results$locked_weather_variables
))
locked_weather_variables <- locked_weather_variables[
  !is.na(locked_weather_variables) & nzchar(locked_weather_variables)
]

selected_environment_table <- selection_results$selected_environment_variables
if (is.null(selected_environment_table)) {
  selected_environment_table <- data.frame()
}

if (
  is.data.frame(selected_environment_table) &&
  "model_variable" %in% names(selected_environment_table)
) {
  selected_environment_variables <- unique(as.character(
    selected_environment_table$model_variable
  ))
} else if (is.character(selected_environment_table)) {
  selected_environment_variables <- unique(selected_environment_table)
} else {
  selected_environment_variables <- character(0)
}
selected_environment_variables <- selected_environment_variables[
  !is.na(selected_environment_variables) & nzchar(selected_environment_variables)
]

final_model_variables <- unique(c(
  locked_weather_variables,
  selected_environment_variables
))

if (!length(final_model_variables)) {
  stop("Lopullisesta predictive-valinnasta ei loytynyt yhtaan mallimuuttujaa.")
}

missing_variables <- setdiff(final_model_variables, names(X_sample))
if (length(missing_variables) > 0L) {
  stop(
    "Lopullisia mallimuuttujia puuttuu X_sample-taulusta: ",
    paste(missing_variables, collapse = ", ")
  )
}

final_ids_requested <- as.character(selection_results$final_sample_ids)
if (!length(final_ids_requested)) {
  stop("S1/S2 C+D -tuloksesta puuttuvat final_sample_ids.")
}

common_ids <- Reduce(
  intersect,
  list(
    final_ids_requested,
    rownames(Y_annual_all),
    rownames(Loff_annual_all),
    as.character(sample_metadata$sample_id),
    as.character(X_sample$sample_id)
  )
)
common_ids <- final_ids_requested[final_ids_requested %in% common_ids]

if (!length(common_ids)) {
  stop("Lopulliselle mallille ei loytynyt yhteisia sample_id-riveja.")
}

md_rows <- match(common_ids, sample_metadata$sample_id)
x_rows <- match(common_ids, X_sample$sample_id)

predictor_ok <- apply(
  as.matrix(X_sample[x_rows, final_model_variables, drop = FALSE]),
  1,
  function(z) all(is.finite(z))
)
y_ok <- rowSums(is.finite(Y_annual_all[common_ids, , drop = FALSE])) > 0L
offset_ok <- apply(
  Loff_annual_all[common_ids, , drop = FALSE],
  1,
  function(z) all(is.finite(z))
)

final_ids <- common_ids[predictor_ok & y_ok & offset_ok]
if (length(final_ids) < 20L) {
  stop("S4:n lopulliseen matched-aineistoon jai alle 20 paikkavuotta.")
}

sample_metadata_final <- sample_metadata[
  match(final_ids, sample_metadata$sample_id),
  ,
  drop = FALSE
]
X_raw_final <- X_sample[
  match(final_ids, X_sample$sample_id),
  c("sample_id", final_model_variables),
  drop = FALSE
]
Y_final <- Y_annual_all[final_ids, , drop = FALSE]
Loff_final <- Loff_annual_all[final_ids, colnames(Y_final), drop = FALSE]

storage.mode(Y_final) <- "numeric"
storage.mode(Loff_final) <- "numeric"
dimnames(Loff_final) <- dimnames(Y_final)

if (any(Y_final < 0, na.rm = TRUE)) {
  stop("Poisson-vasteessa on negatiivisia arvoja.")
}
finite_y <- is.finite(Y_final)
if (any(abs(Y_final[finite_y] - round(Y_final[finite_y])) > 1e-8)) {
  stop("Lognormal Poisson -vaste sisaltaa ei-kokonaislukuarvoja.")
}
Y_final[finite_y] <- round(Y_final[finite_y])

# Poista mahdolliset nollavarianssimuuttujat lopullisella matched-paneelilla.
variable_sd <- vapply(
  final_model_variables,
  function(v) sd(X_raw_final[[v]], na.rm = TRUE),
  numeric(1)
)
variables_kept <- final_model_variables[
  is.finite(variable_sd) & variable_sd > 0
]
variables_removed_zero_variance <- setdiff(final_model_variables, variables_kept)

if (length(variables_removed_zero_variance) > 0L) {
  warning(
    "S4 poisti lopulliselta paneelilta nollavarianssimuuttujat: ",
    paste(variables_removed_zero_variance, collapse = ", ")
  )
}

if (length(variables_kept) > 0L) {
  scaling_mean <- vapply(
    X_raw_final[, variables_kept, drop = FALSE],
    mean,
    numeric(1),
    na.rm = TRUE
  )
  scaling_sd <- vapply(
    X_raw_final[, variables_kept, drop = FALSE],
    sd,
    numeric(1),
    na.rm = TRUE
  )
  X_scaled_final <- as.data.frame(lapply(variables_kept, function(v) {
    (X_raw_final[[v]] - scaling_mean[[v]]) / scaling_sd[[v]]
  }))
  names(X_scaled_final) <- variables_kept
  X_formula <- reformulate(variables_kept)
} else {
  scaling_mean <- numeric(0)
  scaling_sd <- numeric(0)
  X_scaled_final <- data.frame(intercept_helper = rep(0, length(final_ids)))
  X_formula <- ~ 1
}
rownames(X_scaled_final) <- final_ids

if (any(!is.finite(as.matrix(X_scaled_final)))) {
  stop("Standardoinnin jalkeen S4:n X-matriisiin jai NA/Inf-arvoja.")
}

studyDesign_final <- data.frame(
  site = factor(sample_metadata_final$site),
  year = factor(sample_metadata_final$year)
)
rownames(studyDesign_final) <- final_ids

ranLevels_final <- list(
  site = HmscRandomLevel(units = levels(studyDesign_final$site)),
  year = HmscRandomLevel(units = levels(studyDesign_final$year))
)

hmsc_distribution <- "lognormal poisson"

model_unfitted_template <- Hmsc(
  Y = Y_final,
  distr = rep(hmsc_distribution, ncol(Y_final)),
  Loff = Loff_final,
  XData = X_scaled_final,
  XScale = FALSE,
  YScale = FALSE,
  XFormula = X_formula,
  studyDesign = studyDesign_final,
  ranLevels = ranLevels_final
)

model_definition <- data.frame(
  n_site_years = nrow(Y_final),
  n_sites = n_distinct(sample_metadata_final$site),
  n_years = n_distinct(sample_metadata_final$year),
  first_year = min(sample_metadata_final$year),
  last_year = max(sample_metadata_final$year),
  n_species = ncol(Y_final),
  n_weather_variables = sum(variables_kept %in% locked_weather_variables),
  n_environment_variables = sum(variables_kept %in% selected_environment_variables),
  n_total_variables = length(variables_kept),
  distribution = hmsc_distribution,
  stringsAsFactors = FALSE
)

write_csv2(model_definition, file.path(output_root, "S4_model_definition.csv2"))
write_csv2(
  data.frame(variable = variables_kept, stringsAsFactors = FALSE),
  file.path(output_root, "S4_final_model_variables.csv2")
)
write_csv2(
  data.frame(sample_id = final_ids, stringsAsFactors = FALSE),
  file.path(output_root, "S4_final_sample_ids.csv2")
)
write_csv2(
  data.frame(
    variable = names(scaling_mean),
    mean = as.numeric(scaling_mean),
    sd = as.numeric(scaling_sd),
    stringsAsFactors = FALSE
  ),
  file.path(output_root, "S4_predictor_scaling.csv2")
)

cat("\n===============================================================================\n")
cat("S4: LUKITTU LOPULLINEN PREDICTIVE-MALLI\n")
cat("===============================================================================\n")
print(model_definition, row.names = FALSE)
cat("\nSaamuuttujat:\n")
print(intersect(variables_kept, locked_weather_variables))
cat("\nYmparistomuuttujat:\n")
print(intersect(variables_kept, selected_environment_variables))

cat("\nS3:n nested outer CV -tulos pidetaan erillisena predictive-validointina.\n")
if (!is.null(S3_RESULTS$pooled_outer_metrics)) {
  print(S3_RESULTS$pooled_outer_metrics, row.names = FALSE)
}

#===============================================================================
# 5. BETA-POSTERIORI
#===============================================================================

beta_table_from_model_s4 <- function(model_fitted) {
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

  if (
    !identical(dim(beta_mean), expected_dim) ||
    !identical(dim(beta_support), expected_dim)
  ) {
    stop(
      "Beta-posteriorin dimensio ei vastaa mallia. mean=",
      paste(dim(beta_mean), collapse = "x"),
      ", support=", paste(dim(beta_support), collapse = "x"),
      ", odotettu=", paste(expected_dim, collapse = "x")
    )
  }

  bind_rows(lapply(seq_along(predictor_names), function(i) {
    data.frame(
      predictor = predictor_names[i],
      species = species_names,
      posterior_mean = as.numeric(beta_mean[i, ]),
      support_positive = as.numeric(beta_support[i, ]),
      support_negative = 1 - as.numeric(beta_support[i, ]),
      posterior_support = pmax(
        as.numeric(beta_support[i, ]),
        1 - as.numeric(beta_support[i, ])
      ),
      stringsAsFactors = FALSE
    )
  }))
}

#===============================================================================
# 6. CODA / KONVERGENSSID IAGNOSTIIKKA
#===============================================================================

convert_coda_s4 <- function(model_fitted) {
  # Hmsc:n nykyinen convertToCodaObject() tarvitsee Eta- tai Lambda-rakenteen
  # Omega-parametrien latenttifaktorimäärän tunnistamiseen. Kaytetaan Lambdaa,
  # mutta se otetaan varsinaiseen riittavyysarvioon vain, jos
  # monitor_latent_parameters = TRUE.
  raw <- convertToCodaObject(
    model_fitted,
    Beta = TRUE,
    Gamma = TRUE,
    V = FALSE,
    Sigma = FALSE,
    rho = FALSE,
    Eta = FALSE,
    Lambda = TRUE,
    alpha = FALSE,
    Omega = TRUE,
    Psi = FALSE,
    Delta = FALSE
  )

  flattened <- list()
  random_level_names <- model_fitted$rLNames
  if (is.null(random_level_names)) {
    random_level_names <- paste0("random", seq_len(model_fitted$nr))
  }

  for (component in names(raw)) {
    obj <- raw[[component]]

    if (inherits(obj, "mcmc.list")) {
      if (component != "Lambda" || monitor_latent_parameters) {
        flattened[[component]] <- obj
      }
      next
    }

    # Eta/Lambda/Omega/alpha/Psi/Delta ovat Hmsc:ssa satunnaistasoittaisia
    # listoja. Omega halutaan aina mukaan; Lambda vain valinnaisesti.
    if (is.list(obj)) {
      if (component == "Lambda" && !monitor_latent_parameters) next
      if (!component %in% c("Omega", "Lambda")) next

      for (r in seq_along(obj)) {
        if (!inherits(obj[[r]], "mcmc.list")) next
        level_name <- if (r <= length(random_level_names)) {
          safe_name(random_level_names[r])
        } else {
          paste0("random", r)
        }
        flattened[[paste0(component, "_", level_name)]] <- obj[[r]]
      }
    }
  }

  flattened
}

component_parameter_diagnostics <- function(component_name, obj) {
  if (!inherits(obj, "mcmc.list")) {
    return(data.frame())
  }

  parameter_names <- colnames(as.matrix(obj[[1]]))
  if (is.null(parameter_names)) {
    parameter_names <- paste0("parameter_", seq_len(ncol(as.matrix(obj[[1]]))))
  }

  gelman <- tryCatch(
    gelman.diag(
      obj,
      multivariate = FALSE,
      autoburnin = FALSE
    )$psrf,
    error = function(e) NULL
  )

  ess <- tryCatch(
    effectiveSize(obj),
    error = function(e) NULL
  )

  out <- data.frame(
    component = component_name,
    parameter = parameter_names,
    rhat_point = NA_real_,
    rhat_upper = NA_real_,
    ESS = NA_real_,
    stringsAsFactors = FALSE
  )

  if (!is.null(gelman)) {
    gelman <- as.matrix(gelman)
    g_names <- rownames(gelman)
    if (is.null(g_names) && nrow(gelman) == nrow(out)) {
      g_names <- out$parameter
    }
    if (!is.null(g_names)) {
      idx <- match(out$parameter, g_names)
      ok <- !is.na(idx)
      out$rhat_point[ok] <- as.numeric(gelman[idx[ok], 1])
      if (ncol(gelman) >= 2L) {
        out$rhat_upper[ok] <- as.numeric(gelman[idx[ok], 2])
      }
    }
  }

  if (!is.null(ess)) {
    ess <- as.numeric(ess)
    ess_names <- names(tryCatch(effectiveSize(obj), error = function(e) NULL))
    if (!is.null(ess_names)) {
      idx <- match(out$parameter, ess_names)
      ok <- !is.na(idx)
      out$ESS[ok] <- ess[idx[ok]]
    } else if (length(ess) == nrow(out)) {
      out$ESS <- ess
    }
  }

  out
}

convergence_diagnostics_s4 <- function(model_fitted) {
  coda_objects <- tryCatch(
    convert_coda_s4(model_fitted),
    error = function(e) {
      warning("convertToCodaObject() epaonnistui: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(coda_objects)) {
    return(list(
      parameters = data.frame(),
      components = data.frame(),
      coda_objects = NULL
    ))
  }

  parameter_tables <- lapply(names(coda_objects), function(component) {
    component_parameter_diagnostics(component, coda_objects[[component]])
  })
  names(parameter_tables) <- names(coda_objects)
  parameter_table <- bind_rows(parameter_tables)

  if (!nrow(parameter_table)) {
    return(list(
      parameters = parameter_table,
      components = data.frame(),
      coda_objects = coda_objects
    ))
  }

  component_table <- parameter_table %>%
    group_by(.data$component) %>%
    summarise(
      n_parameters = n(),
      n_rhat = sum(is.finite(.data$rhat_point)),
      median_rhat = finite_median(.data$rhat_point),
      q95_rhat = finite_quantile(.data$rhat_point, 0.95),
      max_rhat = finite_max(.data$rhat_point),
      median_rhat_upper = finite_median(.data$rhat_upper),
      max_rhat_upper = finite_max(.data$rhat_upper),
      min_ESS = finite_min(.data$ESS),
      q05_ESS = finite_quantile(.data$ESS, 0.05),
      median_ESS = finite_median(.data$ESS),
      fraction_rhat_good = ifelse(
        sum(is.finite(.data$rhat_point) & is.finite(.data$rhat_upper)) > 0L,
        mean(
          .data$rhat_point[is.finite(.data$rhat_point) & is.finite(.data$rhat_upper)] <=
            rhat_point_target &
          .data$rhat_upper[is.finite(.data$rhat_point) & is.finite(.data$rhat_upper)] <=
            rhat_upper_target
        ),
        NA_real_
      ),
      fraction_ESS_good = ifelse(
        sum(is.finite(.data$ESS)) > 0L,
        mean(.data$ESS[is.finite(.data$ESS)] >= ess_target),
        NA_real_
      ),
      .groups = "drop"
    )

  list(
    parameters = parameter_table,
    components = component_table,
    coda_objects = coda_objects
  )
}

assess_mcmc_sufficiency <- function(convergence) {
  p <- convergence$parameters
  ctab <- convergence$components

  reasons <- character(0)
  if (!nrow(p) || !nrow(ctab)) {
    return(list(
      sufficient = FALSE,
      reasons = "Konvergenssidiagnostiikkaa ei voitu muodostaa.",
      max_rhat = NA_real_,
      max_rhat_upper = NA_real_,
      min_ESS = NA_real_,
      median_ESS = NA_real_,
      fraction_rhat_good = NA_real_,
      fraction_ESS_good = NA_real_,
      beta_ok = FALSE
    ))
  }

  valid_rhat <- is.finite(p$rhat_point) & is.finite(p$rhat_upper)
  valid_ess <- is.finite(p$ESS)

  max_rhat <- finite_max(p$rhat_point)
  max_rhat_upper <- finite_max(p$rhat_upper)
  min_ESS <- finite_min(p$ESS)
  median_ESS <- finite_median(p$ESS)

  fraction_rhat_good <- if (any(valid_rhat)) {
    mean(
      p$rhat_point[valid_rhat] <= rhat_point_target &
        p$rhat_upper[valid_rhat] <= rhat_upper_target
    )
  } else {
    NA_real_
  }

  fraction_ESS_good <- if (any(valid_ess)) {
    mean(p$ESS[valid_ess] >= ess_target)
  } else {
    NA_real_
  }

  if (!is.finite(fraction_rhat_good) ||
      fraction_rhat_good < good_parameter_fraction_target) {
    reasons <- c(
      reasons,
      paste0(
        "Alle ", round(100 * good_parameter_fraction_target),
        " % parametreista tayttaa R-hat-kriteerin."
      )
    )
  }

  if (!is.finite(max_rhat) || max_rhat > rhat_point_hard_limit) {
    reasons <- c(
      reasons,
      paste0("Huonoin R-hat > ", rhat_point_hard_limit, ".")
    )
  }

  if (!is.finite(fraction_ESS_good) ||
      fraction_ESS_good < good_parameter_fraction_target) {
    reasons <- c(
      reasons,
      paste0(
        "Alle ", round(100 * good_parameter_fraction_target),
        " % parametreista saavuttaa ESS >= ", ess_target, "."
      )
    )
  }

  if (!is.finite(min_ESS) || min_ESS < ess_hard_minimum) {
    reasons <- c(
      reasons,
      paste0("Pienin ESS < ", ess_hard_minimum, ".")
    )
  }

  if (!is.finite(median_ESS) || median_ESS < ess_median_target) {
    reasons <- c(
      reasons,
      paste0("Mediaani-ESS < ", ess_median_target, ".")
    )
  }

  beta <- p[p$component == "Beta", , drop = FALSE]
  beta_ok <- TRUE
  if (require_beta_strict) {
    if (!nrow(beta)) {
      beta_ok <- FALSE
      reasons <- c(reasons, "Beta-konvergenssidiagnostiikka puuttuu.")
    } else {
      beta_valid <- is.finite(beta$rhat_point) & is.finite(beta$rhat_upper) &
        is.finite(beta$ESS)
      beta_ok <- all(beta_valid) &&
        all(beta$rhat_point <= rhat_point_target) &&
        all(beta$rhat_upper <= rhat_upper_target) &&
        all(beta$ESS >= ess_target)
      if (!beta_ok) {
        reasons <- c(
          reasons,
          paste0(
            "Kaikki Beta-parametrit eivat tayta ehtoja R-hat <= ",
            rhat_point_target, ", upper <= ", rhat_upper_target,
            " ja ESS >= ", ess_target, "."
          )
        )
      }
    }
  }

  list(
    sufficient = length(reasons) == 0L,
    reasons = if (length(reasons)) paste(unique(reasons), collapse = " ") else
      "MCMC-konvergenssi ja Monte Carlo -tarkkuus tayttavat asetetut kriteerit.",
    max_rhat = max_rhat,
    max_rhat_upper = max_rhat_upper,
    min_ESS = min_ESS,
    median_ESS = median_ESS,
    fraction_rhat_good = fraction_rhat_good,
    fraction_ESS_good = fraction_ESS_good,
    beta_ok = beta_ok
  )
}

#===============================================================================
# 7. OFFSET-TIETOINEN ENNUSTE, FIT JA PPC
#===============================================================================

posterior_subset_s4 <- function(model_fitted, maximum_draws) {
  post <- poolMcmcChains(model_fitted$postList, start = 1L, thin = 1L)
  if (length(post) > maximum_draws) {
    keep <- unique(round(seq(1, length(post), length.out = maximum_draws)))
    post <- post[keep]
  }
  post
}

as_prediction_array_s4 <- function(predicted, n_rows, n_species, n_draws) {
  predicted <- as.array(predicted)
  d <- dim(predicted)
  if (identical(as.integer(d), as.integer(c(n_rows, n_species, n_draws)))) {
    return(predicted)
  }

  permutations <- list(
    c(1L, 3L, 2L), c(2L, 1L, 3L), c(2L, 3L, 1L),
    c(3L, 1L, 2L), c(3L, 2L, 1L)
  )
  for (perm in permutations) {
    candidate <- aperm(predicted, perm)
    if (identical(
      as.integer(dim(candidate)),
      as.integer(c(n_rows, n_species, n_draws))
    )) {
      return(candidate)
    }
  }

  stop(
    "Ennustearrayn dimensioita ei voitu jarjestaa. Saatu: ",
    paste(d, collapse = "x"),
    ", odotettu: ", paste(c(n_rows, n_species, n_draws), collapse = "x")
  )
}

predict_array_s4 <- function(model_fitted, post, expected, seed) {
  set.seed(seed)
  pred_list <- predict(
    model_fitted,
    post = post,
    Loff = model_fitted$Loff,
    expected = expected,
    nParallel = 1L
  )
  predicted <- simplify2array(pred_list)
  as_prediction_array_s4(
    predicted,
    n_rows = nrow(model_fitted$Y),
    n_species = ncol(model_fitted$Y),
    n_draws = length(post)
  )
}

extract_fit_metric_s4 <- function(x, n_species) {
  if (is.null(x)) return(rep(NA_real_, n_species))
  if (is.matrix(x) || is.array(x)) {
    if (length(x) == n_species) x <- as.vector(x)
  }
  x <- as.numeric(x)
  if (length(x) != n_species) rep(NA_real_, n_species) else x
}

fit_metrics_s4 <- function(model_fitted, pred_expected) {
  mf <- evaluateModelFit(hM = model_fitted, predY = pred_expected)
  n_species <- ncol(model_fitted$Y)
  data.frame(
    species = colnames(model_fitted$Y),
    RMSE = extract_fit_metric_s4(mf$RMSE, n_species),
    SR2 = extract_fit_metric_s4(mf$SR2, n_species),
    C.RMSE = extract_fit_metric_s4(mf$C.RMSE, n_species),
    C.SR2 = extract_fit_metric_s4(mf$C.SR2, n_species),
    stringsAsFactors = FALSE
  )
}

ppc_interval_s4 <- function(simulated, observed) {
  simulated <- simulated[is.finite(simulated)]
  if (!length(simulated) || !is.finite(observed)) {
    return(c(
      q025 = NA_real_, median = NA_real_, q975 = NA_real_,
      covered = NA_real_, p_value = NA_real_
    ))
  }
  interval <- quantile(simulated, c(0.025, 0.5, 0.975), na.rm = TRUE)
  p_value <- min(
    1,
    2 * min(
      mean(simulated <= observed, na.rm = TRUE),
      mean(simulated >= observed, na.rm = TRUE)
    )
  )
  c(
    q025 = unname(interval[1]),
    median = unname(interval[2]),
    q975 = unname(interval[3]),
    covered = as.numeric(observed >= interval[1] && observed <= interval[3]),
    p_value = p_value
  )
}

posterior_predictive_check_s4 <- function(model_fitted, pred_realized) {
  Y <- model_fitted$Y

  bind_rows(lapply(seq_len(ncol(Y)), function(j) {
    observed <- Y[, j]
    keep <- is.finite(observed)
    observed <- observed[keep]
    simulated <- matrix(
      pred_realized[keep, j, , drop = FALSE],
      nrow = sum(keep),
      ncol = dim(pred_realized)[3]
    )

    draw_mean <- colMeans(simulated, na.rm = TRUE)
    draw_zero <- colMeans(simulated == 0, na.rm = TRUE)
    draw_q95 <- apply(
      simulated, 2, quantile, probs = 0.95, na.rm = TRUE, names = FALSE
    )
    draw_q99 <- apply(
      simulated, 2, quantile, probs = 0.99, na.rm = TRUE, names = FALSE
    )
    draw_max <- apply(simulated, 2, max, na.rm = TRUE)

    mean_check <- ppc_interval_s4(draw_mean, mean(observed, na.rm = TRUE))
    zero_check <- ppc_interval_s4(draw_zero, mean(observed == 0, na.rm = TRUE))
    q95_check <- ppc_interval_s4(
      draw_q95,
      unname(quantile(observed, 0.95, na.rm = TRUE))
    )
    q99_check <- ppc_interval_s4(
      draw_q99,
      unname(quantile(observed, 0.99, na.rm = TRUE))
    )
    max_check <- ppc_interval_s4(draw_max, max(observed, na.rm = TRUE))

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
      max_check["covered"]
    ) == 1))

    ppc_status <- if (core_ok && tail_ok) {
      "OK"
    } else if (central_and_zero_ok && (!core_ok || !tail_ok)) {
      "UPPER_TAIL_REQUIRES_REVIEW"
    } else {
      "REQUIRES_REVIEW"
    }

    data.frame(
      species = colnames(Y)[j],
      n = length(observed),
      posterior_predictive_draws = ncol(simulated),
      observed_mean = mean(observed, na.rm = TRUE),
      predicted_mean_q025 = mean_check["q025"],
      predicted_mean_median = mean_check["median"],
      predicted_mean_q975 = mean_check["q975"],
      mean_covered_95 = as.logical(mean_check["covered"]),
      mean_ppc_p = mean_check["p_value"],
      observed_zero_proportion = mean(observed == 0, na.rm = TRUE),
      predicted_zero_q025 = zero_check["q025"],
      predicted_zero_median = zero_check["median"],
      predicted_zero_q975 = zero_check["q975"],
      zero_covered_95 = as.logical(zero_check["covered"]),
      zero_ppc_p = zero_check["p_value"],
      observed_q95 = unname(quantile(observed, 0.95, na.rm = TRUE)),
      predicted_q95_q025 = q95_check["q025"],
      predicted_q95_median = q95_check["median"],
      predicted_q95_q975 = q95_check["q975"],
      q95_covered_95 = as.logical(q95_check["covered"]),
      q95_ppc_p = q95_check["p_value"],
      observed_q99 = unname(quantile(observed, 0.99, na.rm = TRUE)),
      predicted_q99_q025 = q99_check["q025"],
      predicted_q99_median = q99_check["median"],
      predicted_q99_q975 = q99_check["q975"],
      q99_covered_95 = as.logical(q99_check["covered"]),
      q99_ppc_p = q99_check["p_value"],
      observed_maximum = max(observed, na.rm = TRUE),
      predicted_maximum_q025 = max_check["q025"],
      predicted_maximum_median = max_check["median"],
      predicted_maximum_q975 = max_check["q975"],
      maximum_covered_95 = as.logical(max_check["covered"]),
      maximum_ppc_p = max_check["p_value"],
      ppc_status = ppc_status,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  }))
}

assess_ppc_s4 <- function(ppc_table) {
  if (is.null(ppc_table) || !nrow(ppc_table)) {
    return(list(
      sufficient = FALSE,
      status = "PPC_MISSING",
      reason = "Posterior predictive check puuttuu."
    ))
  }
  statuses <- unique(as.character(ppc_table$ppc_status))
  statuses <- statuses[!is.na(statuses) & nzchar(statuses)]

  if (length(statuses) && all(statuses == "OK")) {
    list(
      sufficient = TRUE,
      status = "PPC_OK",
      reason = "Kaikkien lajien PPC:n keskiarvo-, nolla-, q95-, q99- ja maksimikriteerit ovat kunnossa."
    )
  } else if (
    length(statuses) &&
    all(statuses %in% c("OK", "UPPER_TAIL_REQUIRES_REVIEW"))
  ) {
    list(
      sufficient = FALSE,
      status = "PPC_UPPER_TAIL_REQUIRES_REVIEW",
      reason = "PPC:n keski-/nollaosa on paaosin kunnossa, mutta jakauman ylapaa vaatii tarkistusta."
    )
  } else {
    list(
      sufficient = FALSE,
      status = "PPC_REQUIRES_REVIEW",
      reason = "Posterior predictive check osoittaa mallisovituksen puutteen yhdelle tai useammalle lajille."
    )
  }
}

#===============================================================================
# 8. VARIANSSIOSITUS JA WAIC LOPULLISELLE HYVAKSYTYLLE MALLILLE
#===============================================================================

make_vp_mapping_s4 <- function(model_fitted) {
  predictor_names <- colnames(model_fitted$X)
  if (is.null(predictor_names)) {
    stop("Mallin X-matriisilta puuttuvat sarakenimet variance partitioningia varten.")
  }

  group_name <- rep(NA_character_, length(predictor_names))
  names(group_name) <- predictor_names

  intercept_hits <- predictor_names %in% c("(Intercept)", "Intercept")
  group_name[intercept_hits] <- "Intercept"

  group_name[predictor_names %in% locked_weather_variables] <- "weather"

  if (length(selected_environment_variables) > 0L) {
    for (v in intersect(predictor_names, selected_environment_variables)) {
      ecological_group <- NA_character_
      if (
        is.data.frame(selected_environment_table) &&
        all(c("model_variable", "ecological_group") %in%
            names(selected_environment_table))
      ) {
        hit <- selected_environment_table$ecological_group[
          match(v, selected_environment_table$model_variable)
        ]
        if (length(hit) && !is.na(hit)) ecological_group <- as.character(hit)
      }
      if (is.na(ecological_group) || !nzchar(ecological_group)) {
        ecological_group <- "environment"
      }
      group_name[v] <- ecological_group
    }
  }

  # Joissain Hmsc-versioissa interceptin nimi voi olla ensimmainen X-sarake.
  if (is.na(group_name[1])) group_name[1] <- "Intercept"

  if (anyNA(group_name)) {
    stop(
      "Variance partitioning -ryhma puuttuu muuttujilta: ",
      paste(names(group_name)[is.na(group_name)], collapse = ", ")
    )
  }

  groupnames <- unique(unname(group_name))
  lookup <- setNames(seq_along(groupnames), groupnames)
  group <- unname(lookup[group_name])

  list(
    group = group,
    groupnames = groupnames,
    mapping = data.frame(
      predictor = predictor_names,
      group_name = unname(group_name),
      group_id = group,
      stringsAsFactors = FALSE
    )
  )
}

variance_partition_s4 <- function(model_fitted) {
  mapping <- make_vp_mapping_s4(model_fitted)
  VP <- computeVariancePartitioning(
    model_fitted,
    group = mapping$group,
    groupnames = mapping$groupnames
  )

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

  long <- data.frame(
    variance_source = source_names,
    values,
    row.names = NULL,
    check.names = FALSE
  ) %>%
    pivot_longer(
      cols = -"variance_source",
      names_to = "species",
      values_to = "variance_proportion"
    )

  list(VP = VP, mapping = mapping$mapping, long = long)
}

compute_waic_s4 <- function(model_fitted) {
  tryCatch(
    computeWAIC(model_fitted),
    error = function(e) {
      warning("WAIC:n laskenta epaonnistui: ", conditionMessage(e))
      NULL
    }
  )
}

#===============================================================================
# 9. YHDEN PITKAN STAGEN SOVITUS JA DIAGNOSTIIKKA
#===============================================================================

run_long_stage <- function(stage_index, mcmc, seed) {
  stage_name <- paste0("stage_", sprintf("%02d", stage_index))
  stage_dir <- file.path(output_root, stage_name)
  dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)

  checkpoint <- file.path(stage_dir, "STAGE_RESULT.rds")
  model_file <- file.path(stage_dir, "Hmsc_model.rds")

  if (resume_from_checkpoints && file.exists(checkpoint)) {
    cat("\nLuetaan valmis S4-stage checkpoint: ", checkpoint, "\n", sep = "")
    result <- readRDS(checkpoint)
    if (is.null(result$model) && file.exists(model_file)) {
      result$model <- readRDS(model_file)
    }
    return(result)
  }

  cat("\n===============================================================================\n")
  cat("S4 PITKA AJO ", stage_index, "\n", sep = "")
  cat("===============================================================================\n")
  cat("samples / chain : ", mcmc$samples, "\n", sep = "")
  cat("transient       : ", mcmc$transient, "\n", sep = "")
  cat("thin            : ", mcmc$thin, "\n", sep = "")
  cat("chains          : ", mcmc$chains, "\n", sep = "")
  cat("parallel        : ", mcmc$parallel, "\n", sep = "")
  cat(
    "MCMC steps / chain (approx): ",
    mcmc$transient + mcmc$samples * mcmc$thin,
    "\n",
    sep = ""
  )

  set.seed(seed)
  model_fitted <- sampleMcmc(
    model_unfitted_template,
    samples = mcmc$samples,
    transient = mcmc$transient,
    thin = mcmc$thin,
    nChains = mcmc$chains,
    nParallel = mcmc$parallel,
    verbose = max(100L, round_up_int((mcmc$transient + mcmc$samples * mcmc$thin) / 50)),
    alignPost = TRUE
  )

  if (save_all_stage_models) {
    saveRDS(model_fitted, model_file)
  }

  beta_table <- beta_table_from_model_s4(model_fitted)
  convergence <- convergence_diagnostics_s4(model_fitted)
  mcmc_assessment <- assess_mcmc_sufficiency(convergence)

  max_draws <- if (stage_index >= max_stages) {
    max_prediction_draws_final
  } else {
    max_prediction_draws_intermediate
  }
  post_eval <- posterior_subset_s4(model_fitted, max_draws)

  pred_expected <- predict_array_s4(
    model_fitted,
    post = post_eval,
    expected = TRUE,
    seed = seed + 100000L
  )
  fit_metrics <- fit_metrics_s4(model_fitted, pred_expected)
  rm(pred_expected)
  gc()

  pred_realized <- predict_array_s4(
    model_fitted,
    post = post_eval,
    expected = FALSE,
    seed = seed + 200000L
  )
  ppc_table <- posterior_predictive_check_s4(model_fitted, pred_realized)
  ppc_assessment <- assess_ppc_s4(ppc_table)
  rm(pred_realized)
  gc()

  write_csv2(beta_table, file.path(stage_dir, "beta_posterior.csv2"))
  write_csv2(
    convergence$parameters,
    file.path(stage_dir, "convergence_by_parameter.csv2")
  )
  write_csv2(
    convergence$components,
    file.path(stage_dir, "convergence_by_component.csv2")
  )
  write_csv2(fit_metrics, file.path(stage_dir, "offset_fit_metrics.csv2"))
  write_csv2(ppc_table, file.path(stage_dir, "posterior_predictive_check.csv2"))

  result <- list(
    stage = stage_index,
    mcmc = mcmc,
    seed = seed,
    model = model_fitted,
    model_file = if (save_all_stage_models) model_file else NA_character_,
    beta_table = beta_table,
    convergence_parameters = convergence$parameters,
    convergence_components = convergence$components,
    mcmc_assessment = mcmc_assessment,
    fit_metrics = fit_metrics,
    ppc_table = ppc_table,
    ppc_assessment = ppc_assessment,
    prediction_draws_used = length(post_eval)
  )

  # Checkpointiin ei tallenneta Hmsc-objektia toiseen kertaan, koska se voi olla
  # hyvin suuri. Malli on erillisessa Hmsc_model.rds-tiedostossa.
  checkpoint_result <- result
  checkpoint_result$model <- NULL
  saveRDS(checkpoint_result, checkpoint)
  result
}

#===============================================================================
# 10. KONSOLIRAPORTTI JA JOHTOPAATOS ENNEN SEURAAVAA AJOA
#===============================================================================

print_stage_report <- function(result) {
  cat("\n\n###############################################################################\n")
  cat("S4 STAGE ", result$stage, " - PARAMETRIT JA RIITTAVYYSARVIO\n", sep = "")
  cat("###############################################################################\n")

  cat("\nMCMC-ASETUKSET\n")
  print(as.data.frame(result$mcmc, stringsAsFactors = FALSE), row.names = FALSE)

  cat("\nBETA-POSTERIORIT\n")
  beta_print <- result$beta_table %>%
    mutate(
      posterior_mean = round(.data$posterior_mean, 4),
      support_positive = round(.data$support_positive, 4),
      support_negative = round(.data$support_negative, 4),
      posterior_support = round(.data$posterior_support, 4)
    )
  print(beta_print, row.names = FALSE)

  cat("\nKONVERGENSSI KOMPONENTEITTAIN\n")
  print(result$convergence_components, row.names = FALSE)

  cat("\nHUONOIMMIN KONVERGOIVAT PARAMETRIT (enintaan 20)\n")
  worst <- result$convergence_parameters %>%
    mutate(
      rhat_problem = ifelse(is.finite(.data$rhat_point), .data$rhat_point, Inf),
      ess_problem = ifelse(is.finite(.data$ESS), .data$ESS, -Inf)
    ) %>%
    arrange(desc(.data$rhat_problem), .data$ess_problem) %>%
    select(-.data$rhat_problem, -.data$ess_problem) %>%
    head(20)
  print(worst, row.names = FALSE)

  cat("\nOFFSET-TIETOINEN KOKO AINEISTON FIT (diagnostinen, EI S3:n korvike)\n")
  print(result$fit_metrics, row.names = FALSE)

  cat("\nPOSTERIOR PREDICTIVE CHECK\n")
  print(result$ppc_table, row.names = FALSE)

  cat("\n---------------- MCMC-JOHTOPAATOS ----------------\n")
  if (isTRUE(result$mcmc_assessment$sufficient)) {
    cat("MCMC: RIITTAVA\n")
  } else {
    cat("MCMC: EI VIELA RIITTAVA\n")
  }
  cat(result$mcmc_assessment$reasons, "\n")
  cat(
    "max R-hat = ", round(result$mcmc_assessment$max_rhat, 4),
    "; max upper = ", round(result$mcmc_assessment$max_rhat_upper, 4),
    "; min ESS = ", round(result$mcmc_assessment$min_ESS, 1),
    "; median ESS = ", round(result$mcmc_assessment$median_ESS, 1),
    "\n",
    sep = ""
  )

  cat("\n---------------- MALLISOVITUKSEN JOHTOPAATOS ----------------\n")
  if (isTRUE(result$ppc_assessment$sufficient)) {
    cat("PPC: RIITTAVA\n")
  } else {
    cat("PPC: VAATII TARKISTUSTA\n")
  }
  cat(result$ppc_assessment$reason, "\n")

  final_ok <- isTRUE(result$mcmc_assessment$sufficient) &&
    (!require_ppc_for_final_adequacy || isTRUE(result$ppc_assessment$sufficient))

  cat("\n================ KOKONAISJOHTOPAATOS ================\n")
  if (final_ok) {
    cat("MALLIN PITKAN AJON RIITTAVYYS: RIITTAVA.\n")
    cat("S4 voi lopettaa; pidempi MCMC ei ole asetetuilla kriteereilla tarpeen.\n")
  } else if (!isTRUE(result$mcmc_assessment$sufficient)) {
    cat("MALLIN PITKAN AJON RIITTAVYYS: EI VIELA RIITTAVA.\n")
    cat("Seuraava ajo pidentyy konvergenssidiagnostiikan perusteella.\n")
  } else {
    cat("MCMC ON RIITTAVA, MUTTA MALLISOVITUS EI OLE TAYDELLINEN.\n")
    cat(
      "Pelkkä MCMC:n pidentaminen ei yleensa korjaa PPC-ongelmaa; ",
      "tehdaan korkeintaan yksi pidempi varmistusajo.\n",
      sep = ""
    )
  }
  cat("======================================================\n")

  invisible(final_ok)
}

#===============================================================================
# 11. MUODOSTA SEURAAVAN AJON PAREMMAT ASETUKSET
#===============================================================================

improve_mcmc_settings <- function(current, assessment, reason = "mcmc") {
  next_mcmc <- current

  if (reason == "ppc_confirmation") {
    # MCMC on jo konvergoitunut; PPC-varmistuksessa lisataan posteriorinaytteita
    # mutta ei tarpeettomasti moninkertaisteta burn-inia.
    next_mcmc$samples <- min(
      max_samples,
      same_or_larger(current$samples + 1L, round_up_int(current$samples * 1.5))
    )
    next_mcmc$thin <- min(
      max_thin,
      same_or_larger(current$thin, round_up_int(current$thin * 1.25))
    )
    return(next_mcmc)
  }

  bad_rhat <-
    !is.finite(assessment$max_rhat) ||
    assessment$max_rhat > rhat_point_hard_limit ||
    !is.finite(assessment$fraction_rhat_good) ||
    assessment$fraction_rhat_good < 0.90 ||
    !isTRUE(assessment$beta_ok)

  low_ess <-
    !is.finite(assessment$min_ESS) ||
    assessment$min_ESS < ess_hard_minimum ||
    !is.finite(assessment$median_ESS) ||
    assessment$median_ESS < ess_median_target ||
    !is.finite(assessment$fraction_ESS_good) ||
    assessment$fraction_ESS_good < good_parameter_fraction_target

  if (bad_rhat) {
    # Ketjut eivat ole viela sekoittuneet riittavasti: pidempi transient on
    # ensisijainen korjaus, samalla kasvatetaan varsinaista posterioria.
    next_mcmc$transient <- min(
      max_transient,
      same_or_larger(
        current$transient + 1L,
        round_up_int(current$transient * 2)
      )
    )
    next_mcmc$samples <- min(
      max_samples,
      same_or_larger(
        current$samples + 1L,
        round_up_int(current$samples * 1.5)
      )
    )
    next_mcmc$thin <- min(
      max_thin,
      same_or_larger(current$thin, round_up_int(current$thin * 1.25))
    )
  }

  if (low_ess && !bad_rhat) {
    # Ketjut ovat samalla posteriorialueella mutta autokorrelaatio / Monte Carlo
    # -tarkkuus on heikko: lisataan posteriorinaytteita ja MCMC-valia.
    next_mcmc$samples <- min(
      max_samples,
      same_or_larger(
        current$samples + 1L,
        round_up_int(current$samples * 1.5)
      )
    )
    next_mcmc$thin <- min(
      max_thin,
      same_or_larger(
        current$thin + 1L,
        round_up_int(current$thin * 1.5)
      )
    )
  }

  if (bad_rhat && low_ess) {
    # Yhdistetty ongelma: annetaan myos thinningille selvempi kasvu.
    next_mcmc$thin <- min(
      max_thin,
      same_or_larger(current$thin + 1L, round_up_int(current$thin * 1.5))
    )
  }

  # Jos yksikaan yksittainen ehto ei muuttanut asetuksia mutta MCMC ei ollut
  # riittava, kasvatetaan samples turvallisesti.
  if (identical(next_mcmc, current)) {
    next_mcmc$samples <- min(
      max_samples,
      same_or_larger(current$samples + 1L, round_up_int(current$samples * 1.5))
    )
  }

  next_mcmc
}

settings_changed <- function(old, new) {
  any(c(
    old$samples != new$samples,
    old$transient != new$transient,
    old$thin != new$thin
  ))
}

print_next_settings <- function(current, next_mcmc, reason) {
  cat("\nSEURAAVAN PIDEMMAN AJON ASETUKSET\n")
  cat("Syy: ", reason, "\n", sep = "")
  comparison <- data.frame(
    parameter = c("samples", "transient", "thin", "chains", "parallel"),
    current = c(
      current$samples, current$transient, current$thin,
      current$chains, current$parallel
    ),
    next = c(
      next_mcmc$samples, next_mcmc$transient, next_mcmc$thin,
      next_mcmc$chains, next_mcmc$parallel
    ),
    stringsAsFactors = FALSE
  )
  print(comparison, row.names = FALSE)
  cat(
    "Seuraavan ajon MCMC steps / chain (approx): ",
    next_mcmc$transient + next_mcmc$samples * next_mcmc$thin,
    "\n",
    sep = ""
  )
}

#===============================================================================
# 12. ADAPTIIVINEN PITKIEN AJOJEN SILMUKKA
#===============================================================================

stage_results <- list()
stage_history <- list()
current_mcmc <- initial_mcmc
ppc_confirmation_used <- 0L
final_stage_result <- NULL
final_status <- "NOT_RUN"

for (stage_index in seq_len(max_stages)) {
  stage_result <- run_long_stage(
    stage_index = stage_index,
    mcmc = current_mcmc,
    seed = stage_seed_base + stage_index * 1000L
  )

  # Jos stage checkpoint luettiin ilman mallia mutta mallia tarvitaan lopuksi,
  # haetaan se erillisesta stage-mallitiedostosta.
  if (is.null(stage_result$model) &&
      !is.null(stage_result$model_file) &&
      !is.na(stage_result$model_file) &&
      file.exists(stage_result$model_file)) {
    stage_result$model <- readRDS(stage_result$model_file)
  }

  print_stage_report(stage_result)

  mcmc_ok <- isTRUE(stage_result$mcmc_assessment$sufficient)
  ppc_ok <- isTRUE(stage_result$ppc_assessment$sufficient)
  overall_ok <- mcmc_ok && (!require_ppc_for_final_adequacy || ppc_ok)

  stage_history[[stage_index]] <- data.frame(
    stage = stage_index,
    samples = current_mcmc$samples,
    transient = current_mcmc$transient,
    thin = current_mcmc$thin,
    chains = current_mcmc$chains,
    mcmc_ok = mcmc_ok,
    ppc_status = stage_result$ppc_assessment$status,
    ppc_ok = ppc_ok,
    max_rhat = stage_result$mcmc_assessment$max_rhat,
    max_rhat_upper = stage_result$mcmc_assessment$max_rhat_upper,
    min_ESS = stage_result$mcmc_assessment$min_ESS,
    median_ESS = stage_result$mcmc_assessment$median_ESS,
    fraction_rhat_good = stage_result$mcmc_assessment$fraction_rhat_good,
    fraction_ESS_good = stage_result$mcmc_assessment$fraction_ESS_good,
    beta_ok = stage_result$mcmc_assessment$beta_ok,
    overall_ok = overall_ok,
    stringsAsFactors = FALSE
  )

  stage_result_for_progress <- stage_result
  stage_result_for_progress$model <- NULL
  stage_results[[stage_index]] <- stage_result_for_progress
  history_table <- bind_rows(stage_history)
  write_csv2(history_table, file.path(output_root, "S4_STAGE_HISTORY.csv2"))
  saveRDS(stage_results, file.path(output_root, "S4_STAGE_RESULTS_PROGRESS.rds"))

  if (overall_ok) {
    final_stage_result <- stage_result
    final_status <- "ADEQUATE_MCMC_AND_PPC"
    cat("\nS4 lopettaa: asetetut MCMC- ja PPC-kriteerit tayttyivat.\n")
    break
  }

  if (stage_index >= max_stages) {
    final_stage_result <- stage_result
    if (!mcmc_ok) {
      final_status <- "MCMC_INSUFFICIENT_AT_MAX_STAGE"
    } else {
      final_status <- "MCMC_ADEQUATE_MODEL_FIT_REQUIRES_REVISION"
    }
    cat("\nS4 saavutti max_stages-rajan. Uutta ajoa ei kaynnisteta.\n")
    break
  }

  if (!mcmc_ok) {
    next_mcmc <- improve_mcmc_settings(
      current = current_mcmc,
      assessment = stage_result$mcmc_assessment,
      reason = "mcmc"
    )
    if (!settings_changed(current_mcmc, next_mcmc)) {
      final_stage_result <- stage_result
      final_status <- "MCMC_INSUFFICIENT_AT_CONFIG_LIMITS"
      cat(
        "\nMCMC ei ole riittava, mutta automaattiset max-rajoitukset estavat ",
        "pidemman ajon. Lopetetaan.\n",
        sep = ""
      )
      break
    }

    print_next_settings(
      current_mcmc,
      next_mcmc,
      paste0("MCMC ei ollut riittava: ", stage_result$mcmc_assessment$reasons)
    )
    current_mcmc <- next_mcmc
    next
  }

  # Tassa MCMC on jo kunnossa mutta PPC ei ole.
  if (
    require_ppc_for_final_adequacy &&
    !ppc_ok &&
    ppc_confirmation_used < max_ppc_confirmation_stages
  ) {
    ppc_confirmation_used <- ppc_confirmation_used + 1L
    next_mcmc <- improve_mcmc_settings(
      current = current_mcmc,
      assessment = stage_result$mcmc_assessment,
      reason = "ppc_confirmation"
    )

    if (!settings_changed(current_mcmc, next_mcmc)) {
      final_stage_result <- stage_result
      final_status <- "MCMC_ADEQUATE_MODEL_FIT_REQUIRES_REVISION"
      cat(
        "\nPPC vaatii tarkistusta, mutta pidempi vahvistusajo ei mahdu ",
        "asetettuihin max-rajoihin. Lopetetaan.\n",
        sep = ""
      )
      break
    }

    print_next_settings(
      current_mcmc,
      next_mcmc,
      paste0(
        "MCMC on riittava mutta PPC = ",
        stage_result$ppc_assessment$status,
        ". Tehdaan yksi pidempi varmistusajo."
      )
    )
    current_mcmc <- next_mcmc
    next
  }

  final_stage_result <- stage_result
  final_status <- "MCMC_ADEQUATE_MODEL_FIT_REQUIRES_REVISION"
  cat("\n===============================================================================\n")
  cat("S4 LOPETTAA ENNEN UUTTA PIDEMPAA AJOA\n")
  cat("===============================================================================\n")
  cat("MCMC on riittava, mutta PPC ei ole korjaantunut vahvistusajossa.\n")
  cat(
    "Johtopaatos: pidempi MCMC ei ole tarkoituksenmukainen korjaus. ",
    "Havaintomallia / mallirakennetta on tarkistettava.\n",
    sep = ""
  )
  break
}

if (is.null(final_stage_result)) {
  stop("S4 ei tuottanut yhtaan loppuun suoritettua stagea.")
}

#===============================================================================
# 13. TALLENNA LOPULLINEN STAGE JA LASKETAAN LOPPUYHTEENVEDOT
#===============================================================================

final_model <- final_stage_result$model
if (is.null(final_model) &&
    !is.null(final_stage_result$model_file) &&
    !is.na(final_stage_result$model_file) &&
    file.exists(final_stage_result$model_file)) {
  final_model <- readRDS(final_stage_result$model_file)
}
if (is.null(final_model)) {
  stop(
    "Lopullinen Hmsc-malli ei ole muistissa eika stage-mallitiedostoa loydy. ",
    "Aseta save_all_stage_models = TRUE."
  )
}

final_model_file <- file.path(output_root, "S4_FINAL_LONG_HMSC_MODEL.rds")
saveRDS(final_model, final_model_file)

final_beta <- beta_table_from_model_s4(final_model)
write_csv2(final_beta, file.path(output_root, "S4_FINAL_beta_posterior.csv2"))

final_convergence <- convergence_diagnostics_s4(final_model)
write_csv2(
  final_convergence$parameters,
  file.path(output_root, "S4_FINAL_convergence_by_parameter.csv2")
)
write_csv2(
  final_convergence$components,
  file.path(output_root, "S4_FINAL_convergence_by_component.csv2")
)

final_vp <- tryCatch(
  variance_partition_s4(final_model),
  error = function(e) {
    warning("Variance partitioning epaonnistui: ", conditionMessage(e))
    NULL
  }
)
if (!is.null(final_vp)) {
  write_csv2(
    final_vp$mapping,
    file.path(output_root, "S4_FINAL_variance_partitioning_mapping.csv2")
  )
  write_csv2(
    final_vp$long,
    file.path(output_root, "S4_FINAL_variance_partitioning.csv2")
  )
}

final_waic <- compute_waic_s4(final_model)
if (!is.null(final_waic)) {
  writeLines(
    capture.output(print(final_waic)),
    file.path(output_root, "S4_FINAL_WAIC.txt")
  )
}

stage_history_table <- bind_rows(stage_history)

S4_RESULTS <- list(
  role = "FINAL_PREDICTIVE_HMSC_ADAPTIVE_LONG_MCMC",
  final_status = final_status,
  final_stage = final_stage_result$stage,
  final_mcmc = final_stage_result$mcmc,
  model_definition = model_definition,
  final_sample_ids = final_ids,
  locked_weather_variables = intersect(variables_kept, locked_weather_variables),
  selected_environment_variables = intersect(
    variables_kept,
    selected_environment_variables
  ),
  variables_removed_zero_variance = variables_removed_zero_variance,
  scaling_mean = scaling_mean,
  scaling_sd = scaling_sd,
  stage_history = stage_history_table,
  final_beta = final_beta,
  final_convergence_parameters = final_convergence$parameters,
  final_convergence_components = final_convergence$components,
  final_mcmc_assessment = final_stage_result$mcmc_assessment,
  final_fit_metrics = final_stage_result$fit_metrics,
  final_ppc = final_stage_result$ppc_table,
  final_ppc_assessment = final_stage_result$ppc_assessment,
  final_variance_partitioning = if (!is.null(final_vp)) final_vp$long else NULL,
  final_waic = final_waic,
  s3_pooled_outer_metrics = S3_RESULTS$pooled_outer_metrics,
  s3_environment_incremental_predictive_value =
    S3_RESULTS$pooled_environment_delta,
  input_files = list(
    primary_rdata_file = primary_rdata_file,
    selection_results_file = selection_results_file,
    s3_results_file = s3_results_file
  ),
  final_model_file = final_model_file,
  session_info = capture.output(sessionInfo())
)

saveRDS(S4_RESULTS, file.path(output_root, "S4_FINAL_LONG_RUN_RESULTS.rds"))
writeLines(S4_RESULTS$session_info, file.path(output_root, "sessionInfo.txt"))

#===============================================================================
# 14. LOPULLINEN KONSOLIKOONTI
#===============================================================================

cat("\n\n===============================================================================\n")
cat("S4 ADAPTIIVINEN PITKA MCMC-AJO VALMIS\n")
cat("===============================================================================\n")
cat("Final status: ", final_status, "\n", sep = "")
cat("Hyvaksytty / viimeinen stage: ", final_stage_result$stage, "\n", sep = "")
cat("\nLopulliset MCMC-asetukset:\n")
print(as.data.frame(final_stage_result$mcmc), row.names = FALSE)

cat("\nStage-historia:\n")
print(stage_history_table, row.names = FALSE)

cat("\nLopullinen MCMC-johtopaatos:\n")
if (isTRUE(final_stage_result$mcmc_assessment$sufficient)) {
  cat("MCMC RIITTAVA\n")
} else {
  cat("MCMC EI RIITTAVA\n")
}
cat(final_stage_result$mcmc_assessment$reasons, "\n")

cat("\nLopullinen PPC-johtopaatos:\n")
cat(final_stage_result$ppc_assessment$status, "\n")
cat(final_stage_result$ppc_assessment$reason, "\n")

cat("\nLopulliset Beta-posteriorit:\n")
print(final_beta, row.names = FALSE)

cat("\nLopullinen konvergenssi komponenteittain:\n")
print(final_convergence$components, row.names = FALSE)

cat("\nS3 predictive-validointi (ei korvata S4:n in-sample-diagnostiikalla):\n")
if (!is.null(S3_RESULTS$pooled_outer_metrics)) {
  print(S3_RESULTS$pooled_outer_metrics, row.names = FALSE)
}

cat("\nLopullinen Hmsc-malli: ", final_model_file, "\n", sep = "")
cat("S4 tulokset: ", output_root, "\n", sep = "")
cat("===============================================================================\n")
