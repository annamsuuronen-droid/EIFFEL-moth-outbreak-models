# S1a selection states v1 — synthetic, pure implementation, 2026-10-19

Base: `695307f6695d3ec57f332d3c6ea057d3ca31c01f`, checkpoint branch
`feature/s1a-checkpoint-resume-v1`. Work branch:
`feature/s1a-adaptive-state-machine-v1`. This implements the approved design B
boundary only. The checkpoint engine and historical R scripts are unchanged.

Review correction base: `db8833169f69a790ca151c5b1966041893611497`.
Correction branch: `feature/s1a-state-machine-review-fixes-v1`, targeting the
original state-machine branch. PR #4 and PR #5 remain separate Drafts.

## Implemented boundary

`tools/eiffel_s1a_selection_state_v1.py` uses Python 3.10+ standard library only.
It has no CLI, IO, filesystem persistence, RNG draws, subprocesses, R/Hmsc calls,
scientific backend or imports from the checkpoint engine. It returns immutable
canonical JSON bytes. A `Record.data` view is a detached copy; mutating it cannot
alter a prior contract, state, decision, plan or certificate.

The public sequence is:

```text
selection = Selection.start(explicit_contract)
batch = plan(selection)             # Replays and verifies the entire history.
source = result(batch.data['source_id'], status, explicit_payload,
                rng_before_reference, rng_after_reference)
event = decision(selection.base, selection.state, source)
selection = selection.apply(event, source)
snapshot = selection.export()       # In-memory record; nothing is written.
restored = Selection.restore(snapshot)
certificate = restored.completion() # Only after full validated termination.
groups = restored.group_summary()   # Derived history/representation view.
```

The complete synthetic contract and payload examples live in the test file.
All fixture profiles, digests, decisions, ranks, species and RNG references are
artificial. They do not identify historical models or accepted scientific rules.

## Immutable base and fixed batches

Contract schema `1` binds logical selection ID, predictive/explanatory mode,
species ID, declared source-code/input SHA-256 maps, ordered weather-group
definitions, an explicit policy ID and limits, screen/confirm/backward profiles,
software version strings and the RNG policy/initial reference. No historical
threshold or profile is supplied by default. The caller explicitly sets the
forward limit or `None`; there is no first/two-group stopping rule.

Each `plan()` is a fixed **decision-input batch descriptor**, not an executable
checkpoint DAG. It binds the exact parent-state SHA, base SHA, slot, candidate
order, current variables/groups, profile and RNG-before reference. Its source ID
is derived from those bytes. Later plans do not mutate earlier ones. No workers,
task scheduling or checkpoint-engine integration are implemented.

The public `plan(selection)` accepts a `Selection` history and calls `verify()`
before constructing a descriptor. Passing a raw state, a forged history or the old
two-argument signature is refused. `_plan_for_state()` is a private replay/event
helper, not a dispatch API. `decision(base, state, source)` only builds an event;
it does not validate a history or authorize execution. `Selection.apply()` performs
the history check before accepting that event. Planning does not replace future
single-writer locking, fresh-HEAD checks or atomic publication.

## States, supplied decisions and transitions

States carry version, parent/base SHA, forward/backward phase, next slot, step
counters, selected groups/variables, ordered remaining groups, screening rows,
confirmation queue, context-specific rejections, termination reasons, unresolved
issue, the last decision/source reference and RNG reference. The parent chain
preserves earlier decision history without copying all history into every state.

Slots:

| Slot | Complete input and effect |
| --- | --- |
| `screen` | One row per remaining group, explicit boolean acceptance, unique ranks `0..n-1`, resolved variables. Ranks order the confirmation queue. |
| `confirm` | Expected group, explicit acceptance and the same screened variables. Rejection advances the queue; acceptance starts a new forward context. |
| `forward_end` | Exact pending reason, allowed by the immutable contract. |
| `backward_start` | Explicit applicability and structural reason. Required backward cannot be skipped while two or more variables remain. |
| `backward_round` | One row per current variable, explicit removal decision, rank and group-guard flag. First ranked accepted removal is applied. |
| `backward_end` | Exact pending reason after no allowed removal, one remaining variable, or documented inapplicability. |
| `review` | Explicit matching failed-source SHA, `retry` authorization and reason. Restores the pending slot, never a partial MCMC chain. |

