# EIFFEL: six-species annual data build (PROVISIONAL)

This branch does not run, reselect or overwrite Hmsc models. The scripts are
stored on GitHub; large input data, intermediate results and fitted model
objects remain on the researcher's local D: drive.

## What is built

- Source-system rule: **the moth registry records positive species catches
  only**. If a trap was operating and a focal species was absent from the
  source catch list, its count is a **true observed zero**. The build expands
  the six species **only within registered trap events**, never outside
  trapping periods. Annual counts are summed at
  `(site, flight_year, species)`; January–March *Operophtera* records
  belong to the preceding autumn flight year. Explicit-source versus
  reconstructed-zero flags describe provenance, **not imputation**.
  Same-day catches are retained even if interval duration is unknown.
  `effort_days` and `annual_count_per_7d` are then NA instead of an
  invented sampling effort.
- Weather is reconstructed from the source daily weather file. Features for
  **May 1** use weather through **April 30**, for **June 1** weather through
  **May 31**. Also calculate October–March overwinter weather, lag1/lag2
  calendar-year conditions and provisional species-specific life stages.
  Missing weather never becomes zero; lag2 may be unavailable for some years.
- **Phase 1 uses catches, daily weather and an optional separately audited
  frostmodel source** for soil-pupa species. It does **not** read or combine
  NDVI, Greenup, CORINE, forest, DTW or other environmental buffers.
  These require separate later coverage/temporal audits.
- Retrospective weather, species-specific seasonal stages and frostmodel data
  are written as explanatory **candidates**, not scientifically validated
  drivers or a fitted Hmsc model.
- May/June **FEATURES_ONLY** files never contain response counts or realized future
  effort. Response and effort remain in `annual_site_species_flight_year.csv`.
  No future effort offset has yet been justified, so these are not ready-made Hmsc fits.

## Input filenames

Inside `D:\EIFFEL\data`:

- `Eiffel_1993_2024.csv` (semicolon; `PvmAlku` and `PvmLoppu` Finnish dates)
- `Daily_weather_from_NC_needed_trap_years_and_previous_year.txt` (semicolon)
- Optional frostmodel file `cold_sum20_by_trap_year.csv` (comma; site × flight-year aggregates); discoverable under `D:/EIFFEL_runtime/EIFFELgis/buffer_outputs/frostmodel` or passed using `-FrostFile`. The NDVI/other environment tables are **not Phase 1 inputs**.

Run **from Windows PowerShell with R 4.5.2 and the `data.table` package installed**:

```powershell
& .\tools\run_eiffel_build.ps1 -Mode inspect
& .\tools\run_eiffel_build.ps1 -Mode audit
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
