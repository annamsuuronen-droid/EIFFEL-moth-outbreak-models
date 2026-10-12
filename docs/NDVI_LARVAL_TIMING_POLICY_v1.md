# NDVI, larval timing, and endogeneity — EIFFEL methodological policy v1

**Stage 1 (current): weather-only.** The six-species annual observation and climate build deliberately reads only `Eiffel_1993_2024.csv` and `Daily_weather_from_NC_needed_trap_years_and_previous_year.txt`. Neither `model_data_environment_nearly_constant_years_filled.csv` nor the separate NDVI sources are required, loaded, joined or modelled. Satellite Greenup and other vegetation phenology are deferred too.

**Stage 2 (future): independent, coverage-aware NDVI assessment.** The file name `Eiffel_NDVI_Landsat_Sentinel_all_buffers_1993_2024.csv` suggests an annual archive over 1993–2024, but does **not** establish that all study site × year × buffer combinations are observed, that there are observations before larvae fed, or that the underlying measurements were available at a historical forecast issue date. The older combined environment table also contains NDVI summaries with potentially different coverage. Validate these sources separately without dropping the rows from the weather-only baseline or duplicating annual moth catches across buffers.

## Cohort-aware timing

For the number of **adult moths trapped in flight year t**, use these provisional larval windows and cohort offsets:

| Species | Larval year for adults t | Provisional feeding interval | Implication for NDVI |
| --- | --- | --- | --- |
| *Epirrita autumnata* | t | May–June | Growing-season NDVI(t) can already contain defoliation by the same cohort. |
| *Operophtera brumata* | t | April–June | Summer NDVI(t) may be post-feeding. |
| *Operophtera fagata* | t | April–June | Summer NDVI(t) may be post-feeding. |
| *Lymantria monacha* | t | May–July | NDVI(t) during/after larvae may measure damage or subsequent recovery. |
| *Bupalus piniarius* (literature: *B. piniaria*) | t − 1 | July–October in t − 1 | NDVI(t − 1) may capture feeding/damage of the adult cohort counted in t. |
| *Panolis flammea* | t − 1 | May–July in t − 1 | NDVI(t − 1) during/after feeding may capture damage of adults counted in t. |

These windows are **candidate phenological ranges**, not verified Finland-wide local timing. Match them against Finnish trap phenology, daily weather, host growth and scene dates before drawing ecological conclusions. A substantial NDVI change is not diagnostic of insect defoliation without independent disturbance evidence.

## Separate scientific interpretations

1. **Before feeding:** Dated, cloud/snow/quality-screened NDVI prior to a cohort's larvae may proxy pre-feeding foliage/host condition. It is a candidate ecological predictor, not automatic proof of causation.
2. **During/after feeding:** NDVI can be *caused* by caterpillar feeding (and many other disturbances), making it inappropriate to interpret uncritically as independent foliage availability. It can instead serve as an exploratory historical *damage/response indicator* if independently validated.
3. **Lagged damage information:** For an adult cohort t that was larval in t − 1, dated NDVI(t − 1) might be genuinely available by the 1 May / 1 June t issue date and could help **predict** abundance as a prior-damage proxy. It still must not be labelled pre-larval environmental quality, and it cannot be used if the source was only processed/released later.
4. **Annual NDVI mean/median/max:** These summaries combine potentially different satellite acquisitions across stages. Without individual acquisition dates and historical availability metadata they are **temporally unresolved**, even if all calendar years are listed. Do not declare their values valid pre-feeding predictors or issue-time features.
5. **Cross-species and forest health:** NDVI is non-specific; other moth species, forestry, drought, snow/cloud cover, Landsat/Sentinel sensor harmonization and canopy composition may affect NDVI. Investigate buffer- and sensor-specific coverage and data quality rather than equating low NDVI with defoliation by the studied species.

## Existing safeguards and next actions

`R/environment/NDVI_TEMPORAL_POLICY_v1.R` supplies an **optional phase-2 audit**, not a production NDVI build. For each species and adult observation year it computes larval year/season. A scene-level NDVI input requires site, `acquisition_date`, `available_date`, `buffer_m` and NDVI value; the audit classifies pre-, during- and post-larval observations and separately checks whether the record was available before an issue date. Even an eligible observation is tagged `forecast_feature_approved = FALSE` until scientific review. Annual NDVI files lacking scene dates are refused rather than guessed.

Comparisons needed after stage 1 QA:
- Establish NDVI observation counts and missing site × year × buffer cells independently of historical weather/catches, but do not change the weather-only analysis sample.
- Recover scene acquisition and release dates for annual composites; if unavailable, confine those NDVI summaries to carefully qualified retrospective association analysis.
- Compare weather-only prediction with a separately preregistered, temporally valid lagged NDVI/damage model on **identical rows and CV folds**, using selection/imputation only on training years.
- Report ecological association, possible insect-caused leaf loss, and operational forecast accuracy as separate estimands; compare affected/non-affected sites and consider independent defoliation data where available.

Do not use annual count or realized end-of-season sampling effort as May/June predictors. Do not refit Hmsc models based solely on temporal audit results. Preserve legacy fits and evidence unchanged.
