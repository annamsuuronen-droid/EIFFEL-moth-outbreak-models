# P0 local extraction — existing fits only

Cloud read-only findings are in [REPORT.md](REPORT.md); [CHECK_STATUS.json](CHECK_STATUS.json) explicitly records that no real predictive chain diagnostic has yet been recovered. Original scientific results/imports/audits remain immutable.

After synchronizing this repository's main branch locally, run **one PowerShell command from D:\EIFFEL-control**:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\extract_p0_existing_evidence.ps1 -RscriptPath 'D:\ProgramFiles\R\R-4.5.2\bin\x64\Rscript.exe'
```

This is read-only diagnostic arithmetic, not modelling. It uses sequential existing-object reads, no Hmsc fitting/MCMC/CV/prediction, no S4/S5 producer sourcing and no package installation. Installed Hmsc/coda are required; if `posterior` is already installed, modern diagnostics are recovered too. Its absence is explicitly recorded; classic diagnostics do not substitute for modern ones. The conifer directory/job is neither inspected nor modified.

Four exact source paths under **D:\EIFFEL_runtime**, reviewed in [LOCAL_EXTRACTION_ALLOWLIST.csv](LOCAL_EXTRACTION_ALLOWLIST.csv):

1. Current weather-only direct Hmsc model,169986680bytes.
2. Current weather-plus-environment direct Hmsc model,183315952bytes.
3. Predictive primary `PRIMARY_ANNUAL_RESULTS.rds` metadata,13825bytes.
4. `data/Eiffel_1993_2024.csv` source copy,1808547bytes; only extreme-group/date/effort aggregates leave memory.

The size contract is from the original inventory, not an invented current hash. All actual source bytes are SHA256-recorded before and after read-only extraction. Any missing/different file causes refusal; do not edit the allowlist to bypass it. Recover a reviewed new manifest/procedure version instead. It opens no original D:\EIFFEL file and exports no entire raw observations, abundance-row table, RData/rds or MCMC object.

Output is a **fresh** `D:\EIFFEL-control\local_p0_evidence_v1`, ignored by Git. Existing output causes refusal; do not delete a completed run to force reuse. On failure, any partial output is retained with FAILED status and is not publishable; source files remain untouched. The directory must have no competing writers.

Successful terminal output ends with:

```text
SUCCESS: four source files SHA256 unchanged; existing posterior/aggregate evidence extracted without copying source objects or raw rows.
EXTRACTION COMPLETE; convergence and preparation are NOT certified. Review recovery_status.csv and diagnostics; local evidence remains unpublished.
```

It should contain execution/model-observation summaries, extreme links, primary preparation aggregates, raw extreme/date aggregate, component diagnostics/chain-block summaries and selected actual trace PDFs when recoverable, plus `STATUS.csv`, `recovery_status.csv`, `runtime.csv`, `tool_manifest.csv`, `source_manifest.csv` and `artifact_manifest.csv`. Every source/artifact has byte-size/SHA256 evidence. `UNRECOVERED`, `NOT_RETURNED`, unavailable modern metrics, constant draws or NA statistics must remain visible; a successful extraction is not successful convergence or completed P0 science.

Evidence required next: all manifests/status/runtime records; actual recovered diagnostic/chain-block CSVs and selected trace PDFs; observation/PPC-reference and matched-Y/Loff checks plus primary/raw extreme aggregate summaries. Review first, then transfer only these lightweight artifacts into a new reviewed repository evidence version. **Do not force-add the whole ignored directory or publish binaries/raw data.** The current cloud code/report publication does not claim these local results exist.

The procedure checks whether source-copy exact-distinct counts sum to379332 at site1308/year2004; it preserves the observation regardless of the outcome. It also reports source missing counts/duplicates/unparsed or nonpositive durations without clamping them. The raw site-year date-pair sum uses original `year` and is a diagnostic comparator; active flight-year/GIS join and trap-operation records still require provenance. Aggregate agreement alone does not prove the whole preparation chain.

The primary and sensitivity fitted objects plus historicalfold1–4/r2fold5 posterior availability are documented separately in the inventory/report. They are not all loaded by this minimal first extraction, do not substitute for current full-data mixing, and require a separately reviewed exact-path recovery if later relevant. No expensive stage is started.
