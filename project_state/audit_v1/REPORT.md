# Phase 2 evidence audit — version 1

Audited 2026-10-07. Source `main`: `427136e134caf6e93cfdc3080c1520170627a9d5`; local import: `bd4717603df052bb92a3172f630c754df84de30d`.

The audit of available evidence is complete. The project is **not ready for final scientific validation**. Latest workflow roles and recorded selections can be identified, but omitted summaries, missing producer revisions and unfinished validation prevent blanket authority or completeness claims. No R code or scientific model was executed. Existing imported outputs were preserved.

## Scope and verification

The full recursive remote tree was inspected, including root AGENTS.md and the updated project state. All 3,206 repository blobs retrieved for the snapshot matched their Git blob hashes byte-for-byte. All 17 discovered local R scripts were imported. All 3,159 imported non-R files were read and inventoried; all imported text/table summaries were parsed for structure, status and convergence flags. The 8,995-row local manifest records 3,176 copies, with no missing copied files or unmanifested imports.

Cheap checks reproduced 285 recorded component gate decisions and 192 metric values for the four available outer-year folds. The latter includes sample size, count/conditional RMSE, signed squared Spearman correlation, occurrence RMSE, AUC and Tjur R2. All passed. These are consistency checks of saved exports, not independent refits, posterior convergence certification or proof of scientific adequacy. Repeated convergence summaries/stages count as separate records, not independent models. R/Rscript is unavailable here, so no R syntax/runtime validation is claimed.

Reproduce with `python tools/audit_imported_lightweight.py --output work/new_audit_directory`. The tool refuses to overwrite its output directory, uses only the Python standard library and never executes imported scripts. FILE_AUDIT_001–008.csv contain every imported file, its source Git blob, decoded-file checksum, table shape and flags. Other check tables contain no new model estimates or row-level observations.

## Status interpretation

`COMPLETE` means the recorded selection or fitting/export stage has finish evidence appropriate to its role. It does not mean every scientific check passes or every file was imported. For species-specific fits and S5, a local completion marker is recorded in the manifest, but its contents remain unavailable; completion is therefore supported by local inventory plus final gate/exports, not verified marker content. `FAILED` includes failure of the recorded inferential gate, even if computations finished. `LEGACY` denotes a superseded or incompatible branch. `PARTIAL` preserves genuine unfinished evidence without inventing a failure. `NOT_EVIDENCED` denotes a configured destination with no observed output. No output family can be positively classified as a standalone `TEST` run; embedded quick/smoke-test switches do not establish such a result family.

[FOLDER_STATUS.csv](FOLDER_STATUS.csv) covers all 19 imported output families, the manifest-only S5 v1 family, and the configured predictive S4 destination. [SCRIPT_AUDIT.csv](SCRIPT_AUDIT.csv) covers all 17 scripts. No files have been deleted, moved or relabelled on disk.

## Authoritative roles and final structures

### Explanatory inference

The explanatory selector is `imported_local/R/S1_S2_c_d_explanatory model with posterior predictive model checking.R`. Its offset-corrected C+D output retains weather only; no environmental group passes confirmed selection. This is a selection result, not the final inference fit. The latest explanatory coefficient export is the species-specific `HMSC_ANNUAL_SPECIES_SPECIFIC_FINAL_FITS_v4_INFERENCE_GATE/results/S4_ALL_SPECIES_beta_coefficients.csv2`. It contains the same 13 non-intercept explanatory weather variables for all three species. The five groups are current summer temperature, current spring moisture/snow, current annual moisture, current annual temperature and lag2 winter temperature. Exact variables are in [LOCKED_PREDICTORS.csv](LOCKED_PREDICTORS.csv).

