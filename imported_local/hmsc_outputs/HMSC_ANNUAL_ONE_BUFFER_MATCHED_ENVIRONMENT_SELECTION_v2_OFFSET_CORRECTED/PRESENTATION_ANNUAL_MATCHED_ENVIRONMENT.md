# Annual matched environmental selection

## Model structure

- Response: annual total count.
- Observation model: lognormal Poisson.
- Effort offset: log(total effort days / 7).
- Every model comparison uses predict(..., Loff = model$Loff).
- Count SR2 and RMSE use expected offset-corrected count predictions.
- Occurrence metrics use posterior P(Y > 0) from realized draws.
- Random levels: site and year.
- No flight-week splines and no predictive cross-validation.
- Analysis status: **OFFSET_CORRECTED_ENVIRONMENT_SELECTION_LOCKED_WEATHER_INPUT_NOT_REVALIDATED__FINAL_PPC_REQUIRES_REVIEW**.

### Effort offset multiplier

| species | minimum | q25 | median | mean | q75 | maximum |
| --- | --- | --- | --- | --- | --- | --- |
| Epirrita autumnata | 4 | 7 | 9 | 9.964 | 12 | 25.714 |
| Operophtera fagata | 4 | 7 | 9 | 9.964 | 12 | 25.714 |
| Operophtera brumata | 4 | 7 | 9 | 9.964 | 12 | 25.714 |

## Locked weather model

- Earlier weather-selection evaluation explicitly offset-corrected: FALSE
- Weather groups: current_summer_temperature, current_spring_moisture_snow, current_annual_moisture, current_annual_temperature, lag2_winter_temperature
- Weather variables: current_summer_mean_Tmin, current_summer_min_Tmin, current_summer_mean_Tmax, current_spring_mean_snow, current_annual_max_snow, current_annual_API_mean, current_annual_API_max, current_annual_min_Tmin, current_annual_GDD_5, current_annual_days_Tmin_below_minus37, current_annual_cold_exposure_below_minus37, lag2_winter_min_Tmin, lag2_winter_days_Tmin_below_minus37
- Phenology-period and primary predictor sets identical: FALSE

## One selected buffer per comparable ecological group

| ecological_group | selected_buffer_m | variables |
| --- | --- | --- |
| DTW_wetness | 50 | DTW_lt25m_prop__b50m/DTW_lt50m_prop__b50m/DTW_lt100m_prop__b50m/DTW_lt250m_prop__b50m/DTW_lt500m_prop__b50m/DTW_mean__b50m/DTW_q10__b50m/DTW_q25__b50m/DTW_sd__b50m/DTW_wetness_exp150_mean__b50m/DTW_wetness_exp150_sd__b50m/LocalWetPatchIndex__b50m |
| soil_moisture_retention | 100 | OverwinteringSoilBufferIndex__b100m/SoilMoistureRetentionIndex__b100m/low_soil_retention_lt025_prop__b100m/soil_retention_gt05_prop__b100m/soil_retention_max__b100m/soil_retention_mean__b100m/soil_retention_min__b100m/soil_retention_sd__b100m |
| tree_drought_stress | 50 | HostTreeDroughtStressIndex__b50m/SoilDrynessSensitivityIndex__b50m |
| vegetation_productivity | 1000 | NDVI_mean__b1000m/NDVI_median__b1000m/NDVI_max__b1000m |

## Final environmental selection

- Forward-selection status: NO_ENVIRONMENT_GROUP_PASSED_CONFIRMED_SELECTION
No rows.

## Final matched explanatory comparison

| comparison | species | reference_SR2 | candidate_SR2 | delta_SR2 |
| --- | --- | --- | --- | --- |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | Epirrita autumnata | 0.723 | 0.723 | 0 |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | Operophtera fagata | 0.692 | 0.692 | 0 |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | Operophtera brumata | 0.620 | 0.620 | 0 |

| comparison | mean_delta_SR2 | median_delta_SR2 | min_delta_SR2 | max_delta_SR2 | n_nonnegative_species |
| --- | --- | --- | --- | --- | --- |
| FINAL_WEATHER_ONLY_vs_WEATHER_PLUS_ENVIRONMENT_MATCHED | 0 | 0 | 0 | 0 | 3 |

## Posterior predictive checks

### Weather-only model

