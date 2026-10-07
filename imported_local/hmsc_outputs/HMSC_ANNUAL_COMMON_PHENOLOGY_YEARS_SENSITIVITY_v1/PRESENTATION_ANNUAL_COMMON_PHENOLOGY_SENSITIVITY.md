# Annual Hmsc sensitivity to common phenology years

## Role and scope

This is a diagnostic explanatory sensitivity analysis. It is not cross-validation and it does not refit the full-period primary selection workflow.
Primary-model PPC status: **DIAGNOSTIC_ONLY_PRIMARY_PPC_REQUIRES_REVIEW**.

## Common phenology period

- Reference group: current_growing_phenology
- Variables: current_growing_start_doy, current_growing_end_doy, current_growing_n_days
- Eligible years: 1993, 1994, 1995, 1996, 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024
- Matched site-years in the final comparison: 1298
- Original and reselected predictor sets identical: FALSE

## Weather-selection stability

- Full-period groups: current_summer_temperature, current_spring_moisture_snow, current_annual_moisture, current_annual_temperature, lag2_winter_temperature
- Common-period groups: current_annual_moisture, lag1_winter_moisture_snow, lag2_spring_temperature, lag1_annual_moisture, lag2_season_phenology

| item_type | item | selected_full_period | selected_common_phenology_years | same_selection |
| --- | --- | --- | --- | --- |
| group | current_annual_moisture | TRUE | TRUE | TRUE |
| group | current_annual_temperature | TRUE | FALSE | FALSE |
| group | current_spring_moisture_snow | TRUE | FALSE | FALSE |
| group | current_summer_temperature | TRUE | FALSE | FALSE |
| group | lag1_annual_moisture | FALSE | TRUE | FALSE |
| group | lag1_winter_moisture_snow | FALSE | TRUE | FALSE |
| group | lag2_season_phenology | FALSE | TRUE | FALSE |
| group | lag2_spring_temperature | FALSE | TRUE | FALSE |
| group | lag2_winter_temperature | TRUE | FALSE | FALSE |
| variable | current_annual_API_end | FALSE | TRUE | FALSE |
| variable | current_annual_API_max | TRUE | FALSE | FALSE |
| variable | current_annual_API_mean | TRUE | FALSE | FALSE |
| variable | current_annual_GDD_5 | TRUE | FALSE | FALSE |
| variable | current_annual_cold_exposure_below_minus37 | TRUE | FALSE | FALSE |
| variable | current_annual_days_Tmin_below_minus37 | TRUE | FALSE | FALSE |
| variable | current_annual_max_snow | TRUE | FALSE | FALSE |
| variable | current_annual_min_Tmin | TRUE | FALSE | FALSE |
| variable | current_spring_mean_snow | TRUE | FALSE | FALSE |
| variable | current_summer_mean_Tmax | TRUE | FALSE | FALSE |
| variable | current_summer_mean_Tmin | TRUE | FALSE | FALSE |
| variable | current_summer_min_Tmin | TRUE | FALSE | FALSE |
| variable | lag1_annual_API_max | FALSE | TRUE | FALSE |
| variable | lag1_winter_snowmelt_sum | FALSE | TRUE | FALSE |
| variable | lag2_spring_days_above_10 | FALSE | TRUE | FALSE |
| variable | lag2_thermal_autumn_start_10_doy | FALSE | TRUE | FALSE |
| variable | lag2_winter_days_Tmin_below_minus37 | TRUE | FALSE | FALSE |
| variable | lag2_winter_min_Tmin | TRUE | FALSE | FALSE |

## Matched-sample explanatory comparison

Both models below were fitted to exactly the same site-years. Positive delta SR2 favours the common-period reselected weather model.

| species | original_RMSE | original_SR2 | original_O_RMSE | original_O_AUC | original_O_TjurR2 | original_C_RMSE | original_C_SR2 | reselected_RMSE | reselected_SR2 | reselected_O_RMSE | reselected_O_AUC | reselected_O_TjurR2 | reselected_C_RMSE | reselected_C_SR2 | delta_SR2 | delta_RMSE | delta_O_AUC | delta_O_TjurR2 | delta_C_SR2 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Epirrita autumnata | 12019.926 | 0.641 | 0.157 | 0.907 | 0.507 | 12052.467 | 0.636 | 12022.183 | 0.635 | 0.154 | 0.896 | 0.501 | 12054.730 | 0.630 | -0.007 | 2.257 | -0.012 | -0.006 | -0.006 |
| Operophtera fagata | 107.360 | 0.517 | 0.449 | 0.905 | 0.386 | 140.026 | 0.523 | 107.394 | 0.501 | 0.451 | 0.900 | 0.380 | 140.068 | 0.510 | -0.016 | 0.034 | -0.004 | -0.006 | -0.013 |
| Operophtera brumata | 117.641 | 0.514 | 0.449 | 0.822 | 0.292 | 125.566 | 0.478 | 117.982 | 0.508 | 0.448 | 0.823 | 0.296 | 125.930 | 0.462 | -0.006 | 0.341 | 0.001 | 0.003 | -0.016 |

