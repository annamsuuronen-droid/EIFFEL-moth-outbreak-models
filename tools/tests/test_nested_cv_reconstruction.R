# Base-R tests only. Scientific functions are stubbed to fail if invoked.
args <- commandArgs(trailingOnly = TRUE)
repository <- normalizePath(if (length(args)) args[1] else getwd(), winslash = "/")
script <- file.path(repository, "R/S3_NESTED_OUTER_CROSS_VALIDATION_predictive_HMSC_v2_RECONSTRUCTED.R")
invisible(parse(script))
source(script)
fit_train_model <- predict_new_data <- recon_v1_backend <- function(...) stop("SCIENTIFIC EXECUTION FORBIDDEN IN TEST")
root <- normalizePath(file.path(repository, "imported_local/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2"), winslash = "/")
count <- 0L
pass <- function(ok, label) { stopifnot(isTRUE(ok)); count <<- count + 1L; cat("PASS", label, "\n") }
refuses <- function(code, pattern, label) {
  error <- tryCatch({ force(code); NULL }, error = identity)
  pass(inherits(error, "error") && grepl(pattern, conditionMessage(error)), label)
}
snapshot <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE))
  list(paths = paths, md5 = unname(tools::md5sum(paths)), mtime = file.info(paths)$mtime)
}
before <- snapshot(root)
plan <- recon_inspect(root, repository, evidence_only = TRUE)
pass(all(vapply(plan$folds[1:4], function(r) r$complete && r$next_action == "SKIP_IMMUTABLE_COMPLETE_FOLD", logical(1))), "complete folds skipped")
pass(!plan$folds[["5"]]$complete && plan$folds[["5"]]$status == "SELECTION_COMPLETE_FINAL_PENDING", "incomplete fold detected")
pass(identical(snapshot(root), before), "inspection preserves output bytes/timestamps")
recon_main(c("--dry-run", "--evidence-only", "--output-root", root, "--repository", repository, "--fold", "5"))
pass(identical(snapshot(root), before), "CLI dry-run never fits or changes output")
refuses(recon_inspect(root, repository, fold_only = 1, evidence_only = TRUE), "Only fold-5", "fold-5-only guard")
refuses(recon_resume_fold5(root, repository, "nonexistent", fold = 1), "completed folds", "refuse execution of complete folds")
refuses(recon_resume_fold5(root, repository, "nonexistent"), "Imported snapshots", "output-root snapshot protection")
refuses(recon_root(repository), "Wrong output root", "wrong output-root refusal")
refuses(recon_main(c("--run", "--fold", "5")), "DRY-RUN", "no real scientific CLI")
refuses(recon_profile_gate(NULL), "Missing verified", "unverified historical profile blocked")
refuses(recon_inspect(root, repository), "Missing completion checkpoint", "missing local checkpoint refusal")
refuses(recon_main(c("--dry-run", "--fold", "4", "--output-root", root, "--repository", repository)), "Only fold-5", "CLI fold-5-only")

