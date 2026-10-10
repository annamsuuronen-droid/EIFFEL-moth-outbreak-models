# Safe local annual response and existing-posterior verification

From `D:\EIFFEL-control`, after updating main, run exactly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\verify_p0_annual_response.ps1 -RscriptPath 'D:\ProgramFiles\R\R-4.5.2\bin\x64\Rscript.exe'
```

The same command first runs cross-platform contract checks, native Windows safety fixtures and36 synthetic annual arithmetic tests. Fixture files exist only in an ordinary temporary directory and are removed; none is scientific evidence. Any test failure stops before reading real sources. Requires existing installed Hmsc/coda; posterior is optional and never installed automatically. Use no alternative CSV, especially no Olddata filename/size substitute. All21 paths are listed in `LOCAL_EXTRACTION_ALLOWLIST.csv`; only16 small diagnostic texts are copied. The GIS input and4 model/metadata objects are read only. See REPORT.md for source/size/hash provenance limits.

Successful console output begins `SUCCESS: 21 source files SHA256 unchanged; 16 existing diagnostic texts copied and verified` and names `D:\EIFFEL-control\local_p0_count_effort_v1`. It also states extraction is complete but convergence/preparation are not certified. No scientific model runs. The directory contains source/artifact/tool hash manifests, aggregate reconstruction/extreme/zero/timing summaries, response_offset_comparison.csv, execution/provenance records, existing diagnostic text summaries and available actual posterior diagnostics/mixing summaries/trace PDFs.

Success means safe extraction finished. Check `STATUS.csv` and every `response_offset_comparison.csv` row: matching requires zero missing row IDs, missingness/count/observed-offset discrepancies and `response_and_observed_offset_match=TRUE`; the final status may correctly report FALSE. Review all `recovery_status.csv` unresolved components and all diagnostic parameters; no console success certifies convergence. Historical file-byte identity remains unverified unless actual execution hashes can be linked and checked, even if response matrices match.

An absent source, historical size mismatch, reparse path, oversized output or existing destination causes refusal. Do not replace a source or modify the allow-list. Preserve the original results and any failed extraction directory; report the precise failure for a new reviewed procedure/version. Source SHA256 unchanged does not independently establish historical input identity. Do not publish raw counts, models or unreviewed local output: this directory is ignored. Return the lightweight manifests, comparison/recovery/status summaries and diagnostic evidence for verification and a separate versioned publication. No S4/S5/CV/MCMC run is the next action.
