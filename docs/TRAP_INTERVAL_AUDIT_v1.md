# Annual EIFFEL trapping-interval diagnostics (no date correction)

The original moth abundance file \`Eiffel_1993_2024.csv\` includes \`PvmAlku\` and \`PvmLoppu\` per trap interval. The annual-count and 7-day effort normalization require **positive** intervals (date difference > 0). Do not silently clamp zero-length intervals to 1 day; this can bias effort and abundance and would mask errors.

The development pipeline now offers:

\`\`\`powershell
Set-Location D:\EIFFEL-control
git pull --ff-only
& .\tools\run_eiffel_build.ps1 -Mode audit
\`\`\`

The command validates the R temporary directory on D: and reads **only the catches CSV**, not daily weather, frost, NDVI, other environmental sources or Hmsc models. It writes a newly timestamped directory under \`D:\EIFFEL_runtime\annual_pipeline_v3\build_YYYYmmdd_HHMMSS\` with:

- \`TRAP_INTERVAL_AUDIT_ISSUES.csv\`: original source CSV record number (header counted as row 1), site, year, species, count, original start/end dates, parsed start/end, computed duration in days, issue code and excluded-site flag.
- \`TRAP_INTERVAL_AUDIT_SUMMARY.csv\`: total and excluded records plus numbers of blocking zero-length, negative-length, missing/invalid-date issues.

Rows for the excluded site 152 appear in the audit **but do not block the build**. A zero or negative interval at other analysed sites stops the build before any modelling. Original raw files remain untouched. No date is swapped, shifted or truncated automatically.

**Review protocol:** Establish for each flagged source row whether it is a data-entry mistake, same-day servicing that represents a scientifically valid effort duration, a missing deployment/retrieval date, or a historical cross-year interval. Check the original trap logs/metadata. Document corrections as an explicit versioned, sourced correction table before implementing them. Re-run the audit on the *corrected derived input*, never overwrite the original observations. All species at a given event must share one real interval length.

If \`-Mode build\` fails due to intervals, the timestamped directory still includes both audit CSVs. It does not produce a falsely corrected annual count table.

The `-Mode audit` command **completes normally even when anomalies exist**, prints the number of rows requiring manual review and writes both CSV reports. Only `-Mode build` refuses to continue with blocking intervals; this is intentional.
