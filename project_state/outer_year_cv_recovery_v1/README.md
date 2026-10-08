# Completed r2 fold-5 capture and full-year audit — v1

Repository inspected at `c465e59eaac88c64e0aa91fad53b20e473081efb`, 2026-10-08. The user reports successful local r2 completion (916 TRAIN / 222 TEST) and a successful copy to `D:\EIFFEL_runtime`. Completed fold-5 outputs are not yet in the cloud snapshot. This report distinguishes local completion from cloud evidence verification; it does not fabricate metrics.

## Reviewed allow-list

Every entry in `LOCAL_EVIDENCE_ALLOWLIST.csv` is independently pinned by its ordered path/action/cap SHA256 in the importer. Adding, removing or changing an entry is refused.

| Source relative to D:\EIFFEL_runtime | Action | Maximum bytes | Rationale |
| --- | --- | ---: | --- |
| hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_05/outer_test_predictions.csv2 | COPY | 2097152 | Derived held-out predictions explicitly requested for verification, including their observed evaluation responses. This narrow exception does not authorize raw observation/abundance datasets. |
| hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_05/outer_test_metrics.csv2 | COPY | 65536 | Six model/species aggregate rows; recomputed independently. |
| hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_05/OUTER_FOLD_COMPLETE.rds | EXTRACT ONLY | 2097152 | Validate IDs, selections, coverage, predictions, metrics and embedded provenance; export eight PASS checks only. No binary imported. |
| hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_05/RECONSTRUCTED_r2/PROVENANCE.rds | EXTRACT ONLY | 262144 | Compare with completion provenance; export whitelisted scalar/profile/predictor summary. No binary imported. |
| hmsc_outputs/HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1/HMSC_annual_three_species_weather_environment_buffers_results.RData | VERIFY ONLY | 4194304 | Read existing prepared input to verify exact observed values, partition, matched IDs and coverage; verify training-provenance MD5. Never copy/export its tables. |

**Do NOT import** `RECONSTRUCTED_r2/WEATHER_ONLY_FINAL_FIT.rds` or `WEATHER_PLUS_ENVIRONMENT_FINAL_FIT.rds`, historical/failed staging objects, MCMC objects, raw datasets, other row datasets, GIS, NetCDF, or any unlisted file. The script never enumerates source directories. It does not inspect `D:\EIFFEL\hmsc_outputs\conifer_species`, the old E: backup, or either large final model.

Sizes of the new outputs are not remotely known. The manifest explicitly records `UNKNOWN_BEFORE_CAPTURE`, the cap, actual byte size and SHA256 rather than inventing an expected exact size. Held read-only source handles prevent concurrent write/rename/deletion; copy size and SHA256 are checked, and all source size/hashes are rechecked after extraction. Oversized files fail closed; do not raise caps without reviewing their role/content.

## Local operation

From `D:\EIFFEL-control`, after this revision is in main:

```powershell
git pull --ff-only origin main; if ($LASTEXITCODE -eq 0) { powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\capture_completed_fold5.ps1 -PublishGit }
```

Requires Rscript.exe on PATH (the existing R installation), Git and Windows PowerShell 5.1 or newer. No packages are installed; R runs only base-R read/verification/arithmetic code, with `--vanilla`. The maintained recovery R defaults now use D:\EIFFEL_runtime; historical imported code retains its original paths as provenance. Do not run the historical or current fold-5 execution wrapper again.

`-PublishGit` is explicit consent for a scoped commit/push of only the new evidence and full-CV summary directories. It requires main, the expected origin and no pre-existing staged changes. Unrelated working-tree changes are not staged. Empty per-command Git hooks prevent hooks from starting local analyses. Push is non-forced. Failure leaves evidence/any local commit intact; it does not retry or overwrite anything.

Success creates only:

