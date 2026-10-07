# Primary analysis: annual predictive Hmsc model

## Workflow

1. The annual response for each species was the total annual count. Trapping effort was included as Loff = log(total effort days / 7).
2. Counts were analysed jointly with a lognormally overdispersed Poisson Hmsc model. Counts were not scaled; continuous predictors were standardised.
3. The sampling unit was a site-year. Site and year were included as random levels; flight-week and spline terms were not used.
4. Weather groups were selected using 5-fold year-blocked cross-validated SR2, followed by group-protected backward elimination using the same predictive criterion.
5. One spatial buffer was first selected for each environmental group using identical site-years for all buffer candidates within that group.
6. Environmental groups at their selected buffer scales were evaluated predictively on top of the locked weather model, and the final model was fitted with the longer MCMC settings.
7. The final model was evaluated with year-blocked CV for new years and site-blocked CV for new sites; explanatory fit, coefficients, posterior predictive checks, convergence diagnostics, and variance partitioning were also retained as diagnostics.

## Data and selected variables

- Species: Epirrita autumnata, Operophtera fagata, Operophtera brumata
- Site-years in the final model: 1279
- Selected weather groups: lag1_summer_temperature, lag1_growing_moisture, lag1_autumn_temperature
- Selected weather variables: lag1_summer_mean_Tmin, lag1_summer_mean_Tmax, lag1_summer_max_Tmax, lag1_growing_sum_precipitation, lag1_autumn_mean_Tmax
- Selected environmental groups: none

### Selected environmental groups and buffers

No rows.

## Predictive and explanatory performance by species

| model | evaluation | species | RMSE | SR2 | O.RMSE | O.AUC | O.TjurR2 | C.RMSE | C.SR2 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FINAL_THREE_SPECIES_ANNUAL | explanatory | Epirrita autumnata | 12759.400 | 0.607 | 0.127 | 0.724 | 0.179 | 12769.386 | 0.605 |
| FINAL_THREE_SPECIES_ANNUAL | explanatory | Operophtera fagata | 137.621 | 0.513 | 0.448 | 0.901 | 0.377 | 183.660 | 0.536 |
| FINAL_THREE_SPECIES_ANNUAL | explanatory | Operophtera brumata | 129.826 | 0.495 | 0.440 | 0.801 | 0.268 | 138.051 | 0.466 |
| FINAL_THREE_SPECIES_ANNUAL | cv_year | Epirrita autumnata | 12775.816 | 0.386 | 0.112 | 0.632 | 0.139 | 12785.813 | 0.384 |
| FINAL_THREE_SPECIES_ANNUAL | cv_year | Operophtera fagata | 139.730 | 0.319 | 0.467 | 0.835 | 0.286 | 186.439 | 0.237 |
| FINAL_THREE_SPECIES_ANNUAL | cv_year | Operophtera brumata | 131.373 | 0.288 | 0.435 | 0.729 | 0.176 | 139.662 | 0.254 |
| FINAL_THREE_SPECIES_ANNUAL | cv_site | Epirrita autumnata | 12788.460 | 0.184 | 0.095 | 0.690 | 0.005 | 12798.446 | 0.182 |
| FINAL_THREE_SPECIES_ANNUAL | cv_site | Operophtera fagata | 140.067 | 0.070 | 0.529 | 0.638 | 0.066 | 186.962 | 0.037 |
| FINAL_THREE_SPECIES_ANNUAL | cv_site | Operophtera brumata | 133.309 | 0.111 | 0.448 | 0.645 | 0.075 | 141.689 | 0.076 |

## Posterior predictive check

