# Workflow — pending local import

1. Clone this repository to a separate Windows directory outside D:\EIFFEL.
2. Run tools/sync_from_local_EIFFEL.ps1 using Windows PowerShell 5.1 or newer.
3. Review local_manifest.csv and imported_local/ for raw data, sensitive content and unwanted files before committing. Filename/path filters are conservative heuristics, not proof that a table contains no raw observations. Inspect Rmd/qmd/md for embedded data too.
4. Commit and push only the reviewed lightweight import and manifest.
5. Once the cloud sees the import, update PROJECT_STATE.md and inventory scripts, outputs and dependencies before scientific auditing or model execution.

The import is one-time: it refuses to overwrite imported_local/ or local_manifest.csv. It preserves relative paths, does not execute scripts and writes nothing to the source. Scripts/documents are capped at 1 MiB; txt/csv/csv2/tsv files at 256 KiB; aggregate copies at 20 MiB. Tables require a summary-style filename or directory. Unmatched tables remain local and are recorded in the manifest. All images and non-allowlisted formats are excluded.

Do not infer active/authoritative status from filenames. Record evidence in AUTHORITATIVE_FILES.csv only after review. Result tables currently contain a generic bookkeeping schema, to be replaced with an evidence-based schema before the first scientific result version is created. Keep completed result versions immutable.
