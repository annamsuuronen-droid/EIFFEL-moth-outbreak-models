# Validation scope, site-CV decision and S4 assessment

## Outer-year question and scope

Retained `imported_local/R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC.R` defines year CV as primary and site CV as secondary. Frozen v2 exports implement shuffled held-out-year blocks with inner selection and training-only scaling. They assess the complete ecological selection/prediction procedure in unseen calendar-year blocks within the sampled site network, on rows with the selected covariates available. This permits temporal out-of-sample predictive comparison of WEATHER_ONLY and WEATHER_PLUS_ENVIRONMENT under that design.

It is not a chronological forward forecast: training may include later years, and some candidate weather groups are current-year. Site/year random effects and NDVI may carry information unavailable at an advance issuance cutoff. Availability/preparation provenance still needs verification before advance-forecast or outbreak-warning claims. Missing-covariate coverage (1229/1430) must accompany any performance statement.

## Is outer-site CV required?

**Not required for the restricted primary claim above; required if the manuscript claims transfer to new sites, unsampled forests, spatial mapping or geographically independent outbreak prediction.** Site CV addresses predictions for held-out locations rather than held-out years. Present METHODS_DRAFT/RESULTS_DRAFT/FIGURE_PLAN are scaffolds and do not establish a spatial-transfer manuscript claim. Therefore current evidence supports proceeding with the primary temporal claim, with no automatic site run. It does not support declaring site CV unnecessary for every future EIFFEL conclusion.

There are no observed completed v2 outer-site selections/checkpoints/metrics in the imported inventory. Retained v1 gives a defensible design starting point, but the missing v2 producer cannot establish exact historical site-fold selection behavior. A future spatial claim requires an independently versioned, frozen site design, saved partition, inner training-only predictor/buffer selection, matched rows, explicit unseen-site random-level prediction and cheap preflight/synthetic tests **before** any fitting. Leave the present year procedure and candidate logic frozen. No site executor is introduced now.

Year-fold selections cannot be reused for held-out-site selection: they used observations from those sites. Existing fitted checkpoints would be reusable only with identical TRAIN IDs, selected variables, scaling, offsets, profile and random-level units; no such site checkpoints are evidenced. Reuse data preparation, candidate definitions and audited helper code, not year selections/posteriors. Retained v1/r2 demonstrate construction mechanics, not scientific equivalence of an unimplemented site branch.

At the accepted final-fit profile, five site folds × two models require at least ten long final fits: each four-chain fit has 4 × (10000 + 5000 × 20) = 440000 chain iterations, or 4.4 million final-fit chain iterations before inner selection. Inner CV would add many shorter comparison fits. Wall-clock cost cannot be estimated reliably from available completion summaries; local timing evidence is needed. Running legacy v1 now risks altering the frozen candidate/selection logic and would compete with the active conifer workflow. Neither is authorized.

## Full-data predictive model and stale S4

Legacy `imported_local/R/S4_ADAPTIVE_LONG_MCMC_predictive_HMSC.R` references selector v1 and nested CV v1, uses active E: paths, creates output directories immediately, fits adaptive long MCMC, and exports full-data diagnostic results. It must not be sourced for inspection. Its automatic predictor dropping/outcome rounding would undermine an exact frozen configuration if inputs drift. An in-sample PPC/performance export never replaces nested validation.

The latest full-data predictive selector is C+D v2. Its eight frozen predictors are:

- lag1_summer_mean_Tmin
- lag1_summer_mean_Tmax
- lag1_summer_max_Tmax
- lag1_growing_sum_precipitation
- lag1_autumn_mean_Tmax
- NDVI_mean__b100m
- NDVI_median__b100m
- NDVI_max__b100m

This selected full-data structure was recorded before the completed outer CV and uses 1277 matched rows. It is **not** the seven-weather/two-environment fold-5 structure. Nested CV evaluates the selection procedure; the full-data selector supplies the final model structure. No outer-test score may choose or revise these predictors, lags, buffers or thresholds.

