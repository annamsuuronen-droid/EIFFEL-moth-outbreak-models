# S1a checkpoint/resume v1 — isolated adapter boundary, 2026-10-19

This extends the existing EIFFEL development line. It does not replace scientific
selection or introduce another modelling pipeline. Base:
`feature/six-species-annual-forecast-pipeline` at
`9e16508af66327e09f75ceb75b2a0bf3ccb3da02`.

The objective is **all of S1a weather selection**, not stopping after one or two
accepted groups. This implementation has no weather-group stopping count.
The historical third group's screening acceptance is not final confirmation.
The historical user stop is intentional, not an unexplained modelling crash.

## Implemented and deliberately unimplemented

`tools/eiffel_checkpoint_v1.py` is a Python 3.10+ standard-library module. Importing
it performs no IO. It has no CLI, R invocation, Hmsc import, scheduler submission,
scientific backend or historical-result discovery. The accompanying Python test
adapter writes only new temporary synthetic artifacts. CI uses Python 3.11.

Implemented:

- Explicit run/task/attempt IDs, ordered dependency graph, `pending`, `running`,
  `complete`, `needs_review`; run-level pause-requested/paused status.
- Immutable run specification; exact input/code SHA-256, software and scientific
  settings compatibility. Caller supplies explicit reviewed source path bindings;
  current bytes are rehashed on opening, admission, reuse and completion. The
  checkpoint engine's own bytes are also pinned. No source search is performed.
- New attempts without prior-attempt overwrite; source files are never written.
- Task publication from a same-filesystem `.stage` directory only after regular
  file/schema/size/SHA checks. Manifest identity is bound into committed task state.
- Parent checkpoint manifest hashes bound into dependent checkpoints: replacing
  an upstream attempt invalidates already-derived children.
- One cooperating writer per physical run root, OS kernel lock, process identity
  and owner-token fence before publication. No stale-lock unlink or live takeover.
- A separate short admission lock allows another process to request pause while a
  task runs. Once the request is committed, no unadmitted task can start. A task
  already admitted may finish and publish. Pause requests and acknowledgements
  are retained; resume requires the exact current request ID.
- Incomplete running state becomes `needs_review` when a new writer acquires the
  released kernel lock. Explicit matching-attempt review is required to retry.
  A published artifact whose state commit was interrupted also needs explicit
  hash-checked adoption; it is never assumed complete just from its directory.
- REF/CAND identity gate for exact ordered sample IDs, fold vector, response hash
  and offset hash, checked against the declared panel. Rejected confirmation is a
  complete reusable result. Every checkpoint has `scientific_approval=false`.

### Technical review corrections, 2026-10-19

The follow-up on commit `185898fc84ecd8ddb7b9cb8274b0dd925ff3eecb`
addresses the four reviewed defects only:

- JSON floating-point conversion rejects overflow such as `1e999`/`-1e999`,
  including nested values, as well as the already forbidden NaN/Infinity tokens.
  Ordinary finite JSON values keep their existing structure.
- Explicit adoption checks current input/code/engine compatibility directly,
  including dependency-free root tasks, and rechecks before recording adoption.
  A refused adoption leaves the attempt and review-required state intact.
- Dependency verification uses a fresh memo for each public verification or
  dependency batch in admission, completion or adoption. Each reachable node's
  manifest is checked at most once within that operation. No memo survives to
  another operation: later corruption and changed sources must be checked again.
  SHA checks, attempt identities and dependency-manifest bindings remain required.
- Logical identifiers reject Windows device names on every OS. Task names must
  also be unique ignoring case, while dependency references remain exact. The
  original ASCII/length/path restrictions remain. Artifact inventories reject
  case collisions and all case variants of the reserved `MANIFEST.json` name.

**Format and version compatibility:** JSON schema remains `1`; no stored fields
or publication layout change. The corrected engine's source SHA-256 necessarily
differs from the original engine, so the existing strict guard **refuses runs
created by the old engine**. There is no automatic migration or compatibility
bypass. Keep old checkpoints unchanged with their recorded producer version;
any cross-engine migration requires separate review. The tests include a
synthetic old-engine fingerprint refusal without rewriting its run metadata.
Restoring changed inputs/code permits review-based adoption only within the same
compatible engine contract. It does not upgrade an old-engine checkpoint.