The engine does **not** calculate SR2, acceptance thresholds, scientific rankings,
correlations or panels. Input rank ties are refused; the later adapter must
reproduce the actual source's ranking/tie behavior before assigning ranks.
Scientific addition/removal acceptance is supplied explicitly. The structural
group guard checks the declared positive minimum against declared group membership
and refuses contradictions; its parameter is synthetic until locally reviewed.

An accepted group alone is removed from `remaining`. Screening/confirmation
rejections are local to the current forward context, so the same group can be
reconsidered after another group is accepted. The original state remains intact.
Backward removes individual variables and never automatically removes group IDs.

## Group history and current representation

The serialized `selected_groups` field means **accepted_groups_history**: unique
groups accepted in forward order. It does not assert continued representation.
`Selection.group_summary()` verifies the complete history and returns a detached,
derived record with:

- `accepted_groups_history`: the unchanged `selected_groups` acceptance history;
- `represented_groups`: contract groups with at least one declared variable in
  the current selection, in contract order.

Neither view adds fields to serialized states or certificates. If declared groups
overlap, an unaccepted group may be represented through a shared variable; this
does not accept that group or remove it from the remaining candidate universe.

At each accepted forward confirmation, the resolved variable list must contain
at least one variable of the candidate group. An empty list, or a list consisting
only of unrelated previously selected variables, cannot accept that group. No
exception rule is supplied. Rejected confirmations do not acquire this acceptance
requirement. Existing scientific acceptance flags and ranks are unchanged.

A later accepted forward result may remove every variable of an earlier group,
for example as an adapter-supplied correlation-filtering result. Its historical
acceptance remains recorded, while its current representation disappears. The
previous states and exact screened/confirmed variable lists remain in the hashed
chain. This is a traceable state change, not silent removal from the history.
Every current variable must have an accepted-group origin; a nonempty acceptance
history cannot have an entirely empty current variable set.

`minimum_variables_per_group` is specifically a **backward-removal guard**, not a
minimum for forward acceptance or final group sizes. A backward removal affecting
an accepted, represented group must leave at least this many of its variables.
With the required positive minimum, backward cannot eliminate its representation.
Already unrepresented historical groups do not block other removals. Forward
filtering may leave fewer variables than this removal minimum; the engine does
not invent replacement variables or change scientific addition decisions. Whether
the local scientific rule uses this same distinction remains unverified.

Completion replays all confirmations and removals and checks the group-state
invariant. Thus it refuses inconsistent histories, while allowing a legitimate
historical group to be unrepresented later. Certificate `selected_groups` retains
the history meaning; obtain current representation from `group_summary()` and
the bound contract, not from this certificate field alone.

`technical_error` and `incomplete` results record a distinct unresolved issue and
require explicit review before retry. They are not scientific rejections. A full
batch retry starts from the known RNG-before reference; no partial computation is
claimed recovered. A rejected completed confirmation advances without retrying it.
A complete batch asserts every listed row is technically complete. A per-candidate
technical failure must block the batch as an issue; it cannot be encoded as a
scientific `accepted=false` result. Real mixed-result handling remains an adapter
responsibility, with no historical error-skipping rule inferred here.

## Decision integrity and replay

Each decision binds base SHA, parent-state SHA, slot, source ID/SHA and payload
SHA; its own ID hashes those fields. Source SHA is recomputed from the supplied
source record bytes. `Selection.verify()` replays the full recorded chain from
the base and compares every derived state byte-for-byte, including RNG references.
Unknown parents, incorrect order, missing batches, wrong source/content hashes,
contract changes and state corruption fail verification.