| model | species | n | posterior_predictive_draws | observed_mean | predicted_mean_q025 | predicted_mean_median | predicted_mean_q975 | mean_covered_95 | mean_ppc_p | observed_zero_proportion | predicted_zero_q025 | predicted_zero_median | predicted_zero_q975 | zero_covered_95 | zero_ppc_p | observed_q95 | predicted_q95_q025 | predicted_q95_median | predicted_q95_q975 | q95_covered_95 | q95_ppc_p | observed_q99 | predicted_q99_q025 | predicted_q99_median | predicted_q99_q975 | q99_covered_95 | q99_ppc_p | observed_maximum | predicted_maximum_q025 | predicted_maximum_median | predicted_maximum_q975 | maximum_covered_95 | maximum_ppc_p | ppc_status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FINAL_ANNUAL_WEATHER_ONLY_MATCHED | Epirrita autumnata | 1298 | 1000 | 816.837 | 268.742 | 312.674 | 396.208 | FALSE | 0.000 | 0.005 | 0.002 | 0.005 | 0.010 | TRUE | 1.000 | 1039.55 | 982.852 | 1154.225 | 1384.475 | TRUE | 0.212 | 2856.06 | 2478.358 | 3381.725 | 4869.215 | TRUE | 0.256 | 379332 | 8109.275 | 20512.0 | 76128.10 | FALSE | 0.000 | UPPER_TAIL_REQUIRES_REVIEW |
| FINAL_ANNUAL_WEATHER_ONLY_MATCHED | Operophtera fagata | 1298 | 1000 | 28.280 | 27.780 | 37.248 | 60.714 | TRUE | 0.078 | 0.414 | 0.355 | 0.379 | 0.402 | FALSE | 0.006 | 134.45 | 111.150 | 141.150 | 186.789 | TRUE | 0.680 | 463.11 | 410.070 | 617.660 | 1019.580 | TRUE | 0.162 | 1795 | 1656.100 | 4448.5 | 23963.35 | TRUE | 0.078 | REQUIRES_REVIEW |
| FINAL_ANNUAL_WEATHER_ONLY_MATCHED | Operophtera brumata | 1298 | 1000 | 38.016 | 32.753 | 40.284 | 52.896 | TRUE | 0.564 | 0.124 | 0.092 | 0.109 | 0.127 | TRUE | 0.110 | 150.30 | 127.049 | 153.825 | 192.022 | TRUE | 0.826 | 457.21 | 368.261 | 523.875 | 776.614 | TRUE | 0.470 | 2051 | 1135.800 | 2962.0 | 10899.92 | TRUE | 0.492 | OK |

### Weather plus environment model

| model | species | n | posterior_predictive_draws | observed_mean | predicted_mean_q025 | predicted_mean_median | predicted_mean_q975 | mean_covered_95 | mean_ppc_p | observed_zero_proportion | predicted_zero_q025 | predicted_zero_median | predicted_zero_q975 | zero_covered_95 | zero_ppc_p | observed_q95 | predicted_q95_q025 | predicted_q95_median | predicted_q95_q975 | q95_covered_95 | q95_ppc_p | observed_q99 | predicted_q99_q025 | predicted_q99_median | predicted_q99_q975 | q99_covered_95 | q99_ppc_p | observed_maximum | predicted_maximum_q025 | predicted_maximum_median | predicted_maximum_q975 | maximum_covered_95 | maximum_ppc_p | ppc_status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FINAL_ANNUAL_WEATHER_ONLY_MATCHED | Epirrita autumnata | 1298 | 1000 | 816.837 | 268.742 | 312.674 | 396.208 | FALSE | 0.000 | 0.005 | 0.002 | 0.005 | 0.010 | TRUE | 1.000 | 1039.55 | 982.852 | 1154.225 | 1384.475 | TRUE | 0.212 | 2856.06 | 2478.358 | 3381.725 | 4869.215 | TRUE | 0.256 | 379332 | 8109.275 | 20512.0 | 76128.10 | FALSE | 0.000 | UPPER_TAIL_REQUIRES_REVIEW |
| FINAL_ANNUAL_WEATHER_ONLY_MATCHED | Operophtera fagata | 1298 | 1000 | 28.280 | 27.780 | 37.248 | 60.714 | TRUE | 0.078 | 0.414 | 0.355 | 0.379 | 0.402 | FALSE | 0.006 | 134.45 | 111.150 | 141.150 | 186.789 | TRUE | 0.680 | 463.11 | 410.070 | 617.660 | 1019.580 | TRUE | 0.162 | 1795 | 1656.100 | 4448.5 | 23963.35 | TRUE | 0.078 | REQUIRES_REVIEW |
| FINAL_ANNUAL_WEATHER_ONLY_MATCHED | Operophtera brumata | 1298 | 1000 | 38.016 | 32.753 | 40.284 | 52.896 | TRUE | 0.564 | 0.124 | 0.092 | 0.109 | 0.127 | TRUE | 0.110 | 150.30 | 127.049 | 153.825 | 192.022 | TRUE | 0.826 | 457.21 | 368.261 | 523.875 | 776.614 | TRUE | 0.470 | 2051 | 1135.800 | 2962.0 | 10899.92 | TRUE | 0.492 | OK |

## Occurrence metrics

### Weather-only model

| species | O.RMSE | O.AUC | O.TjurR2 |
| --- | --- | --- | --- |
| Epirrita autumnata | 0.069 | 0.895 | 0.113 |
| Operophtera fagata | 0.343 | 0.915 | 0.487 |
| Operophtera brumata | 0.290 | 0.852 | 0.218 |

### Weather plus environment model

| species | O.RMSE | O.AUC | O.TjurR2 |
| --- | --- | --- | --- |
| Epirrita autumnata | 0.069 | 0.895 | 0.113 |
| Operophtera fagata | 0.343 | 0.915 | 0.487 |
| Operophtera brumata | 0.290 | 0.852 | 0.218 |

## Interpretation

Buffer candidates were compared on matched rows within each ecological group. Environmental groups were then compared on one fixed site-year panel. All comparisons used an explicit effort offset in prediction. UPPER_TAIL_REQUIRES_REVIEW means that the model describes zeros and the central distribution but not the most extreme outbreak years.
