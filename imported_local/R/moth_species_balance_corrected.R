#========================================================
# KOHDERYHMÄN YÖPERHOSAINEISTO
#
# Long-muotoinen lähtöaineisto sisältää vain positiiviset
# lajikohtaiset havainnot.
#
# Skripti:
# 1. muodostaa todelliset pyyntijaksot
# 2. lisää kuusi kohdelajia jokaiselle pyyntijaksolle
# 3. asettaa puuttuville lajiyhdistelmille count = 0
# 4. määrittää lajien lentoajat
# 5. muodostaa vuosittaiset lajimäärät
#========================================================

library(dplyr)
library(tidyr)
library(lubridate)
library(stringr)
library(ggplot2)

#========================================================
# 1. Tiedostopolut
#========================================================

base_dir <- "//kk11/E1008169$/Documents/EIFFEL"

input_file <- file.path(
  base_dir,
  "data",
  "Eiffel_1993_2024.csv"
)

output_dir <- file.path(
  base_dir,
  "data",
  "target_moth_species"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

#========================================================
# 2. Kohdelajit
#========================================================

target_species <- c(
  "Lymantria monacha",
  "Bupalus piniarius",
  "Panolis flammea",
  "Epirrita autumnata",
  "Operophtera brumata",
  "Operophtera fagata"
)

winter_species <- c(
  "Operophtera brumata",
  "Operophtera fagata"
)

#========================================================
# 3. Lue ja muotoile long-muotoinen aineisto
#========================================================

dat_raw <- read.csv(
  input_file,
  header = TRUE,
  sep = ";",
  dec = ".",
  stringsAsFactors = FALSE,
  check.names = FALSE
) %>%
  rename(
    count       = KokMaara,
    start_DateN = PvmAlku,
    end_DateN   = PvmLoppu
  ) %>%
  distinct() %>%
  mutate(
    site = as.character(site),
    year = as.integer(year),
    count = as.numeric(count),
    species = str_squish(as.character(species)),
    NimiRysapaikka = as.character(NimiRysapaikka),
    ETRS_TM35FIN_N = as.numeric(ETRS_TM35FIN_N),
    ETRS_TM35FIN_E = as.numeric(ETRS_TM35FIN_E),
    
    start_DateN = as.Date(
      parse_date_time(
        as.character(start_DateN),
        orders = c(
          "dmy", "ymd", "dmY", "Ymd",
          "d.m.Y", "d/m/Y", "d-m-Y", "Y-m-d"
        ),
        quiet = TRUE
      )
    ),
    
    end_DateN = as.Date(
      parse_date_time(
        as.character(end_DateN),
        orders = c(
          "dmy", "ymd", "dmY", "Ymd",
          "d.m.Y", "d/m/Y", "d-m-Y", "Y-m-d"
        ),
        quiet = TRUE
      )
    ),
    
    sample_id = paste(
      site,
      start_DateN,
      end_DateN,
      sep = "_"
    )
  )
dat_raw<-unique(dat_raw)
message("Aineiston rivimäärä: ", nrow(dat_raw))

#========================================================
# 4. Todelliset pyyntijaksot
#========================================================
#
# Jokaisella paikalla on yksi rysä.
# Yksi pyyntijakso määritellään yhdistelmällä:
# site + start_DateN + end_DateN.
#
# Pyyntijaksot muodostetaan koko aineistosta, jotta
# kohdelajille voidaan lisätä nolla myös silloin, kun
# samalla jaksolla havaittiin vain muita lajeja.
#========================================================

sampling_events <- dat_raw %>%
  distinct(
    sample_id,
    site,
    year,
    start_DateN,
    end_DateN,
    NimiRysapaikka,
    ETRS_TM35FIN_N,
    ETRS_TM35FIN_E
  ) %>%
  mutate(
    interval_days = pmax(
      as.numeric(end_DateN - start_DateN),
      1
    ),
    
    sample_mid_date =
      start_DateN + floor(interval_days / 2),
    
    sample_year = lubridate::year(sample_mid_date),
    week = lubridate::isoweek(sample_mid_date),
    doy = lubridate::yday(sample_mid_date),
    month = lubridate::month(sample_mid_date),
    
    # Viikot 1–13 sijoitetaan viikkojen 52–53 jälkeen.
    # Näin marras–tammikuun lentokausi ei katkea vuodenvaihteessa.
    flight_week_order = if_else(
      week <= 13,
      week + 53L,
      week
    )
  )

message(
  "Todellisten pyyntijaksojen määrä: ",
  nrow(sampling_events)
)

#========================================================
# 5. Kohdelajien positiiviset havainnot
#========================================================
#
# Jos sama laji esiintyy samassa näytteessä usealla rivillä,
# rivien yksilömäärät summataan.
#========================================================

target_positive <- dat_raw %>%
  filter(species %in% target_species) %>%
  group_by(
    sample_id,
    species
  ) %>%
  summarise(
    count = sum(count),
    .groups = "drop"
  )

#========================================================
# 6. Lisää kaikki kohdelajit jokaiselle pyyntijaksolle
#========================================================

moths_complete <- sampling_events %>%
  crossing(
    species = target_species
  ) %>%
  left_join(
    target_positive,
    by = c(
      "sample_id",
      "species"
    )
  ) %>%
  mutate(
    count = replace_na(count, 0),
    
    count_per_7d =
      count / interval_days * 7,
    
    observed = count > 0,
    
    # Tammi–maaliskuun talvilajihavainnot kuuluvat
    # edellisen syksyn alkaneeseen lentokauteen.
    flight_year = if_else(
      species %in% winter_species & month <= 3,
      sample_year - 1L,
      sample_year
    )
  ) %>%
  arrange(
    site,
    start_DateN,
    end_DateN,
    species
  )

message(
  "Täydennetyn aineiston rivimäärä: ",
  nrow(moths_complete)
)

message(
  "Positiivisten havaintojen määrä: ",
  sum(moths_complete$count > 0)
)

message(
  "Lisättyjen nollahavaintojen määrä: ",
  sum(moths_complete$count == 0)
)

zero_summary <- moths_complete %>%
  group_by(species) %>%
  summarise(
    n_sampling_events = n(),
    n_positive = sum(count > 0),
    n_zero = sum(count == 0),
    total_count = sum(count),
    .groups = "drop"
  ) %>%
  arrange(match(species, target_species))

print(zero_summary)

#========================================================
# 7. Tallenna täydennetty pyyntijaksoaineisto
#========================================================

write.csv(
  moths_complete,
  file.path("//kk11/E1008169$/Documents/EIFFEL/target_moths_sampling_periods_with_zeros.csv"
  ),
  row.names = FALSE,
  na = ""
)

#========================================================
# 8. Lajikohtainen lentojakauma
#========================================================

flight_week_distribution <- moths_complete %>%
  group_by(
    species,
    flight_week_order
  ) %>%
  summarise(
    week = first(week),
    
    total_count = sum(count),
    
    total_count_per_7d =
      sum(count_per_7d),
    
    n_sampling_events = n(),
    
    n_positive_events =
      sum(count > 0),
    
    occurrence_frequency =
      n_positive_events / n_sampling_events,
    
    mean_count_per_event =
      mean(count),
    
    mean_count_per_7d =
      mean(count_per_7d),
    
    .groups = "drop"
  ) %>%
  group_by(species) %>%
  arrange(
    flight_week_order,
    .by_group = TRUE
  ) %>%
  mutate(
    species_total =
      sum(total_count_per_7d),
    
    flight_proportion = if_else(
      species_total > 0,
      total_count_per_7d / species_total,
      0
    ),
    
    cumulative_flight_proportion =
      cumsum(flight_proportion)
  ) %>%
  ungroup()

#========================================================
# 9. Lentoviikon kvantiilifunktio
#========================================================

get_flight_week <- function(
    week,
    cumulative_proportion,
    probability
) {
  
  selected_index <- which(
    cumulative_proportion >= probability
  )[1]
  
  if (is.na(selected_index)) {
    return(NA_integer_)
  }
  
  as.integer(week[selected_index])
}

#========================================================
# 10. Lentoajat koko aineistosta
#========================================================
#
# 5 %  = lentoajan alku
# 25 % = ensimmäinen kvartiili
# 50 % = mediaanilentoviikko
# 75 % = kolmas kvartiili
# 95 % = lentoajan loppu
#========================================================

flight_periods <- flight_week_distribution %>%
  group_by(species) %>%
  summarise(
    total_count =
      sum(total_count),
    
    total_count_per_7d =
      sum(total_count_per_7d),
    
    first_observed_week = if (
      any(total_count > 0)
    ) {
      week[which(total_count > 0)[1]]
    } else {
      NA_integer_
    },
    
    flight_start_week = get_flight_week(
      week,
      cumulative_flight_proportion,
      0.05
    ),
    
    flight_q25_week = get_flight_week(
      week,
      cumulative_flight_proportion,
      0.25
    ),
    
    median_flight_week = get_flight_week(
      week,
      cumulative_flight_proportion,
      0.50
    ),
    
    peak_flight_week = if (
      any(total_count_per_7d > 0)
    ) {
      week[which.max(total_count_per_7d)]
    } else {
      NA_integer_
    },
    
    flight_q75_week = get_flight_week(
      week,
      cumulative_flight_proportion,
      0.75
    ),
    
    flight_end_week = get_flight_week(
      week,
      cumulative_flight_proportion,
      0.95
    ),
    
    last_observed_week = if (
      any(total_count > 0)
    ) {
      week[tail(which(total_count > 0), 1)]
    } else {
      NA_integer_
    },
    
    .groups = "drop"
  ) %>%
  arrange(match(species, target_species))

message("")
message("Aineistosta määritetyt lentoajat:")
print(flight_periods)

write.csv(
  flight_periods,
  file.path(
    output_dir,
    "target_species_flight_periods.csv"
  ),
  row.names = FALSE,
  na = ""
)

write.csv(
  flight_week_distribution,
  file.path(
    output_dir,
    "target_species_weekly_flight_distribution.csv"
  ),
  row.names = FALSE,
  na = ""
)

#========================================================
# 11. Lentoajat lentokausittain
#========================================================
#
# Operophtera-lajien tammi–maaliskuun havainnot kuuluvat
# edellisen syksyn lentokauteen flight_year-muuttujan avulla.
#========================================================

flight_distribution_by_year <- moths_complete %>%
  group_by(
    species,
    flight_year,
    flight_week_order
  ) %>%
  summarise(
    week = first(week),
    
    total_count =
      sum(count),
    
    total_count_per_7d =
      sum(count_per_7d),
    
    n_sampling_events = n(),
    
    n_positive_events =
      sum(count > 0),
    
    .groups = "drop"
  ) %>%
  group_by(
    species,
    flight_year
  ) %>%
  arrange(
    flight_week_order,
    .by_group = TRUE
  ) %>%
  mutate(
    annual_total =
      sum(total_count_per_7d),
    
    proportion = if_else(
      annual_total > 0,
      total_count_per_7d / annual_total,
      0
    ),
    
    cumulative_proportion =
      cumsum(proportion)
  ) %>%
  ungroup()

flight_periods_by_year <- flight_distribution_by_year %>%
  group_by(
    species,
    flight_year
  ) %>%
  summarise(
    annual_count =
      sum(total_count),
    
    annual_count_per_7d =
      sum(total_count_per_7d),
    
    n_sampling_events =
      sum(n_sampling_events),
    
    n_positive_events =
      sum(n_positive_events),
    
    flight_start_week = if (
      sum(total_count) > 0
    ) {
      get_flight_week(
        week,
        cumulative_proportion,
        0.05
      )
    } else {
      NA_integer_
    },
    
    median_flight_week = if (
      sum(total_count) > 0
    ) {
      get_flight_week(
        week,
        cumulative_proportion,
        0.50
      )
    } else {
      NA_integer_
    },
    
    peak_flight_week = if (
      sum(total_count) > 0
    ) {
      week[which.max(total_count_per_7d)]
    } else {
      NA_integer_
    },
    
    flight_end_week = if (
      sum(total_count) > 0
    ) {
      get_flight_week(
        week,
        cumulative_proportion,
        0.95
      )
    } else {
      NA_integer_
    },
    
    .groups = "drop"
  ) %>%
  arrange(
    species,
    flight_year
  )

write.csv(
  flight_periods_by_year,
  file.path(
    output_dir,
    "target_species_flight_periods_by_year.csv"
  ),
  row.names = FALSE,
  na = ""
)

#========================================================
# 12. Paikka × vuosi × laji -vuosiyhteenveto
#========================================================
#
# Tässä käytetään alkuperäistä aineiston year-saraketta.
# Jokainen paikka–vuosi, jolloin rysä oli käytössä, saa
# rivin kaikille kuudelle lajille. Havaitsematon laji saa
# vuosittaiseksi yksilömääräksi nollan.
#========================================================

species_annual_abundance <- moths_complete %>%
  group_by(
    site,
    year,
    NimiRysapaikka,
    ETRS_TM35FIN_N,
    ETRS_TM35FIN_E,
    species
  ) %>%
  summarise(
    annual_count =
      sum(count),
    
    annual_count_per_7d_sum =
      sum(count_per_7d),
    
    mean_sampling_count =
      mean(count),
    
    mean_count_per_7d =
      mean(count_per_7d),
    
    maximum_sampling_count =
      max(count),
    
    n_sampling_events = n(),
    
    n_positive_events =
      sum(count > 0),
    
    occurrence_frequency =
      n_positive_events / n_sampling_events,
    
    total_sampling_days =
      sum(interval_days),
    
    first_sampling_date =
      min(start_DateN),
    
    last_sampling_date =
      max(end_DateN),
    
    .groups = "drop"
  ) %>%
  arrange(
    site,
    year,
    match(species, target_species)
  )

write.csv(
  species_annual_abundance,
  file.path(
    output_dir,
    "target_species_annual_abundance_with_zeros.csv"
  ),
  row.names = FALSE,
  na = ""
)

write.table(
  species_annual_abundance,
  file.path(
    output_dir,
    "target_species_annual_abundance_with_zeros.txt"
  ),
  sep = ";",
  dec = ".",
  row.names = FALSE,
  quote = FALSE,
  na = ""
)

#========================================================
# 13. Paikka × vuosi -pyyntikattavuus
#========================================================

sampling_coverage <- sampling_events %>%
  group_by(
    site,
    year,
    NimiRysapaikka,
    ETRS_TM35FIN_N,
    ETRS_TM35FIN_E
  ) %>%
  summarise(
    n_sampling_events = n(),
    
    total_sampling_days =
      sum(interval_days),
    
    first_sampling_date =
      min(start_DateN),
    
    last_sampling_date =
      max(end_DateN),
    
    first_sampling_week =
      min(week),
    
    last_sampling_week =
      max(week),
    
    .groups = "drop"
  )

write.csv(
  sampling_coverage,
  file.path(
    output_dir,
    "sampling_coverage_by_site_year.csv"
  ),
  row.names = FALSE,
  na = ""
)

#========================================================
# 14. Lentojakauman kuva
#========================================================

flight_plot <- ggplot(
  flight_week_distribution,
  aes(
    x = flight_week_order,
    y = total_count_per_7d
  )
) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 1.4) +
  facet_wrap(
    ~ species,
    scales = "free_y",
    ncol = 2
  ) +
  scale_x_continuous(
    breaks = c(
      seq(1, 53, by = 4),
      57,
      61,
      65
    ),
    labels = c(
      seq(1, 53, by = 4),
      4,
      8,
      12
    )
  ) +
  labs(
    title = "Kohdelajien havaittu lentojakauma",
    subtitle = paste0(
      "Lentoajat perustuvat kaikkien vuosien ja ",
      "pyyntipaikkojen havaintoihin"
    ),
    x = "ISO-viikko",
    y = paste0(
      "Seitsemälle päivälle vakioitujen ",
      "yksilömäärien summa"
    )
  ) +
  theme_bw() +
  theme(
    strip.text = element_text(
      face = "italic"
    )
  )

