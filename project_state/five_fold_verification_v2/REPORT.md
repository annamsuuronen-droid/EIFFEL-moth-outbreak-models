# Five-fold verification review — 2026-10-08

Reviewed main `8b8e623ec3287cbdaed8812a822575186cce9837`. No completed fold-5 capture or full-CV directory exists in that non-truncated GitHub tree. Cloud has no Windows filesystem mount, configured VPN or private TCP access. The supplied Windows paths are instructions for a local operation, not files accessible in this executor. Full five-fold verification is **NOT COMPLETE** in cloud. Local r2 completion remains user-reported; no new fit is necessary.

## Executed independent checks

- Original import audit: all 3176 files accounted for; no missing/unmanifested copied files; 285 recorded convergence-policy decisions and 192 historical outer-fold count/metric cells reproduced, zero check issues.
- All 166 frozen v2 files independently matched both MD5 and SHA256 with the inventory's LF normalization. This is a content check on real historical evidence, not a certificate of posterior adequacy.
- Seven Python integrity cases passed: valid capture, byte corruption, hash corruption, path traversal, duplicate entries, valid audit hashes and corrupted audit bytes. Fixtures remain temporary and are not scientific outputs.
- PowerShell/R CI exercises production syntax and synthetic safety/arithmetic tests; final run IDs and outcomes are recorded in TEST_REPORT.json after completion. No Hmsc package, model fit, MCMC, S4 or S5 is invoked.

## Review findings and corrections

The original importer relied on Rscript.exe being on PATH. It now accepts and validates an explicit absolute Rscript.exe path, preserving PATH fallback for earlier invocations. Production roots remain fixed to D:\EIFFEL_runtime and D:\EIFFEL-control; the reviewed five-entry source allow-list is unchanged.

The earlier extraction checked fold5 against primary data while historical1–4 were validated from immutable exports. The corrected extraction uses the same read-only saved primary input to verify observed values, primary-derived coverage and exact complete-case TEST sample sets for historical1–4 as well. It never reads additional local scientific result directories or historical large model objects. Fold5 already verifies its completion checkpoint and exact TRAIN/TEST IDs; all five now require primary consistency. The checkpoint summary must contain ten exact PASS rows; older eight-row summaries cannot satisfy the new full audit.

Copied capture artifacts are independently SHA256/size-checked again after the arithmetic audit and before publication. The seven generated audit files receive a new AUDIT_ARTIFACT_MANIFEST.csv, with SHA256, MD5 and byte sizes. Extra/unexpected outputs, missing files and existing destinations fail closed. On evidence push, cloud CI independently verifies both manifests and recomputes all five published metric/coverage/status tables into a temporary directory. These tests are enabled conditionally; they have not checked real fold5 while its capture is absent.

## One local command

Run from D:\EIFFEL-control:

```powershell
git -c core.hooksPath=NUL pull --ff-only origin main; if ($LASTEXITCODE -eq 0) { powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\capture_completed_fold5.ps1 -RscriptPath 'D:\ProgramFiles\R\R-4.5.2\bin\x64\Rscript.exe' -PublishGit }
```

It updates code with hooks disabled, reads capped existing evidence, copies only the two allow-listed derived tables into a fresh versioned import, extracts two small RDS records, verifies the existing primary input without copying it, recomputes all fold/pooled metrics, verifies manifests and performs a scoped non-forced commit/push. Source files, imported snapshots and existing results are never modified. The saved primary input is read once for validation, not used to train or predict. Large fitted models and the independent conifer job remain untouched.

Success prints `FULL FIVE-FOLD OUTER-YEAR CV VERIFIED`, after all local checks, and a successful evidence commit/push. GitHub's real-capture hash and arithmetic jobs must then pass before cloud verification is declared complete. A missing/mismatched input, invalid executable, existing/partial destination or failed Git operation stops the command. Do not delete or overwrite a prior snapshot to force a retry; it requires a separate read-only assessment/version. No success claim is made when a gate fails.

## Scientific scope and next stage

Historical folds1–4 and reconstructed-compatibility r2 fold5 remain distinctly labelled. No bitwise identity to the missing historical producer is asserted. Expected design coverage is 1229/1430 site-years, 201 excluded; this is a frozen design expectation until all five real outputs pass capture. Pooled held-out metrics differ from equal-fold averages; no predictor, lag, buffer or threshold selection uses their outer-test performance.

Year CV answers held-out-year prediction in the sampled network, not new-site transfer or chronological advance forecasting. Site CV is conditional on spatial-transfer claims and remains disabled. After successful evidence capture/cloud verification, inspect existing full-data v2 model convergence, primary/count preparation, offsets and information availability. Already reviewed PPCs flag E. autumnata upper-tail and O. fagata zero discrepancies; more MCMC is not an established remedy. The v2 S4 configuration remains inspection-only; no fitting, S4, S5 or population stage is authorized.