- `imported_fold5_completed_r2_v1/`: two CSV2 copies preserving relative paths; `checkpoint_verification.csv`, `reconstructed_provenance_summary.csv`, `source_manifest.csv`, `artifact_manifest.csv`.
- `project_state/outer_year_cv_full_v1/`: recomputed per-fold metrics, pooled held-out metrics, equal-weight fold means/SDs, coverage, input manifest, README and `STATUS.csv`.

Expected final messages:

```text
SUCCESS: 2 CSV2 files SHA256 verified; 2 RDS files verified/extracted; primary input verified read-only, never copied.
FULL FIVE-FOLD OUTER-YEAR CV VERIFIED. Historical folds 1-4 plus reconstructed-compatibility r2 fold 5.
No fitting, MCMC, site CV, S4 or S5 execution occurred. Existing scientific results unchanged.
```

A successful `-PublishGit` run also prints the evidence commit and push output. `STATUS.csv` must say `FULL_FIVE_FOLD_OUTER_YEAR_VALIDATED`. No success is printed if extraction/audit/push fails. Preflight refuses missing files, malformed/tampered allow-lists, traversal, alternate streams, unsupported paths/actions/extensions, reparse points, overlapping roots, temporary paths under source, and pre-existing destinations. Partial destinations are retained as failure evidence and block reuse; no automatic cleanup is performed.

## Verification chain

The eight local extraction checks validate the RDS records against the fixed reconstructed r2 contract and independently against primary inputs. Species, exact ordered sample IDs, six held-out years (1999, 1994, 2013, 2019, 2020, 2014), model types, 11-column schema, observations, 222 matched TEST/916 TRAIN, selected seven weather/two environment variables, primary-derived coverage and all six metric rows must agree. The training profile records R 4.5.2/Hmsc 3.3.7/coda 0.19.4.1, accepted RNGkind, 5000 samples, 10000 transient, thin20, four chains/workers and 1000 prediction draws. Extractor runtime is recorded separately; no current Hmsc installation is needed for this lightweight step.

PowerShell verifies SHA256 of each copied file and records hashes of every inspected source and output artifact. The package-free R audit checks artifact byte counts/MD5 against that SHA256 capture and validates the source manifest/check records. This is a reproducibility/accidental-change chain, not signed forensic attestation of an untrusted machine. A subsequent cloud audit should independently recompute the supplied SHA256 values after import.

The full audit rechecks all 166 frozen historical tables, validates each fold, and recomputes 240 saved count/metric cells (192 historical plus 48 new). Pooled metrics use all held-out rows, not an average of fold metrics; equal-fold means are reported separately. Both models/species retain identical matched sample IDs. Expected overall coverage is 1229/1430 distinct site-years (201 excluded) and 7374 prediction rows. Missing outcomes retain the historical metric-specific missing-value rules; do not assume every species has 1229 observed responses.

All comparisons are audit computations. They do not choose predictors, buffers, lags, thresholds or candidate rules. Fold 5 is **reconstructed compatibility r2**, never bitwise historical v2. No producer search, selection rerun or model execution is part of capture.

## Tests

`tools/tests/Test-CompletedFold5Capture.ps1` parses the actual production script and exercises fixed inventory handling, success hashes/source immutability, missing/empty/oversized inputs, traversal/ADS/drives/reserved names/extensions/action/size tampering, overwrite refusal, extraction failure, partial-version refusal and junction escape on synthetic Windows files. The existing native helper is reused without changing the previous 51-file importer.

`tools/tests/test_completed_outer_year_cv.R` parses new R code and exercises exact synthetic metrics and rejection of held-out-year, probability, species, observation and metric corruption, missing evidence, output overwrite, and frozen S4 configuration. Existing reconstruction CI also covers the maintained producer helpers. New CI runs PowerShell 5.1/7 and base R on Windows, plus base R on Linux. No model or Hmsc sampling is permitted in these tests. Local Windows roots cannot be accessed from cloud; successful real evidence capture remains a local dependency.
