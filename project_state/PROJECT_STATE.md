# Project state — Phase 2 ready

- Cloud environment is ready.
- Full local project is at `D:\EIFFEL` and is not directly visible to Codex Cloud.
- Lightweight local synchronization has completed and was pushed to `main`.
- Imported material is under `imported_local/`.
- The provenance manifest is `local_manifest.csv`.
- Import commit: `bd4717603df052bb92a3172f630c754df84de30d`.
- All 17 discovered R scripts were included in the lightweight import.
- Lightweight HMSC result summaries were included; large `.RData`/`.rds`, raw data, GIS rasters/vectors, and model objects remain local.
- No new scientific model was run during synchronization.
- No imported model result is authoritative merely because it was imported.
- Scientific audit may now begin from the imported scripts, summaries, and manifest.
- Next action: Codex Cloud performs the authoritative-workflow audit, verifies explanatory vs predictive branches, identifies final predictor sets and population-dynamics dependencies, and records any genuinely unresolved scientific decisions.
