# Checkpoint/resume v1 — synthetic test record, 2026-10-19

Base: `9e16508af66327e09f75ceb75b2a0bf3ccb3da02` on the existing six-species
development line. Work branch: `feature/s1a-checkpoint-resume-v1`.
No historical scientific producer or result is edited.

## Executed in this cloud instance

```text
python -B tools/tests/test_checkpoint_resume_v1.py
```

Linux, Python standard library: **22 test methods PASS**, including subcases.
These are synthetic software checks; no actual research result is generated.

Covered behavior:

- Uninterrupted and pause/resume fixture executions produce identical recorded
  decisions. Fixture includes four forward records plus backward completion;
  no implicit stop at the first or second accepted weather group.
- Completed tasks skip adapter calls; rejected completed confirmation is reused.
- Pause persists across writer sessions and needs explicit request acknowledgement.
- Abrupt synthetic Python process exit releases the OS lock but leaves running
  work requiring review. Partial artifacts are preserved, not accepted or erased.
- Interrupted publication and publication-before-state-commit are distinct;
  the latter requires explicit matching manifest-hash adoption after review.
- Corrupt artifact/manifest, changed actual input/code bytes, changed contract,
  software/settings/graph and source changes during a task refuse reuse/publication.
- Incomplete synthetic CV and failed confirmation block dependent decisions.
- Changed parent-attempt identity invalidates a previously complete dependent task.
- Exact pair order, sample IDs, folds, observed response and offset hashes required.
- Same-process and separate-process competing writers are refused. A closed old
  writer cannot publish after a new writer takes ownership.
- Relative checkpoint artifact names survive root relocation. Traversal, drive/UNC,
  ADS, reserved Windows names, symlinks and existing-root initialization are refused.
- Resource admission refusals, duplicate/nonfinite JSON, empty outputs and attempted
  scientific certification are exercised.

The only subprocesses started by tests are short synthetic Python children used
to test OS lock contention and abrupt process exit. No R/Hmsc process is invoked.
All writable test sources/checkpoints are inside a new tempfile tree. Cleanup is
limited to each test's own synthetic tree, never a historical directory.

## Not executed or certified

- Native Windows, Windows PowerShell, Slurm and CSC/shared filesystem behavior:
  **NOT_VERIFIED** locally. A Python 3.11 Linux/Windows CI workflow is supplied;
  configuration is not evidence of a completed CI run. Windows symlink creation
  may be skipped with an explicit reason if runner privileges disallow it.
- Actual monacha controller/S1a: **BLOCKED**, Windows D: inaccessible. No source
  correspondence or real S1a integration is claimed.
- Hmsc offset correctness, real REF/CAND panel identities, temporal weather
  provenance, grouped-year validation adequacy, convergence and scientific
  acceptance: **NOT_VERIFIED** by these tests.
- Opaque model-object schema, live resource monitoring, hard time/memory limits,
  power-loss durability, CV-fold resume and MCMC continuation: not implemented.
- No package installation, fitting, MCMC, prediction, CV, annual build, population
  build, protected-job inspection or CSC submission occurred.

## Publication check

The read-only `gh api user` query returned Forbidden. A Git push **dry run only**
to the new work branch returned HTTP 403: permission denied to `annasuuronen`.
The intended account is `annamsuuronen-droid`. `GH_TOKEN` is present, so an
environment token can take precedence over a stored CLI login; its identity
could not be established through the blocked API. No credential value was
printed, and no connection was disconnected or changed.

No actual push or Draft PR creation was attempted after this refusal. Native
Windows CI therefore remains unexecuted. Publish this same reviewed work branch
from an authorized connection, preferably opening a Draft PR against the existing
six-species feature branch to isolate these five additions. No PR is merged.
