library(ncdf4)
library(dplyr)
options(download.file.method = "wininet")
options(timeout = 7200)

Sys.setenv(
  http_proxy  = "http://sgva02.vyh.fi:81",
  https_proxy = "http://sgva02.vyh.fi:81"
)
#========================================================
# Asetukset
#========================================================
netcdf_dir <- "E:/EIFFEL uusi/netcdf"
dir.create(netcdf_dir, recursive = TRUE, showWarnings = FALSE)

base_dir <- "//kk11/E1008169$/Documents/EIFFEL"
input_file <- file.path(base_dir, "data/Eiffel 1993_2024.csv")
output_file <- file.path(base_dir, "data/Data weather.txt")

years <- 1992:2024

#========================================================
# Lue paikat: koordinaatit ovat jo ETRS-TM35FIN
#========================================================

df <- read.csv(input_file, dec = ".", sep = ";")

df$ETRS_TM35FIN_E <- as.numeric(df$ETRS_TM35FIN_E)
df$ETRS_TM35FIN_N <- as.numeric(df$ETRS_TM35FIN_N)

#========================================================
# FMI NetCDF lataus
#========================================================

fmi_nc_url <- function(measurand, year) {
  paste0(
    "http://fmi-gridded-obs-daily-1km.s3-website-eu-west-1.amazonaws.com/",
    "Netcdf/", measurand, "/", tolower(measurand), "_", year, ".nc"
  )
}

download_fmi_nc <- function(measurand, year, n_try = 10, timeout_sec = 7200) {
  
  url <- fmi_nc_url(measurand, year)
  dest <- file.path(netcdf_dir, paste0(tolower(measurand), "_", year, ".nc"))
  tmp <- paste0(dest, ".part")
  
  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = timeout_sec)
  
  for (i in seq_len(n_try)) {
    
    if (file.exists(dest) && file.info(dest)$size > 0) {
      test <- try(ncdf4::nc_open(dest), silent = TRUE)
      if (!inherits(test, "try-error")) {
        ncdf4::nc_close(test)
        message("Tiedosto on jo ladattu ja toimii: ", dest)
        return(dest)
      } else {
        message("Vanha tiedosto on viallinen, poistetaan: ", dest)
        file.remove(dest)
      }
    }
    
    if (file.exists(tmp)) file.remove(tmp)
    
    message("Ladataan yritys ", i, "/", n_try, ": ", url)
    
    ok <- tryCatch({
      download.file(
        url,
        destfile = tmp,
        mode = "wb",
        method = "wininet",
        quiet = FALSE
      )
      TRUE
    }, error = function(e) {
      message("Lataus epäonnistui: ", conditionMessage(e))
      FALSE
    })
    
    if (ok && file.exists(tmp) && file.info(tmp)$size > 0) {
      
      test <- try(ncdf4::nc_open(tmp), silent = TRUE)
      
      if (!inherits(test, "try-error")) {
        ncdf4::nc_close(test)
        file.rename(tmp, dest)
        message("Lataus onnistui ja NetCDF toimii: ", dest)
        return(dest)
      } else {
        message("Ladattu tiedosto on viallinen tai keskeneräinen, poistetaan ja yritetään uudelleen.")
        file.remove(tmp)
      }
    }
    
    wait <- min(300, 30 * i)
    message("Odotetaan ", wait, " sekuntia ennen uutta yritystä.")
    Sys.sleep(wait)
  }
  
  stop("Tiedoston lataus epäonnistui ", n_try, " yrityksen jälkeen: ", url)
}
#========================================================
# NetCDF-pistepoiminta
#========================================================

read_nc_point <- function(ncfile, x, y, value_name, varname, search_radius = 10) {
  
  ncin <- nc_open(ncfile)
  on.exit(nc_close(ncin))
  
  t <- ncvar_get(ncin, "Time")
  DateN <- as.Date(as.POSIXct(t * 24 * 60 * 60, origin = "1970-01-01", tz = "UTC"))
  
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
# Päälooppi
#========================================================

Data_weather_all <- NULL

for (y in years) {
  
  snow_file <- download_fmi_nc("Snow", y)
  tday_file <- download_fmi_nc("Tday", y)
  rr_file   <- download_fmi_nc("RRday", y)
  tmax_file <- download_fmi_nc("Tmax", y)
  tmin_file <- download_fmi_nc("Tmin", y)
  
  for (j in unique(df$site)) {
    
    dat_j <- df %>% filter(site == j)
    
    x <- dat_j$ETRS_TM35FIN_E[1]
    y_coord <- dat_j$ETRS_TM35FIN_N[1]
    
    message("Käsitellään paikka: ", j)
    message("E = ", x, ", N = ", y_coord)
    
    DataSnow <- read_nc_point(snow_file, x, y_coord, "MeanSnow", "Snow", 10)
    DataTemp <- read_nc_point(tday_file, x, y_coord, "MeanDailyT", "Tday", 10)
    DataPrec <- read_nc_point(rr_file,   x, y_coord, "SumDailyP", "RRday", 10)
    DataTmax <- read_nc_point(tmax_file, x, y_coord, "Tmax", "Tmax", 10)
    DataTmin <- read_nc_point(tmin_file, x, y_coord, "Tmin", "Tmin", 10)
    
    Data_j <- DataTemp %>%
      inner_join(DataPrec, by = "DateN") %>%
      inner_join(DataSnow, by = "DateN") %>%
      inner_join(DataTmin, by = "DateN") %>%
      inner_join(DataTmax, by = "DateN")
    
    Data_j$site <- j
    Data_j$Year <- y
    
    Data_j$ETRS_TM35FIN_E <- x
    Data_j$ETRS_TM35FIN_N <- y_coord
    
    Data_weather_all <- bind_rows(Data_weather_all, Data_j)
  }
}

Data_weather_all <- data.frame(Data_weather_all)
Data_weather_all$site <- as.factor(Data_weather_all$site)


#========================================================
# Tallennus
#========================================================

write.table(
  Data_weather_all,
  file = output_file,
  sep = ";",
  row.names = FALSE
)
