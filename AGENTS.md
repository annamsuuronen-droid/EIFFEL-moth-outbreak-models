# Autonomous working rules

- Explanatory inference and predictive validation must remain separate.
- Never use outer-test data in predictor, lag, threshold or buffer selection. Make these choices using training data and inner validation only.
- Population-lag comparisons must use identical lag-matched observations.
- Growth-model inference is separate from abundance forecasting.
- Same-year cross-species associations are not advance predictors.
- Never overwrite completed scientific results; create new versions with provenance.
- Inspect existing outputs before rerunning expensive models.
- Use cheap tests before expensive runs.
- Document all scientific decisions and dependencies in project_state/.
- Open a GitHub issue labelled needs-scientific-review only for genuine scientific decisions that cannot be resolved from evidence.
- Do not start scientific auditing until local synchronization has populated the repository. Do not invent missing files or results, or declare a file authoritative without evidence.
- imported_local/ preserves source context; importing a file does not establish that it is active or authoritative. Review script roles after import.
