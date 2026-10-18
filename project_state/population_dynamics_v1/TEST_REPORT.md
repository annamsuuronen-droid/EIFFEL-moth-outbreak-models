# Single-pipeline population history integration — 2026-10-17

Baseline: `feature/six-species-annual-forecast-pipeline` at
`3f63f2a3c1a99c083824d8266bf895ebacca9462`. Changes stay on that existing
branch. No new annual producer, parallel branch or workflow is introduced.

## Executed locally

Environment: Linux, R 4.5.0, data.table 1.17.0, PowerShell 7.5.4, Python 3.
R/data.table came from signature-verified Debian packages; PowerShell was
checksum-verified. An external Rscript shim invokes the extracted R executable
because this container has no system R installation. No runtime shim or package
artifact is included in repository changes.

| Check | Result |
| --- | --- |
| Existing ten R scripts in `six-species-annual-light-tests.yml` | PASS, all ten executed with synthetic inputs |
| `test_population_history_v1.R` | PASS, 42 assertions; module and tests reused unchanged from the supplied archive |
| `Test-PopulationLauncherSyntax.ps1` | PASS, PowerShell parser and explicit/default VS Code task guards |
| `Test-PopulationWorkflow.ps1`, mocked platform wrapper + actual R stage | PASS, 40 assertions |
| Same workflow test with `-UseRealWrapper` | PASS, 40 assertions with unchanged actual temp/free-space wrapper |
| `test_population_integration_static.py` | PASS, 17 static checks; not substituted for execution tests |
| Existing workflow YAML structure, path filters, two existing jobs and read-only permissions | PASS |
| `git diff --check` | PASS |

The ten existing R scripts cover annual source contracts, exact duplicates,
ecology, NDVI policy, phase-one scope, synthetic frost, interval uncertainty,
registered-event true zeros and locked-variable schema reuse. Their existing
end-to-end fixture test creates a small synthetic annual table; no research
annual build or weather selection was run.

## Behavioral evidence and review

- Default status does not start R, create runtime directories or logs, rewrite
  QA, parse annual rows or hash local outputs. A deliberately invalid annual CSV
  does not affect status. Snapshots include file bytes and modification times.
- Missing QA, FAIL, unknown statuses, invalid schemas and duplicated mandatory
  gates block population computation. Scientific REVIEW rows remain REVIEW;
  arithmetic PASS is not promoted to scientific approval.
- Explicit population mode passes the population script to the existing
  wrapper. The mock rejects any omitted `-Script`, upstream mode or different
  script. A sentinel annual producer also prevents silent annual regeneration
  in the actual-wrapper test.
- Reuse succeeds with an invalid R executable, proving that an identical
  completed artifact does not start R. Uppercase MD5 values are accepted in both
  hash comparison paths, matching PowerShell's hash representation.
- Input, saved QA, module and runner changes invalidate reuse. Corrupt output,
  missing completion marker and non-allowlisted output names cannot qualify.
  An explicit command creates a new unique directory and preserves old output.
- The R stage independently refuses missing `--build`, duplicate QA gates,
  existing output and destinations outside the runtime history directory.
  Source hashes are checked before and after derivation. Completed output hashes
  are verified by the launcher before reporting DONE.
- All-NA effort/rate columns are explicitly parsed as numeric. A synthetic
  all-unknown-effort panel retains observed counts and produces no invented rate.
- No original annual source, original script, historical result, P0 v1/v2/v3
  file, saved model or protected conifer run is changed. Public changes contain
  code, synthetic fixtures and documentation only; local history filenames are
  ignored by Git and production output is outside the checkout.

## Remaining evidence

Windows PowerShell 5.1 and PowerShell 7 execution on Windows: **NOT_RUN locally**.
Both actual-wrapper tests are added to the existing Windows CI job. Linux
execution does not establish native Windows success; CI status must be reviewed.

Real-data derivation and existing local output acceptance: **NOT_RUN /
NEEDS_LOCAL_EVIDENCE**. Codex cannot inspect the Windows D: drive. No actual
FROST or local site/year values, scientific evidence or model objects are read
or published by this change.

Scientific effort/calendar acceptance, historical model provenance and posterior
diagnostics, forecast issue-date availability, chronological validation, growth
models and ecological outbreak definitions remain separate gates. No Hmsc,
MCMC, CV, S4, S5, predictor selection or model-convergence claim is made.
