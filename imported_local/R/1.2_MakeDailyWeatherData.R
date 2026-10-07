library(ncdf4)
library(dplyr)
library(lubridate)

#========================================================
# Asetukset
#========================================================

base_dir <- "//kk11/E1008169$/Documents/EIFFEL"
input_file <- file.path(base_dir, "data/Eiffel 1993_2024.csv")

nc_dir <- "E:/EIFFEL uusi/netcdf"

output_file <- file.path(
  base_dir,
  "data/Daily_weather_from_NC_needed_trap_years_and_previous_year.txt"
)

day_check_file <- file.path(
  base_dir,
  "data/Daily_weather_day_check_needed_years.txt"
)

years_available <- 1992:2024

#========================================================
# Lue ansapaikat ja pyyntivuodet
#========================================================

df_sites <- read.csv(
  input_file,
  dec = ".",
  sep = ";",
  stringsAsFactors = FALSE
)

df_sites$ETRS_TM35FIN_E <- as.numeric(df_sites$ETRS_TM35FIN_E)
df_sites$ETRS_TM35FIN_N <- as.numeric(df_sites$ETRS_TM35FIN_N)
df_sites$site <- as.character(df_sites$site)

if ("PvmLoppu" %in% names(df_sites)) {
  df_sites$PvmLoppu <- as.Date(df_sites$PvmLoppu)
  df_sites$trap_year <- year(df_sites$PvmLoppu)
} else if ("DateN" %in% names(df_sites)) {
  df_sites$DateN <- as.Date(df_sites$DateN)
  df_sites$trap_year <- year(df_sites$DateN)
} else if ("year" %in% names(df_sites)) {
  df_sites$trap_year <- as.integer(df_sites$year)
} else {
  stop("Aineistosta ei löytynyt saraketta PvmLoppu, DateN tai year.")
}

sites <- df_sites %>%
  filter(
    !is.na(site),
    !is.na(ETRS_TM35FIN_E),
    !is.na(ETRS_TM35FIN_N)
  ) %>%
  select(site, ETRS_TM35FIN_E, ETRS_TM35FIN_N) %>%
  distinct()

needed_site_years <- df_sites %>%
  filter(!is.na(site), !is.na(trap_year)) %>%
  select(site, trap_year) %>%
  distinct() %>%
  tidyr::crossing(offset = c(0, -1)) %>%
  mutate(Year = trap_year + offset) %>%
  filter(Year %in% years_available) %>%
  select(site, Year) %>%
  distinct() %>%
  left_join(sites, by = "site") %>%
  filter(!is.na(ETRS_TM35FIN_E), !is.na(ETRS_TM35FIN_N)) %>%
  arrange(Year, site)

print(head(needed_site_years))
print(dim(needed_site_years))

#========================================================
# NetCDF-tiedostojen haku
#========================================================

get_nc_file <- function(measurand, year) {
  
  f <- file.path(
    nc_dir,
    paste0(tolower(measurand), "_", year, ".nc")
  )
  
  if (!file.exists(f)) {
    stop("NetCDF-tiedostoa ei löydy: ", f)
  }
  
  f
}

#========================================================
# NetCDF-pistepoiminta
#========================================================

read_nc_point <- function(ncfile, x, y, value_name, varname, search_radius = 10) {
  
  ncin <- nc_open(ncfile)
  on.exit(nc_close(ncin))
  
  t <- ncvar_get(ncin, "Time")
  
  DateN <- as.Date(
    as.POSIXct(
      t * 24 * 60 * 60,
      origin = "1970-01-01",
      tz = "UTC"
    )
  )
  
  x_grid <- ncin$dim$Lon$vals
  y_grid <- ncin$dim$Lat$vals
  
  x_i <- which.min(abs(x_grid - x))
  y_i <- which.min(abs(y_grid - y))
  
  vals <- ncvar_get(
    ncin,
    varid = varname,
    start = c(x_i, y_i, 1),
    count = c(1, 1, -1)
  )
  
  vals <- as.vector(vals)
  
  if (all(is.na(vals))) {
    
    x_range <- max(1, x_i - search_radius):min(length(x_grid), x_i + search_radius)
    y_range <- max(1, y_i - search_radius):min(length(y_grid), y_i + search_radius)
    
    best_vals <- NULL
    best_dist <- Inf
    
    for (xx in x_range) {
      for (yy in y_range) {
        
        test_vals <- ncvar_get(
          ncin,
          varid = varname,
          start = c(xx, yy, 1),
          count = c(1, 1, -1)
        )
        
        test_vals <- as.vector(test_vals)
        
        if (!all(is.na(test_vals))) {
          
          d <- sqrt((x_grid[xx] - x)^2 + (y_grid[yy] - y)^2)
          
          if (d < best_dist) {
            best_dist <- d
            best_vals <- test_vals
          }
        }
      }
    }
    
    if (!is.null(best_vals)) {
      vals <- best_vals
    }
  }
  
  out <- data.frame(DateN = DateN)
  out[[value_name]] <- vals
  
  out
}

