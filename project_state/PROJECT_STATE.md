# Project state — Phase 2 available-evidence audit complete

- Cloud environment is ready.
- Full local project remains at `D:\EIFFEL` and is not directly visible to Codex Cloud.
- Lightweight synchronization completed in import commit `bd4717603df052bb92a3172f630c754df84de30d`.
- Phase 2 audited main snapshot `427136e134caf6e93cfdc3080c1520170627a9d5` on 2026-10-07: all 17 imported R scripts, 3,159 non-R files and the 8,995-row manifest. All 3,176 copied files are accounted for.
- Audit report: [audit_v1/REPORT.md](audit_v1/REPORT.md). Script/folder inventories and evidence checks are versioned beside it.
- Latest recorded full-data predictive ecological structure: five lag1 weather variables plus NDVI_mean/median/max at 100m (eight variables; 1,277 matched rows). This identifies selection, not completed outer validation.
- Latest explanatory exports: species-specific final fits v4, 13 weather variables and no environmental variables. Authority remains conditional on missing producer/PPC evidence and non-blocking-V scientific review.
- S5 species dependencies v2 use the explanatory baseline, not the predictive baseline. Exact t-1 abundance is fixed by design; no comparative population-lag selection is evidenced.
- Nested predictive CV v2 is PARTIAL: outer-year folds1–4 verified; fold5 predictions, outer-site validation and final master/pooled summary not evidenced. The exact v2 producer is missing.
- Population-growth inference, predictive population-lag selection, final population forecasting and outbreak validation are not evidenced by imported scripts or manifest. No existing model is declared authoritative for these roles.
- Cheap checks reproduced 285 recorded convergence decisions and 192 available outer-fold metric values. These checks do not certify posterior or observation-model adequacy.
- Explanatory/species-association final gates pass their recorded policy, while V diagnostics fail and are non-blocking. Scientific review: [issue #1](https://github.com/annamsuuronen-droid/EIFFEL-moth-outbreak-models/issues/1), labelled needs-scientific-review.
- All completed scientific outputs are preserved. No scientific model or imported R script was run; no expensive rerun is currently justified. Result-summary scaffolds remain header-only.
- Safe supplemental evidence-import workflow prepared after audit commit `757b78c`: [evidence_import_v1/README.md](evidence_import_v1/README.md). All 51 requested paths reviewed (50 summary/metadata path classes; one conditional aggregate sample-summary schema), 50,918 expected bytes. Sources remain strictly read-only; existing imported snapshot/scientific results are preserved.
- Importer syntax and 32 synthetic safety cases passed on each of Windows PowerShell 5.1 and PowerShell 7: [test report](evidence_import_v1/TEST_REPORT.json). Actual missing local evidence has not been imported or verified in the cloud.
- Next action: user runs the single command in the evidence-import instructions from `D:\EIFFEL-control`, creating a new `imported_local_evidence_v1` snapshot and SHA256 manifest. No fold 5, site CV, S3/S4/S5 refit or other scientific run is authorized by this recovery workflow. Exact species-specific/nested-v2 producer revisions and population-model evidence remain separate unresolved requests.

The audit of available evidence is complete; final scientific validation remains blocked by the specific evidence and completion gaps in UNRESOLVED_ISSUES.md. Missing contents were not guessed.
