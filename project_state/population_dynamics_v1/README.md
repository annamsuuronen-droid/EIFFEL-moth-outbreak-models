# EIFFEL — single-pipeline population history v1 (synthetic-first)

**Scope:** extend, do not replace, the existing `feature/six-species-annual-forecast-pipeline`. The canonical response source is the already-built local `annual_site_species_flight_year.csv` from `R/build_six_species_annual_v3.R`. This stage does not reprocess traps, reconstruct weather, reselect variables, sample Hmsc posteriors, run CV, fit population models or set ecological outbreak thresholds.

## DONE / REUSE / NEW / BLOCKED

| Stage | Status | Action |
| --- | --- | --- |
| Six-species trap-event -> annual site/biological-year/species table | REUSE existing code; local scientific QA remains separately required | Read prior annual output only; preserve registered-trap true zeros and unknown-effort NA |
| Weather and optional frost; May/June issue-date preliminary features | REUSE existing six-species branch | Do not duplicate weather calculations or treat forecast feature files as final validated predictors |
| Three E./Operophtera species historical Hmsc/CV results | REUSE verified immutable outputs | Five-fold numerical CV proof covers only these species/estimands, not six-species predictions or May/June issuance |
| Six-species exact annual abundance history, missingness, mixed coverage | NEW: this module and synthetic tests | No new scientific fitting; output only from an already checked annual build |
| Six-species explanatory/predictive population growth models | BLOCKED: methodology + real-data availability review | Do not fit or copy three-species S5 results to pine moths |
| Ecological outbreak definition and honest advance forecasting | BLOCKED | Threshold candidates are not observed damage or validated outbreaks |

## Input contract

One row per `site × year × species`, where **`year` is the existing biological adult-flight year**, never re-derived from `PvmLoppu`. The producer creates observed zeros only inside registered active trap events. Absent site-years have **no row**. Required numeric fields: `annual_count` (nonnegative integer), `n_sampling_intervals` (positive integer), `n_unknown_effort_intervals`, `effort_days`, `annual_count_per_7d`; `site`, `year`, `species` define the unique key. The six species are E. autumnata, O. brumata, O. fagata, L. monacha, B. piniarius and P. flammea.

- When all durations are known, `effort_days > 0` and `annual_count_per_7d = 7 × annual_count / effort_days`.
- When any duration is unknown, both effort and normalized rate must be `NA`. The observed catch remains in `annual_count` but is **audit-only**, not automatically a comparable predictive abundance measure.
- Raw absent-species zero at a documented active trapping event remains exactly zero if exposure is established. No whole-year grid is expanded and no unobserved year becomes a zero.
- Reject duplicate source keys, inconsistent rate/effort, missing counts, missing keys, invalid species or corrupt counters; report source/effort problems without silent fixes.

## Output and temporal interpretation

`R/population_dynamics/POPULATION_HISTORY_v1.R` exposes base-R functions:

- `population_annual_contract()` validates an already-derived annual dataset.
- `population_make_history()` attaches **exact own- and cross-species lag1, lag2 and lag3** rates and log-rates by same site and `year-k`. The lagged raw count columns are explicitly suffixed `_AUDIT` and must not be used as comparable rate predictors. For each past site/year/species with no observed row or unknown effort, the lagged rate is `NA`.
- `population_lag_coverage()` reports matched usable **response and predictor** rows and distinct sites/years for each target/driver/lag, without discarding the full baseline dataset.
- `population_covariate_coverage()` checks one external numeric variable at a time by explicit unique keys. For buffered variables, first fix the candidate's buffer size and source; identical `site/year` rows from alternative buffers are refused rather than multiplied. Coverage is reported by species, with `n/reference`, matched sites and matched years. There is no implicit imputation or universal 79/80/60% rule.
- `population_training_thresholds()` calculates a **high-abundance candidate** from explicitly designated *training* rows only. Insufficient positive training observations produce `NA` with a reason. This does **not** define a confirmed ecological outbreak or choose a cutoff based on test performance.

Any cross-species lag can be offered as a forecast predictor only if the previous year's response and effort were genuinely known by the forecast issue date. The current module enforces `year-k` but **does not certify source publication dates**; real-data chronological validation must check them. Same-year other-species catches may support separate retrospective S5-style explanations but must never be included in advance forecasts.

## One existing PowerShell workflow, no implicit reruns

The **new derived-stage entrypoint** `R/population_dynamics/BUILD_POPULATION_HISTORY_v1.R` is an explicit local-only derived-data stage. It reads an existing annual build, requires its existing local `LOCAL_VALIDATION_REPORT.csv` to have zero `FAIL` rows and required source/zero/effort checks marked `PASS`, and writes to a *new* local output directory. It refuses to overwrite existing output. It does not invoke an existing data build or Hmsc model. The integration adds explicit `PopulationStatus` and `PopulationHistory` modes to the **existing** PowerShell launcher. `PopulationStatus` is the read-only default; `PopulationHistory` reuses identical completed derived outputs or runs only this explicit lightweight stage.

