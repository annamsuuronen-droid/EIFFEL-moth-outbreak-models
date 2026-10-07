# Primary analysis: annual explanatory Hmsc model

## Workflow

1. The annual response for each species was the total annual count. Trapping effort was included as Loff = log(total effort days / 7).
2. Counts were analysed jointly with a lognormally overdispersed Poisson Hmsc model. Counts were not scaled; continuous predictors were standardised.
3. The sampling unit was a site-year. Site and year were included as random levels; flight-week and spline terms were not used.
4. Weather groups were selected using explanatory SR2, followed by group-protected backward elimination.
5. One spatial buffer was first selected for each environmental group using identical site-years for all buffer candidates within that group.
6. Environmental groups at their selected buffer scales were evaluated on top of the locked weather model, and the final model was fitted with the longer MCMC settings.
7. Species-specific coefficients, posterior support, explanatory SR2, occurrence metrics, posterior predictive checks, convergence diagnostics, and variance partitioning were extracted from the final model.

## Data and selected variables

- Species: Epirrita autumnata, Operophtera fagata, Operophtera brumata
- Site-years in the final model: 1298
- Selected weather groups: current_summer_temperature, current_spring_moisture_snow, current_annual_moisture, current_annual_temperature, lag2_winter_temperature
- Selected weather variables: current_summer_mean_Tmin, current_summer_min_Tmin, current_summer_mean_Tmax, current_spring_mean_snow, current_annual_max_snow, current_annual_API_mean, current_annual_API_max, current_annual_min_Tmin, current_annual_GDD_5, current_annual_days_Tmin_below_minus37, current_annual_cold_exposure_below_minus37, lag2_winter_min_Tmin, lag2_winter_days_Tmin_below_minus37
- Selected environmental groups: none

### Selected environmental groups and buffers

No rows.

## Explanatory model fit by species

| model | evaluation | species | RMSE | SR2 | O.RMSE | O.AUC | O.TjurR2 | C.RMSE | C.SR2 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FINAL_THREE_SPECIES_ANNUAL | explanatory | Epirrita autumnata | 12019.827 | 0.642 | 0.158 | 0.911 | 0.502 | 12052.368 | 0.638 |
| FINAL_THREE_SPECIES_ANNUAL | explanatory | Operophtera fagata | 107.357 | 0.507 | 0.450 | 0.904 | 0.385 | 140.027 | 0.511 |
| FINAL_THREE_SPECIES_ANNUAL | explanatory | Operophtera brumata | 117.582 | 0.512 | 0.448 | 0.822 | 0.292 | 125.503 | 0.473 |

## Posterior predictive check

| model | species | n | posterior_predictive_draws | observed_zero_proportion | predicted_zero_q025 | predicted_zero_median | predicted_zero_q975 | zero_covered_95 | zero_ppc_p | observed_mean | predicted_mean_q025 | predicted_mean_median | predicted_mean_q975 | mean_covered_95 | mean_ppc_p | observed_q95 | predicted_q95_q025 | predicted_q95_median | predicted_q95_q975 | q95_covered_95 | q95_ppc_p | observed_maximum | predicted_maximum_q025 | predicted_maximum_median | predicted_maximum_q975 | maximum_covered_95 | maximum_ppc_p | ppc_status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FINAL_THREE_SPECIES_ANNUAL | Epirrita autumnata | 1298 | 1000 | 0.005 | 0.067 | 0.082 | 0.097 | FALSE | 0 | 816.837 | 29.567 | 35.188 | 44.901 | FALSE | 0 | 1039.55 | 106.296 | 127.45 | 153.004 | FALSE | 0 | 379332 | 1014.975 | 2476.0 | 9832.400 | FALSE | 0.000 | REQUIRES_REVIEW |
| FINAL_THREE_SPECIES_ANNUAL | Operophtera fagata | 1298 | 1000 | 0.414 | 0.634 | 0.657 | 0.680 | FALSE | 0 | 28.280 | 2.148 | 2.948 | 4.496 | FALSE | 0 | 134.45 | 9.000 | 12.00 | 15.004 | FALSE | 0 | 1795 | 118.975 | 328.0 | 1455.175 | FALSE | 0.028 | REQUIRES_REVIEW |
| FINAL_THREE_SPECIES_ANNUAL | Operophtera brumata | 1298 | 1000 | 0.124 | 0.404 | 0.430 | 0.455 | FALSE | 0 | 38.016 | 3.403 | 4.287 | 5.788 | FALSE | 0 | 150.30 | 13.150 | 16.00 | 20.000 | FALSE | 0 | 2051 | 131.975 | 359.5 | 1374.275 | FALSE | 0.014 | REQUIRES_REVIEW |

