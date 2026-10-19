# Synthetic selection states v1 — test record, 2026-10-19

Base commit: `695307f6695d3ec57f332d3c6ea057d3ca31c01f`.
Work branch: `feature/s1a-adaptive-state-machine-v1`.
Existing PR #4 and its checkpoint branch remain unchanged.

Commands:

```text
python -B tools/tests/test_s1a_selection_state_v1.py
python -B tools/tests/test_checkpoint_resume_v1.py
git diff --check
```

Linux result: **27/27 pure-state test methods PASS**, including repeated backward
steps, fixed-plan immutability and the empty candidate universe. The unchanged
checkpoint suite passed **34/34**. `git diff --check` passed. No tests were removed
or weakened. These are software checks, not scientific validation.

Coverage includes: more than two accepted groups; rejected-group reconsideration;
ranked confirmation rejection/fallback; all permitted forward stop categories;
premature/disallowed stop refusal; accepted/rejected backward removals and repeated
rounds; explicit group guards; backward applicability/contract disablement;
wrong decision order, parent, source and content SHA; idempotent replay; conflicting
successors within a supplied history; chain corruption/missing records; required
RNG-before/after/provenance and immutable policy; metadata-only RNG preservation;
explicit RNG-free fixtures; technical/incomplete result review; incomplete/forged
completion refusal; traceable non-scientific certificate; interrupted/exported/
restored versus uninterrupted byte-identical sequence; immutable contracts/states/
plans; malformed batches, ranks and variables; mode binding; strict JSON.

New tests are entirely in-memory. They write no files, draw no random values,
spawn no processes and import no R/Hmsc/checkpoint module. The separate unchanged
checkpoint suite uses only its own synthetic temporary trees and short Python
lock/crash subprocesses, as documented in its existing test report.

## Scope and remaining checks

No real observations, models, FROST values or local scientific evidence are used.
No historical R script, checkpoint engine, existing checkpoint test or PR #4 is
modified. No fit, MCMC, prediction, real CV, annual build or CSC task is run.

The added Linux/Windows CI runs both suites with Python 3.11. A configured workflow
is not proof of execution: this record precedes publication. Actual new-commit CI
status must be checked and reported separately. No native Windows claim follows
from the local Linux test result. No CSC/Slurm or filesystem durability is tested.

The completion certificate covers only supplied synthetic records. It does not
verify actual artifacts, source-file hashes, installed package versions, real RNG
states, convergence or ecological validity. There is no filesystem coordinator,
process lock, atomic publication or real checkpoint/S1a adapter in this layer.

## Review corrections — task 11, 2026-10-19

Correction base: `db8833169f69a790ca151c5b1966041893611497`.
Branch: `feature/s1a-state-machine-review-fixes-v1`.
Target: `feature/s1a-adaptive-state-machine-v1`, not main or the checkpoint branch.

The state suite now has **40/40 passing methods on local Linux**: the original
27 plus 13 review regressions. Original assertions are retained. Seven calls to
the intentionally changed public planning API use `plan(selection)` instead of
`plan(base, state)`; no historical scientific rule or expected result was relaxed.

New coverage:

- Empty-variable forward acceptance and acceptance without candidate-group
  representation are refused; an explicit rejection remains possible.
- A later forward result may remove an earlier group's entire representation,
  with historical acceptance and source/state provenance preserved.
- Detached derived group views distinguish acceptance order from contract-order
  representation, including overlapping definitions without implicit acceptance.
- The declared minimum is a backward-removal guard; forward need not create that
  many variables. Backward cannot erase an accepted group's last representation.
- Contradictory final variables/history refuse both completion and group views.
- Raw records, the old planning signature, forged states with the correct base SHA,
  corrupted intermediate states and missing source history refuse public planning.
- Pause/export/restore through a representation change gives exactly the same
  export, RNG references and certificate as uninterrupted execution.
- Four pre-correction valid-history golden export hashes are unchanged. Complete
  cases also retain their old certificate hashes and restore successfully.

Additional compatibility check, outside the committed test file: five canonical
synthetic history exports were captured under the original implementation before
editing, in a task-specific temporary directory. The corrected implementation
restored all four valid exports byte-for-byte. It refused the old empty-accepted-
group history with `Accepted forward group must be represented at confirmation`.
No old snapshot was changed. This does not imply universal legacy compatibility.

The unchanged checkpoint suite passed **34/34** on local Linux. `git diff --check`
passed. Only the module, its state tests, README and this report are changed. The
existing Linux/Windows workflow already covers module/test changes and needs no
edit. New-commit GitHub Actions results must be reported separately after push;
the earlier commit's successful Windows run does not certify these corrections.

Serialized schema and fields remain unchanged; valid unchanged-contract histories
retain their hashes. Invalid old histories are not migrated or certified. The
Python planning call signature changes intentionally. Actual code SHA bindings
must change in a future real coordinator rather than reuse old source identities.
There is still no real checkpoint coordinator, RNG restoration, R/Hmsc integration,
scientific validation, local Windows evidence or CSC execution in this layer.