From the existing feature-branch Windows checkout, the default is read-only:

```powershell
& .\tools\run_eiffel_local_workflow.ps1
```

Only after review, explicitly request missing population history:

```powershell
& .\tools\run_eiffel_local_workflow.ps1 -Mode PopulationHistory
```

Both accept `-RuntimeRoot`; the explicit mode also accepts `-Rscript` and
`-MinFreeGB` (default 50). Keep the production free-space guard enabled.
The stage selects the latest completed `build_*` under the configured runtime's
`annual_pipeline_v3`, requires the saved QA report, and stops if proof is missing.
It does not call `VerifyLatest` or `BuildAndVerify` to obtain that proof.
A standalone R invocation without the wrapper's runtime configuration is refused.

The explicit command may write **local, unpublished derived site-year history** when the new stage is first needed. Do not upload local history, annual outputs, raw/FROST data, counts, model objects, or logs to GitHub; only the synthetic test code and documentation belong in this public repo. GitHub Actions uses synthetic fixtures only; no study data or fitted model objects.

Synthetic-only test command:

```bash
Rscript --vanilla tools/tests/test_population_history_v1.R
```

## Sparse environment/pairwise model-selection policy (design, not a new fit)

1. Retain the widest scientifically valid weather/response baseline. Report **target-specific baseline N** and missingness/effort coverage.
2. Assess each sparse covariate at its predeclared spatial buffer, temporal/forecast-availability version and matching species. Record `matched_N`, `matched_sites`, `matched_years`, temporal span and `matched_N / baseline_N` before any model comparison. Lack of independent sites/years can prevent inference regardless of total N.
3. Compare REF weather versus CAND weather + covariate on the **same training/validation site-years, effort convention and folds**. Do not compare incompatible panels. A larger in-sample explanatory ΔSR² is not proof of improved held-out prediction; do not create a `coverage_fraction × ΔSR²` statistic or call thresholds p-values.
4. Where multiple sparse covariates are jointly assessed, use a **declared common matched panel for that comparison only**, never globally shrink all baseline data to the scarcest variable.
5. For practical forecasting, an optional baseline-plus-extension approach requires **separate training-only choice, issue-time availability and true held-out assessment over the predeclared target population**. No automatic fallback model is validated by these functions.
6. Preserve the historically used 79% and 80%/60% gates as **original analysis provenance**, not universal defaults. Any new thresholds require prior scientific specification and sufficient effective sites/years and chronologically honest held-out cases.

## Acceptance gates before scientific models

The new **synthetic** unit/refusal checks cover all six species, true zero vs unobserved/missing exposure, exact missing-year lags, cross-species join alignment, duplicate/ambiguous environment keys, variable-specific coverage and training-only threshold isolation. Synthetic PASS does **not** certify the historical annual input, Hmsc posterior mixing, the three additional conifer species, May/June operational prediction, population growth or ecological outbreak identification.

For later scientific analysis: preserve the locked three-species explanatory weather set and separate predictive set and all completed five-fold CV, verify the local six-species input/effort, confirm exact prior-population reporting availability, freeze the evaluation population and nested chronological/site CV before fitting, compare species-specific and justified pooled models, and evaluate events with lead time, calibration and false-alarm rates. Model runs require explicit future approval; this change authorizes none.

## Integration status

Integrated on the existing feature branch from baseline `3f63f2a3c`; no parallel
branch, annual builder or CI workflow is introduced. See
[TEST_REPORT.md](TEST_REPORT.md) for executed tests and limitations.

The archive supplied by the researcher provided the population module and 42
synthetic checks; these are reused. The launcher proposals were reviewed against
branch HEAD and hardened with strict, identical QA gates in PowerShell and R,
QA-bound cache provenance, constrained runtime destinations, numeric all-NA CSV
parsing, and executable orchestration tests. Old annual scripts, original inputs,
P0 versions, scientific outputs and protected runs remain untouched.

A complete artifact contains the local history, coverage report, manifest,
`OUTPUT_HASHES.csv` and `COMPLETE.txt`. Reuse requires exact annual-input, saved-QA,
module and runner MD5 matches plus the three allowlisted output hashes and exact
completion marker. MD5 is used for change detection consistent with the existing
pipeline, not as an authenticity signature. Stale, incomplete or changed outputs
are never overwritten: an explicit request creates a new unique `history_*`.
The manifest and completion marker mean **technical derivation complete**, never
scientific approval, convergence or validated forecasting.

Output is restricted to `annual_pipeline_v3/population_history_v1/history_*`
outside the checkout; no local rows are printed by the population stage.
Status inspects filenames and saved QA statuses only. It never starts R, reads
annual rows, hashes output data, creates logs, runs QA or changes the filesystem.
It reports marker-bearing directories without claiming their hashes are verified.
The explicit command verifies those hashes before reuse.