Exact replay of a decision already in the supplied history returns that history
unchanged. A different successor for its parent/slot raises `Conflict`. Separate
pure histories **can fork** from the same parent. This module cannot know about
another process's value; global serialization and atomic publication belong to a
future coordinator. Hashes provide consistency, not external authenticity.

Input/code digests and software versions are declared metadata here. There are no
file reads to prove actual source bytes or installed versions. Source records are
synthetic evidence objects, not verified model artifacts or external manifests.
A later adapter/coordinator must supply and independently verify those links.

## RNG and completion

RNG references contain ID, SHA and source ID. Required before-state must match
exactly. Computation-result after-state must have the expected source provenance;
metadata-only transitions preserve the reference. Missing or wrong references
refuse advancement. RNG-free contracts explicitly require `None` references and
cannot silently acquire a different policy. No RNG bytes or R `.Random.seed`
vectors are inspected, restored or generated. These fake references do not prove
Python/R/Hmsc random-number equivalence or historical replay.

Completion requires replay of the whole chain, an explicitly allowed forward
termination, completed/documented-inapplicable backward, no unresolved issue and
no pending slot. The certificate binds final state, whole exported chain, final
groups/variables, stop reasons and all decision/source references. It always has:

```text
technical_complete = true
scientific_approval = false
model_artifacts_verified = false
evidence_scope = synthetic_decision_chain_only
```

A summary flag, two accepted groups, missing CAND, unprocessed backward or forged
terminal state cannot substitute for those checks. The backward shape (individual
variable removal, minimum guard, no additional confirmation) is an explicit
synthetic contract inspired by repository references, not proof of the local S1a.

## Schema and compatibility after review corrections

Serialized contract schema `1`, state/plan/event/export/certificate fields and
canonical serialization are unchanged. No migration is performed. The public
Python planning signature intentionally changes from `plan(base, state)` to
`plan(selection)`; callers must update, rather than use an unsafe compatibility
overload. The original 27 test methods retain their assertions; only their seven
planning call sites (including the shared helper) use the new signature.

Golden export/certificate SHA-256 tests captured from `db883316` cover four old
valid histories: initial, three accepted groups, loss of an earlier group's
representation, and a forward size below the backward-removal minimum. They
retain exact bytes/hashes and restore successfully. A separately captured old
history that accepted an empty group is refused by the corrected replay. This is
stricter validation, not an automatic rewrite of that old history. No claim is
made that arbitrary legacy histories will pass, or that old invalid certificates
become valid. Keep old snapshots intact for review.

These compatibility tests hold declared contract metadata fixed. A future real
coordinator must bind the actual corrected code SHA; that changes the contract
identity and downstream hashes. Never silently rebind old results to new code.

## Unimplemented responsibilities and scientific gates

No checkpoint format or existing checkpoint compatibility changes. No actual
checkpoint is opened. No adaptive task graph is added to the existing engine.
Future work needs separately reviewed checkpoint bindings, cross-batch reuse,
single-writer coordination, atomic decision/HEAD publication, durable storage,
process failure recovery, resource controls and actual RNG handling. Full in-memory
replay is not a certified production storage protocol or performance benchmark.

The Windows D: drive is inaccessible here. Recover the closed dated controller,
generated monacha `predictive/scripts/S1a.R`, source copy, settings and package
metadata before real integration. The imported three-species predictive and
explanatory scripts are references, not proven identical local producers.

Hmsc offset propagation, actual REF/CAND panel/NA/NaN/Inf handling, weather timing,
`cv_year` interpretation, convergence and selection/evaluation independence remain
scientific gates. No scientific rule, historical result or original data is changed.
No Hmsc, MCMC, real CV, annual build or CSC operation is authorized by this module.

GO: review this synthetic layer. CONDITIONAL GO: a later synthetic coordinator
stage only after separate approval. NO-GO: real S1a/Hmsc integration or CSC tests.