workspace <- tempfile("recon-synthetic-"); dir.create(workspace)
tryCatch({
  fixture <- file.path(workspace, "hmsc_outputs", recon_basename)
  dir.create(dirname(fixture), recursive = TRUE)
  stopifnot(file.copy(root, dirname(fixture), recursive = TRUE))
  fixture <- normalizePath(fixture, winslash = "/")
  fd <- file.path(fixture, "outer_year/fold_05")
  file.create(file.path(fd, "outer_test_metrics.csv2"))
  refuses(recon_inspect(fixture, repository, evidence_only = TRUE), "Partial prediction", "partial export refusal")
  unlink(file.path(fd, "outer_test_metrics.csv2"))
  saveRDS(list(), file.path(fd, "OUTER_FOLD_COMPLETE.rds"))
  refuses(recon_inspect(fixture, repository, evidence_only = TRUE), "without final outputs", "inconsistent completion marker refusal")
  unlink(file.path(fd, "OUTER_FOLD_COMPLETE.rds"))
  file.create(file.path(fixture, "outer_year/fold_01/OUTER_FOLD_COMPLETE.rds"))
  refuses(recon_inspect(fixture, repository), "read|connection", "unreadable checkpoint refusal")
  unlink(file.path(fixture, "outer_year/fold_01/OUTER_FOLD_COMPLETE.rds"))
  original <- file.path(fd, "01_weather_selection/selected_weather_variables.csv2")
  cat('"variable"\n"unexpected"\n', file = original)
  refuses(recon_inspect(fixture, repository, evidence_only = TRUE), "content mismatch", "changed selection refused")
  # Direct semantic tests establish guards separately from frozen-file fingerprinting.
  expected <- recon_read_expected(repository)
  bad <- expected$partition; bad$fold[1] <- 5
  refuses(recon_same_table(bad, expected$partition, "partition"), "Value mismatch", "partition consistency")
  bad <- expected$folds[["5"]]$coverage; bad$n_site_years[2] <- 917
  refuses(recon_same_table(bad, expected$folds[["5"]]$coverage, "coverage"), "Value mismatch", "coverage consistency")
  r <- plan$folds[["1"]]
  bad <- r$predictions; bad$year[1] <- "1994"
  refuses(recon_validate_predictions(bad, r$metrics, r$partition, r$coverage, 1), "partition", "prediction partition consistency")
  bad <- r$metrics; bad$RMSE[1] <- "1"
  refuses(recon_validate_predictions(r$predictions, bad, r$partition, r$coverage, 1), "Value mismatch", "metric recomputation mismatch")
  bad <- r$predictions; names(bad)[1] <- "other"
  refuses(recon_validate_predictions(bad, r$metrics, r$partition, r$coverage, 1), "schema", "prediction schema mismatch")
  # Synthetic metadata IDs only; no invented scientific observations or fitted values.
  synthetic_ids <- function(years) unlist(lapply(years, function(y) paste0("SYNTHETIC", seq_len(as.integer(r$partition$n[r$partition$block_value == y])), "__", y)))
  cp <- list(scheme = "year", outer_fold = 1L, outer_train_ids = synthetic_ids(r$train_years),
             outer_test_ids = unique(r$predictions$sample_id), final_train_ids = synthetic_ids(r$train_years),
             final_test_ids = unique(r$predictions$sample_id), coverage = r$coverage,
             weather = list(variables = r$weather), environment = list(variables = r$environment),
             predictions = r$predictions, metrics = r$metrics)
  pass(isTRUE(recon_validate_checkpoint(cp, r)), "compatible checkpoint contract accepted")
  bad <- cp; bad$outer_fold <- 5L
  refuses(recon_validate_checkpoint(bad, r), "fold mismatch", "checkpoint fold mismatch")
  bad <- cp; bad$final_test_ids[1] <- "SYNTHETIC_BAD__1994"
  refuses(recon_validate_checkpoint(bad, r), "matched rows|test rows", "checkpoint row inconsistency")
  bad <- cp; bad$weather$variables <- "other"
  refuses(recon_validate_checkpoint(bad, r), "selection mismatch", "checkpoint predictor inconsistency")
  # The grouped-fold generator must not be called: explicit existing partition is used.
  make_grouped_folds <- function(...) stop("REPARTITION FORBIDDEN")
  pass(identical(plan$folds[["5"]]$test_years, c("1999", "1994", "2013", "2019", "2020", "2014")), "saved fold-5 years retained")
  stage <- file.path(workspace, "stage.txt"); dest <- file.path(workspace, "destination.txt")
  writeLines("synthetic-stage", stage); writeLines("existing-sentinel", dest)
  refuses(recon_exclusive_publish(stage, dest), "overwrite", "exclusive publication overwrite refusal")
  pass(identical(readLines(dest), "existing-sentinel"), "existing destination preserved")
  absent <- file.path(workspace, "new.txt")
  recon_exclusive_publish(stage, absent)
  pass(identical(readLines(absent), "synthetic-stage"), "exclusive new-file publication")
}, finally = unlink(workspace, recursive = TRUE))
pass(identical(snapshot(root), before), "all tests preserve real imported evidence")
cat("PASS:", count, "non-scientific tests; all 166 evidence files and 192 completed-fold metrics validated; no Hmsc/MCMC/model execution.\n")
