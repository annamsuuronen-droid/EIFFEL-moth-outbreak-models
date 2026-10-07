# Annual predictive matched environmental selection

## Model structure

- Response: annual total count.
- Observation model: lognormal Poisson.
- Effort offset: log(total effort days / 7).
- Environment buffer, forward and backward selection use year-blocked predictive cross-validation.
- Selection is based on cv_year SR2; final models also report cv_site performance.
- Occurrence metrics use posterior P(Y > 0) from realized draws.
- Random levels: site and year.
- No flight-week splines; predictive cross-validation is used.
- Analysis status: **PREDICTIVE_ENVIRONMENT_SELECTION_LOCKED_WEATHER_INPUT_NOT_REVALIDATED__FINAL_PPC_REQUIRES_REVIEW**.

### Effort offset multiplier

| species | minimum | q25 | median | mean | q75 | maximum |
| --- | --- | --- | --- | --- | --- | --- |
| Epirrita autumnata | 4 | 7 | 9 | 9.964 | 12 | 25.714 |
| Operophtera fagata | 4 | 7 | 9 | 9.964 | 12 | 25.714 |
| Operophtera brumata | 4 | 7 | 9 | 9.964 | 12 | 25.714 |

## Locked weather model

- Earlier weather-selection evaluation explicitly offset-corrected: TRUE
- Weather groups: lag1_summer_temperature, lag1_growing_moisture, lag1_autumn_temperature
- Weather variables: lag1_summer_mean_Tmin, lag1_summer_mean_Tmax, lag1_summer_max_Tmax, lag1_growing_sum_precipitation, lag1_autumn_mean_Tmax
- Phenology-period and primary predictor sets identical: TRUE

## One selected buffer per comparable ecological group

| ecological_group | selected_buffer_m | variables |
| --- | --- | --- |
| DTW_wetness | 1000 | DTW_lt25m_prop__b1000m/DTW_lt50m_prop__b1000m/DTW_lt100m_prop__b1000m/DTW_lt250m_prop__b1000m/DTW_lt500m_prop__b1000m/DTW_mean__b1000m/DTW_q10__b1000m/DTW_q25__b1000m/DTW_sd__b1000m/DTW_wetness_exp150_mean__b1000m/DTW_wetness_exp150_sd__b1000m/LocalWetPatchIndex__b1000m |
| soil_moisture_retention | 500 | OverwinteringSoilBufferIndex__b500m/SoilMoistureRetentionIndex__b500m/low_soil_retention_lt025_prop__b500m/soil_retention_gt05_prop__b500m/soil_retention_max__b500m/soil_retention_mean__b500m/soil_retention_min__b500m/soil_retention_sd__b500m |
| tree_drought_stress | 50 | HostTreeDroughtStressIndex__b50m/SoilDrynessSensitivityIndex__b50m |
| vegetation_productivity | 100 | NDVI_mean__b100m/NDVI_median__b100m/NDVI_max__b100m |

## Final environmental selection

- Forward-selection status: ENVIRONMENT_GROUPS_SELECTED
| ecological_group | raw_variable | selected_buffer_m | model_variable |
| --- | --- | --- | --- |
| vegetation_productivity | NDVI_mean | 100 | NDVI_mean__b100m |
| vegetation_productivity | NDVI_median | 100 | NDVI_median__b100m |
| vegetation_productivity | NDVI_max | 100 | NDVI_max__b100m |

## Final matched predictive comparison

| comparison | evaluation | species | reference_SR2 | reference_RMSE | candidate_SR2 | candidate_RMSE | delta_SR2 | delta_RMSE |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | cv_year | Epirrita autumnata | 0.387 | 12781.681 | 0.383 | 12783.473 | -0.004 | 1.791 |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | cv_year | Operophtera fagata | 0.307 | 139.796 | 0.326 | 139.775 | 0.020 | -0.021 |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | cv_year | Operophtera brumata | 0.281 | 131.210 | 0.277 | 131.139 | -0.004 | -0.071 |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | cv_site | Epirrita autumnata | 0.194 | 12798.368 | 0.225 | 12798.269 | 0.031 | -0.099 |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | cv_site | Operophtera fagata | 0.039 | 140.193 | 0.058 | 140.141 | 0.020 | -0.052 |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | cv_site | Operophtera brumata | 0.118 | 133.015 | 0.157 | 133.002 | 0.039 | -0.013 |

| comparison | evaluation | mean_delta_SR2 | median_delta_SR2 | min_delta_SR2 | max_delta_SR2 | n_nonnegative_species |
| --- | --- | --- | --- | --- | --- | --- |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | cv_year | 0.004 | -0.004 | -0.004 | 0.020 | 1 |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | cv_site | 0.030 | 0.031 | 0.020 | 0.039 | 3 |

## Posterior predictive checks

### Weather-only model

