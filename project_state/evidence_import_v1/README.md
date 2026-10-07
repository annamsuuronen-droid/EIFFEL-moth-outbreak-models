# Safe supplemental evidence import v1

Scope: recover the 51 exact existing paths requested by Phase 2 commit `757b78c4ab10c203f5f070dd197f1c827524dfae`. No scientific model, R, refit, fold 5, site CV or scientific decision is performed. The existing `imported_local` snapshot and scientific outputs remain untouched.

## Local execution

Run this **one command from `D:\EIFFEL-control`**. It first updates the checkout by fast-forward and invokes the importer only if Git succeeds:

```powershell
git pull --ff-only origin main; if ($LASTEXITCODE -eq 0) { powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\import_local_evidence.ps1 }
```

The process execution-policy setting applies only to this invocation; it does not persist a policy change. The entry point accepts no arguments and verifies that its script directory is `D:\EIFFEL-control\tools`. Source is fixed to `D:\EIFFEL`; repository is fixed to `D:\EIFFEL-control`. No Git command, automatic commit/push or R command is run by the importer.

Successful output includes:

```text
SUCCESS: 51/51 allow-listed files copied and SHA256 verified (50,918 bytes).
Destination: D:\EIFFEL-control\imported_local_evidence_v1
Manifest: D:\EIFFEL-control\imported_local_evidence_v1\evidence_manifest.csv (51 VERIFIED rows)
Source opened read-only. No R or models executed. Existing snapshots/results untouched.
```

Success means 51 files in their original relative paths plus `evidence_manifest.csv`, containing 51 `VERIFIED` rows. Each row records the source relative path, expected/actual byte sizes, source SHA256 checked against the copied bytes, destination path and source modification timestamp in UTC. This is an evidence transfer, not certification of scientific results. Original source hashes are unavailable in the Phase 2 request; the manifest establishes hashes at this import, while expected byte sizes are pinned to the request.

## Review of all requested paths

[REQUEST_PATH_REVIEW.csv](REQUEST_PATH_REVIEW.csv) records all 51 individual decisions, expected sizes and refusal conditions. Total expected payload: 50,918 bytes; largest requested file: 4,607 bytes. The list contains selection metadata, PPC summaries, fit/effect/comparison summaries, model-structure summaries, completion markers and session metadata. No requested path is identified as a raw observation table, abundance-row dataset, posterior/MCMC object, GIS or NetCDF object.

**Flagged conditional file: `S5_sample_summary.csv2`. Do NOT import it if it is observation-level or differs from the aggregate schema.** Its imported S5 producer (`imported_local/R/S5_HMSC_annual_species_abundance_dependencies.R`, lines 814–821) defines exactly `species`, `n_original`, `n_with_exact_previous_year`, `n_matched_dynamic`, `proportion_retained`. The importer requires these exact columns, three unique expected species (`Epirrita autumnata`, `Operophtera brumata`, `Operophtera fagata`), integer counts and consistent retention proportions. Existing S5 convergence and variance-partitioning summaries verify these display labels; underscored names are filename aliases. Failure refuses the entire import. Counts are aggregate sample metadata, not abundance observations.

The cloud cannot inspect the actual 51 missing files under `D:\EIFFEL`. Approval here concerns their exact path classes and known producer context, with local byte-size/content guards; actual local contents are not claimed verified. Any changed, binary or observation-level file must NOT be imported. No allow-list entry has been removed or rewritten to evade review.

## Safety design

