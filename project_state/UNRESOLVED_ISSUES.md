# Current unresolved issues — scientific readiness 2026-10-08

The five-fold numerical/evidence gates are resolved; scientific adequacy and deployment gates remain. Details: [readiness report](model_diagnostics_v1/REPORT.md), [priorities](model_diagnostics_v1/REMAINING_PLAN.csv). Do not treat missing diagnostics as successful convergence or an automatic reason to refit.

| ID | Status / issue | Evidence and next resolution |
| --- | --- | --- |
| U01 | RESOLVED supplemental evidence review | All51 recovered lightweight files reviewed in the branch-specific assessment; no blanket fit-adequacy claim. |
| U02 | OPEN explanatory producer provenance | Exact species-specific calibration/final producers remain absent; pooled scripts cannot establish provenance. Recover executed configuration/revisions read-only. |
| U03 | OPEN historical identity | Search closed; preserve historical1–4 versus compatibility-r2fold5. Hash/arithmetic verification does not reconstruct the lost producer. |
| U04 | OPEN scientific V policy | Three v4 and six S5 V components fail their recorded limits but are nonblocking. Resolve [scientific-review issue#1](https://github.com/annamsuuronen-droid/EIFFEL-moth-outbreak-models/issues/1) with inferential rationale/evidence. |
| U05 | RESOLVED five-fold evidence/arithmetic | Real capture145fec, all10 localPASS attestations,12 exact source/audit hashes,166 frozen tables,288 independently reproduced metrics; actual CI hash/base-R steps passed. No fitting needed. |
| U06 | OPEN coverage/forecast scope |1229/1430matched;1993excluded; shuffledyear/current-year weather and unresolved NDVI timing preclude advance forecast claims. Define availability/cutoff and report exclusions without outer-test tuning. |
| U07 | OPEN predictive adequacy/configuration | Existing full-data RDS fits are recorded; staleS4v1 must not execute. Read-only review first; v2 preflight fits nothing. |
| U08 | OPEN population workflow | S5 uses13-weather explanatory baseline/exactlag1, not eight-variable predictive baseline or selected population lags. Locate existing evidence; specify separate growth/forecast analyses and common lag-matched samples if absent. |
| U09 | OPEN observation-model PPC | Recovered latest predictive/explanatory PPCs retain autumnata mean/max upper-tail and fagata zero mismatch; not just legacy problems. Check counts/effort/offset and realized-draw semantics before a remedy; more MCMC is not established as a fix. |
| U10 | OPEN preparation provenance | Active zero-fill/GIS/annuallag2/temporal filling and extreme-count verification records remain missing. Verify extreme379332 and effort/source chain read-only; do not remove/winsorize because outer loss is large. |
| U11 | OPEN portability/metadata | Preserve source snapshots with historicalE:/UNC paths; useD:\EIFFEL_runtime only for future safe review. Protect concurrent conifer job. |
| U12 | PARTLY RESOLVED S5 summaries | Aggregate sample/effect/comparison exports recovered; source enforces exact previouscalendar-year matched rows. Actual row identities/producer execution remain local-only; no independent population-lag or forecasting validation. |
| U13 | OPEN predictive posterior diagnostics (P0) | No matching full-data/fold model chain ESS/R-hat/trace exports. Configuration/completion is not convergence; explanatory diagnostics cannot substitute. Recover existing posterior summaries without refitting. |
| U14 | OPEN six-species scope | Captured CV covers three winter moths, not three conifer species named by preparation. No six-species performance/adequacy claim; active conifer job untouched. |
| U15 | OPEN occurrence export semantics | v4 generic AUC.5/Tjur0 disagrees with dedicated occurrence metrics; S5 expected-count evaluation has analogous degeneracy. Preserve/reconcile estimands in a versioned reporting correction. |
| U16 | OPEN deployment validation | Fixed-predictor siteCV uses full-data selection/scaling; categorical site/year effects have no spatial/AR structure. Define honest nested site/external and chronological validation before any final map/advance forecast. |
| U17 | OPEN environmental interpretability | Tiny mixed outer improvements and unstable selected groups/scales do not support strong mechanisms. Predictive coefficient uncertainty is absent; VP is latent in-sample allocation, not causal explained variance. |

No new GitHub issue was opened for evidence, engineering or unfinished stages. Existing issue#1 is the genuine unresolved scientific-policy decision. Numerical CV may be reported transparently with scope/limitations; final prediction/inference readiness remains false.


## P0 investigation update

- U10 now includes demonstrated **code risks** (upstream missing-sum-to-zero conversion, clamped durations, yearmapping), not demonstrated active-data errors. Extreme is located atsite1308/year2004; originalsource/effort/GIS/trapoperation proof remains open.
- U13 remains open: all available predictive-labelled binary paths inventoried but no real savedchains opened; actualR-hat/ESS/trace/mixing are not recovered. A tested exactfour-file local extraction is prepared, notexecuted. Otherprimary/sensitivity/foldposterior availability is local-only.
- U15 is partly reconciled: genericv4 occurrence constants reproduce always-present arithmetic; retainedS5 usesexpectedcount predictions whileC+D finaloccurrence usesrealizeddraws. Missingv4 producer and anyversioned reportingcorrection remain open; nofit is needed solely tofix semantics.
- U09 remains open: fagata560/1277zeros exceed correctedfull-data predictiveinterval and autumnataextremetails remain mismatched. Preparation/sampling/likelihood causes are not separated withoutlocal evidence.
- U04 remains open: all9 v4/S5 V failures retained; nonblockingacceptance is notconvergence and largeESS doesnot negatePSRF failure. Existingissue1 unchanged.

See [P0 report](p0_investigation_v1/REPORT_v2.md) and [local extraction](p0_investigation_v1/README.md). No spatialprediction/refit starts before thesegates resolve.

P0 export-search addendum:32 existing ESS/Gelman files are now located in the original manifest (16current;8primary;8sensitivity), all excluded from import. The reviewed allowlist now has36paths: four read-onlyobject/raw sources plus32 exact-size diagnostictext copies. Values/convergence remain unverified until local recovery; the helper implementation is located in primaryS1/S2a, with default-autoburnin classicPSRF distinct from the new all-retained-draw/modern diagnostics. Original P0 sourcefindings/status are preserved and superseded by their v2 additions.


## Annual response verification dependencies (2026-10-10)

Final GIS source bytes, historical execution input identity, saved Y/Loff correspondence, count/effort completeness, original379332 trap-count lineage, active calendar/flight-year mapping and actual posterior diagnostics are local-only/unverified. New read-only extraction is p0_count_effort_v1/README.md. Its primary explanatory object is not v4; existing v4/S5 V failures remain open. The O.fagata zero-frequency discrepancy remains unexplained until actual zero-fill/missingness/effort evidence is inspected. No response substitution, offset correction, outlier alteration or model rerun is inferred.