ggsave(
  filename = file.path(
    output_dir,
    "target_species_flight_distributions.png"
  ),
  plot = flight_plot,
  width = 11,
  height = 12,
  dpi = 300
)

#========================================================
# 15. Vuosittaisten lentohuippujen kuva
#========================================================

peak_plot_data <- flight_periods_by_year %>%
  filter(
    annual_count > 0,
    !is.na(peak_flight_week)
  )

peak_plot <- ggplot(
  peak_plot_data,
  aes(
    x = flight_year,
    y = peak_flight_week
  )
) +
  geom_point() +
  geom_smooth(
    method = "lm",
    se = TRUE
  ) +
  facet_wrap(
    ~ species,
    scales = "free_y",
    ncol = 2
  ) +
  labs(
    title = "Kohdelajien vuosittainen lentohuippu",
    x = "Lentokauden vuosi",
    y = "Lentohuipun ISO-viikko"
  ) +
  theme_bw() +
  theme(
    strip.text = element_text(
      face = "italic"
    )
  )

ggsave(
  filename = file.path(
    output_dir,
    "target_species_annual_peak_flight_weeks.png"
  ),
  plot = peak_plot,
  width = 11,
  height = 12,
  dpi = 300
)

#========================================================
# 16. Valmis
#========================================================

