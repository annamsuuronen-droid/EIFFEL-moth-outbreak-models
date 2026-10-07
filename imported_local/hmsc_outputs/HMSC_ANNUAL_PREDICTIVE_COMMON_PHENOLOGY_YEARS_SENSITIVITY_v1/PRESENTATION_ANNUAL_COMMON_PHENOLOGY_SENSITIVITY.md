# Annual predictive Hmsc sensitivity to common phenology years

## Role and scope

This is a predictive sensitivity analysis. Weather selection is repeated within the common-phenology period using year-blocked cross-validation, while the full-period primary predictive selection is kept as the reference.
Primary-model PPC status: **DIAGNOSTIC_ONLY_PRIMARY_PPC_REQUIRES_REVIEW**.

## Common phenology period

- Reference group: current_growing_phenology
- Variables: current_growing_start_doy, current_growing_end_doy, current_growing_n_days
- Eligible years: 1993, 1994, 1995, 1996, 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024
- Matched site-years in the final comparison: 1279
- Original and reselected predictor sets identical: TRUE

## Weather-selection stability

- Full-period groups: lag1_summer_temperature, lag1_growing_moisture, lag1_autumn_temperature
- Common-period groups: lag1_summer_temperature, lag1_growing_moisture, lag1_autumn_temperature

| item_type | item | selected_full_period | selected_common_phenology_years | same_selection |
| --- | --- | --- | --- | --- |
| group | lag1_autumn_temperature | TRUE | TRUE | TRUE |
| group | lag1_growing_moisture | TRUE | TRUE | TRUE |
| group | lag1_summer_temperature | TRUE | TRUE | TRUE |
| variable | lag1_autumn_mean_Tmax | TRUE | TRUE | TRUE |
| variable | lag1_growing_sum_precipitation | TRUE | TRUE | TRUE |
| variable | lag1_summer_max_Tmax | TRUE | TRUE | TRUE |
| variable | lag1_summer_mean_Tmax | TRUE | TRUE | TRUE |
| variable | lag1_summer_mean_Tmin | TRUE | TRUE | TRUE |

## Matched-sample predictive comparison

Both models below were evaluated on exactly the same common-period site-years. The table reports both year-blocked and site-blocked cross-validation. Variable selection itself uses cv_year; positive delta SR2 favours the common-period reselected weather model.

| evaluation | species | original_RMSE | original_SR2 | original_O_RMSE | original_O_AUC | original_O_TjurR2 | original_C_RMSE | original_C_SR2 | reselected_RMSE | reselected_SR2 | reselected_O_RMSE | reselected_O_AUC | reselected_O_TjurR2 | reselected_C_RMSE | reselected_C_SR2 | delta_SR2 | delta_RMSE | delta_O_AUC | delta_O_TjurR2 | delta_C_SR2 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| cv_year | Epirrita autumnata | 12775.816 | 0.386 | 0.112 | 0.632 | 0.139 | 12785.813 | 0.384 | 12775.816 | 0.386 | 0.112 | 0.632 | 0.139 | 12785.813 | 0.384 | 0 | 0 | 0 | 0 | 0 |
| cv_year | Operophtera fagata | 139.730 | 0.319 | 0.467 | 0.835 | 0.286 | 186.439 | 0.237 | 139.730 | 0.319 | 0.467 | 0.835 | 0.286 | 186.439 | 0.237 | 0 | 0 | 0 | 0 | 0 |
| cv_year | Operophtera brumata | 131.373 | 0.288 | 0.435 | 0.729 | 0.176 | 139.662 | 0.254 | 131.373 | 0.288 | 0.435 | 0.729 | 0.176 | 139.662 | 0.254 | 0 | 0 | 0 | 0 | 0 |
| cv_site | Epirrita autumnata | 12788.460 | 0.184 | 0.095 | 0.690 | 0.005 | 12798.446 | 0.182 | 12788.460 | 0.184 | 0.095 | 0.690 | 0.005 | 12798.446 | 0.182 | 0 | 0 | 0 | 0 | 0 |
| cv_site | Operophtera fagata | 140.067 | 0.070 | 0.529 | 0.638 | 0.066 | 186.962 | 0.037 | 140.067 | 0.070 | 0.529 | 0.638 | 0.066 | 186.962 | 0.037 | 0 | 0 | 0 | 0 | 0 |
| cv_site | Operophtera brumata | 133.309 | 0.111 | 0.448 | 0.645 | 0.075 | 141.689 | 0.076 | 133.309 | 0.111 | 0.448 | 0.645 | 0.075 | 141.689 | 0.076 | 0 | 0 | 0 | 0 | 0 |

