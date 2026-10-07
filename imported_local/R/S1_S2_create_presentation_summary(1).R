#========================================================
# HMSC-PÄÄANALYYSIN JA FENOLOGIAHERKKYYDEN ESITYSKOONTI
#========================================================
#
# Aja tämä vasta seuraavien korjattujen skriptien valmistuttua:
#   1) S1_S2_a_variable selection_with_variance_partitioning(1).R
#   2) S1_S2_b_HMSC_weather_common_phenology_years_sensitivity(1).R
#
# Skripti ei sovita malleja uudelleen. Se lukee kummankin analyysin yhden
# hyväksytyn RDS-koontitiedoston ja tuottaa esitykseen sopivat taulukot,
# kuvat sekä yhden Markdown-yhteenvedon.
#========================================================

rm(list = ls())

required_packages <- c("dplyr", "tidyr")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))
]
if (length(missing_packages) > 0L) {
  stop("Asenna puuttuvat paketit: ", paste(missing_packages, collapse = ", "))
}

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

#========================================================
# 1. Kansioasetukset
#========================================================

hmsc_output_root <- "E:/EIFFEL uusi/hmsc_outputs"

primary_dir <- file.path(
  hmsc_output_root,
  "HMSC_three_species_explanatory_midinterval_flightcurve_year_random_v4"
)

phenology_sensitivity_dir <- file.path(
  hmsc_output_root,
  "HMSC_weather_common_phenology_years_sensitivity_v1"
)

presentation_dir <- file.path(
  hmsc_output_root,
  "HMSC_PRESENTATION_SUMMARY"
)
dir.create(presentation_dir, recursive = TRUE, showWarnings = FALSE)

primary_file <- file.path(primary_dir, "PRIMARY_RESULTS.rds")
sensitivity_file <- file.path(
  phenology_sensitivity_dir,
  "SENSITIVITY_RESULTS.rds"
)

missing_result_files <- c(primary_file, sensitivity_file)[
  !file.exists(c(primary_file, sensitivity_file))
]
if (length(missing_result_files) > 0L) {
  stop(
    "Esityskoontia ei voi tehdä ennen korjattuja analyysejä. Puuttuvat tiedostot:\n",
    paste(missing_result_files, collapse = "\n"),
    "\nAja ensin S1_S2_a ja sen jälkeen S1_S2_b kokonaan."
  )
}

PRIMARY <- readRDS(primary_file)
PHENOLOGY <- readRDS(sensitivity_file)

if (!identical(PRIMARY$role, "PRIMARY_EXPLANATORY_HMSC")) {
  stop("PRIMARY_RESULTS.rds ei ole odotettu pääanalyysin koonti.")
}
if (!identical(PHENOLOGY$role, "PHENOLOGY_COMMON_YEARS_SENSITIVITY")) {
  stop("SENSITIVITY_RESULTS.rds ei ole odotettu fenologiaherkkyyden koonti.")
}
if (!grepl("CORRECTED", PRIMARY$script_revision, fixed = TRUE) ||
    !grepl("CORRECTED", PHENOLOGY$script_revision, fixed = TRUE)) {
  stop(
    "Tuloskansioissa on vanhan skriptiversion tuloksia. ",
    "Aja molemmat korjatut skriptit ennen esityskoontia."
  )
}

#========================================================
# 2. Apufunktiot
#========================================================

write_semicolon <- function(x, filename) {
  write.table(
    x,
    file = file.path(presentation_dir, filename),
    sep = ";",
    row.names = FALSE,
    na = ""
  )
}

markdown_table <- function(x, digits = 3L) {
  if (is.null(x) || nrow(as.data.frame(x)) == 0L) return("Ei rivejä.")
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
    apply(x, 1, function(z) paste0("| ", paste(z, collapse = " | "), " |"))
  )
}

collapse_or_none <- function(x) {
  if (length(x) == 0L) "ei yhtään" else paste(x, collapse = ", ")
}

empty_effect_table <- function() {
  data.frame(
    species = character(0),
    predictor = character(0),
    posterior_mean = numeric(0),
    direction = character(0),
    posterior_support = numeric(0),
    stringsAsFactors = FALSE
  )
}