## Posterior predictive checks

### Original weather selection on common-period rows

| model | species | n | posterior_predictive_draws | observed_zero_proportion | predicted_zero_q025 | predicted_zero_median | predicted_zero_q975 | zero_covered_95 | zero_ppc_p | observed_mean | predicted_mean_q025 | predicted_mean_median | predicted_mean_q975 | mean_covered_95 | mean_ppc_p | observed_q95 | predicted_q95_q025 | predicted_q95_median | predicted_q95_q975 | q95_covered_95 | q95_ppc_p | observed_maximum | predicted_maximum_q025 | predicted_maximum_median | predicted_maximum_q975 | maximum_covered_95 | maximum_ppc_p | ppc_status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ANNUAL_COMMON_PERIOD_ORIGINAL_WEATHER | Epirrita autumnata | 1298 | 1000 | 0.005 | 0.068 | 0.082 | 0.096 | FALSE | 0 | 816.837 | 29.585 | 35.219 | 45.603 | FALSE | 0 | 1039.55 | 108.146 | 128.15 | 153.317 | FALSE | 0 | 379332 | 1004.675 | 2510.5 | 11724.17 | FALSE | 0.000 | REQUIRES_REVIEW |
| ANNUAL_COMMON_PERIOD_ORIGINAL_WEATHER | Operophtera fagata | 1298 | 1000 | 0.414 | 0.634 | 0.656 | 0.680 | FALSE | 0 | 28.280 | 2.127 | 2.916 | 4.695 | FALSE | 0 | 134.45 | 9.000 | 12.00 | 15.000 | FALSE | 0 | 1795 | 109.975 | 323.0 | 1720.90 | FALSE | 0.046 | REQUIRES_REVIEW |
| ANNUAL_COMMON_PERIOD_ORIGINAL_WEATHER | Operophtera brumata | 1298 | 1000 | 0.124 | 0.404 | 0.430 | 0.457 | FALSE | 0 | 38.016 | 3.436 | 4.264 | 5.679 | FALSE | 0 | 150.30 | 13.000 | 16.00 | 20.000 | FALSE | 0 | 2051 | 138.000 | 351.0 | 1364.15 | FALSE | 0.012 | REQUIRES_REVIEW |

### Reselected weather model on common-period rows

| model | species | n | posterior_predictive_draws | observed_zero_proportion | predicted_zero_q025 | predicted_zero_median | predicted_zero_q975 | zero_covered_95 | zero_ppc_p | observed_mean | predicted_mean_q025 | predicted_mean_median | predicted_mean_q975 | mean_covered_95 | mean_ppc_p | observed_q95 | predicted_q95_q025 | predicted_q95_median | predicted_q95_q975 | q95_covered_95 | q95_ppc_p | observed_maximum | predicted_maximum_q025 | predicted_maximum_median | predicted_maximum_q975 | maximum_covered_95 | maximum_ppc_p | ppc_status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ANNUAL_COMMON_PERIOD_RESELECTED_WEATHER | Epirrita autumnata | 1298 | 1000 | 0.005 | 0.066 | 0.080 | 0.096 | FALSE | 0 | 816.837 | 29.56 | 35.115 | 44.475 | FALSE | 0 | 1039.55 | 108.15 | 130.525 | 159.004 | FALSE | 0 | 379332 | 966.00 | 2340.5 | 9936.300 | FALSE | 0.000 | REQUIRES_REVIEW |
| ANNUAL_COMMON_PERIOD_RESELECTED_WEATHER | Operophtera fagata | 1298 | 1000 | 0.414 | 0.636 | 0.657 | 0.680 | FALSE | 0 | 28.280 | 2.13 | 2.909 | 4.473 | FALSE | 0 | 134.45 | 9.00 | 11.150 | 15.000 | FALSE | 0 | 1795 | 110.00 | 306.5 | 1749.475 | FALSE | 0.046 | REQUIRES_REVIEW |
| ANNUAL_COMMON_PERIOD_RESELECTED_WEATHER | Operophtera brumata | 1298 | 1000 | 0.124 | 0.403 | 0.430 | 0.455 | FALSE | 0 | 38.016 | 3.40 | 4.243 | 5.721 | FALSE | 0 | 150.30 | 13.00 | 16.000 | 20.000 | FALSE | 0 | 2051 | 124.95 | 325.0 | 1267.075 | FALSE | 0.016 | REQUIRES_REVIEW |

## Interpretation

Stable selections and small matched-sample changes support temporal robustness of weather selection. They do not repair a failed posterior predictive check. If PPC remains poor, the observation model must be reconsidered before the model is treated as final.