- Reads only `project_state/audit_v1/LOCAL_EVIDENCE_REQUEST.csv`; there is no recursive source discovery, wildcard copy or fallback search.
- Requires exact four CSV columns, 51 unique entries and the reviewed ordered path/size SHA256 digest. UTF-8 BOM and Windows/Unix line endings do not affect the digest. Editing paths or sizes requires a new reviewed workflow; do not adjust sizes just to make a refusal pass.
- Accepts only canonical `hmsc_outputs/...` paths ending in `.txt` or `.csv2`, with a 256 KiB hard cap per file. Rejects traversal, empty/dot segments, drive/UNC/ADS paths, backslashes, wildcards, reserved device names and trailing dots.
- Source/repository roots must be separate local drive directories. Checks ancestors and files for reparse points. Pins directory handles without delete sharing and verifies opened source/destination physical paths with Windows `GetFinalPathNameByHandleW`.
- Opens source files only with `Open`, `Read`, `FileShare.Read`; holds all 51 source handles during the transfer, denying normal concurrent writes/deletion. The allow-list is also guarded read-only. Compiler temporary paths must be outside the source root. No source-writing, moving, renaming or deleting operation exists in the importer.
- All 51 paths, byte sizes, text checks and initial SHA256 hashes must pass before any destination creation. Missing files are fatal, not skipped. UTF-8 text is required; binary/NUL content and recognized observation-level CSV schemas are rejected.
- Native atomic directory creation rejects an existing version directory; each destination file and manifest uses `CreateNew`. No overwrite, merge or automatic version selection. A second invocation refuses the existing `imported_local_evidence_v1` directory.
- Destination bytes and size are verified against the held source stream using SHA256. Success is reported only after manifest writing/flushing completes. No scientific results are replaced.

These checks assume ordinary Windows filesystem behavior and no administrator deliberately changing mounts/reparse metadata while the process runs. Do not run the importer concurrently with filesystem-maintenance tools. The script does not claim protection against a hostile administrator or compromised machine.

## Refusal/recovery

A preflight refusal returns a nonzero exit status and copies nothing; no destination/manifest is created. A failure after destination creation returns nonzero and retains partial files and, if writable, a manifest with `FAILED`/`NOT_COPIED` statuses. It never deletes source or partial destination files. A retained partial version blocks another invocation. Preserve it for diagnosis and prepare a separately reviewed new version; do not delete or overwrite scientific evidence to force a retry. A wrong-size/missing/rejected source requires evidence review, not an R/model run.

## Tests

`tools/tests/Test-EiffelEvidenceImport.ps1` parses the importer using the actual PowerShell parser and tests synthetic exact-size fixtures in a uniquely named temporary directory. It never uses the production source roots. The test harness may create/delete its own synthetic fixtures, unlike the read-only-source production importer.

`.github/workflows/evidence-import-safety.yml` runs the synthetic suite on Windows PowerShell 5.1 and PowerShell 7. Checks cover successful 51-file/hash/manifest transfer, unchanged source bytes/timestamps and existing snapshot, exclusion of unlisted files, repeated-run overwrite refusal, missing/changed files, changed allow-list paths/sizes/counts, traversal/absolute/ADS/UNC/device paths, unexpected extensions, binary/observation content, conditional aggregate schema, source/repository junctions and source/allow-list symlinks, overlapping roots and production-argument refusal. Additional cases verify BOM/CRLF compatibility, injected SHA256-verification failure with a retained 51-row failure manifest, refusal to reuse that partial destination, and denial of concurrent source writes.

Validation completed on 2026-10-07: the actual PowerShell parser and all **32 synthetic safety cases passed on both Windows PowerShell 5.1.26100.33438 and PowerShell 7.6.6** (64 case executions). [Windows CI run 37604699690](https://github.com/annamsuuronen-droid/EIFFEL-moth-outbreak-models/actions/runs/37604699690) succeeded for tested code commit `e0b5bd541e68ea93eb387d89e55deea4d8103853`. [TEST_REPORT.json](TEST_REPORT.json) records code hashes and scope. The documentation-only follow-up leaves tested script/test/workflow bytes unchanged. Inventory/digest/prohibited-operation static checks also passed in the cloud shell. Tests contain only labelled synthetic data; no real scientific values or results were generated. Actual source contents on the user computer remain untested until the local invocation.
