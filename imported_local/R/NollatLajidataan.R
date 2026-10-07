#========================================================
# KOHDERYHMÄN YÖPERHOSAINEISTO
#
# Long-muotoinen lähtöaineisto sisältää vain positiiviset
# lajikohtaiset havainnot.
#
# Skripti:
# 1. muodostaa todelliset pyyntijaksot
# 2. lisää puuttuvat kohdelajit jokaiselle pyyntijaksolle
# 3. asettaa puuttuville havainnoille count = 0
# 4. määrittää lajien lentoajat aineistosta
# 5. muodostaa vuosittaiset lajimäärät
#========================================================

library(dplyr)
library(tidyr)
library(lubridate)
library(stringr)
library(ggplot2)
library(readr)

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

#========================================================
# 3. Lue long-muotoinen aineisto
#========================================================

dat_raw <- read.csv(
  input_file,
  header = TRUE,
  sep = ";",
  dec = ".",
  stringsAsFactors = FALSE,
  check.names = FALSE
)


dat_raw <- dat_raw %>%
  rename(
    count       = KokMaara,
    start_DateN = PvmAlku,
    end_DateN   = PvmLoppu
  )
message("Aineiston rivimäärä: ", nrow(dat_raw))
message("Aineiston sarakkeet:")
print(names(dat_raw))

#========================================================
# 4. Tarkista pakolliset sarakkeet
#========================================================

required_columns <- c(
  "site",
  "species",
  "count",
  "PvmLoppu",
  "end_DateN"
)

missing_columns <- setdiff(
  required_columns,
  names(dat_raw)
)

if (length(missing_columns) > 0) {
  
  stop(
    paste0(
      "Aineistosta puuttuvat pakolliset sarakkeet: ",
      paste(missing_columns, collapse = ", ")
    )
  )
}

#========================================================
# 5. Muotoile päivämäärät, paikat ja määrät
#========================================================

dat_raw <- dat_raw %>%
  mutate(
    site = as.character(site),
    
    species = str_squish(
      as.character(species)
    ),
    
    PvmLoppu = as.Date(PvmLoppu),
    end_DateN = as.Date(end_DateN),
    
    count = suppressWarnings(
      as.numeric(count)
    )
  )

# Tarkista päivämäärät
if (any(is.na(dat_raw$PvmLoppu))) {
  
  stop(
    "PvmLoppu-sarakkeessa on arvoja, joita ei voitu ",
    "muuntaa päivämääriksi."
  )
}

if (any(is.na(dat_raw$end_DateN))) {
  
  stop(
    "end_DateN-sarakkeessa on arvoja, joita ei voitu ",
    "muuntaa päivämääriksi."
  )
}

# Lähtöaineiston pitäisi sisältää vain positiivisia havaintoja.
if (any(is.na(dat_raw$count))) {
  
  stop(
    "count-sarakkeessa on arvoja, joita ei voitu ",
    "muuntaa numeerisiksi."
  )
}

if (any(dat_raw$count <= 0)) {
  
  warning(
    "Lähtöaineistossa on nolla- tai negatiivisia count-arvoja. ",
    "Ne säilytetään tarkistusta varten, vaikka lähtöaineiston ",
    "oletettiin sisältävän vain positiivisia havaintoja."
  )
}

#========================================================
# 6. Korjaa lajien mahdolliset kirjoitusasut
#========================================================

dat_raw <- dat_raw %>%
  mutate(
    species = case_when(
      
      species %in% c(
        "Lymantria_monacha",
        "Lymantria  monacha"
      ) ~ "Lymantria monacha",
      
      species %in% c(
        "Bupalus piniaria",
        "Bupalus_piniaria",
        "Bupalus_piniarius",
        "Bupalus  piniarius"
      ) ~ "Bupalus piniarius",
      
      species %in% c(
        "Panolis_flammea",
        "Panolis  flammea"
      ) ~ "Panolis flammea",
      
      species %in% c(
        "Epirrita_autumnata",
        "Epirrita  autumnata"
      ) ~ "Epirrita autumnata",
      
      species %in% c(
        "Operophtera_brumata",
        "Operophtera  brumata"
      ) ~ "Operophtera brumata",
      
      species %in% c(
        "Operophtera_fagata",
        "Operophtera  fagata"
      ) ~ "Operophtera fagata",
      
      TRUE ~ species
    )
  )

