# EIFFEL ecological variables v4 — implementation and limits

This supplements [the six-species pipeline v3](SIX_SPECIES_ANNUAL_PIPELINE_v3.md) and the researcher's Word report (12 October 2026). This is a **candidate-data construction** update, NOT a fitting/selection/validation of Hmsc models. Old predictions and posteriors remain unchanged.

## Newly implemented

- Six species have separate overwinter stages, focal freezing-hypothesis metadata and host-tree/soil priority **metadata** in `species_ecological_registry_REQUIRE_REVIEW.csv`. The table is not used for unvalidated automatic variable selection. Egg freezing thresholds are not transferred to soil pupae.
- *Epirrita autumnata*: -37 C candidate extreme-cold sensitivity (not a verified lethality boundary).
- *Lymantria monacha*: -29.5 C experimental egg freezing median (not a mortality limit).
- *Bupalus piniarius* (often reported as *Bupalus piniaria*): an exploratory 4.9 C GDD developmental base (with 5 C common comparison) for its stage summaries. The source observation name remains stable; taxonomy is documented.
- *Bupalus* and *Panolis*: the **previous-year larval season** and the overwintering **soil pupa** weather periods remain separate. Air minimum temperature and snow do not directly measure soil microclimate. Host priorities include pine and the existing DTW/soil indices.
- Weather-only spring start based on five consecutive days above 0 or 5 C, 50/100 GDD5-crossing dates, *so-far* snow-free runs / last snow days, 30/90d precipitation totals, and 90d antecedent-rain index with a 7-day half-life. These are meteorological **proxies**, not measurements of host budburst, actual caterpillar hatch or snowmelt discharge.
- Rain sums, GDD, cold-day totals and temperature extremes are **NA** unless every date has weather observations. This avoids treating 95% coverage as a full-season total.
- The 1 May forecast only uses weather through 30 April; 1 June through 31 May; explanatory historical ecology is a separate candidate table. Actual post-issue annual catches and realized sampling effort never enter the `*_FEATURES_ONLY_*` files.

## Optional independently observed Greenup

The old Greenup file's observation/publication **availability date is not demonstrated** by its filename or greenup day-of-year alone. Therefore no Greenup is fabricated from climate and historical Greenup is not implicitly authorized for forecasting.

If a **source-audited** independent Greenup table is available, set `$env:EIFFEL_GREENUP_FILE` before running. It must contain unique `site,year,greenup_doy,available_date` rows (CSV comma or TXT semicolon). Example header:

```text
site,year,greenup_doy,available_date
```

Forecast Greenup and `eco_greenup_minus_gdd5_50_proxy_days` become available **only** if both the recorded greenup occurrence and the source's true availability date are on or before the issue cutoff. This latter difference is **not an observed hatch-greenup mismatch**. Without the independent source, those variables stay NA. The `greenup_source_provenance_AUDIT.csv` table explains the missingness.

## Important unfinished scientific decisions

1. Validate species-specific flying seasons from local trap dates and decide how to handle traps spanning New Year. The 2023 observation count is an annual capture total, not absolute population size; the effort offset/standardization and forecast target must be defined before modelling.
2. Validate the ecological period bounds for all six species (notably early *Panolis* flights, and *Operophtera* adult periods extending beyond December). Calendar windows are provisional hypotheses.
3. Validate Greenup metadata/availability and greenup-hatch synchronization; DO NOT confuse the 50 GDD proxy with empirical hatch.
4. Validate the annual conifer species weather feature groups, buffer choice, current-year NDVI release/coverage, and temporally interpolated CORINE/VMI/forest variables. The original filled environment remains historical explanatory data and is NOT merged into forecast features.
5. Choose GDD bases, predictor groups, spatial/buffer scales, weather/host interactions, and standardization on **training years only** within the nested CV. Existing five-fold historical-year evidence is not evidence for 1 May / 1 June operational forecast skill.
6. Recover and audit older Hmsc posterior diagnostics and data provenance before deciding whether any fits can be reused. No old results were deleted or overwritten.

## Local workflow

```powershell
Set-Location D:\EIFFEL-control
git pull --ff-only
& .\tools\run_eiffel_build.ps1 -Mode inspect
# After inspection and scientific QA sign-off:
# & .\tools\run_eiffel_build.ps1 -Mode build
```

The launcher fixes `TMPDIR`, `TMP`, `TEMP` under `D:\EIFFEL_runtime\temp\R` **before Rscript starts**, performs a Windows temp location check, and writes to a timestamped `D:\EIFFEL_runtime\annual_pipeline_v3\build_*` directory. No Hmsc models run in this stage.