Not implemented or certified:

- Integration with the local historical controller or generated monacha S1a.
- Actual Hmsc object/schema validation: `opaque` artifacts are checked as nonempty
  regular bytes only. Future adapters must supply object-specific acceptance.
- Adaptive scientific task generation or selection decisions. V1 receives an
  explicit immutable task graph; the test graph contains predeclared fixture
  decisions. Changing a graph is incompatible. The real adaptive S1a scheduling
  interface must be reviewed against the actual source before integration.
- CV-fold orchestration, internal MCMC continuation, new posterior prediction,
  Slurm commands/signals/resubmission, automatic retries or convergence acceptance.
- A security sandbox for arbitrary Python callbacks, outside file editors or
  adversarial filesystem changes. Use private, stable, ordinary directories and
  reviewed adapters; not active/protected historical job directories.
- Distributed locking across copied roots or unverified shared filesystems.

## API and adapter contract

The public boundary is:

```text
Run.create(new_absolute_root, spec, tasks, source_bindings)
Run(existing_root, expected_spec, expected_tasks, current_source_bindings)
run.writer() -> context manager
writer.run_task(task_id, producer, resources, **resource_observations)
run.request_pause() -> request_id
writer.resume(request_id)
writer.retry_after_review(task_id, old_attempt_id)
writer.adopt_after_review(task_id, attempt_id, reviewed_manifest_sha256)
```

`spec` requires run ID, species, explanatory/predictive mode, stage `S1a`, named
input/code SHA-256 maps, software identities (R/Hmsc/dependencies), and a model
contract including response, offset, distribution, priors, variables, seeds,
profile, preprocessing, random levels and forecast scope. Use logical source IDs
in specifications; bind them to actual local paths at runtime. Closed stable
inputs are required; the module does not provide P0 native source-handle guards.

Every task declares its kind, predecessors and exact task-specific contract.
Per-task variable sets, screening/confirmation profiles, seeds, panel/fold identity
and any departures from the run-level model settings must be explicit there.
Allowed kinds: `fit`, `evaluation`, `ref_cand`, `screening_decision`,
`confirmation_decision`, `forward_step`, `backward_step`.

A producer receives a new owned staging directory and returns an exact mapping
of leaf artifact names to kinds (`json` or `opaque`) plus structured evidence.
JSON artifacts must parse as objects/arrays. Metadata is capped at 4 MiB; opaque
files are streamed for SHA-256 without loading scientific model objects.
Task evidence is JSON and never executes. Pair tasks require `reference` and
`candidate` panels equal to each other and the declared panel. Decision tasks
require an explicit boolean `accepted`; the checkpoint engine never calculates
or changes the scientific acceptance rule.

Use a scoped writer session to verify and reuse results. `run.status()` reports
stored states only and explicitly says `integrity_verified=false`; it is not a
reuse authorization or proof of whole-S1a completion. An adapter must explicitly
request the declared terminal S1a task. A fixed fixture graph completing proves
orchestration only, not completeness of the real scientific selection.

## Boundaries and historical reuse

First-version boundaries are completed model fit, completed REF/CAND comparison,
screening decision, confirmation decision, forward step and backward step.
`evaluation` may represent one whole existing CV call: it is deliberately opaque
to this engine. **An interrupted `computePredictedValues(partition=...)` may need
that entire evaluation repeated later.** The engine does not recover partial CV
folds or restart a partial MCMC chain. A completed separately saved fit can be
retained while its evaluation is retried after review.

Historical text summaries, `.RData` progress files or half-finished confirmation
are never automatically adopted. Adoption applies only to a complete manifest
published by this engine for the same contract and dependencies. Legacy evidence
needs a separately reviewed provenance adapter. No historical directory is
initialized, renamed, overwritten, repaired or deleted by this change.

Reference audit anchors (not proof of the local monacha implementation):

- `imported_local/R/S1_S2_a_PREDICTIVE_variable_selection_with_variance_partitioning.R`
  lines 1525, 1676–1679: fits saved only when requested; selection pairs leave the
  default false. Lines 2484–2503: forward progress only after accepted confirmation.
  Lines 2647–2653: backward progress only after accepted removal.