#========================================================
# 7. Tarkista kohdelajien löytyminen
#========================================================

species_check <- dat_raw %>%
  filter(
    species %in% target_species
  ) %>%
  count(
    species,
    name = "n_positive_rows"
  ) %>%
  complete(
    species = target_species,
    fill = list(
      n_positive_rows = 0
    )
  ) %>%
  arrange(
    match(species, target_species)
  )

message("")
message("Kohdelajien positiiviset havaintorivit:")
print(species_check)

missing_target_species <- species_check %>%
  filter(n_positive_rows == 0) %>%
  pull(species)

if (length(missing_target_species) > 0) {
  
  warning(
    paste0(
      "Seuraaville kohdelajeille ei löytynyt yhtään havaintoa: ",
      paste(missing_target_species, collapse = ", ")
    )
  )
}

#========================================================
# 8. Luo yksilöllinen pyyntijaksotunnus
#========================================================
#
# Sama rysä ja sama pyyntijakso muodostavat yhden näytteen.
#
# Jos aineistossa on erillinen trap_id-sarake, se otetaan
# mukaan tunnukseen. Muuten käytetään site-tunnusta.
#========================================================

if ("trap_id" %in% names(dat_raw)) {
  
  dat_raw <- dat_raw %>%
    mutate(
      trap_id = as.character(trap_id),
      
      sample_id = paste(
        site,
        trap_id,
        PvmLoppu,
        end_DateN,
        sep = "_"
      )
    )
  
} else {
  
  dat_raw <- dat_raw %>%
    mutate(
      trap_id = site,
      
      sample_id = paste(
        site,
        PvmLoppu,
        end_DateN,
        sep = "_"
      )
    )
}

#========================================================
# 9. Yhdistä saman lajin mahdolliset päällekkäiset rivit
#========================================================
#
# Jos sama laji esiintyy samassa näytteessä usealla rivillä,
# yksilömäärät summataan ennen nollien täydentämistä.
#========================================================

identifier_columns <- c(
  "sample_id",
  "site",
  "trap_id",
  "PvmLoppu",
  "end_DateN"
)

# Säilytetään mahdolliset näytekohtaiset lisäsarakkeet.
# Niiden tulee olla samoja saman sample_id:n sisällä.
possible_sample_columns <- setdiff(
  names(dat_raw),
  c(
    "species",
    "count"
  )
)

# Tarkistetaan, että jokaisella sample_id:llä on vain yksi
# site/start/end-yhdistelmä.
sample_conflicts <- dat_raw %>%
  group_by(sample_id) %>%
  summarise(
    n_site = n_distinct(site),
    n_trap = n_distinct(trap_id),
    n_start = n_distinct(PvmLoppu),
    n_end = n_distinct(end_DateN),
    .groups = "drop"
  ) %>%
  filter(
    n_site > 1 |
      n_trap > 1 |
      n_start > 1 |
      n_end > 1
  )

if (nrow(sample_conflicts) > 0) {
  
  stop(
    "Sama sample_id vastaa useita eri pyyntijaksoja. ",
    "Tarkista site-, trap_id- ja päivämääräsarakkeet."
  )
}

# Kohdelajien positiiviset havainnot
target_positive <- dat_raw %>%
  filter(
    species %in% target_species
  ) %>%
  group_by(
    sample_id,
    site,
    trap_id,
    PvmLoppu,
    end_DateN,
    species
  ) %>%
  summarise(
    count = sum(count),
    .groups = "drop"
  )

#========================================================
# 10. Muodosta kaikki todelliset pyyntijaksot
#========================================================
#
# Pyyntijaksot otetaan koko alkuperäisestä aineistosta,
# eivät vain kuuden kohdelajin riveistä.
#
# Tämä on tärkeää: vaikka yhtäkään kohdelajia ei havaittu
# tietyllä pyyntijaksolla, pyyntijakso oli silti olemassa,
# jos siinä havaittiin muita lajeja.
#========================================================

