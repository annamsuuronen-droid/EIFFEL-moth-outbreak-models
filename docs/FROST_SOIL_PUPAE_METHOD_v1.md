# Soil-pupa frostmodel: exact legacy definitions and safe reuse (13 Oct 2026)

**Applies to:** *Bupalus piniarius* (also *B. piniaria*) and *Panolis flammea* ONLY, adult flight year Y. Their larvae fed primarily in Y−1; they overwinter as pupae in/near soil. All other species retain NA for these frostmodel covariates. Egg frost survival hypotheses must not be confused with this source.

## Provenance recovered from EIFFEL R code

Original input path in `2.2_EautumnataOperophteraAllEnvironmentAndWeeklySpeciesData(1).R`:

`E:/EIFFEL uusi/EIFFELgis/buffer_outputs/frostmodel/cold_sum20_by_trap_year.csv`

The original R code section 27.8 reads a comma-delimited source and selects `site`, `year`, `n_days20`, `cold_sum20`, `min_tmin`, `mean_tmin_below20`. Section 27.14 joins `site + year` without `buffer_m`. The frost source is **not** CORINE/VMI/DTW/NDVI, and the later interpolation of environmental years explicitly excluded frost.

Previously agreed processing from the daily frost model used the 3rd-order watershed identifier `jako3_id` (not NDVI buffers). Watershed IDs and site spatial matching must be audited against the original shapefile methodology. The exact accepted threshold and summary meaning:

```r
qualifies <- !is.na(frost_Tmin) & frost_Tmin <= -20
n_days20  <- sum(qualifies)
cold_sum20 <- sum(frost_Tmin[qualifies])  # NEGATIVE total of actual Tmin
min_tmin <- min(frost_Tmin, na.rm = TRUE) # minimum over the source's winter interval
mean_tmin_below20 <- if (n_days20 > 0) mean(frost_Tmin[qualifies]) else NA_real_
```

Example: two qualifying days with modelled Tmin −24 and −21 degrees give `n_days20 = 2` and `cold_sum20 = −45` (degrees C·days), **NOT** −5 (threshold excess). If all days exist and no Tmin ≤ −20, `n_days20 = 0`, `cold_sum20 = 0`, `mean_tmin_below20 = NA`. An absent winter/year remains **NA**, not zero.

**Important:** the existing summary CSV fields do not reveal the actual start/end dates of its source winter. Prior calculation discussions used **November Y−1 to March Y**; before final interpretation, verify the frostmodel daily-source code and whether `year` really denotes the matching adult flight year. Verify modelled vertical depth/units and whether they represent the pupal microclimate. Air `Tmin` from the daily weather file must not be used to manufacture these frostmodel variables.

## Implemented pipeline contract

`R/frost/FROST_MODEL_TRAP_YEAR_v1.R` reads the original CSV and preserves original values under familiar names:

| Input | Annual output | Role |
| --- | --- | --- |
| `min_tmin` | `frost_min_tmin` (= requested `frost_min`) | Most extreme modelled winter minimum |
| `cold_sum20` | `frost_cold_sum20` | Negative cumulative Tmin for days ≤ −20 C |
| `n_days20` | `frost_n_days20` | Count of qualifying days |
| `mean_tmin_below20` | `frost_mean_tmin_below20` | Mean of qualifying Tmin, NA if none |

It rejects nonunique site-year keys, impossible positive threshold sums, and incompatible conditional means; NEVER interpolates missing frost years. It does not modify annual moth counts, create buffers, or fit models.

The frost input is **optional** to phase 1. Auto-discovery tries only known D:-drive locations: `D:/EIFFEL/data/inputs_frost/`, `D:/EIFFEL/data/`, and `D:/EIFFEL_runtime/EIFFELgis/buffer_outputs/frostmodel/` for a file named `cold_sum20_by_trap_year.csv`. If more than one exists, choose explicitly; if none exists, records remain NA and an audit is written. To supply the correct CSV explicitly:

```powershell
Set-Location D:\EIFFEL-control
git pull --ff-only
& .\tools\run_eiffel_build.ps1 -Mode inspect -FrostFile "D:\YOUR_ACTUAL_FROST_SOURCE\cold_sum20_by_trap_year.csv"
# After inspect + audit, use -Mode build with the same -FrostFile argument
```

Output in the new timestamped `D:/EIFFEL_runtime/annual_pipeline_v3/build_*` folder:

- `frost_soil_pupae_site_year_EXPLANATORY_CANDIDATES.csv`: matched annual rows and source values, only two soil-pupa species (other four NA).
- `FROST_INPUT_QA.csv`: source path, source coverage and match counts.
- `frost_asof_may01_AUDIT.csv`, `frost_asof_jun01_AUDIT.csv`: independently checked issue-date eligibility.
- `annual_weather_stages_EXPLANATORY_CANDIDATES.csv.gz`: legacy frost candidates for retrospective explanation.
- `predictive_may01_FEATURES_ONLY_UNVALIDATED.csv.gz`, `predictive_jun01_FEATURES_ONLY_UNVALIDATED.csv.gz`: frost predictor present **only** if frost source includes independently validated `winter_end_date` and `available_date` BEFORE the forecast issuance date. Original four-column frost summaries lack these provenance fields; therefore forecasting values remain NA by design. An audited sidecar with dates can be built later without rewriting original numbers.

**Do not mistake scientific absence for a negative result:** a legacy frost CSV without issue-time metadata can be used as a retrospective explanatory candidate, but should not be claimed as a valid historically real-time May/June forecast. Do not use the measured annual response or realized future sampling effort as predictors. Prior Hmsc fits are preserved and require provenance audit before reuse.
