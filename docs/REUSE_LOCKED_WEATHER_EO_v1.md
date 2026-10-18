# EIFFEL: reuse prior weather selection without repeating S1/S2 (13 Oct 2026)

## Decision

For **Epirrita autumnata**, **Operophtera brumata** and **Operophtera fagata**, keep previously selected climate variables **locked**. Do NOT rerun the broad weather pre-screen, forward/backward selection, exploratory environmental group selection, or full historical Hmsc fits merely because the six-species weather data are being rebuilt.

The original selections and separate explanatory and predictive evidence already exist in this repository. Read them **as evidence**, not as proof of new scientific validity. The other three species (*Lymantria monacha*, *Bupalus piniarius*, *Panolis flammea*) have their own ecological stage candidates and are not automatically assigned the three-species locked weather set.

## Two historical, NON-INTERCHANGEABLE selection branches

**Retrospective explanatory + S5 baseline — 13 locked variables:**

```text
current_summer_mean_Tmin
current_summer_min_Tmin
current_summer_mean_Tmax
current_spring_mean_snow
current_annual_max_snow
current_annual_API_mean
current_annual_API_max
current_annual_min_Tmin
current_annual_GDD_5
current_annual_days_Tmin_below_minus37
current_annual_cold_exposure_below_minus37
lag2_winter_min_Tmin
lag2_winter_days_Tmin_below_minus37
```

Evidence: `imported_local_evidence_v1/hmsc_outputs/HMSC_ANNUAL_PRIMARY_EXPLANATORY_LOGNORMAL_POISSON_v1/selected_weather_variables_final.txt`, and `project_state/audit_v1/LOCKED_PREDICTORS.csv`. Historical explanatory performance did not establish valid May/June advance prediction; later-year climate and E. autumnata cold thresholds must not be silently generalized to other taxa.

**Historical year-blocked predictive selection — 5 locked variables:**

```text
lag1_summer_mean_Tmin
lag1_summer_mean_Tmax
lag1_summer_max_Tmax
lag1_growing_sum_precipitation
lag1_autumn_mean_Tmax
```

Evidence: `imported_local_evidence_v1/hmsc_outputs/HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1/selected_weather_variables_final.txt`, `project_state/audit_v1/LOCKED_PREDICTORS.csv`, and the historical matched predictive environment comparison. These lagged weather variables are plausible information available by 1 May or 1 June of year t **subject to exact time-index and source-availability checks**. Old blocked-CV is not itself unbiased validation of newly revised outcomes. Nested outer-year v2 includes fold-specific selected variable sets that may differ from this global fixed set; do not relabel one as the other.

## Fast audit only: no R model fitting

The committed script `R/validation/AUDIT_REUSE_LOCKED_WEATHER_v1.R` compares both historical source selection lists to the locked evidence manifest and **only reads the headers** of any historical weather tables it finds. It creates CSV source-schema coverage reports, not new model results or weather-screening fits. It does **not** load the full ~1GB environmental table.

Run in Windows PowerShell after `git pull --ff-only`:

```powershell
Set-Location D:\EIFFEL-control
& .\tools\run_eiffel_build.ps1 -Mode inspect -Script "D:\EIFFEL-control\R\validation\AUDIT_REUSE_LOCKED_WEATHER_v1.R"
```

The audit searches the older daily-weather/phenology file `D:\EIFFEL\data\Epirrita_Operophtera_species_weather_greenup_current_lag1_lag2.txt` and the existing combined `D:\EIFFEL\data\model_data_environment_nearly_constant_years_filled.csv`. You can choose an explicit alternate archive by setting `$env:EIFFEL_HISTORICAL_WEATHER` beforehand. The new CSV reports are timestamped under `D:\EIFFEL_runtime\annual_pipeline_v3\locked_weather_audit_*`. `EXACT_COLUMN_PRESENT` means only that an identically named column exists; it is NOT a numerical or ecological equivalence certificate.

For comparing with a **particular successfully completed** new annual build directory, set `$env:EIFFEL_AUDIT_BUILD_DIR` to its complete path before running the audit; do not choose an incomplete folder. The audit checks exact variable names in that build. Differences are expected: the new v3/4 weather-only pipeline has narrower seasonal features and must not replace the previously selected summer/autumn/API variables by similar-looking but different annual summaries.

## Gate before reusing old fits or computing new forecasts

1. Compare observation rows, site/year assignments and genuine observed-zero reconstruction, including uncertain same-day trapping effort. Old models used an offset based on `total_effort_days/7` and a minimum number of trapping intervals; new `NA` efforts need a scientifically justified strategy. Old posterior objects and performance scores cannot simply be attached to a differently defined response.
2. Reuse the previous variables and previously archived selection evidence, **not newly selected substitutes**. Verify each required variable's original ecological season, year lag, input source, missingness and exact units. If column names or definitions differ, produce a conversion/lineage audit before any fit.
3. For retrospective explanatory analysis, historical model objects may be audited read-only; do not rerun full S1/S2. For May/June forecasts use only as-of-valid predictors. Do not promote current-year full growing/summer/annual climate features into a 1 May/1 June forecast.
4. A future prediction/confirmation model, if needed, can fit only the **fixed locked set** after QA, without expensive exploratory screening. Compare on honest held-out future/outer years and ensure training-only estimation. Avoid treating selections made using the full historical record as strictly independent of that record's original CV.
5. Heavy model runs, if ultimately necessary, occur at CSC in **Insects of the north** after validation, never in GitHub Actions or by default in the local data-build script.

This file changes workflow decisions and adds a fast QA utility; it does not certify prior Hmsc convergence or rerun expensive fits.
