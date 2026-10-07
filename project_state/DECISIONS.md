# Decisions

## Phase 1: infrastructure only

User requested a lightweight local import before scientific auditing. Source originals remain untouched. Imports preserve directory context and use conservative extension, path, size and table-role filters. CSV scaffolds have no result rows; authoritative-file and dependency registries are empty. No scientific decisions have yet been made.

## Phase 2 — available-evidence audit v1 (2026-10-07)

- Pinned source main at 427136e134caf6e93cfdc3080c1520170627a9d5 and inventoried all imported scripts/summaries and manifest entries. Audit records are new immutable audit_v1 files.
- Authority is scoped: latest recorded predictive selection is C+D v2 (five lag1 weather plus three100m NDVI variables); latest explanatory export is species-specific v4, conditional on missing producer/PPC evidence and V review. Selection and validation are separate.
- S5 is species-association inference using the explanatory baseline and fixed exact lag1. It is not growth-model inference or predictive population-lag selection. No directions/effect estimates were invented from excluded files.
- COMPLETE distinguishes recorded stage completion from scientific adequacy; PARTIAL/NOT_EVIDENCED were added instead of falsely labelling unfinished/absent runs as FAILED. No standalone TEST run is positively evidenced.
- Saved metrics/policy flags were checked cheaply without R execution. No expensive rerun was justified; missing summaries should be recovered and existing checkpoints inspected first.
- Opened scientific-review issue#1 only for the non-blocking-V inferential policy. Import/path gaps remain in UNRESOLVED_ISSUES.md.
- No existing scientific output or result-summary placeholder was overwritten or populated with unverified estimates.

## Controlled nested-CV reconstruction r1 (2026-10-07)

- Accept the user's completed forensic search conclusion: original v2 producer is unavailable; do not continue searching. Preserve v1 as immutable historical evidence.
- Treat v1 final-fit semantics as a candidate backend, not established v2 behavior. Different success/failure statuses prove directory renaming alone is insufficient; no causal fix is invented.
- Freeze all 166 observed v2 tables and saved outer partition. Read completed selection exports; never reselect from outer-test performance or silently repeat completed selection. Complete folds 1-4 are immutable skips.
- Expose only read-only dry-run/validation at the command line. A separately defined fold-5 recovery API requires local checkpoint/input validation and evidenced final-profile compatibility. No profile or model result is fabricated; no scientific command is provided or run.
- Validate existing metric arithmetic and selection flags cheaply. Use only temporary test copies and mock metadata for refusal tests; scientific backends are failing stubs. Keep outer-site CV and pooled/master completion disabled.
- Missing final-fit configuration is a provenance/compatibility blocker, not an inferred new scientific choice requiring an issue. Existing issue #1 is untouched.
