# EIFFEL: one-click local checks from VS Code

These tasks belong **only** to the `D:\EIFFEL-control` personal EIFFEL clone, not the MaaltaMerelle CSC/Roihu project. They run locally on Windows. The Rscript executable and its temporary files use `D:\EIFFEL_runtime`, while input CSV/TXT files are read-only under `D:\EIFFEL\data`. GitHub stores code and synthetic test fixtures, never these local scientific data.

## Initial setup (once)

1. In VS Code select **File > Open Folder...** and choose `D:\EIFFEL-control`. Click **Trust** only if you trust this repository. VS Code login to a work GitHub account does not change the clone's configured Git remote.
2. Update your clone once from the repo's own existing terminal or VS Code terminal: `git pull --ff-only`. The machine's repo-local Git proxy must be configured as previously verified; no need to connect the work GitHub account to this repo.
3. Open **Terminal > Run Task...**. Choose any task whose name begins `EIFFEL:`. The tasks are saved in `.vscode/tasks.json` and remain available every time this folder is opened.

## Available tasks

| VS Code task | Does it create new annual output? | Purpose |
| --- | --- | --- |
| **EIFFEL: Paivita + muodosta + validoi (YKSI TEHTAVA)** | Yes | Sequential Git fast-forward, full six-species weather+optional frost data build, local QA report. |
| **EIFFEL: Tila (ei uusia laskentoja)** | No writes | **Ctrl+Shift+B default:** filenames and saved QA statuses only; no R or logs. |
| **EIFFEL: Muodosta vain puuttuva populaatiohistoria** | Derived history only, if missing/changed | Explicit command; reuse verified history or derive from an existing annual build with saved passing QA. No upstream build or QA rerun. |
| **EIFFEL: Tarkista viimeisin aineisto ilman uudelleenajoa** | No new annual build | Explicit QA: reads original catches and rewrites validation reports. It is not read-only status. |
| **EIFFEL: Tarkista alkuperaiset pyyntijaksot** | Audit CSVs only | Existing trap intervals, unknown durations and invalid dates. |
| **EIFFEL: Aiemmin valitut 13+5 saamuuttujaa (ei esikarsintaa)** | Small audit only | Match locked preselected E. autumnata/Operophtera weather variables to historical archive headers; no new selection. |

The complete one-task workflow starts only when explicitly chosen by the researcher. It does not automatically run a heavy data build when VS Code opens or on every file save. An unsuccessful Git fast-forward or QA check stops the chain.

## Exactly repeated observations vs apparent overlapping trap dates

- **Remove exact duplicates from the derived analysis only**, comparing *all original CSV fields* **before any normalization**. The untouched `Eiffel_1993_2024.csv` remains the provenance source. Duplicates excluded from annual counting, including original CSV line numbers, appear in `EXACT_DUPLICATES_EXCLUDED_FROM_DERIVED_DATA.csv`. The original source file is not deleted or overwritten.
- **Retain apparent overlapping trapping intervals and their counts**, because their recorded dates can contain historical transcription errors and are not proof of genuinely simultaneous exposure. The diagnostic `overlap_audit.csv` remains, but no duplicate removal, date clamping or exclusion is based on this indicator. Do not take summed nominal `effort_days` as verified real exposure where dates overlap.
- In the moth recording system a focal species with no recorded catch during a registered active trapping event is a **true observed zero**. No zero is created outside recorded trapping periods.
- A same-day start and end is a catch event with an unknown exposure duration. Keep its count, including zeros; leave its duration and any invalid effort-normalized abundance `NA`.
- `response_checked` remains `NA` for scientific acceptance until detailed date/effort/ecology provenance checks are complete; `counts_reconciled_after_exact_dedup=TRUE` means only that source and derived **counts reconcile arithmetically**.

## Automatic reports and logs

New builds always write a uniquely named `D:\EIFFEL_runtime\annual_pipeline_v3\build_*` folder. The one-task chain writes:

- `QA_SUMMARY.csv` including exact duplicate and overlap counts.
- `EXACT_DUPLICATES_EXCLUDED_FROM_DERIVED_DATA.csv` (no source mutation).
- `LOCAL_VALIDATION_REPORT.csv` and `LOCAL_VALIDATION_REPORT.md`: machine-readable PASS/REVIEW/FAIL results for counts, zeros, duplicated source rows, and effort uncertainty.
- Existing frost-model coverage audit and temporal-availability reviews.

Except in the read-only status mode, a uniquely named PowerShell transcript is stored in `D:\EIFFEL_runtime\logs\EIFFEL_*.log` so you can inspect the run directly in VS Code without copying and pasting. Missing annual output or saved QA blocks population derivation without starting any upstream task. A build must be requested separately.

## Scientific model boundary

The first stage does **not** use NDVI or the other incomplete environmental layers, does not launch Hmsc fits, and does not repeat the preselection already completed for *Epirrita autumnata*, *Operophtera brumata* and *Operophtera fagata*. The historical 13 explanatory / 5 predictive variable lists remain locked; compare definitions and source availability before reuse. Old models are not automatically applicable to revised effort/response definitions. Actual resource-intensive fits, once approved, belong to the CSC **Insects of the north** project.

Running VS Code tasks uses local PowerShell and R; it cannot be performed remotely by opening a ChatGPT conversation. Read the generated QA report to check scientific readiness.

## Population history within the existing workflow

From the existing feature-branch checkout, `tools/run_eiffel_local_workflow.ps1`
without arguments only checks status. After review, use the explicit
`-Mode PopulationHistory` command or its named VS Code task. Neither task depends
on Git pull, annual build, source QA, variable selection or model fitting.

Identical completed history is reused after input/code/QA and output hash checks.
Otherwise only the population stage runs through the existing temp/free-space
wrapper with `-Script R/population_dynamics/BUILD_POPULATION_HISTORY_v1.R`.
New local directories are `annual_pipeline_v3/population_history_v1/history_*`;
existing annual and history directories are not overwritten. Keep local outputs
and transcripts private. See the [population-stage contract](../project_state/population_dynamics_v1/README.md).

Arithmetic QA permits technical derivation only. Source effort, ecological timing,
issue-date availability and scientific model reuse remain subject to local review.