| model | species | n | posterior_predictive_draws | observed_mean | predicted_mean_q025 | predicted_mean_median | predicted_mean_q975 | mean_covered_95 | mean_ppc_p | observed_zero_proportion | predicted_zero_q025 | predicted_zero_median | predicted_zero_q975 | zero_covered_95 | zero_ppc_p | observed_q95 | predicted_q95_q025 | predicted_q95_median | predicted_q95_q975 | q95_covered_95 | q95_ppc_p | observed_q99 | predicted_q99_q025 | predicted_q99_median | predicted_q99_q975 | q99_covered_95 | q99_ppc_p | observed_maximum | predicted_maximum_q025 | predicted_maximum_median | predicted_maximum_q975 | maximum_covered_95 | maximum_ppc_p | ppc_status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FINAL_ANNUAL_WEATHER_ONLY_MATCHED | Epirrita autumnata | 1277 | 1000 | 975.981 | 305.635 | 360.211 | 457.415 | FALSE | 0.000 | 0.002 | 0.001 | 0.003 | 0.007 | TRUE | 0.436 | 1150.4 | 1093.79 | 1293.6 | 1550.825 | TRUE | 0.176 | 4208.72 | 2915.592 | 4043.34 | 5843.340 | TRUE | 0.82 | 379332 | 9920.825 | 24631.0 | 98344.75 | FALSE | 0.000 | UPPER_TAIL_REQUIRES_REVIEW |
| FINAL_ANNUAL_WEATHER_ONLY_MATCHED | Operophtera fagata | 1277 | 1000 | 29.312 | 27.334 | 38.489 | 74.051 | TRUE | 0.170 | 0.439 | 0.374 | 0.403 | 0.428 | FALSE | 0.006 | 131.6 | 102.79 | 132.6 | 179.415 | TRUE | 0.970 | 499.72 | 411.560 | 649.68 | 1044.127 | TRUE | 0.29 | 3171 | 1918.625 | 5582.5 | 36591.95 | TRUE | 0.382 | REQUIRES_REVIEW |
| FINAL_ANNUAL_WEATHER_ONLY_MATCHED | Operophtera brumata | 1277 | 1000 | 41.560 | 36.038 | 44.437 | 59.742 | TRUE | 0.554 | 0.117 | 0.085 | 0.103 | 0.119 | TRUE | 0.084 | 158.2 | 138.20 | 168.6 | 209.015 | TRUE | 0.558 | 507.24 | 402.219 | 583.88 | 880.166 | TRUE | 0.45 | 2051 | 1364.800 | 3462.5 | 15195.80 | TRUE | 0.338 | OK |

### Weather plus environment model

| model | species | n | posterior_predictive_draws | observed_mean | predicted_mean_q025 | predicted_mean_median | predicted_mean_q975 | mean_covered_95 | mean_ppc_p | observed_zero_proportion | predicted_zero_q025 | predicted_zero_median | predicted_zero_q975 | zero_covered_95 | zero_ppc_p | observed_q95 | predicted_q95_q025 | predicted_q95_median | predicted_q95_q975 | q95_covered_95 | q95_ppc_p | observed_q99 | predicted_q99_q025 | predicted_q99_median | predicted_q99_q975 | q99_covered_95 | q99_ppc_p | observed_maximum | predicted_maximum_q025 | predicted_maximum_median | predicted_maximum_q975 | maximum_covered_95 | maximum_ppc_p | ppc_status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FINAL_ANNUAL_WEATHER_PLUS_ENVIRONMENT_MATCHED | Epirrita autumnata | 1277 | 1000 | 975.981 | 304.370 | 359.644 | 453.140 | FALSE | 0.000 | 0.002 | 0.001 | 0.003 | 0.006 | TRUE | 0.382 | 1150.4 | 1089.79 | 1298.4 | 1547.69 | TRUE | 0.152 | 4208.72 | 2926.517 | 3978.08 | 5729.540 | TRUE | 0.732 | 379332 | 9622.475 | 25169.0 | 104817.75 | FALSE | 0.000 | UPPER_TAIL_REQUIRES_REVIEW |
| FINAL_ANNUAL_WEATHER_PLUS_ENVIRONMENT_MATCHED | Operophtera fagata | 1277 | 1000 | 29.312 | 26.585 | 38.127 | 71.917 | TRUE | 0.168 | 0.439 | 0.377 | 0.403 | 0.428 | FALSE | 0.006 | 131.6 | 101.20 | 131.7 | 178.40 | TRUE | 1.000 | 499.72 | 411.273 | 646.78 | 1046.116 | TRUE | 0.272 | 3171 | 1696.275 | 5553.5 | 34383.78 | TRUE | 0.446 | REQUIRES_REVIEW |
| FINAL_ANNUAL_WEATHER_PLUS_ENVIRONMENT_MATCHED | Operophtera brumata | 1277 | 1000 | 41.560 | 35.696 | 44.543 | 60.172 | TRUE | 0.552 | 0.117 | 0.085 | 0.103 | 0.121 | TRUE | 0.108 | 158.2 | 136.20 | 170.4 | 212.40 | TRUE | 0.498 | 507.24 | 411.836 | 596.54 | 875.866 | TRUE | 0.400 | 2051 | 1344.000 | 3251.5 | 14129.33 | TRUE | 0.352 | OK |

## Occurrence metrics

### Weather-only model

| species | O.RMSE | O.AUC | O.TjurR2 |
| --- | --- | --- | --- |
| Epirrita autumnata | 0.042 | 0.671 | 0.011 |
| Operophtera fagata | 0.347 | 0.913 | 0.478 |
| Operophtera brumata | 0.285 | 0.841 | 0.199 |

### Weather plus environment model

| species | O.RMSE | O.AUC | O.TjurR2 |
| --- | --- | --- | --- |
| Epirrita autumnata | 0.041 | 0.671 | 0.010 |
| Operophtera fagata | 0.347 | 0.914 | 0.481 |
| Operophtera brumata | 0.284 | 0.844 | 0.201 |

## Interpretation

Buffer candidates were compared on matched rows within each ecological group. Environmental groups were then compared on one fixed site-year panel. All comparisons used an explicit effort offset in prediction. UPPER_TAIL_REQUIRES_REVIEW means that the model describes zeros and the central distribution but not the most extreme outbreak years.