Final v4 Beta maximum PSRF upper/minimum ESS are 1.00178/4632.51 for E. autumnata, 1.01017/400.67 for O. fagata and 1.00160/5448.26 for O. brumata. All recorded blocking components pass. V diagnostics fail for all three species (maximum upper PSRF 1.2663–1.2991 versus 1.10) but the recorded policy makes V non-blocking. `accepted=TRUE` must not be reported as all-components convergence. Issue [#1](https://github.com/annamsuuronen-droid/EIFFEL-moth-outbreak-models/issues/1), labelled `needs-scientific-review`, asks for the scientific rationale and estimand-specific sensitivity evidence for this policy.

Species-specific v4 is the **latest conditional explanatory output source**, not an unqualified final model. Its PPC, explanatory-fit, completion marker and exact producer implementation were excluded or absent. The imported S3 explanatory script instead targets pooled calibration v2; the imported S4 reads pooled calibration v1 and targets pooled final v1. Neither generates species-specific v4. Available species-specific v3/v4 convergence exports are byte-identical; this supports export reuse/supersession, not a claim that their posterior objects are identical.

The older pooled calibration v1/v3/v4 and NF1 trial fail their recorded site-Omega gates. Pooled final v1 also fails (site Omega upper PSRF 1.8398 versus 1.10), despite acceptable Beta. Do not use them to establish final multispecies inference or residual associations.

### Predictive ecological selection and validation

The current full-data selector is `imported_local/R/S1_S2_c_d_PREDICTIVE_environment_selection_with_blocked_CV.R` and output family `HMSC_ANNUAL_PREDICTIVE_ONE_BUFFER_MATCHED_ENVIRONMENT_SELECTION_v2`. Its report and selection summaries establish this eight-variable structure:

| Component | Recorded variables |
| --- | --- |
| Lag1 summer temperature | lag1_summer_mean_Tmin; lag1_summer_mean_Tmax; lag1_summer_max_Tmax |
| Lag1 growing moisture | lag1_growing_sum_precipitation |
| Lag1 autumn temperature | lag1_autumn_mean_Tmax |
| Vegetation productivity, 100 m | NDVI_mean__b100m; NDVI_median__b100m; NDVI_max__b100m |

This corrects a misleading reading of the older primary report, which has no environmental variables. The primary and common-phenology reports agree on the same five weather variables; the later C+D selector adds NDVI. The primary model has 1,279 site-years and C+D has 1,277 matched site-years. Buffer winners for other candidate groups are not retained predictors. The report's final year-CV mean gain is about 0.00370: species deltas approximately -0.00361, +0.01951 and -0.00432. The strong-single-species acceptance rule can admit this group despite two small negative deltas; that alone is not an inconsistency. Do not reselect the group from the reported outer-test gains.

Full-data S1/S2 CV supports selection; it is reused for ranking and scales/correlation-filters the candidate panel before its partition CV. It is not an unbiased outer assessment of the selection pipeline. Older in-sample PPC uses `computePredictedValues` without explicit Loff, whereas C+D uses explicit-offset predictions. C+D's heuristic treating any cv_year metric as evidence of prior offset handling is not a verification of a specific Hmsc package implementation. Recover session/package information and old source revisions before interpreting the old PPC failure as a need to refit.

The nested-CV reference script separates outer train/test, recalculates correlations/availability and predictors using outer training data, scales using each model's training rows and explicitly passes held-out Loff. Its inner comparisons use common rows and grouped folds. It imports original candidate groups/data, not the final eight selected variables. This code is the appropriate design reference. Its configured destination is v1, which has 42 `failed: subscript out of bounds` screen records. The successful v2 producer revision is missing; do not infer byte-identical implementation from the v2 directory name.

The latest observed validation family is `S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2`, which is **PARTIAL**:

| Outer-year fold | All test rows | Final complete test rows | Prediction/metric exports |
| --- | ---: | ---: | --- |
| 1 | 305 | 305 | Present; verified |
| 2 | 274 | 172 | Present; verified |
| 3 | 274 | 242 | Present; verified |
| 4 | 304 | 288 | Present; verified |
| 5 | 273 | 222 | Absent; selection and coverage only |

Available predictions cover 1,007 site-years per model/species. Final selected-covariate completeness would cover 1,229/1,430 rows across all five folds. The 201 excluded test rows and missing fifth-fold predictions must remain explicit. WEATHER_ONLY and WEATHER_PLUS_ENVIRONMENT exports use identical sample IDs and observed values within every completed fold; prediction years match the saved held-out year partitions. No final pooled metrics, finished master result or outer-site records exist in the manifest. Do not call four-fold aggregation the final five-fold result or interpret this as completed forward-year holdout validation.

Fold-level selected weather sets differ considerably; fold1 is intercept-only weather. Folds2/3 include `current_growing_mean_Tmax` / `current_autumn_mean_Tmax`. This nested pipeline permits same-year weather even though the full-data weather set is lag1-only. Random held-out-year CV measures transfer to unseen years, not chronological forecasting without future training data. A forecast information cutoff, candidate availability (including NDVI provenance) and any temporal buffer must be fixed from scientific requirements/training data before a separate forecast evaluation. No post-hoc choice from outer-test performance is justified.

The imported adaptive predictive S4 script still reads matched-selector v1 and nested-CV v1. Its output destination has no manifest entries. A completed long predictive posterior cannot be verified and is not required to check the already saved CV metrics.

### Species dependencies and population dynamics

`imported_local/R/S5_HMSC_annual_species_abundance_dependencies.R` is the observed species-association producer. It reads species-specific explanatory S4 v4 and S3 calibration v2 templates. S4 variables_kept, corroborated by its coefficient table, are the 13-variable explanatory baseline, **not the eight-variable predictive ecological baseline**.

S5 models annual abundance, with effort-normalized predictors `z(log1p(count / exp(Loff)))`: same-year abundance of the two other species, own abundance in exact previous calendar year and the two other species' abundance in that previous year. It matches site and `year - 1`, rejects duplicate site-years and does not substitute nearest years. Baseline and full dynamic models are both fitted on the same complete lag-matched rows within each response species. Random levels are rebuilt for that subset. The script supports these implementation statements; actual retained sample counts/row identity and effect estimates cannot be verified without the excluded sample/effect summaries. Full-data scaling here belongs to explanatory inference, not predictive validation.

All six final baseline/dynamic gates pass the recorded non-blocking-V policy. The O. fagata full-dynamic initial Beta gate fails and its longer retry passes; do not report the rejected initial fit as the final result. The latest family is COMPLETE in the restricted fitting/export sense, with a local completion marker recorded but not read. Dynamic coefficient/directional-relationship tables were excluded, so no association direction or supported effect is promoted into results_summary.

Lag1 is fixed by design, not selected against lag2/lag3. There is no predictive lag-CV procedure in S5. Same-year cross-species association is contemporaneous and cannot be an advance predictor. No imported script or manifest output implements population-growth response inference, density-dependent growth-model selection, a predictive population-lag comparison, final population forecast validation or outbreak threshold validation. These analyses are **not evidenced in the synchronized project**; the audit cannot prove they do not exist elsewhere on the Windows computer. Growth-model inference and abundance forecasting must remain distinct.

## Missing evidence and other inconsistencies

1. Fifty-one specific existing, excluded, <=256 KiB summaries/metadata files are listed in [LOCAL_EVIDENCE_REQUEST.csv](LOCAL_EVIDENCE_REQUEST.csv). They include final PPC, completion markers, selected variables, S5 sample/effect/comparison tables and session information. Their existence/size is known; their content is not. Export them before considering refits. Do not copy the excluded abundance row tables, raw observations, RData/rds or MCMC objects.
2. Exact species-specific S3/S4 and nested-CV v2 producers are missing, although all 17 on-disk R scripts in the manifest were copied. These may have been executed from an unsaved/other revision; that is a possibility, not a finding. Recover actual source/history rather than inventing a replacement.
3. Most scripts hard-code `E:/EIFFEL uusi` or an old network share, while synchronization came from `D:\EIFFEL`. No migrated execution paths are verified. Downloader settings reference a historical institutional proxy. Preserve originals and version any portability changes after provenance recovery.
4. `S1_S2_create_presentation_summary(1).R` targets older midinterval-flightcurve/nonannual directories absent in this manifest. The predictive S1/S2a result role string incorrectly says PRIMARY_ANNUAL_EXPLANATORY_HMSC; workflow role must follow implementation and validated inputs, not that label.
5. The two zero-filling scripts overlap destinations; their active/superseded order is unproven. The GIS/prepared model table producer and annual lag2 weather derivation are absent. The daily weather extractor only requests t and t-1. Source zero-filling, year filling, extreme-count verification and forecast covariate availability cannot be certified from these imports.
6. Legacy and C+D reports show poor E. autumnata extreme-tail PPC and O. fagata zero checks; final v4 PPC is missing, so neither claim that this problem is repaired nor presume that it persists unchanged. Longer MCMC is not automatically a remedy for observation-model misspecification or missing offsets.

These findings are also recorded in ../UNRESOLVED_ISSUES.md. The only scientific-review issue concerns non-blocking V. No issue was opened merely for an import, path or completion gap.

## Next action and rerun decision

First recover the requested lightweight evidence and exact producer revisions. Then verify final fit/PPC/association exports, locate any population-growth/forecast workflows, and reconcile paths and provenance. For nested CV, inspect local run progress and existing expensive checkpoints before deciding how to finish fold5/site CV. A resume or new fit is warranted only after confirming which tasks are unfinished and that producer/configuration and checkpoint compatibility are known. Any revised forecast candidate/horizon design requires a separately versioned, fully nested evaluation; never tune on the existing outer-test results.

No expensive rerun has been justified or executed during this audit. No summary placeholders were populated with unverified results. New audit files are versioned under project_state/audit_v1; existing scientific exports remain immutable.
