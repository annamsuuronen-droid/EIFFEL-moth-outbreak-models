# EIFFEL: same-day trapping records and effort uncertainty (13 Oct 2026)

## Study-data observation

In the 19,822 source rows of \`D:/EIFFEL/data/Eiffel_1993_2024.csv\`, the user's local audit identified **146 rows with PvmAlku=PvmLoppu** at analysed sites: 143 at site 712 in 2017–2019, two at site 112 in 1996, and one at site 318 in 2019. There were **no** negative-length or unparseable-date rows in that audit. The rows include **positive catches** (examples from site 712 in 2017 contain Epirrita autumnata 1–10 per recorded date), not just zero catches.

**Never treat zero trap duration as zero catch.** A same-date field in the historical source is not evidence that actual trap exposure was zero; nor does it justify automatically setting exposure to one full day. Retain observed counts, including explicit real zero counts. Do not silently drop source lines or change \`KokMaara\`.

## What the v3/v4 phase-1 R build now does

- Reads and preserves the original source CSV, removes excluded site 152 **only for the analysis**, and keeps the original date values in a separate read-only interval audit.
- Interprets \`PvmAlku=PvmLoppu\` as a **dated sampling/catch event of unknown exposure duration**. It can enter the annual raw count, with the relevant recorded date as the event date. The event has \`duration_unknown=TRUE\`, \`interval_days=NA\`, \`count_per_7d=NA\` and \`recorded_interval_days=0\` for transparency.
- Generates **species zero counts only within documented sampled events** across the six study species; it never makes up new sampling dates or zeros for absent trap operations. This requires verification of the trap sampling protocol for site 712. Each generated zero has `zero_filled_from_sampled_event=TRUE`, whereas an explicit source zero has `explicit_zero_source_rows>=1`; annual QA tracks both categories separately.
- Aggregates \`annual_count\` by site × flight year × species without losing same-day positive or zero events. \`n_sampling_intervals\` counts dated visits, not confirmed equal exposure intervals.
- Keeps a separate \`known_effort_days\` (sum of known-duration periods) and \`n_unknown_effort_intervals\`. If **any** of an annual species row's visits has unknown duration, its \`effort_days\` and \`annual_count_per_7d\` are **NA**, NOT zero, 1 or a misleading sum of only known days. No model exposure offset is inferred.
- Continues to **block** negative intervals, unparseable dates and missing site keys; original date anomalies remain listed in the audit. The \`-Mode audit\` always writes reports and returns without running models.

The zero/positive catch rules are distinct from **missing species observations** and **no trapping**: only confirmed trapping events can be expanded to species zeros. A source count of zero must not be dropped or interpreted as a missing record.

## Audit and provenance files

\`\`\`powershell
Set-Location D:\EIFFEL-control
git pull --ff-only
& .\tools\run_eiffel_build.ps1 -Mode audit
# After validation, do a full weather/frost data build only (NO Hmsc):
# & .\tools\run_eiffel_build.ps1 -Mode build
\`\`\`

Each command makes a new timestamped output directory below \`D:/EIFFEL_runtime/annual_pipeline_v3\`.

- \`TRAP_INTERVAL_AUDIT_ISSUES.csv\`: raw source CSV row, original start/end dates, site, species, counts and interval status.
- \`TRAP_INTERVAL_AUDIT_SUMMARY.csv\`: \`zero_duration_retained\`, truly \`interval_issues_blocking\` (not including same-day records), negative/invalid-date counts, site 152 and total rows.
- \`sampling_intervals_with_zeros.csv.gz\`: catch counts and per-event effort status; \`count_per_7d=NA\` for unknown-duration entries.
- \`SAME_DAY_EVENTS_EFFORT_UNKNOWN.csv\`: observed and zero-filled species data for same-day events, with unknown duration explicitly labelled.
- \`ANNUAL_COUNTS_UNKNOWN_EFFORT_REVIEW.csv\`: retained raw annual species counts with uncertain effort, suitable for counts QA but **not automatically** for an Hmsc offset/exposure model.
- \`annual_site_species_flight_year.csv\`: full annual catches and effort-status columns.

## Before fitting models or reporting normalized abundance

1. Confirm that site 712 (2017–2019) date fields represent actual visits, and whether a source exists to reconstruct exposure time. Verify sites 112 and 318 independently.
2. Confirm all species were actually sampled/eligible on these visits before treating unlisted target species as **observed zeros**.
3. Keep annual raw counts and explicit zeros, but do not use uncertain annual rows in effort-normalized responses, effort offsets or cross-site raw-count comparisons without a defensible exposure strategy.
4. Validate agreement of sum of retained source catches with generated annual sums, without counting same-day repeated species observations twice.
5. Model runs happen later on CSC, project **Insects of the north**, after data/QA sign-off. No Hmsc fits in GitHub Actions.

The original dataset, previous Hmsc fits and historical evidence files remain unchanged.