sampling_events <- dat_raw %>%
  distinct(
    sample_id,
    site,
    trap_id,
    PvmLoppu,
    end_DateN
  ) %>%
  mutate(
    interval_days = as.numeric(
      end_DateN - PvmLoppu
    ),
    
    sample_mid_date =
      PvmLoppu +
      floor(interval_days / 2),
    
    year = year(sample_mid_date),
    week = isoweek(sample_mid_date),
    doy = yday(sample_mid_date),
    month = month(sample_mid_date)
  )

# Tyhjennyspäivien erotus voi olla esimerkiksi 7 päivää.
# Jos sekä alku- että loppupäivä ovat pyyntipäiviä,
# todellinen kesto voi olla erotus + 1. Tavallisesti
# rysäaineistossa käytetään päivämäärien erotusta.
sampling_events <- sampling_events %>%
  mutate(
    interval_days = if_else(
      interval_days > 0,
      interval_days,
      NA_real_
    )
  )

if (any(is.na(sampling_events$interval_days))) {
  
  warning(
    "Joillakin pyyntijaksoilla end_DateN ei ole ",
    "PvmLoppu-päivää myöhempi. Näiden count_per_7d-arvoa ",
    "ei voida laskea luotettavasti."
  )
}

message("")
message("Todellisten pyyntijaksojen määrä: ", nrow(sampling_events))

#========================================================
# 11. Lisää kaikki kuusi lajia jokaiselle pyyntijaksolle
#========================================================

moths_complete <- sampling_events %>%
  crossing(
    species = target_species
  ) %>%
  left_join(
    target_positive,
    by = c(
      "sample_id",
      "site",
      "trap_id",
      "PvmLoppu",
      "end_DateN",
      "species"
    )
  ) %>%
  mutate(
    # Puuttuva lajiyhdistelmä tarkoittaa nollahavaintoa,
    # koska pyyntijakso oli olemassa.
    count = replace_na(count, 0),
    
    count_per_7d = if_else(
      !is.na(interval_days) &
        interval_days > 0,
      
      count / interval_days * 7,
      
      NA_real_
    ),
    
    observed = count > 0
  ) %>%
  arrange(
    site,
    trap_id,
    PvmLoppu,
    species
  )

#========================================================
# 12. Tarkista täydennetty aineisto
#========================================================

expected_rows <- nrow(sampling_events) *
  length(target_species)

if (nrow(moths_complete) != expected_rows) {
  
  stop(
    "Täydennetyn aineiston rivimäärä ei vastaa odotettua: ",
    expected_rows,
    "."
  )
}

duplicate_complete <- moths_complete %>%
  count(
    sample_id,
    species,
    name = "n"
  ) %>%
  filter(n > 1)

if (nrow(duplicate_complete) > 0) {
  
  stop(
    "Täydennetyssä aineistossa on päällekkäisiä ",
    "sample_id × species -rivejä."
  )
}

message("")
message("Täydennetyn aineiston rivimäärä: ", nrow(moths_complete))

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
  )

message("")
message("Lajikohtainen yhteenveto:")
print(zero_summary)

#========================================================
# 13. Tallenna täydellinen viikkoaineisto
#========================================================

write.csv(
  moths_complete,
  file.path(
    output_dir,
    "target_moths_weekly_complete_with_zeros.csv"
  ),
  row.names = FALSE,
  na = ""
)

write.table(
  moths_complete,
  file.path(
    output_dir,
    "target_moths_weekly_complete_with_zeros.txt"
  ),
  sep = ";",
  dec = ".",
  row.names = FALSE,
  quote = FALSE,
  na = ""
)

#========================================================
# 14. Lajikohtainen viikoittainen lentojakauma
#========================================================
#
# Lentojakauma lasketaan positiivisten yksilömäärien
# perusteella, mutta täydennetty aineisto säilyttää myös
# aidot nollat myöhempää mallinnusta varten.
#========================================================

