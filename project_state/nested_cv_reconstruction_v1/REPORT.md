# Controlled S3 nested-CV v2 reconstruction r1

Scope: reconstruction and read-only validation, based on repository snapshot `3176b29093d3bf0cc97252604c23522d390a36e2`. The user reports that the original v2 producer cannot be recovered from either project drive or the RStudio caches. That search is closed. No further producer search, R model, Hmsc, MCMC, fold 5, site CV or refit was executed.

The new source is `R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R`. The imported historical v1 source is unchanged. This is a **resume-only reconstruction**, not a claim that the exact historical v2 source has been recovered. Completed selection is read from validated exports; the selection pipeline is deliberately not re-executed.

## Facts established by available evidence

- The v1 script names `S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v1`. Its imported first weather screen records 42 `failed: subscript out of bounds` comparisons. V2 contains 1,228 `fitted` selection-comparison rows and five `no_rows` availability tables. This demonstrates a behavioral difference; changing the directory name alone is not defensible.
- All 166 imported v2 files were read, inventoried, checked for table shape, and matched byte-for-byte to the current GitHub snapshot. [EVIDENCE_INVENTORY.csv](EVIDENCE_INVENTORY.csv) records path, size, MD5, SHA256, rows and schema. Validation tolerates CRLF/LF conversion but requires otherwise identical frozen contents.
- The 32-year outer-year partition is identical in v1 and v2 (Git blob `323989011f4aa28f7077e4ec41007674fe3c1454`). It contains 1,430 site-year rows. The reconstruction reads it; it does not regenerate partitions from a seed.
- Every one of 2,468 available acceptance/community/strong-species/removal flags matches v1's explicit numerical rules. [SELECTION_RULE_CHECKS.csv](SELECTION_RULE_CHECKS.csv) records these checks. Agreement does not prove that correlation filtering, inner partitions, scaling or candidate availability were implemented identically.
- Completed folds 1–4 contain the expected selections, coverage, two compared prediction panels and six metric rows each. All 192 metric values reproduce from existing predictions under the v1 definitions; no posterior draws were generated. Folds 3–4 select no environment variables and their two model exports are the same prediction comparison by design, consistent with v1's copy branch.
- The manifest lists four `OUTER_FOLD_COMPLETE.rds` files and `outer_scheme_progress.rds`; these binary contents are not imported. Fold 5 has 446 inner-CV cache RDS files and no recorded final-fit model checkpoint or completion RDS. Inner-CV prediction/metric caches cannot substitute for final-model posteriors. Actual local files are checked during dry-run; past manifest existence is not treated as current verification.
- Manifest UTC timestamps place the brief v1 run at 09:12 and v2's start at 09:21 on 2026-08-21, consistent with the user's reported 12:12/12:21 local times. No exact package or stack trace can be inferred from timestamps.

## Fold expectations

| Fold | Final weather variables | Final environment variables | All TRAIN → matched TRAIN | All TEST → matched TEST | Recorded state |
| --- | ---: | ---: | --- | --- | --- |
| 1 | 0 | 3, NDVI at 2000m | 1125 → 1125 | 305 → 305 | Complete lightweight outputs; local checkpoint validation required |
| 2 | 11 | 8, soil retention at 2000m | 1156 → 991 | 274 → 172 | Complete lightweight outputs; local checkpoint validation required |
| 3 | 3 | 0 | 1156 → 1034 | 274 → 242 | Complete lightweight outputs; local checkpoint validation required |
| 4 | 3 | 0 | 1126 → 1010 | 304 → 288 | Complete lightweight outputs; local checkpoint validation required |
| 5 | 7 | 2, tree drought stress at 100m | 1157 → 916 | 273 → 222 | Selection/coverage complete; final outputs absent |

Exact variable/group/coverage expectations for every fold are frozen in [expected_v2_evidence.R](expected_v2_evidence.R). Fold 5's saved test years are 1999, 1994, 2013, 2019, 2020 and 2014. The seven weather variables are `lag1_summer_mean_Tmin`, `lag1_summer_min_Tmin`, `lag1_summer_mean_Tmax`, `lag1_summer_max_Tmax`, `lag2_growing_sum_precipitation`, `lag2_autumn_sum_precipitation`, `lag2_autumn_mean_precipitation`. Environment variables are `HostTreeDroughtStressIndex__b100m`, `SoilDrynessSensitivityIndex__b100m`. These are fold-specific choices, not a revision to the previously audited full-data predictive baseline.

## Reconstruction confidence and unresolved differences

[FORENSIC_COMPARISON.csv](FORENSIC_COMPARISON.csv) separates direct facts, compatible behavior, defects, safety changes and unknowns.

**High confidence:** frozen partition, fold numbering, selected variables/groups/buffers, coverage, completed-output filenames/schemas, point-metric arithmetic, and the need to preserve completed work. Explicit variable selection remains independent of held-out outer outcomes. Existing outer-test outputs are used only for verification, never tuning predictors, lags, buffers, thresholds or final-fit settings.

**Unproven:** the actual v2 fix for v1's initial subscript error, final Hmsc version, MCMC settings, RNG configuration, random-level construction and whether the v1 prediction backend was changed. Posterior-median and occurrence-probability fields are compatible with v1; their schema does not identify the algorithm that generated them. The lack of a v2 producer/session record/final-fit checkpoint prevents an exact scientific reconstruction.