message("")
message("==============================================")
message("KÄSITTELY VALMIS")
message("==============================================")
message("Alkuperäisiä positiivisia rivejä: ", nrow(dat_raw))
message("Todellisia pyyntijaksoja: ", nrow(sampling_events))
message("Täydennettyjä pyyntijakso × laji -rivejä: ", nrow(moths_complete))
message("Lisättyjä nollarivejä: ", sum(moths_complete$count == 0))
message("Paikka × vuosi × laji -vuosirivejä: ", nrow(species_annual_abundance))
message("")
message("Tulokset tallennettiin kansioon:")
message(output_dir)

#========================================================
# Lentopäivien histogrammit noin kymmenen vuoden jaksoittain
#========================================================
#
# Histogrammit tehdään erikseen jokaiselle kohdelajille.
#
# X-akseli:
#   Lentopäivä vuoden alusta eli DOY.
#
# Y-akseli:
#   Havaittujen yksilöiden määrä.
#
# Histogrammit:
#   Eri ajanjaksot piirretään omina läpinäkyvinä
#   histogrammeinaan samaan kuvaan.
#
# Ajanjaksot:
#   Tavallisesti 10 vuotta.
#   Jos viimeinen jakso jää alle 10 vuoden mittaiseksi,
#   se yhdistetään edelliseen jaksoon.
#
# Esimerkiksi vuosille 1993–2024:
#   1993–2002
#   2003–2012
#   2013–2024
#
# Värit:
#   Vanhin ajanjakso on sininen ja uusin punainen.
#========================================================