flight_week_distribution <- moths_complete %>%
  group_by(
    species,
    week
  ) %>%
  summarise(
    total_count = sum(
      count,
      na.rm = TRUE
    ),
    
    total_count_per_7d = sum(
      count_per_7d,
      na.rm = TRUE
    ),
    
    n_sampling_events = n(),
    
    n_positive_events = sum(
      count > 0
    ),
    
    occurrence_frequency =
      n_positive_events / n_sampling_events,
    
    mean_count_per_event = mean(
      count,
      na.rm = TRUE
    ),
    
    mean_count_per_7d = mean(
      count_per_7d,
      na.rm = TRUE
    ),
    
    .groups = "drop"
  ) %>%
  group_by(species) %>%
  arrange(
    week,
    .by_group = TRUE
  ) %>%
  mutate(
    species_total = sum(
      total_count_per_7d,
      na.rm = TRUE
    ),
    
    flight_proportion = if_else(
      species_total > 0,
      total_count_per_7d / species_total,
      NA_real_
    ),
    
    cumulative_flight_proportion = cumsum(
      replace_na(
        flight_proportion,
        0
      )
    )
  ) %>%
  ungroup()

#========================================================
# 15. Funktio lentoviikon määrittämiseen
#========================================================

get_flight_week <- function(
    week,
    cumulative_proportion,
    probability
) {
  
  valid <- !is.na(week) &
    !is.na(cumulative_proportion)
  
  if (!any(valid)) {
    return(NA_integer_)
  }
  
  week <- week[valid]
  cumulative_proportion <-
    cumulative_proportion[valid]
  
  selected_index <- which(
    cumulative_proportion >= probability
  )[1]
  
  if (is.na(selected_index)) {
    return(NA_integer_)
  }
  
  as.integer(
    week[selected_index]
  )
}

#========================================================
# 16. Lentoajat koko aineistosta
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
    total_count = sum(
      total_count,
      na.rm = TRUE
    ),
    
    total_count_per_7d = sum(
      total_count_per_7d,
      na.rm = TRUE
    ),
    
    first_observed_week = if (
      any(total_count > 0)
    ) {
      min(week[total_count > 0])
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
      week[
        which.max(total_count_per_7d)
      ]
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
      max(week[total_count > 0])
    } else {
      NA_integer_
    },
    
    .groups = "drop"
  ) %>%
  arrange(
    match(species, target_species)
  )

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
# 17. Lentoajat vuosittain
#========================================================

flight_distribution_by_year <- moths_complete %>%
  group_by(
    species,
    year,
    week
  ) %>%
  summarise(
    total_count = sum(
      count,
      na.rm = TRUE
    ),
    
    total_count_per_7d = sum(
      count_per_7d,
      na.rm = TRUE
    ),
    
    n_sampling_events = n(),
    
    n_positive_events = sum(
      count > 0
    ),
    
    .groups = "drop"
  ) %>%
  group_by(
    species,
    year
  ) %>%
  arrange(
    week,
    .by_group = TRUE
  ) %>%
  mutate(
    annual_total = sum(
      total_count_per_7d,
      na.rm = TRUE
    ),
    
    proportion = if_else(
      annual_total > 0,
      total_count_per_7d / annual_total,
      NA_real_
    ),
    
    cumulative_proportion = cumsum(
      replace_na(
        proportion,
        0
      )
    )
  ) %>%
  ungroup()