V1 also contains an over-escaped confirmation `strsplit` regex. Literal-pipe splitting is the intended operation, but this later-stage defect cannot explain the errors already recorded in the initial screen. No causal patch has been invented. The reconstruction bypasses historical selection entirely by reading the completed exports.

The candidate fitting backend preserves v1's explicit offsets, TRAIN-only scaling, matched rows, lognormal-Poisson distribution, all-metadata random-level units and posterior median/presence summarization. It is a **candidate**, not verified v2 behavior. The old RNG seed formula would give weather-fit/prediction seeds 80060818/80060819 and full-fit/prediction seeds 90060818/90060819 for fold 5. These are inherited v1 semantics, not facts about the lost producer. No guessed v2 final-fit settings are automatically accepted.

## Safety and resumption design

The command-line entry accepts only `--dry-run` or `--validate`; scientific CLI execution is disabled. Fold 5 is the only supported recovery target. There is no outer-site driver, new-selection driver, progress-file rewrite or pooled/master completion writer.

Validation requires the existing canonical `hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2` directory, exactly five fold directories, the frozen evidence fingerprints, schemas, selection lists, saved partition, coverage and metric agreement. Incorrect roots/aliases, incomplete paired prediction/metric outputs, missing completion checkpoints and inconsistent checkpoint content fail closed. Complete folds are immutable skips. Execution into any imported snapshot is prohibited.

Local `--check-data` loads only the existing predictive primary RData (recorded size about 2.1 MB) for object/identifier/species alignment, saved year counts, exact matched row sets, coverage and observed-outcome agreement with completed exports. It does not fit or sample a model. Four local completion checkpoints are read and compared with their CSV outputs and input rows. Inner-CV cache objects and MCMC objects are not opened during this validation.

The separately defined recovery API requires these local checks **and** a verified local final-profile contract with an existing evidence reference, Hmsc version, RNG kind, MCMC parameters, random-level units and draw cap. That contract is not available in the cloud; no contract is fabricated or approved here. The dry-run explicitly reports `safe_to_fit = FALSE` even when lightweight validation succeeds. Resolving the final profile is a provenance/compatibility task, not permission to tune settings using outer-test performance.

If later authorized with verified compatible settings, the API would reuse frozen selection CSVs, saved partitions, matched data rows and completed-fold checkpoints. It would compute only fold 5's WEATHER_ONLY and WEATHER_PLUS_ENVIRONMENT final TRAIN fits, predict the same 222 held-out rows, compute metrics and exclusively publish previously absent fold-5 exports/completion checkpoint. New fitted-model checkpoints/provenance go in a versioned `fold_05/RECONSTRUCTED_r1` staging directory. Compatible staged fits can be reused after checking provenance, predictor lists, TRAIN IDs/scaling and posterior structure; an inconsistent checkpoint is refused, never silently refitted. A lock prevents concurrent recovery. Existing selection, coverage, folds 1–4, original scheme-progress and master files are never overwritten. Interrupted partial publication is retained and refuses automatic repair.

No actual staged posterior exists in the recorded evidence. Reuse of inner-CV caches as final fits would be scientifically incorrect. New fits remain required unless a locally discovered final-fit checkpoint passes the reconstruction's exact provenance contract; this task does not search for one or run fitting.

## Dry-run only: one Windows command

From `D:\EIFFEL-control`, with `Rscript` available on PATH, run:

```powershell
git pull --ff-only origin main; if ($LASTEXITCODE -eq 0) { Rscript --vanilla .\R\S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R --dry-run --check-data --fold 5 }
```

This uses the known `E:/EIFFEL uusi/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2` and sibling primary-data path. It prints all five statuses, held-out years, selections, coverage, skip/reuse decisions and the exact pending stage. It writes no scientific output. Temporary checksum scratch is created and removed outside the scientific output root. On success, partition/frozen evidence match and folds 1–4 skip; fold 5 remains blocked for fitting by the unverified historical final profile. If any local checkpoint, data object, identifier, selection or coverage is inconsistent/missing, it stops with a specific error and does not repair or recompute anything.

An imported-evidence-only validation mode exists for CI; it explicitly does not certify local checkpoints or fit readiness. No real fold-5 scientific command is provided.

## Validation status

The automated base-R suite uses immutable imported evidence plus temporary test copies and mock class/list metadata. All scientific fitting/prediction backends are replaced with failing stubs in tests. It checks skips, incomplete stages, dry-run immutability, root protection, fold-5-only guards, selection/partition/coverage/schema/metric mismatches, missing/corrupt/inconsistent completion checkpoints, staged-fit scaling/posterior structure, exclusive no-overwrite publication and profile gating. It never constructs or samples an Hmsc model. The actual R parser and all **35 non-scientific tests passed on Windows and Linux** in [CI run 37612554414](https://github.com/annamsuuronen-droid/EIFFEL-moth-outbreak-models/actions/runs/37612554414) for code commit `1cd0b0e7a9efb615b5570c6b82910e7549fb629d`. [TEST_REPORT.json](TEST_REPORT.json) records tested source hashes and scope. Documentation-only publication leaves that tested code unchanged. Actual local RData/checkpoint compatibility cannot be certified by CI.

Remaining uncertainties prevent certifying that fold 5 is scientifically fit-ready. Selection is reusable with high confidence; final-fit compatibility remains conditional. No finished scientific output was altered, no original script overwritten and no missing model result invented.