effect_table <- function(x) {
  x <- as.data.frame(x)
  required <- c(
    "species", "predictor", "posterior_mean",
    "direction", "posterior_support"
  )
  if (nrow(x) == 0L || !all(required %in% names(x))) {
    return(empty_effect_table())
  }
  x[, required, drop = FALSE]
}

empty_variance_partition_table <- function() {
  data.frame(
    variance_source = character(0),
    species = character(0),
    variance_proportion = numeric(0),
    stringsAsFactors = FALSE
  )
}

variance_partition_table <- function(x) {
  x <- as.data.frame(x)
  required <- c("variance_source", "species", "variance_proportion")
  if (nrow(x) == 0L || !all(required %in% names(x))) {
    return(empty_variance_partition_table())
  }
  x[, required, drop = FALSE]
}

#========================================================
# 3. Esityksen taulukot
#========================================================

analysis_overview <- data.frame(
  analysis = c(
    "Primary explanatory Hmsc",
    "Common phenology years sensitivity"
  ),
  role = c("PRIMARY", "SENSITIVITY"),
  n_samples = c(PRIMARY$n_samples, PHENOLOGY$n_samples),
  selected_weather_groups = c(
    length(PRIMARY$selected_weather_groups),
    length(PHENOLOGY$selected_weather_groups)
  ),
  selected_weather_variables = c(
    length(PRIMARY$selected_weather_variables),
    length(PHENOLOGY$selected_weather_variables)
  ),
  selected_environment_groups = c(
    length(PRIMARY$selected_environment_groups),
    NA_integer_
  ),
  script_revision = c(PRIMARY$script_revision, PHENOLOGY$script_revision),
  stringsAsFactors = FALSE
)

primary_metrics <- as.data.frame(PRIMARY$explanatory_metrics)
sensitivity_metrics <- as.data.frame(PHENOLOGY$explanatory_metrics)

selected_buffers <- as.data.frame(PRIMARY$selected_buffers) %>%
  filter(selected_buffer) %>%
  select(
    ecological_group, buffer_m, n_samples,
    mean_delta_explanatory_SR2,
    min_delta_explanatory_SR2,
    max_delta_explanatory_SR2,
    variables_after_correlation
  )

primary_effects <- effect_table(PRIMARY$supported_effects_95)
sensitivity_effects <- effect_table(PHENOLOGY$supported_weather_effects_95)
primary_variance_partition <- variance_partition_table(
  PRIMARY$variance_partitioning
)

selection_stability <- as.data.frame(PHENOLOGY$selection_comparison)
selection_stability_summary <- selection_stability %>%
  count(item_type, same_selection, name = "n") %>%
  arrange(item_type, desc(same_selection))

write_semicolon(analysis_overview, "01_analysis_overview.txt")
write_semicolon(primary_metrics, "02_primary_explanatory_metrics.txt")
write_semicolon(selected_buffers, "03_selected_environment_buffers.txt")
write_semicolon(primary_effects, "04_primary_supported_effects_95.txt")
write_semicolon(sensitivity_metrics, "05_phenology_sensitivity_metrics.txt")
write_semicolon(selection_stability, "06_full_vs_phenology_selection_comparison.txt")
write_semicolon(selection_stability_summary, "07_selection_stability_summary.txt")
write_semicolon(
  primary_variance_partition,
  "08_primary_variance_partitioning.txt"
)

#========================================================
# 4. Esitykseen sopivat kuvat
#========================================================

plot_files <- character(0)