#========================================================
# Päälooppi: vain tarvittavat vuodet / site
#========================================================

Data_weather_all <- NULL

for (yr in sort(unique(needed_site_years$Year))) {
  
  message("Vuosi: ", yr)
  
  snow_file <- get_nc_file("Snow", yr)
  tday_file <- get_nc_file("Tday", yr)
  rr_file   <- get_nc_file("RRday", yr)
  tmax_file <- get_nc_file("Tmax", yr)
  tmin_file <- get_nc_file("Tmin", yr)
  
  sites_this_year <- needed_site_years %>%
    filter(Year == yr)
  
  for (i in seq_len(nrow(sites_this_year))) {
    
    j <- sites_this_year$site[i]
    x <- sites_this_year$ETRS_TM35FIN_E[i]
    y_coord <- sites_this_year$ETRS_TM35FIN_N[i]
    
    message("  paikka: ", j)
    
    DataSnow <- read_nc_point(snow_file, x, y_coord, "MeanSnow", "Snow", 10)
    DataTemp <- read_nc_point(tday_file, x, y_coord, "MeanDailyT", "Tday", 10)
    DataPrec <- read_nc_point(rr_file,   x, y_coord, "SumDailyP", "RRday", 10)
    DataTmax <- read_nc_point(tmax_file, x, y_coord, "Tmax", "Tmax", 10)
    DataTmin <- read_nc_point(tmin_file, x, y_coord, "Tmin", "Tmin", 10)
    
    Data_j <- DataTemp %>%
      full_join(DataPrec, by = "DateN") %>%
      full_join(DataSnow, by = "DateN") %>%
      full_join(DataTmin, by = "DateN") %>%
      full_join(DataTmax, by = "DateN") %>%
      arrange(DateN)
    
    if (nrow(Data_j) == 0) {
      warning("Ei säädataa paikalle ", j, " vuonna ", yr)
      next
    }
    
    Data_j$site <- j
    Data_j$Year <- yr
    Data_j$ETRS_TM35FIN_E <- x
    Data_j$ETRS_TM35FIN_N <- y_coord
    
    Data_weather_all <- bind_rows(Data_weather_all, Data_j)
  }
}

#========================================================
# Siisti
#========================================================

Data_weather_all <- Data_weather_all %>%
  mutate(
    DateN = as.Date(DateN),
    site = as.character(site),
    Year = as.integer(Year)
  ) %>%
  arrange(site, DateN)

#========================================================
# Tarkista päivien määrä per site / vuosi
#========================================================

day_check <- Data_weather_all %>%
  group_by(site, Year) %>%
  summarise(
    min_date = min(DateN),
    max_date = max(DateN),
    n_days = n_distinct(DateN),
    expected_days = ifelse(leap_year(first(Year)), 366, 365),
    missing_days = expected_days - n_days,
    prop_days_available = n_days / expected_days,
    .groups = "drop"
  ) %>%
  arrange(desc(missing_days), site, Year)
print(day_check)

write.day_checkwrite.table(
  day_check,
  file = day_check_file,
  sep = ";",
  row.names = FALSE
)

print(day_check %>% filter(missing_days > 5))

#========================================================
# Tallenna
#========================================================

write.table(
  Data_weather_all,
  file = output_file,
  sep = ";",
  row.names = FALSE
)

print(dim(Data_weather_all))
print(head(Data_weather_all))
summary(Data_weather_all$MeanDailyT)
summary(Data_weather_all$SumDailyP)
summary(Data_weather_all$MeanSnow)