| model | species | n | posterior_predictive_draws | observed_zero_proportion | predicted_zero_q025 | predicted_zero_median | predicted_zero_q975 | zero_covered_95 | zero_ppc_p | observed_mean | predicted_mean_q025 | predicted_mean_median | predicted_mean_q975 | mean_covered_95 | mean_ppc_p | observed_q95 | predicted_q95_q025 | predicted_q95_median | predicted_q95_q975 | q95_covered_95 | q95_ppc_p | observed_maximum | predicted_maximum_q025 | predicted_maximum_median | predicted_maximum_q975 | maximum_covered_95 | maximum_ppc_p | ppc_status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FINAL_THREE_SPECIES_ANNUAL | Epirrita autumnata | 1279 | 1000 | 0.002 | 0.050 | 0.063 | 0.076 | FALSE | 0 | 975.614 | 34.943 | 41.598 | 53.776 | FALSE | 0 | 1147.7 | 122.085 | 145 | 176.002 | FALSE | 0 | 379332 | 1265.550 | 3253.5 | 13414.800 | FALSE | 0.000 | REQUIRES_REVIEW |
| FINAL_THREE_SPECIES_ANNUAL | Operophtera fagata | 1279 | 1000 | 0.439 | 0.653 | 0.675 | 0.697 | FALSE | 0 | 29.267 | 2.031 | 2.987 | 5.023 | FALSE | 0 | 131.3 | 8.100 | 11 | 14.100 | FALSE | 0 | 3171 | 127.975 | 384.0 | 2082.175 | FALSE | 0.024 | REQUIRES_REVIEW |
| FINAL_THREE_SPECIES_ANNUAL | Operophtera brumata | 1279 | 1000 | 0.117 | 0.385 | 0.412 | 0.440 | FALSE | 0 | 41.785 | 3.748 | 4.687 | 6.483 | FALSE | 0 | 159.2 | 14.100 | 18 | 22.000 | FALSE | 0 | 2051 | 140.975 | 375.5 | 1765.525 | FALSE | 0.034 | REQUIRES_REVIEW |

## Ecological effects with posterior support of at least 0.95

| species | predictor | posterior_mean | direction | posterior_support |
| --- | --- | --- | --- | --- |
| Epirrita autumnata | lag1_summer_max_Tmax | -0.289 | negative | 1.000 |
| Epirrita autumnata | lag1_summer_mean_Tmin | -0.383 | negative | 1.000 |
| Epirrita autumnata | lag1_summer_mean_Tmax | 0.211 | positive | 0.998 |
| Operophtera brumata | lag1_summer_mean_Tmin | -0.374 | negative | 1.000 |
| Operophtera brumata | lag1_summer_max_Tmax | -0.116 | negative | 0.968 |
| Operophtera fagata | lag1_growing_sum_precipitation | 0.187 | positive | 0.996 |

## Variance partitioning

| model | variance_source | species | variance_proportion |
| --- | --- | --- | --- |
| FINAL_THREE_SPECIES_ANNUAL | Intercept | Epirrita autumnata | 0.000 |
| FINAL_THREE_SPECIES_ANNUAL | Intercept | Operophtera fagata | 0.000 |
| FINAL_THREE_SPECIES_ANNUAL | Intercept | Operophtera brumata | 0.000 |
| FINAL_THREE_SPECIES_ANNUAL | weather | Epirrita autumnata | 0.148 |
| FINAL_THREE_SPECIES_ANNUAL | weather | Operophtera fagata | 0.017 |
| FINAL_THREE_SPECIES_ANNUAL | weather | Operophtera brumata | 0.115 |
| FINAL_THREE_SPECIES_ANNUAL | Random: site | Epirrita autumnata | 0.611 |
| FINAL_THREE_SPECIES_ANNUAL | Random: site | Operophtera fagata | 0.762 |
| FINAL_THREE_SPECIES_ANNUAL | Random: site | Operophtera brumata | 0.642 |
| FINAL_THREE_SPECIES_ANNUAL | Random: year | Epirrita autumnata | 0.242 |
| FINAL_THREE_SPECIES_ANNUAL | Random: year | Operophtera fagata | 0.221 |
| FINAL_THREE_SPECIES_ANNUAL | Random: year | Operophtera brumata | 0.244 |

## Scope of interpretation

Variable selection is based on out-of-sample year-blocked cross-validation. cv_year quantifies prediction to held-out years and cv_site quantifies prediction to held-out sites. Explanatory metrics and coefficients are secondary diagnostics and should not be interpreted as causal effects.