library(dplyr)
library(ggplot2)
library(stringr)

#========================================================
# Tuloshakemisto
#========================================================

plot_dir <- file.path(
  output_dir,
  "histograms_10_year_periods"
)

dir.create(
  plot_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

#========================================================
# Valitse positiiviset havainnot
#========================================================
#
# Täydennetyt nollahavainnot jätetään pois.
# Histogrammi perustuu vain havaintoihin, joissa lajin
# yksilömäärä on suurempi kuin nolla.
#========================================================

flight_dates <- moths_complete %>%
  filter(
    !is.na(count),
    count > 0,
    !is.na(year),
    !is.na(doy),
    !is.na(species)
  )

if (nrow(flight_dates) == 0) {
  stop(
    "Positiivisia havaintoja ei löytynyt histogrammien tekemistä varten."
  )
}

#========================================================
# Muodosta kymmenen vuoden jaksot
#========================================================
#
# Jos viimeinen jakso jää alle 10 vuoden mittaiseksi,
# poistetaan sen oma aloitusvuosi ja yhdistetään vuodet
# edelliseen jaksoon.
#
# Esimerkiksi vuosille 1993–2024:
#
# Alustavat jaksot:
#   1993–2002
#   2003–2012
#   2013–2022
#   2023–2024
#
# Lopulliset jaksot:
#   1993–2002
#   2003–2012
#   2013–2024
#========================================================

first_year <- min(
  flight_dates$year,
  na.rm = TRUE
)

last_year <- max(
  flight_dates$year,
  na.rm = TRUE
)

period_starts <- seq(
  from = first_year,
  to = last_year,
  by = 10
)

# Viimeisen alustavan jakson pituus
last_period_length <- last_year -
  tail(period_starts, 1) +
  1

# Yhdistä viimeinen vajaa jakso edelliseen jaksoon
if (
  length(period_starts) > 1 &&
  last_period_length < 10
) {
  period_starts <- head(
    period_starts,
    -1
  )
}

# Jaksojen oikeat päättymisvuodet:
# seuraavan jakson aloitusvuosi - 1,
# paitsi viimeinen päättyy aineiston viimeiseen vuoteen
period_ends <- c(
  period_starts[-1] - 1,
  last_year
)

period_breaks <- c(
  period_starts,
  last_year + 1
)

period_labels <- paste0(
  period_starts,
  "–",
  period_ends
)

flight_dates <- flight_dates %>%
  mutate(
    ten_year_period = cut(
      year,
      breaks = period_breaks,
      labels = period_labels,
      right = FALSE,
      include.lowest = TRUE
    )
  )

#========================================================
# Tarkista muodostuneet ajanjaksot
#========================================================

period_table <- flight_dates %>%
  distinct(
    year,
    ten_year_period
  ) %>%
  arrange(year)

print(period_table)

if (any(is.na(flight_dates$ten_year_period))) {
  warning(
    "Joillekin havainnoille ei muodostunut ajanjaksoa."
  )
}

#========================================================
# Muodosta sinisestä punaiseen etenevät värit
#========================================================

period_levels <- levels(
  flight_dates$ten_year_period
)

period_colors <- colorRampPalette(
  c(
    "#2166AC",
    "#67A9CF",
    "#F7F7F7",
    "#EF8A62",
    "#B2182B"
  )
)(
  length(period_levels)
)

names(period_colors) <- period_levels

#========================================================
# Tulosta havaintojen yhteenveto
#========================================================

period_summary <- flight_dates %>%
  group_by(
    ten_year_period,
    species
  ) %>%
  summarise(
    n_positive_observations = n(),
    
    total_individuals = sum(
      count,
      na.rm = TRUE
    ),
    
    first_year = min(
      year,
      na.rm = TRUE
    ),
    
    last_year = max(
      year,
      na.rm = TRUE
    ),
    
    n_years = n_distinct(year),
    
    .groups = "drop"
  ) %>%
  arrange(
    species,
    ten_year_period
  )

print(period_summary)

#========================================================
# Lentopäivien histogrammit
#========================================================
#
# weight = count:
#   Histogrammin pylvään korkeus perustuu havaittujen
#   yksilöiden määrään.
#
# position = "identity":
#   Eri ajanjaksot piirretään omina histogrammeinaan
#   päällekkäin.
#
# alpha = 0.45:
#   Histogrammit ovat läpinäkyviä.
#
# Histogrammin luokkaväli on seitsemän päivää.
#========================================================

for (sp in target_species) {
  
  dat_sp <- flight_dates %>%
    filter(
      species == sp
    )
  
  if (nrow(dat_sp) == 0) {
    message(
      "Ei positiivisia havaintoja lajille: ",
      sp
    )
    
    next
  }
  
  p <- ggplot(
    dat_sp,
    aes(
      x = doy,
      weight = count,
      fill = ten_year_period
    )
  ) +
    geom_histogram(
      binwidth = 7,
      boundary = 1,
      position = "identity",
      alpha = 0.45,
      colour = "grey30",
      linewidth = 0.15
    ) +
    scale_x_continuous(
      breaks = seq(
        1,
        366,
        by = 30
      ),
      limits = c(
        1,
        366
      ),
      expand = expansion(
        mult = c(
          0,
          0.01
        )
      )
    ) +
    scale_fill_manual(
      values = period_colors,
      limits = period_levels,
      drop = FALSE
    ) +
    labs(
      title = sp,
      
      subtitle = paste0(
        "Havaitut yksilömäärät ajanjaksoittain"
      ),
      
      x = "Lentopäivä vuoden alusta (DOY)",
      
      y = "Havaittujen yksilöiden määrä",
      
      fill = "Ajanjakso"
    ) +
    theme_bw() +
    theme(
      plot.title = element_text(
        face = "italic"
      ),
      
      legend.position = "bottom",
      
      legend.title = element_text(
        face = "bold"
      ),
      
      panel.grid.minor = element_blank()
    )
  
  print(p)
  
  # Muodosta tiedostonimeen sopiva lajinimi
  species_filename <- sp %>%
    str_replace_all(
      "[^[:alnum:]]+",
      "_"
    ) %>%
    str_remove(
      "_$"
    )
  
  ggsave(
    filename = file.path(
      plot_dir,
      paste0(
        species_filename,
        "_flight_days_10_year_periods.png"
      )
    ),
    plot = p,
    width = 10,
    height = 6,
    dpi = 300,
    bg = "white"
  )
}

#========================================================
# Tallenna ajanjaksojen yhteenveto
#========================================================

write.csv(
  period_summary,
  file = file.path(
    plot_dir,
    "flight_observations_by_species_and_10_year_period.csv"
  ),
  row.names = FALSE,
  na = ""
)

message("")
message(
  "Ajanjaksojen histogrammit tallennettiin:"
)
message(plot_dir)

message("")
message(
  "Käytetyt ajanjaksot: ",
  paste(
    period_labels,
    collapse = ", "
  )
)