## Ecological effects with posterior support of at least 0.95

| species | predictor | posterior_mean | direction | posterior_support |
| --- | --- | --- | --- | --- |
| Epirrita autumnata | current_summer_mean_Tmax | 0.260 | positive | 1.000 |
| Epirrita autumnata | current_summer_mean_Tmin | -0.393 | negative | 1.000 |
| Epirrita autumnata | current_annual_cold_exposure_below_minus37 | -0.149 | negative | 1.000 |
| Epirrita autumnata | current_annual_GDD_5 | -0.393 | negative | 1.000 |
| Epirrita autumnata | current_annual_max_snow | -0.161 | negative | 0.995 |
| Epirrita autumnata | current_annual_API_max | 0.094 | positive | 0.952 |
| Operophtera brumata | current_annual_GDD_5 | -0.495 | negative | 1.000 |
| Operophtera brumata | current_summer_mean_Tmax | 0.351 | positive | 1.000 |
| Operophtera brumata | current_summer_mean_Tmin | -0.520 | negative | 1.000 |
| Operophtera brumata | lag2_winter_min_Tmin | 0.297 | positive | 1.000 |
| Operophtera brumata | current_annual_cold_exposure_below_minus37 | -0.153 | negative | 0.999 |
| Operophtera brumata | current_annual_API_max | 0.154 | positive | 0.992 |
| Operophtera brumata | current_summer_min_Tmin | 0.130 | positive | 0.979 |
| Operophtera fagata | lag2_winter_min_Tmin | 0.612 | positive | 1.000 |
| Operophtera fagata | current_summer_mean_Tmin | -0.496 | negative | 0.999 |
| Operophtera fagata | current_annual_min_Tmin | 0.361 | positive | 0.996 |
| Operophtera fagata | lag2_winter_days_Tmin_below_minus37 | -0.231 | negative | 0.993 |
| Operophtera fagata | current_annual_cold_exposure_below_minus37 | -0.241 | negative | 0.979 |

## Variance partitioning

| model | variance_source | species | variance_proportion |
| --- | --- | --- | --- |
| FINAL_THREE_SPECIES_ANNUAL | Intercept | Epirrita autumnata | 0.000 |
| FINAL_THREE_SPECIES_ANNUAL | Intercept | Operophtera fagata | 0.000 |
| FINAL_THREE_SPECIES_ANNUAL | Intercept | Operophtera brumata | 0.000 |
| FINAL_THREE_SPECIES_ANNUAL | weather | Epirrita autumnata | 0.225 |
| FINAL_THREE_SPECIES_ANNUAL | weather | Operophtera fagata | 0.202 |
| FINAL_THREE_SPECIES_ANNUAL | weather | Operophtera brumata | 0.201 |
| FINAL_THREE_SPECIES_ANNUAL | Random: site | Epirrita autumnata | 0.533 |
| FINAL_THREE_SPECIES_ANNUAL | Random: site | Operophtera fagata | 0.573 |
| FINAL_THREE_SPECIES_ANNUAL | Random: site | Operophtera brumata | 0.595 |
| FINAL_THREE_SPECIES_ANNUAL | Random: year | Epirrita autumnata | 0.241 |
| FINAL_THREE_SPECIES_ANNUAL | Random: year | Operophtera fagata | 0.225 |
| FINAL_THREE_SPECIES_ANNUAL | Random: year | Operophtera brumata | 0.204 |

## Scope of interpretation

These results describe within-sample explanatory power and conditional ecological associations. Predictive performance must be evaluated later in a separate cross-validation analysis of the locked model.