## Posterior predictive checks

### Original weather selection on common-period rows

| model | species | n | posterior_predictive_draws | observed_zero_proportion | predicted_zero_q025 | predicted_zero_median | predicted_zero_q975 | zero_covered_95 | zero_ppc_p | observed_mean | predicted_mean_q025 | predicted_mean_median | predicted_mean_q975 | mean_covered_95 | mean_ppc_p | observed_q95 | predicted_q95_q025 | predicted_q95_median | predicted_q95_q975 | q95_covered_95 | q95_ppc_p | observed_maximum | predicted_maximum_q025 | predicted_maximum_median | predicted_maximum_q975 | maximum_covered_95 | maximum_ppc_p | ppc_status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ANNUAL_COMMON_PERIOD_ORIGINAL_WEATHER | Epirrita autumnata | 1279 | 1000 | 0.002 | 0.050 | 0.063 | 0.077 | FALSE | 0 | 975.614 | 35.008 | 41.522 | 54.313 | FALSE | 0 | 1147.7 | 122 | 146 | 176 | FALSE | 0 | 379332 | 1328.825 | 3359 | 12761.700 | FALSE | 0.00 | REQUIRES_REVIEW |
| ANNUAL_COMMON_PERIOD_ORIGINAL_WEATHER | Operophtera fagata | 1279 | 1000 | 0.439 | 0.652 | 0.675 | 0.698 | FALSE | 0 | 29.267 | 2.101 | 2.972 | 5.054 | FALSE | 0 | 131.3 | 9 | 11 | 15 | FALSE | 0 | 3171 | 120.975 | 369 | 2059.550 | FALSE | 0.02 | REQUIRES_REVIEW |
| ANNUAL_COMMON_PERIOD_ORIGINAL_WEATHER | Operophtera brumata | 1279 | 1000 | 0.117 | 0.385 | 0.412 | 0.441 | FALSE | 0 | 41.785 | 3.740 | 4.701 | 6.418 | FALSE | 0 | 159.2 | 15 | 18 | 22 | FALSE | 0 | 2051 | 143.975 | 379 | 1707.475 | FALSE | 0.03 | REQUIRES_REVIEW |

### Reselected weather model on common-period rows

| model | species | n | posterior_predictive_draws | observed_zero_proportion | predicted_zero_q025 | predicted_zero_median | predicted_zero_q975 | zero_covered_95 | zero_ppc_p | observed_mean | predicted_mean_q025 | predicted_mean_median | predicted_mean_q975 | mean_covered_95 | mean_ppc_p | observed_q95 | predicted_q95_q025 | predicted_q95_median | predicted_q95_q975 | q95_covered_95 | q95_ppc_p | observed_maximum | predicted_maximum_q025 | predicted_maximum_median | predicted_maximum_q975 | maximum_covered_95 | maximum_ppc_p | ppc_status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ANNUAL_COMMON_PERIOD_ORIGINAL_WEATHER | Epirrita autumnata | 1279 | 1000 | 0.002 | 0.050 | 0.063 | 0.077 | FALSE | 0 | 975.614 | 35.008 | 41.522 | 54.313 | FALSE | 0 | 1147.7 | 122 | 146 | 176 | FALSE | 0 | 379332 | 1328.825 | 3359 | 12761.700 | FALSE | 0.00 | REQUIRES_REVIEW |
| ANNUAL_COMMON_PERIOD_ORIGINAL_WEATHER | Operophtera fagata | 1279 | 1000 | 0.439 | 0.652 | 0.675 | 0.698 | FALSE | 0 | 29.267 | 2.101 | 2.972 | 5.054 | FALSE | 0 | 131.3 | 9 | 11 | 15 | FALSE | 0 | 3171 | 120.975 | 369 | 2059.550 | FALSE | 0.02 | REQUIRES_REVIEW |
| ANNUAL_COMMON_PERIOD_ORIGINAL_WEATHER | Operophtera brumata | 1279 | 1000 | 0.117 | 0.385 | 0.412 | 0.441 | FALSE | 0 | 41.785 | 3.740 | 4.701 | 6.418 | FALSE | 0 | 159.2 | 15 | 18 | 22 | FALSE | 0 | 2051 | 143.975 | 379 | 1707.475 | FALSE | 0.03 | REQUIRES_REVIEW |

## Interpretation

Stable selections and small cross-validated changes support temporal robustness of predictive weather selection. PPC remains a separate observation-model diagnostic and should be reviewed independently of predictive CV performance.