if (requireNamespace("ggplot2", quietly = TRUE)) {
  if (nrow(primary_effects) > 0L) {
    beta_plot_data <- primary_effects %>%
      mutate(
        predictor = gsub("__b", " (", predictor, fixed = TRUE),
        predictor = gsub("m$", " m)", predictor),
        predictor = reorder(predictor, posterior_mean)
      )

    p_beta <- ggplot2::ggplot(
      beta_plot_data,
      ggplot2::aes(
        x = posterior_mean,
        y = predictor,
        colour = direction,
        size = posterior_support
      )
    ) +
      ggplot2::geom_vline(xintercept = 0, colour = "grey65", linewidth = 0.4) +
      ggplot2::geom_point(alpha = 0.9) +
      ggplot2::facet_wrap(~species, scales = "free_y") +
      ggplot2::scale_colour_manual(
        values = c(negative = "#2C7BB6", positive = "#D7191C", zero = "grey50")
      ) +
      ggplot2::labs(
        title = "Supported environmental responses",
        subtitle = "Posterior directional support ≥ 0.95",
        x = "Posterior mean for standardized predictor",
        y = NULL,
        colour = "Direction",
        size = "Support"
      ) +
      ggplot2::theme_bw(base_size = 12) +
      ggplot2::theme(legend.position = "bottom")

    beta_plot_file <- file.path(
      presentation_dir,
      "presentation_primary_supported_effects.png"
    )
    ggplot2::ggsave(
      beta_plot_file,
      p_beta,
      width = 13,
      height = 8,
      dpi = 300
    )
    plot_files <- c(plot_files, basename(beta_plot_file))
  }

  primary_vp <- primary_variance_partition
  if (nrow(primary_vp) > 0L) {
    p_vp <- ggplot2::ggplot(
      primary_vp,
      ggplot2::aes(
        x = species,
        y = variance_proportion,
        fill = variance_source
      )
    ) +
      ggplot2::geom_col(width = 0.72) +
      ggplot2::scale_y_continuous(labels = function(x) paste0(round(100 * x), "%")) +
      ggplot2::labs(
        title = "Variance partitioning of the primary Hmsc model",
        x = NULL,
        y = "Variance proportion",
        fill = "Variance source"
      ) +
      ggplot2::theme_bw(base_size = 12) +
      ggplot2::theme(
        axis.text.x = ggplot2::element_text(angle = 20, hjust = 1),
        legend.position = "right"
      )

    vp_plot_file <- file.path(
      presentation_dir,
      "presentation_primary_variance_partitioning.png"
    )
    ggplot2::ggsave(
      vp_plot_file,
      p_vp,
      width = 10,
      height = 7,
      dpi = 300
    )
    plot_files <- c(plot_files, basename(vp_plot_file))
  }

  if (nrow(selection_stability) > 0L) {
    stability_plot_data <- selection_stability %>%
      select(item_type, item, selected_full_period, selected_common_phenology_years) %>%
      pivot_longer(
        cols = starts_with("selected_"),
        names_to = "analysis_period",
        values_to = "selected"
      ) %>%
      mutate(
        analysis_period = recode(
          analysis_period,
          selected_full_period = "Full period",
          selected_common_phenology_years = "Common phenology years"
        )
      )

    p_stability <- ggplot2::ggplot(
      stability_plot_data,
      ggplot2::aes(x = analysis_period, y = item, fill = selected)
    ) +
      ggplot2::geom_tile(colour = "white") +
      ggplot2::facet_wrap(~item_type, scales = "free_y") +
      ggplot2::scale_fill_manual(values = c(`FALSE` = "grey90", `TRUE` = "#238B45")) +
      ggplot2::labs(
        title = "Stability of weather-variable selection",
        x = NULL,
        y = NULL,
        fill = "Selected"
      ) +
      ggplot2::theme_bw(base_size = 11) +
      ggplot2::theme(
        axis.text.x = ggplot2::element_text(angle = 20, hjust = 1),
        legend.position = "bottom"
      )

    stability_plot_file <- file.path(
      presentation_dir,
      "presentation_phenology_selection_stability.png"
    )
    ggplot2::ggsave(
      stability_plot_file,
      p_stability,
      width = 11,
      height = max(6, 0.26 * nrow(selection_stability)),
      dpi = 300,
      limitsize = FALSE
    )
    plot_files <- c(plot_files, basename(stability_plot_file))
  }
}

#========================================================
# 5. Yhdistetty työnkuvaus ja tulokset
#========================================================

phenology_years <- PHENOLOGY$eligible_years

