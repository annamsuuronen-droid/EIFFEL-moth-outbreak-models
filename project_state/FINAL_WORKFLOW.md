# Current workflow — verified evidence and scientific readiness

See [model diagnostics v1](model_diagnostics_v1/REPORT.md), [readiness matrix](model_diagnostics_v1/READINESS_MATRIX.csv), and [prioritized plan](model_diagnostics_v1/REMAINING_PLAN.csv). Historical audit/recovery documents are immutable snapshots; this page supersedes their pending-capture status.

## Explanatory inference

Historical explanatory selection retains13 weather predictors and no environment. Species-specific calibrationv2 and finalv4 exports are the latest recorded branch; imported pooled S3/S4 are legacy producers, not their exact implementations. Recovered v4 PPCs still flag autumnata upper tail and fagata zeros. Beta/Gamma/Omega pass recorded classic diagnostic limits; failed V is nonblocking, not converged. Resolve issue#1 and producer/observation provenance before final inference. Generic occurrence columns conflict with dedicated realized-occurrence exports; preserve both and reconcile their estimands in a new version.

S5 uses final explanatoryv4 and calibrationv2 templates, effort-standardized same-year/previous-calendar-year abundances and identical lag-matched baseline/dynamic observations. It remains conditional association evidence, not advance prediction, growth-response inference or lag selection. Do not use its explanatory baseline as the eight-variable predictive ecology baseline.

## Predictive ecological validation

1. Retain full-data C+Dv2 selection: five lag1 weather variables plus NDVI mean/median/max at100m,1277 matched rows. Exact names and fold selections are in diagnosticsv1. Full-data selection and evaluation of the nested selection procedure are distinct.
2. Five outer-year folds are numerically verified for autumnata/brumata/fagata. Preserve historical1–4 and compatibility-r2 fold5, their frozen selections, matched observations and provenance. No outer-test predictor/lag/threshold/buffer tuning. Exact historical producer identity remains unresolved, not hidden by the compatibility label.
3. Preserve completed evidence under `imported_fold5_completed_r2_v1` and full summaries under `outer_year_cv_full_v1`. Explicit Git-EOL restoration must reproduce recorded size/SHA256/MD5 before using temporary source-byte copies. The cloud base-R audit and Python independently reproduce real arithmetic; primary input identities are local attestations.
4. Report conditional coverage1229/1430,31/32years,1993excluded; signed-squared-Spearman SR2, count-median RMSE, occurrence class support and mixed environmental increments. No six-species, causal, spatial or chronological-advance claim follows from this evidence.
5. Inspect already-existing full-data fits read-only. Predictive chain diagnostics are missing; PPC discrepancies persist. Legacy adaptiveS4 has stalev1 inputs; correctedv2 preflight is configuration-only. Do not execute S4/S5/MCMC because a completion flag or arithmetic validation passed.

## Readiness gates and future stages

First recover predictive posterior/execution summaries and count/offset/extreme preparation evidence. Diagnose Monte Carlo uncertainty separately from observation-model adequacy. Resolve failed nonblockingV policy and occurrence-export inconsistencies. Retain fits/exports unchanged until a correction is evidenced; changed producers/likelihood/data require separately versioned results and validation.

Define deployment target, forecast issuance, current-year weather/NDVI availability and unseen site/year treatment before future validation. Existing fixed-predictor siteCV is exploratory because selection/scaling use the full panel. Spatial/new-site claims require training-only nested site/external validation. Shuffled-year validation does not establish chronological advance forecasts. Prepare cheap design/preflight first; no such expensive run was executed or authorized here.

Locate existing population-growth/forecast workflows before implementing new ones. Keep growth inference distinct from abundance forecasting; predictive lags must use identical lag-matched observations and training-only choice. Same-year cross-species associations cannot be advance predictors. Independent outbreak labels/threshold validation follows an adequate, correctly validated forecasting model.

## Reproducible lightweight review

`python tools/assess_model_readiness_v1.py --output <new directory>` checks hashes, saved metrics, coverage, selections, PPC flags and diagnostic gates without R/models; existing output directories are refused. Versioned outputs and input fingerprints are under `model_diagnostics_v1`. Windows safety and base-R arithmetic tests run in CI; synthetic refusal tests are distinct from real-evidence recomputation.

Retain D:\EIFFEL_runtime as active existing-output root; preserve the E: backup, imported snapshots and all scientific results. The concurrent conifer job is protected. No new capture or expensive fitting is the current next step; the remaining evidence review needs read-only local posterior/preparation access.
