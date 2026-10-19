# Checkpoint/resume v1 — synthetic test record, 2026-10-19

Base: `9e16508af66327e09f75ceb75b2a0bf3ccb3da02` on the existing six-species
development line. Work branch: `feature/s1a-checkpoint-resume-v1`.
No historical scientific producer or result is edited.

## Executed in this cloud instance

```text
python -B tools/tests/test_checkpoint_resume_v1.py
```

Linux, Python standard library: **34 test methods PASS**, including subcases:
all original **22** methods plus **12** targeted regression methods. Also ran
`git diff --check`, which passed. No original test method was removed or weakened.
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

## Four-defect correction regressions

1. `test_json_nonfinite_forms_rejected_at_any_depth`: positive/negative exponent
   overflow, NaN and positive/negative Infinity, both scalar and nested JSON.
2. `test_json_finite_values_preserve_structure`: ordinary finite values, booleans,
   null and nested structures survive parsing and complete-artifact verification.
3. `test_nonfinite_json_artifact_never_completes`: an overflow in a staged JSON
   artifact is refused, with partial output preserved and `needs_review` retained.
4. `test_root_adoption_requires_compatible_sources_and_explicit_review`: publication
   before state interruption, then changed input/code bytes. Correct manifest SHA
   cannot complete adoption; restoring bytes still requires explicit review.
   Original attempt bytes remain unchanged and the review event is preserved.
5. `test_diamond_verifies_each_node_once_per_operation`: each of four nodes is
   verified once per operation; a second operation performs all checks afresh.
6. `test_large_reconvergent_graph_verification_is_linear`: 18 nodes across eight
   shared-ancestor layers produce exactly 18 manifest validations for the sink.
   This is a validation-call bound, not a walltime benchmark for real models.
7. `test_dependency_batch_shares_one_operation_memo`: admission/completion share
   checks across sibling dependencies; final publication verification is fresh.
8. `test_changed_dependency_detected_in_next_operation`: corruption of a previously
   checked shared ancestor is detected, invalidating dependent completion.
9. `test_windows_identifiers_reject_reserved_and_nonportable_names`: all specified
   Windows device names, case variants, path/ADS/trailing-dot/space/length limits;
   valid existing identifier forms remain accepted on every OS.
10. `test_task_names_refuse_case_collisions_before_creation`: collisions and device
    names fail before any run tree is created; dependency spelling stays exact.
11. `test_artifact_names_refuse_windows_case_collisions`: case variants of the
    manifest name, reserved components and colliding artifact names are refused.
12. `test_old_engine_fingerprint_is_not_silently_migrated`: same schema with a
    synthetic previous-engine fingerprint is refused without modifying metadata.

Storage schema and layout do not change. Strict source fingerprinting means old
engine checkpoints are **not automatically compatible with this corrected engine**.
No historical checkpoint is opened, altered or migrated by these tests.

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

## Publication and existing CI evidence

The initial HTTP 403 was subsequently resolved by the researcher. Original commit
`185898fc84ecd8ddb7b9cb8274b0dd925ff3eecb` is published on the same work branch.
PR #4 exists as Draft against `feature/six-species-annual-forecast-pipeline`.
Do not create another PR or change its base.

Original-commit CI run `39242023971` was verified from GitHub: Linux and Windows
jobs, including the synthetic test step, succeeded. That evidence predates these
corrections. **It does not certify the new 34-test correction on Windows.**
This record is written before the correction commit is published; its eventual
CI results must be checked against that new commit and reported separately.

GitHub API requests currently return Forbidden and `api.github.com` is absent from
the enforced cloud allowlist; ordinary public GitHub pages and HTTPS Git access
work. No authentication setting is changed and no credential value is printed.
No PR is merged. S1a integration and CSC use remain separately approval-gated.
