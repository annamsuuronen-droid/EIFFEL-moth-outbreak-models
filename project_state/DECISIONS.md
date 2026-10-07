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