report_lines <- c(
  "# Hmsc-pääanalyysi ja fenologian herkkyystesti",
  "",
  "## Analyysien roolit",
  "",
  "Pääanalyysi on koko käyttökelpoisen ajanjakson selittävä viikkotason Hmsc. Fenologian yhteisten vuosien analyysi on erillinen herkkyystesti, jolla tarkistetaan, johtuuko säämuuttujien valinta fenologiatietojen lyhyemmästä saatavuusjaksosta.",
  "",
  markdown_table(analysis_overview),
  "",
  "## Pääanalyysin työnkulku",
  "",
  "1. Kolmen lajin kokonaislukusaaliit mallinnettiin yhdessä lognormal-Poisson Hmsc -mallissa.",
  "2. Pyyntijakson pituus sisällytettiin estimoitavana log(interval_days)-kontrollina.",
  "3. Lentokausi mallinnettiin pyyntijakson keskikohdan luonnollisella splinellä; paikka ja vuosi olivat satunnaistasoja.",
  "4. Sääryhmät valittiin explanatory SR2:n perusteella.",
  "5. Jokaiselle ympäristöryhmälle valittiin yksi bufferi siten, että saman ryhmän bufferit vertailtiin samoilla havaintoriveillä.",
  "6. Bufferikorjatut ympäristöryhmät valittiin lukitun sääpohjan päälle.",
  "7. Lopullisesta mallista raportoitiin selitysaste, beta-kertoimet, posteriorituki, varianssin jakautuminen ja MCMC-konvergenssi.",
  "",
  "## Pääanalyysin valinnat",
  "",
  paste0("- Sääryhmät: ", collapse_or_none(PRIMARY$selected_weather_groups)),
  paste0("- Säämuuttujat: ", collapse_or_none(PRIMARY$selected_weather_variables)),
  paste0("- Ympäristöryhmät: ", collapse_or_none(PRIMARY$selected_environment_groups)),
  "",
  "### Valitut bufferit",
  "",
  markdown_table(selected_buffers),
  "",
  "### Selitysaste lajeittain",
  "",
  markdown_table(primary_metrics),
  "",
  "### Tuetut ekologiset vaikutukset",
  "",
  markdown_table(primary_effects),
  "",
  "## Fenologian yhteisten vuosien herkkyystesti",
  "",
  paste0("- Mukana olleet vuodet: ", paste(phenology_years, collapse = ", ")),
  paste0("- Havaintoja: ", PHENOLOGY$n_samples),
  paste0("- Valitut sääryhmät: ", collapse_or_none(PHENOLOGY$selected_weather_groups)),
  paste0("- Valitut säämuuttujat: ", collapse_or_none(PHENOLOGY$selected_weather_variables)),
  "",
  "### Valintojen pysyvyys",
  "",
  markdown_table(selection_stability_summary),
  "",
  "### Herkkyysmallin selitysaste",
  "",
  markdown_table(sensitivity_metrics),
  "",
  "### Herkkyysmallin tuetut säävaikutukset",
  "",
  markdown_table(sensitivity_effects),
  "",
  "## Tulkinta esitystä varten",
  "",
  "- Pääanalyysi vastaa kysymykseen, mitkä sää- ja ympäristötekijät selittävät lajien havaittua viikoittaista runsautta.",
  "- Fenologiaherkkyys ei ole toinen päämalli, vaan tarkistus sille, säilyvätkö säävalinnat yhteisellä havaintojaksolla.",
  "- Tulokset ovat aineistonsisäisiä selittäviä yhteyksiä. Uusien vuosien ja paikkojen ennustekyky raportoidaan erillisestä ristiinvalidointianalyysistä.",
  "",
  "## Luodut esityskuvat",
  "",
  if (length(plot_files) == 0L) "Kuvia ei luotu." else paste0("- ", plot_files)
)

report_file <- file.path(
  presentation_dir,
  "HMSC_WORKFLOW_AND_RESULTS_FOR_PRESENTATION.md"
)
writeLines(report_lines, report_file)

PRESENTATION_RESULTS <- list(
  primary = PRIMARY,
  phenology_sensitivity = PHENOLOGY,
  analysis_overview = analysis_overview,
  selected_buffers = selected_buffers,
  selection_stability = selection_stability,
  plot_files = file.path(presentation_dir, plot_files),
  report_file = report_file
)
saveRDS(
  PRESENTATION_RESULTS,
  file.path(presentation_dir, "PRESENTATION_RESULTS.rds")
)

cat("\n========================================================\n")
cat("ESITYSKOONTI VALMIS\n")
cat("Tulokset:", presentation_dir, "\n")
cat("Raportti:", report_file, "\n")
cat("R-objekti: PRESENTATION_RESULTS\n")
cat("========================================================\n")
