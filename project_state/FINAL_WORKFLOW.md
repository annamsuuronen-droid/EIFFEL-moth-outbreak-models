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
3. Nested outer CV must reselect weather, buffer and environment within each outer training set using inner CV. The imported S3 is a design reference targeting failed v1; the exact successful v2 producer is unrecoverable after the completed local search. The new resume-only reconstruction is documented in [nested_cv_reconstruction_v1/REPORT.md](nested_cv_reconstruction_v1/REPORT.md), with immutable partition/selection exports and a validation-only CLI.
4. Historical folds1–4 have verified outer-year outputs. The user reports reconstructed r2 fold5 complete locally (916 TRAIN / 222 TEST); cloud evidence capture and full five-fold arithmetic verification are pending. Use [recovery v1](outer_year_cv_recovery_v1/README.md), never rerun completed folds or selection. The resulting versioned full-year STATUS.csv becomes the current validation record when captured. No outer-test tuning or historical bitwise-identity claim.
5. Legacy adaptive S4 references selector v1/CV v1; do not execute it. The v2 configuration-only preflight fixes eight full-data variables independently of outer scores, with fitting disabled. Existing C+D v2 full-data model objects are recorded locally. Final PPC evidence is already reviewed and flags upper-tail/zero discrepancies in two species. Inspect provenance/convergence/preparation and observation-model adequacy before justifying any refit. See [site-CV and S4 assessment](outer_year_cv_recovery_v1/NEXT_PREDICTIVE_STAGE.md).

## Population branch still to locate or specify

No population-growth or abundance-forecasting producer/output is evidenced in this synchronized snapshot. S5 neither uses the selected predictive ecology baseline nor compares alternative lags. First locate existing local evidence; do not assume a new analysis is necessary merely because it was not imported.

If a forecast branch is needed, document its ecological baseline, available information at forecast issuance, response, candidate population lags, training-only choices, lag-matched common observations and fully separated outer validation before implementation. Keep growth-model inference separate. Same-year cross-species responses are not advance predictors. Current-year weather and NDVI availability cannot be assumed at an advance forecast cutoff. Held-out-year CV is not automatically chronological forecasting.

## Recovery before expensive work

1. Supplemental import is now present with 51 VERIFIED manifest entries; inspect the recovered summaries separately. For any later recovery, export only the existing metadata/summary paths in [LOCAL_EVIDENCE_REQUEST.csv](audit_v1/LOCAL_EVIDENCE_REQUEST.csv), after content review; keep raw observations, row-level abundance tables, GIS, RData/rds and MCMC objects local. Copy into a new supplemental-import version; do not overwrite imported_local originals or the original manifest. The original sync script is intentionally one-time; do not delete its prior outputs to force a second run.
2. Recover the exact species-specific S3/S4 revisions and any local population scripts separately. The nested-CV v2 producer search is closed; use the controlled reconstruction and verify available local configuration/package/checkpoint compatibility. All 17 on-disk scripts discovered by the original manifest were already imported; missing revisions may need source-history/session recovery.
3. Verify final v4 PPC/fit and S5 sample/effect tables; resolve [scientific review #1](https://github.com/annamsuuronen-droid/EIFFEL-moth-outbreak-models/issues/1). Recover preparation/GIS/zero-filling provenance and extreme-count verification. Missing exports are not a reason to fit models again.
4. Capture locally completed fold5 from D:\EIFFEL_runtime using the reviewed versioned importer and base-R extraction/audit. Preserve completed outputs and old snapshots. No further fitting is authorized; exact historical identity remains unproven and is not required for the labelled r2 compatibility audit. Site CV remains disabled unless a new-site claim is established and a separately frozen/preflighted design is prepared. Do not inspect the concurrent conifer result tree or use the E: backup as active workspace.
5. Once evidence is recovered, update state and registries and create audit_v2. Existing audit/scientific exports stay immutable. Populate separately versioned scientific summaries only from verified source tables.

## Cheap verification

`python tools/audit_imported_lightweight.py --output work/new_audit_directory`

This standard-library utility parses imports, checks manifest coverage, recalculates saved convergence policy flags and recomputes metrics from existing outer-fold predictions. It does not execute R. Audit_v1 records no failed consistency checks, but missing evidence remains explicitly unresolved.

## Current recovery sequence

1. One read-only local capture → primary/checkpoint verification → full five-fold arithmetic audit → scoped evidence commit/push.
2. Independently verify captured SHA256 in cloud and review pooled and equal-fold metrics, reporting matched coverage and mixed producer provenance.
3. Restrict claims to held-out years in the sampled network unless separately validating new sites; do not claim advance forecasting without availability/chronological evidence.
4. Inspect existing full-data v2 fit diagnostics and frozen configuration before deciding whether any S4 fit is required. No site/S4/S5/population execution is authorized.