A fixed full-data model can be justified for applying the validated procedure to all available calibration data, provided primary inputs/availability are suitable for the intended prediction task. However, **a new expensive S4 refit is not yet justified**: the manifest already records `04_final_models/FINAL_ANNUAL_WEATHER_ONLY_MATCHED_Hmsc_model.rds` (169986680 bytes) and `04_final_models/FINAL_ANNUAL_WEATHER_PLUS_ENVIRONMENT_MATCHED_Hmsc_model.rds` (183315952 bytes) under the v2 selector. Imported final performance summaries exist, but labels such as `explanatory_offset_corrected` are diagnostic/calibration metadata; they do not establish adequate final-posterior convergence. Recovered supplemental final offset-corrected PPC tables are present and agree with the presentation: both models flag E. autumnata upper-tail/mean/max coverage and O. fagata zero coverage. All 30 saved interval-coverage flags reproduce; the two alternate-name PPC exports are exact blob-identical aliases, not independent fits. See EXISTING_FULL_DATA_PPC_REVIEW.csv. Final convergence evidence for the exact large objects remains unestablished; inspect execution/convergence records and preparation/outlier provenance before deciding whether those fits suffice.

`R/S4_PREDICTIVE_FULL_DATA_v2_CONFIG_PREFLIGHT.R` supplies a corrected **configuration-only** stage with v2 selector, primary prepared input, frozen eight variables, matched-row target and v2 full-year audit gate. Dry-run reports pending CV evidence without touching files. Optional local input checks read only the capped selector/primary input, reject drift/zero variance rather than silently dropping variables, and never open large final model objects. Fitting is unconditionally disabled; the accepted r2 profile is a recorded compatibility reference, not proof of the appropriate S4 adaptive sampling schedule or adequate posterior convergence.

Next legitimate predictive stage after successful capture: inspect existing C+D v2 full-data fit provenance, convergence, posterior predictive adequacy, effort offsets and forecast-covariate availability. Reuse suitable existing fits. If evidence proves further MCMC necessary, prepare a separate versioned executor with explicit diagnostic policy, primary/CV checks and no competing-job guard before seeking a future execution decision. More MCMC does not repair observation-model misspecification. S5/explanatory associations and population forecasting remain distinct analyses; this recovery authorizes neither refitting nor new population models.

## Existing full-data PPC evidence actually reviewed

Read both recovered `FINAL_ANNUAL_*_MATCHED_PPC_offset_corrected.csv2` tables and their `FINAL_WEATHER_*_MATCHED_PPC.csv2` aliases in `imported_local_evidence_v1/.../04_final_models`. Each table has three species, 1277 rows per species and 1000 predictive draws. Weather-only pair shares Git blob `7c898b63a282f24d097b23ecb98a56577bbbbad3`; environment pair shares `b2c9d606e2a6d99b59a94e989fe6d9cbee50d81e`. All 30 interval inclusion checks (mean, zero proportion, q95, q99, maximum × six model/species groups) agree with the saved flags.

- E. autumnata: both models have mean and maximum outside their 95% predictive intervals; `UPPER_TAIL_REQUIRES_REVIEW`. Recorded observed maximum is 379332; weather-plus-environment maximum interval is 9622.475–104817.75. This describes an existing aggregate diagnostic, not a new simulation.
- O. fagata: both models have zero proportion outside its 95% predictive interval; `REQUIRES_REVIEW`. Recorded observed zero proportion is about 0.43853, environment-model interval about 0.37664–0.42835.
- O. brumata: all five aggregate checks covered; recorded `OK`. This alone does not establish convergence or model adequacy for every prediction task.

The retained C+D producer's final profile already uses samples5000/transient10000/thin20/four chains and workers. Source settings do not certify the serialized fits, but contradict any assumption these were merely tiny screening fits. Legacy S4 starts at samples10000/transient20000/thin20/four chains and can escalate four stages; doubling sampling without convergence evidence cannot resolve these PPC mismatches. The next scientific work is verification of observation preparation/extremes, offsets, convergence and model adequacy while keeping outer-test choices frozen. Any changed observation model needs a new validation design/version; do not silently reinterpret or tune the completed outer CV.
