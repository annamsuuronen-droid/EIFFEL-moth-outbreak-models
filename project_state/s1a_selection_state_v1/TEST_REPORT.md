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