- Hmsc 3.3-7 CRAN-mirror commit `92039a6c73d552520a08f4f9beac15f7e77c9958`,
  `R/computePredictedValues.R` lines 89–191: internal fold loop and refitting;
  `R/sampleMcmc.R` lines 167–170: initialization/reset is not resume.

## Atomicity, failures and storage assumptions

Generated files are flushed before publication; POSIX directory fsync is requested.
Windows has no portable standard-library directory fsync here. Rename is used only
on the same filesystem with a single cooperating writer and a new destination.
Do not claim power-loss durability from rename alone. NTFS/shared-filesystem,
storage-controller and CSC persistence behavior require platform testing.

Artifact hashes detect corruption; they are not authenticity signatures against
someone rewriting the whole private checkpoint tree. No pickle/RDS/RData is
deserialized by this module. Links/junctions and nonportable filenames are refused,
but concurrent hostile path replacement is outside the security contract.
Source hashes are compared before/after work, not protected against deliberate
change-and-restore attacks. Rejected/corrupt attempts remain for review.

State/owner/pause pointers are operational metadata atomically replaced under
locks; completed attempt artifacts and review/pause records remain immutable.
An interrupted metadata write may leave `.part_*` files. They are never checkpoint
completion markers and are not automatically removed. OS process death releases
the kernel lock; a slow/old heartbeat alone does not authorize takeover.

## Resource and Windows/CSC boundary

`Resources` provides admission checks for measured memory, free disk, estimated
task duration, optional remaining walltime and checkpoint margin. No hardware
memory/disk/time defaults are invented. Unknown observations block a requested
limit; omitted limits mean **unconfigured**, not verified resource safety. One
heavy task at a time is an architectural v1 limit, not a suggested CPU count.

This interface does not monitor or kill a running process, enforce Windows Job
Object/cgroup limits, predict artifact size, or reserve disk space. Before real
use, the platform adapter must supply measured total-worker memory, disk budget
including staging/retained fits, expected duration, thread/chain parallelism and
OS responsiveness reserves. Pause cannot preempt an in-progress sampler safely.

On CSC use the separate EIFFEL/Insects of the north project and an explicitly
approved persistent checkpoint root. Node-local temporary storage cannot be the
only copy. A future Slurm adapter must anticipate time limits and request pause
before a safe boundary; SIGTERM may still lose the current uncheckpointed task.
Do not serialize a mutable large model from an asynchronous signal handler.
New Slurm jobs must reopen and verify the same run; no submission command ships.
Kernel-lock and rename semantics must be verified on the selected shared storage.

Specs/artifact references use relative logical names and roots can relocate.
This is not approval to mix Windows/CSC package versions, RNG/BLAS behavior or
platforms silently. Unchanged declared software and code are required; any planned
environment exception/migration policy needs separate review. These checkpoints
are not bitwise MCMC-continuation states.

## Scientific and integration gates

Checkpoint completeness is technical only. Offset propagation in the actual Hmsc
implementation, REF/CAND panel equality, annual response/effort definitions,
weather-window acquisition/release dates and the interpretation of grouped
`cv_year` remain unresolved. No future-year validation or scientific convergence
is certified. A matching pair identity does not itself prove upstream NA/NaN/Inf
filtering, training-only scaling/selection or ecological correctness.

Before integration recover the closed historical dated controller, its actual
configuration/manifest, generated predictive monacha `scripts/S1a.R`, corresponding
source copy and run-specific package metadata. The researcher reports the old
controller checks STOP_AFTER_STAGE only between whole stages, waits in system2(),
may mark an interrupted child failed and removes an old stop marker on a new run.
Those are REPORTED_LOCAL here, not independently inspected source behavior.
This new module does not change or reuse those stop files.

GO: review the isolated code and synthetic Linux/Windows tests.
NO-GO: real S1a adapter integration until source correspondence and scientific
contracts are reviewed and the researcher separately approves implementation.
NO-GO: Hmsc smoke tests, real fitting, CV, CSC tests/submission without separate
approval. Old models, selections, original inputs and protected jobs stay intact.

Run only the synthetic suite from the repository root:

```text
python -B tools/tests/test_checkpoint_resume_v1.py
```

See TEST_REPORT.md for actual executed evidence and unverified platform limits.
