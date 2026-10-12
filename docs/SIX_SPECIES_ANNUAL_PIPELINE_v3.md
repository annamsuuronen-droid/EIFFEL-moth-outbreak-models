# EIFFEL: six-species annual data build (PROVISIONAL)

This branch does not run, reselect or overwrite Hmsc models. The scripts are
stored on GitHub; large input data, intermediate results and fitted model
objects remain on the researcher's local D: drive.

## What is built

- Original raw catch observations (`Eiffel_1993_2024.csv`) are expanded to the
  **six target species for recorded sampling intervals only**. Annual counts
  are summed at `(site, flight_year, species)`; January–March records for the
  two *Operophtera* species are assigned to the previous autumn flight year.
  `annual_count` is the actual sum of captures, not the sum of weekly
  effort-standardized counts. `effort_days` is also retained.
- Weather is reconstructed from the source daily weather file. Features for
  **May 1** use weather through **April 30**, for **June 1** weather through
  **May 31**. Also calculate October–March overwinter weather, lag1/lag2
  calendar-year conditions and provisional species-specific life stages.
  Missing weather never becomes zero; lag2 may be unavailable for some years.
- Old-species environmental observation/response and weather columns are **not
  transferred**. Environmental values are deduplicated for each
  `(site, year, buffer_m)` and written to a separate table. Current-year
  environmentally filled values are **not cleared for forecast use**, because
  temporal interpolation can use information from later years.
- Retrospective weather, species-specific seasonal stages, and environmental data can
  be examined in an explanatory candidate file, but explanatory/causal claims are not validated.
- May/June **FEATURES_ONLY** files never contain response counts or realized future
  effort. Response and effort remain in `annual_site_species_flight_year.csv`.
  No future effort offset has yet been justified, so these are not ready-made Hmsc fits.

## Input filenames

Inside `D:\EIFFEL\data`:

- `Eiffel_1993_2024.csv` (semicolon; `PvmAlku` and `PvmLoppu` Finnish dates)
- `Daily_weather_from_NC_needed_trap_years_and_previous_year.txt` (semicolon)
- `model_data_environment_nearly_constant_years_filled.csv` (comma; long buffer table)

Run **from Windows PowerShell with R 4.5.2 and the `data.table` package installed**:

```powershell
& .\tools\run_eiffel_build.ps1 -Mode inspect
& .\tools\run_eiffel_build.ps1 -Mode build
```

`inspect` reads file headers only. `build` writes a uniquely named new output
folder under `D:\EIFFEL_runtime\annual_pipeline_v3` and source MD5 hashes.
Both modes force `TEMP`, `TMP` and `TMPDIR` to `D:\EIFFEL_runtime\temp\R`
BEFORE R starts. The directory has a preflight free-space check. Do not
launch this analysis through plain RStudio/VS Code Run buttons, since those
bypass the temp wrapper.

## Scientific acceptance gates before Hmsc

1. Review exact duplicate raw rows, trapping-interval overlaps, site exclusion,
   annual response/offset alignment and all notable abundance extremes.
2. Review provisional seasonal calendar windows per species; verify timing
   from external biology and actual historical trap seasons. Adult-flight
   weather can affect detection and is not an automatic abundance driver.
3. Audit monthly source coverage, degree-day base, true soil/frost variables,
   weather product units and ecological cold-temperature thresholds.
4. Confirm when each dynamic environmental raster was known; do not use
   future-filled contemporaneous NDVI/VMI/CORINE in advance forecasts.
5. Verify Greenup/leaf phenology from independent data and train-only
   estimation. It is not inferred from the response or the full dataset.
6. Benchmark unchanged historical E/O results and fitted objects before any
   recomputation. Legacy fold scores are not estimates of May/June forecast
   accuracy; keep all existing posterior objects and CV evidence immutable.
7. Perform a nested, chronological outer-validation design; tune and impute
   only on training years and compare identical matched site/species/year
   observations. No heavy modelling until these checks pass.

The stage definitions and environmental joins are **candidates**, not
validated final Hmsc predictors; no fit is run by this script.
## Existing model reuse (read-only)

Do not overwrite or run prior model folders. Existing E./Operophtera five-fold
held-out-year metric tables have been validated separately, but they **do not**
validate May/June advance prediction. Older full-data Hmsc fits can only be reused
for the same response, time attribution, input columns, offsets, scaling and
modelling/validation target after checking provenance, object diagnostics and
posterior predictive checks. Prepare a read-only manifest locally before deciding
what must be refitted.