flight_periods_by_year <- flight_distribution_by_year %>%
  group_by(
    species,
    year
  ) %>%
  summarise(
    annual_count = sum(
      total_count,
      na.rm = TRUE
    ),
    
    annual_count_per_7d = sum(
      total_count_per_7d,
      na.rm = TRUE
    ),
    
    n_sampling_events = sum(
      n_sampling_events
    ),
    
    n_positive_events = sum(
      n_positive_events
    ),
    
    flight_start_week = if (
      annual_count > 0
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
      annual_count > 0
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
      annual_count > 0
    ) {
      week[
        which.max(total_count_per_7d)
      ]
    } else {
      NA_integer_
    },
    
    flight_end_week = if (
      annual_count > 0
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
# 18. Paikka × vuosi × laji -vuosiyhteenveto
#========================================================
#
# Koska moths_complete sisältää kaikki kuusi lajia jokaisella
# todellisella pyyntijaksolla, myös vuosiyhteenvedossa ovat
# mukana nollavuodet silloin, kun rysä oli käytössä mutta
# lajia ei havaittu.
#========================================================

species_annual_abundance <- moths_complete %>%
  group_by(
    site,
    trap_id,
    species,
    year
  ) %>%
  summarise(
    annual_count = sum(
      count,
      na.rm = TRUE
    ),
    
    annual_count_per_7d_sum = sum(
      count_per_7d,
      na.rm = TRUE
    ),
    
    mean_weekly_count = mean(
      count,
      na.rm = TRUE
    ),
    
    mean_weekly_count_per_7d = mean(
      count_per_7d,
      na.rm = TRUE
    ),
    
    maximum_weekly_count = max(
      count,
      na.rm = TRUE
    ),
    
    n_sampling_events = n(),
    
    n_positive_events = sum(
      count > 0
    ),
    
    occurrence_frequency =
      n_positive_events / n_sampling_events,
    
    total_sampling_days = sum(
      interval_days,
      na.rm = TRUE
    ),
    
    first_sampling_date = min(
      PvmLoppu
    ),
    
    last_sampling_date = max(
      end_DateN
    ),
    
    .groups = "drop"
  ) %>%
  arrange(
    site,
    year,
    species
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
# 19. Paikka × vuosi -pyyntikattavuus
#========================================================

sampling_coverage <- sampling_events %>%
  group_by(
    site,
    trap_id,
    year
  ) %>%
  summarise(
    n_sampling_events = n(),
    
    total_sampling_days = sum(
      interval_days,
      na.rm = TRUE
    ),
    
    first_sampling_date = min(
      PvmLoppu
    ),
    
    last_sampling_date = max(
      end_DateN
    ),
    
    first_sampling_week = min(
      week
    ),
    
    last_sampling_week = max(
      week
    ),
    
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
# 20. Lentojakauman kuva
#========================================================

flight_plot <- ggplot(
  flight_week_distribution,
  aes(
    x = week,
    y = total_count_per_7d
  )
) +
  geom_line(
    linewidth = 0.7
  ) +
  geom_point(
    size = 1.4
  ) +
  facet_wrap(
    ~ species,
    scales = "free_y",
    ncol = 2
  ) +
  scale_x_continuous(
    breaks = seq(
      1,
      53,
      by = 4
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
# 21. Vuosittaisten huippuviikkojen kuva
#========================================================

peak_plot_data <- flight_periods_by_year %>%
  filter(
    annual_count > 0,
    !is.na(peak_flight_week)
  )

peak_plot <- ggplot(
  peak_plot_data,
  aes(
    x = year,
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
    x = "Vuosi",
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
# 22. Lopputarkistukset
#========================================================

message("")
message("==============================================")
message("KÄSITTELY VALMIS")
message("==============================================")

message(
  "Alkuperäisiä positiivisia rivejä: ",
  nrow(dat_raw)
)

message(
  "Todellisia pyyntijaksoja: ",
  nrow(sampling_events)
)

message(
  "Täydennettyjä pyyntijakso × laji -rivejä: ",
  nrow(moths_complete)
)

message(
  "Lisättyjä nollarivejä: ",
  sum(moths_complete$count == 0)
)

message(
  "Paikka × vuosi × laji -vuosirivejä: ",
  nrow(species_annual_abundance)
)

message("")
message("Tulokset tallennettiin kansioon:")
message(output_dir)

message("")
message("Tärkeimmät tiedostot:")

message(
  "1. target_moths_weekly_complete_with_zeros.csv"
)

message(
  "2. target_species_flight_periods.csv"
)

message(
  "3. target_species_flight_periods_by_year.csv"
)

message(
  "4. target_species_annual_abundance_with_zeros.csv"
)

message(
  "5. sampling_coverage_by_site_year.csv"
)