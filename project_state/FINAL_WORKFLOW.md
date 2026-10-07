# Current workflow and next steps — Phase 2 audit v1

Source snapshot: `427136e134caf6e93cfdc3080c1520170627a9d5`. [Full audit](audit_v1/REPORT.md), [script roles](audit_v1/SCRIPT_AUDIT.csv), [folder statuses](audit_v1/FOLDER_STATUS.csv) and [recorded predictors](audit_v1/LOCKED_PREDICTORS.csv).

## Observed explanatory branch

1. Annual explanatory S1/S2a selects the historical weather structure; S1/S2b is a common-phenology-period sensitivity, not a replacement selection.
2. Explanatory C+D (`S1_S2_c_d_explanatory model with posterior predictive model checking.R`) performs offset-corrected, matched environment comparisons. Latest selector retains the 13 weather variables and no environmental variables.
3. Latest calibration family is species-specific v2_INFERENCE_GATE; latest final coefficient family is species-specific final v4_INFERENCE_GATE. Exact producing scripts are absent. Imported S3/S4 explanatory scripts are pooled legacy producers and must not be used as though they reproduce those families.
4. Treat v4 coefficients as the latest recorded explanatory export, conditional on producer/PPC recovery and review of its V gate. Do not use pooled legacy Omega/fit results as final inference.
5. S5 species dependencies v2_RANDOMLEVEL_REBUILT continues this explanatory branch, with same-year and exact previous-year effort-normalized species abundance. Baseline/full models use identical lag-matched rows. It is association inference, not population growth or forecast validation.

## Observed predictive ecological branch

1. Predictive S1/S2a selects five lag1 weather variables; predictive common-phenology sensitivity reports the same set.
2. Predictive C+D v2 adds NDVI_mean__b100m, NDVI_median__b100m and NDVI_max__b100m on a 1,277-row panel. This is the eight-variable full-data selected ecological structure. Older primary/no-environment summaries do not supersede C+D.
3. Nested outer CV must reselect weather, buffer and environment within each outer training set using inner CV. The imported S3 is a design reference targeting failed v1; its exact successful v2 producer revision is absent.
4. Latest observed nested CV v2 contains verified outer-year predictions for folds1–4. Fold5 selection/coverage exists, but final predictions do not. Outer-site and final pooled/master outputs are not evidenced. Do not present the partial run as final validation or choose predictors from these outer-test scores.
5. Adaptive predictive S4 references selector v1/CV v1; no output is evidenced. Recover/reconcile its actual version before considering a final long fit. Its in-sample PPC would remain diagnostic rather than predictive validation.

## Population branch still to locate or specify

No population-growth or abundance-forecasting producer/output is evidenced in this synchronized snapshot. S5 neither uses the selected predictive ecology baseline nor compares alternative lags. First locate existing local evidence; do not assume a new analysis is necessary merely because it was not imported.

If a forecast branch is needed, document its ecological baseline, available information at forecast issuance, response, candidate population lags, training-only choices, lag-matched common observations and fully separated outer validation before implementation. Keep growth-model inference separate. Same-year cross-species responses are not advance predictors. Current-year weather and NDVI availability cannot be assumed at an advance forecast cutoff. Held-out-year CV is not automatically chronological forecasting.

## Recovery before expensive work

1. Export only the existing metadata/summary paths in [LOCAL_EVIDENCE_REQUEST.csv](audit_v1/LOCAL_EVIDENCE_REQUEST.csv), after content review; keep raw observations, row-level abundance tables, GIS, RData/rds and MCMC objects local. Copy into a new supplemental-import version; do not overwrite imported_local originals or the original manifest. The original sync script is intentionally one-time; do not delete its prior outputs to force a second run.
2. Recover the exact species-specific S3/S4 and nested-CV v2 producer revisions, saved configuration/fingerprints/package versions and any local population scripts. All 17 on-disk scripts discovered by the original manifest were already imported; missing revisions may need source-history/session recovery.
3. Verify final v4 PPC/fit and S5 sample/effect tables; resolve [scientific review #1](https://github.com/annamsuuronen-droid/EIFFEL-moth-outbreak-models/issues/1). Recover preparation/GIS/zero-filling provenance and extreme-count verification. Missing exports are not a reason to fit models again.
4. Inspect local CV progress and checkpoints. Resume unfinished fold5/site-CV only when missing completion is confirmed and code/configuration compatibility is established; preserve completed fits and version any changes. Do not use outer-test performance to choose a revised candidate set, lag, threshold or buffer.
5. Once evidence is recovered, update state and registries and create audit_v2. Existing audit/scientific exports stay immutable. Populate separately versioned scientific summaries only from verified source tables.

## Cheap verification

`python tools/audit_imported_lightweight.py --output work/new_audit_directory`

This standard-library utility parses imports, checks manifest coverage, recalculates saved convergence policy flags and recomputes metrics from existing outer-fold predictions. It does not execute R. Audit_v1 records no failed consistency checks, but missing evidence remains explicitly unresolved.
