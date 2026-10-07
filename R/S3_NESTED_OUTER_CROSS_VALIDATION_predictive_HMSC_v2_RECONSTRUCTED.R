# Controlled recovery producer, reconstruction r1. This is NOT the recovered historical v2.
# CLI is validation/dry-run ONLY. No package installation or model fitting at entry.
# An explicit fold-5 recovery API is defined below, gated by local validation and
# independently verified historical final-fit settings. No site-CV driver exists.
recon_version <- "S3_v2_RECONSTRUCTED_r2"
recon_basename <- "S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2"
recon_assert <- function(ok, message) {
  if (length(ok) != 1L || is.na(ok) || !ok) stop(message, call. = FALSE)
}
recon_table <- function(path) {
  recon_assert(file.exists(path), paste("Missing required file:", path))
  read.table(path, header = TRUE, sep = ";", dec = ",", quote = '"',
             colClasses = "character", check.names = FALSE, stringsAsFactors = FALSE,
             comment.char = "", na.strings = character(0), fileEncoding = "UTF-8-BOM")
}
recon_same_table <- function(actual, expected, label) {
  actual <- as.data.frame(actual); expected <- as.data.frame(expected)
  recon_assert(identical(names(actual), names(expected)) && nrow(actual) == nrow(expected),
               paste("Schema/row count mismatch:", label))
  for (name in names(expected)) {
    a <- as.character(actual[[name]]); b <- as.character(expected[[name]])
    a[is.na(a)] <- ""; b[is.na(b)] <- ""
    numeric_b <- suppressWarnings(as.numeric(gsub(",", ".", b, fixed = TRUE)))
    numeric_column <- is.numeric(expected[[name]]) || (length(b) && any(is.finite(numeric_b)) && all(!nzchar(b) | is.finite(numeric_b)))
    if (numeric_column) {
      numeric_a <- suppressWarnings(as.numeric(gsub(",", ".", a, fixed = TRUE)))
      recon_assert(identical(!nzchar(a), !nzchar(b)), paste("Missing-value mismatch:", label, name))
      keep <- nzchar(b)
      recon_assert(all(is.finite(numeric_a[keep])) && all(abs(numeric_a[keep] - numeric_b[keep]) <= 1e-8 + 1e-9 * abs(numeric_b[keep])), paste("Value mismatch:", label, name))
    } else {
      recon_assert(identical(a, b), paste("Value mismatch:", label, name))
    }
  }
  invisible(TRUE)
}
recon_root <- function(root, execution = FALSE) {
  recon_assert(dir.exists(root), "Output root must already exist; never create a replacement root.")
  # Reject textual traversal before normalizing, and physical aliases after normalizing.
  clean <- gsub("\\", "/", root, fixed = TRUE)
  recon_assert(!grepl("(^|/)\\.\\.?(/|$)", clean), "Output-root traversal refused.")
  physical <- normalizePath(root, winslash = "/", mustWork = TRUE)
  recon_assert(basename(physical) == recon_basename && basename(dirname(physical)) == "hmsc_outputs",
               "Wrong output root: expected the existing hmsc_outputs/S3...v2 directory.")
  recon_assert(identical(tolower(sub("/+$", "", clean)), tolower(physical)),
               "Output-root aliases, symlinks and relative paths refused.")
  if (execution) {
    recon_assert(!grepl("(^|/)imported_local[^/]*(/|$)", physical), "Imported snapshots cannot receive scientific output.")
  }
  physical
}
recon_path <- function(root, relative) {
  recon_assert(!grepl("(^|/)\\.\\.?(/|$)|[:\\\\]", relative), "Unsafe evidence path.")
  path <- file.path(root, relative)
  recon_assert(file.exists(path) || dir.exists(path), paste("Missing:", path))
  resolved <- normalizePath(path, winslash = "/", mustWork = TRUE)
  recon_assert(identical(tolower(path), tolower(resolved)) && startsWith(resolved, paste0(root, "/")),
               paste("Evidence path alias/escape refused:", relative))
  path
}
recon_read_expected <- function(repository) {
  path <- file.path(repository, "project_state/nested_cv_reconstruction_v1/expected_v2_evidence.R")
  e <- new.env(parent = baseenv())
  sys.source(path, envir = e)
  e$recon_expected
}
recon_md5_lf <- function(path, protected_root) {
  # Temporary hashing scratch is outside scientific output; no output-root writes.
  recon_assert(!startsWith(normalizePath(tempdir(), winslash = "/"), paste0(protected_root, "/")), "Temporary directory inside scientific output refused.")
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  text <- gsub("\r\n", "\n", rawToChar(bytes), fixed = TRUE)
  tmp <- tempfile("recon-hash-")
  on.exit(unlink(tmp), add = TRUE)
  con <- file(tmp, "wb"); writeBin(charToRaw(text), con); close(con)
  unname(tools::md5sum(tmp))
}
recon_validate_inventory <- function(root, repository) {
  inventory <- read.csv(file.path(repository, "project_state/nested_cv_reconstruction_v1/EVIDENCE_INVENTORY.csv"), stringsAsFactors = FALSE)
  recon_assert(nrow(inventory) == 166L && !anyDuplicated(inventory$relative_path), "Invalid frozen evidence inventory.")
  for (i in seq_len(nrow(inventory))) {
    path <- recon_path(root, inventory$relative_path[i])
    recon_assert(recon_md5_lf(path, root) == inventory$md5[i], paste("Frozen v2 evidence content mismatch:", inventory$relative_path[i]))
  }
  invisible(TRUE)
}
recon_values <- function(root, relative, column) {
  data <- recon_table(recon_path(root, relative))
  recon_assert(identical(names(data), column), paste("Unexpected selected-variable/group schema:", relative))
  values <- data[[column]]
  recon_assert(!anyNA(values) && !anyDuplicated(values) && all(nzchar(values)), "Invalid selection list.")
  values
}
recon_metrics <- function(predictions) {
  number <- function(x) as.numeric(gsub(",", ".", x, fixed = TRUE))
  signed_r2 <- function(y, p) {
    ok <- is.finite(y) & is.finite(p); y <- y[ok]; p <- p[ok]
    if (length(y) < 3 || length(unique(y)) < 2 || length(unique(p)) < 2) return(NA_real_)
    r <- suppressWarnings(cor(y, p, method = "spearman")); sign(r) * r^2
  }
  output <- list()
  for (model in c("WEATHER_ONLY", "WEATHER_PLUS_ENVIRONMENT")) {
    for (species in c("Epirrita autumnata", "Operophtera brumata", "Operophtera fagata")) {
      z <- predictions[predictions$model_type == model & predictions$species == species, , drop = FALSE]
      y <- number(z$observed); p <- number(z$predicted_median); pr <- number(z$presence_probability)
      occ <- as.numeric(y > 0); pos <- is.finite(y) & y > 0 & is.finite(p)
      finite_occurrence <- is.finite(occ) & is.finite(pr)
      occ_auc <- occ[finite_occurrence]; pr_auc <- pr[finite_occurrence]
      npos <- sum(occ_auc == 1); nneg <- sum(occ_auc == 0)
      auc <- if (npos && nneg) (sum(rank(pr_auc, ties.method = "average")[occ_auc == 1]) - npos * (npos + 1) / 2) / (npos * nneg) else NA_real_
      output[[length(output) + 1L]] <- data.frame(evaluation = "outer_year", model_type = model, species = species,
        n = sum(is.finite(y) & is.finite(p)), RMSE = sqrt(mean((y - p)^2, na.rm = TRUE)), SR2 = signed_r2(y, p),
        O.RMSE = sqrt(mean((occ - pr)^2, na.rm = TRUE)), O.AUC = auc,
        O.TjurR2 = if (npos && nneg) mean(pr[occ == 1], na.rm = TRUE) - mean(pr[occ == 0], na.rm = TRUE) else NA_real_,
        C.RMSE = if (any(pos)) sqrt(mean((y[pos] - p[pos])^2)) else NA_real_, C.SR2 = signed_r2(y[pos], p[pos]),
        outer_fold = unique(z$outer_fold), scheme = "year", stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, output)
}
recon_validate_predictions <- function(pred, metrics, partition, coverage, fold) {
  columns <- c("evaluation", "model_type", "sample_id", "site", "year", "species", "observed", "predicted_median", "presence_probability", "outer_fold", "scheme")
  recon_assert(identical(names(pred), columns), "Prediction schema mismatch.")
  recon_assert(all(pred$evaluation == "outer_year") && all(pred$scheme == "year") && all(as.integer(pred$outer_fold) == fold), "Prediction scheme/fold mismatch.")
  recon_assert(all(partition$fold[match(pred$year, partition$block_value)] == fold), "Prediction partition mismatch.")
  models <- c("WEATHER_ONLY", "WEATHER_PLUS_ENVIRONMENT")
  species <- c("Epirrita autumnata", "Operophtera brumata", "Operophtera fagata")
  recon_assert(setequal(unique(pred$model_type), models) && setequal(unique(pred$species), species), "Prediction model/species mismatch.")
  expected_n <- as.integer(coverage$n_site_years[coverage$label == "outer_test_final_complete"])
  reference_ids <- NULL
  for (model in models) for (sp in species) {
    z <- pred[pred$model_type == model & pred$species == sp, , drop = FALSE]
    recon_assert(nrow(z) == expected_n && !anyDuplicated(z$sample_id), "Prediction sample coverage mismatch.")
    recon_assert(all(z$sample_id == paste0(z$site, "__", z$year)), "Prediction sample/site/year inconsistency.")
    if (is.null(reference_ids)) reference_ids <- z$sample_id
    recon_assert(identical(z$sample_id, reference_ids), "Unmatched final-model/species rows.")
    p <- as.numeric(gsub(",", ".", z$presence_probability, fixed = TRUE))
    recon_assert(all(is.finite(p) & p >= 0 & p <= 1), "Invalid occurrence probability.")
    median <- as.numeric(gsub(",", ".", z$predicted_median, fixed = TRUE))
    recon_assert(all(is.finite(median) & median >= 0), "Invalid abundance prediction.")
    if (model == models[2]) {
      ref <- pred[pred$model_type == models[1] & pred$species == sp, , drop = FALSE]
      recon_assert(identical(z$observed, ref$observed), "Observed outcomes differ between compared models.")
    }
  }
  expected <- recon_metrics(pred)
  key <- function(x) paste(x$model_type, x$species)
  recon_assert(nrow(metrics) == 6L && !anyDuplicated(key(metrics)), "Metrics group mismatch.")
  metrics <- metrics[match(key(expected), key(metrics)), , drop = FALSE]
  recon_same_table(metrics, expected, paste("recomputed metrics fold", fold))
  invisible(TRUE)
}
recon_load_inputs <- function(path) {
  recon_assert(file.exists(path), "Missing primary RData: input-row compatibility cannot be verified.")
  e <- new.env(parent = baseenv()); objects <- load(path, envir = e)
  required <- c("target_species", "Y_annual_all", "Loff_annual_all", "sample_metadata", "X_sample", "weather_groups", "environment_groups_buffered", "environment_candidate_table")
  recon_assert(all(required %in% objects), "Primary RData schema mismatch.")
  inputs <- mget(required, envir = e, inherits = FALSE)
  y <- inputs$Y_annual_all; o <- inputs$Loff_annual_all; md <- inputs$sample_metadata; x <- inputs$X_sample
  recon_assert(!is.null(rownames(y)) && !anyDuplicated(rownames(y)) && !anyDuplicated(md$sample_id) && !anyDuplicated(x$sample_id), "Duplicate/missing primary identifiers.")
  ids <- rownames(y)[rownames(y) %in% Reduce(intersect, list(rownames(y), rownames(o), as.character(md$sample_id), as.character(x$sample_id)))]
  recon_assert(length(ids) == 1430L, "Primary base panel is not the recorded 1430 rows.")
  inputs$Y_annual_all <- y[ids, , drop = FALSE]; inputs$Loff_annual_all <- o[ids, , drop = FALSE]
  inputs$sample_metadata <- md[match(ids, md$sample_id), , drop = FALSE]
  inputs$X_sample <- x[match(ids, x$sample_id), , drop = FALSE]
  recon_assert(identical(as.character(inputs$sample_metadata$sample_id), ids) && identical(as.character(inputs$X_sample$sample_id), ids), "Primary row-order mismatch.")
  expected_species <- c("Epirrita autumnata", "Operophtera fagata", "Operophtera brumata")
  primary_species <- as.character(inputs$target_species)
  recon_assert(length(primary_species) == 3L && !anyDuplicated(primary_species) &&
                 setequal(primary_species, expected_species),
               "Primary target species mismatch.")
  recon_assert(identical(colnames(inputs$Y_annual_all), primary_species),
               "Primary Y species/order differs from target_species.")
  recon_assert(identical(colnames(inputs$Loff_annual_all), colnames(inputs$Y_annual_all)),
               "Primary offset species/order mismatch.")
  recon_assert(identical(dim(inputs$Y_annual_all), dim(inputs$Loff_annual_all)), "Offset dimensions mismatch.")
  storage.mode(inputs$Y_annual_all) <- "numeric"; storage.mode(inputs$Loff_annual_all) <- "numeric"
  dimnames(inputs$Loff_annual_all) <- dimnames(inputs$Y_annual_all)
  inputs$base_ids <- ids
  inputs
}
recon_complete_ids <- function(inputs, variables, ids) {
  recon_assert(all(variables %in% names(inputs$X_sample)), "Selected variables missing from primary input.")
  x <- inputs$X_sample[match(ids, inputs$base_ids), variables, drop = FALSE]
  valid <- rep(TRUE, length(ids))
  if (length(variables)) valid <- apply(as.matrix(x), 1L, function(z) all(is.finite(z)))
  y <- inputs$Y_annual_all[ids, , drop = FALSE]; o <- inputs$Loff_annual_all[ids, , drop = FALSE]
  ids[valid & rowSums(is.finite(y)) > 0L & apply(o, 1L, function(z) all(is.finite(z)))]
}
recon_coverage <- function(inputs, ids, label, fold) {
  md <- inputs$sample_metadata[match(ids, inputs$base_ids), , drop = FALSE]
  data.frame(label = label, n_site_years = length(ids), n_sites = length(unique(md$site)), n_years = length(unique(md$year)),
             first_year = min(as.numeric(md$year)), last_year = max(as.numeric(md$year)), scheme = "year", outer_fold = fold, stringsAsFactors = FALSE)
}
recon_partition_ids <- function(inputs, partition, fold) {
  years <- as.character(inputs$sample_metadata$year)
  recon_assert(setequal(unique(years), partition$block_value), "Primary years disagree with saved partition.")
  counts <- vapply(partition$block_value, function(y) sum(years == y), integer(1))
  recon_assert(identical(as.integer(counts), as.integer(partition$n)), "Primary per-year counts disagree with saved partition.")
  assignment <- as.integer(partition$fold[match(years, partition$block_value)])
  recon_assert(!anyNA(assignment), "Unassigned primary rows.")
  list(train = inputs$base_ids[assignment != fold], test = inputs$base_ids[assignment == fold])
}
recon_validate_checkpoint <- function(cp, report, inputs = NULL) {
  required <- c("scheme", "outer_fold", "outer_train_ids", "outer_test_ids", "final_train_ids", "final_test_ids", "coverage", "weather", "environment", "predictions", "metrics")
  recon_assert(is.list(cp) && all(required %in% names(cp)), "Completion checkpoint schema inconsistent with reconstructed contract.")
  recon_assert(identical(cp$scheme, "year") && as.integer(cp$outer_fold) == report$fold, "Checkpoint fold mismatch.")
  recon_assert(identical(as.character(cp$weather$variables), report$weather) && identical(as.character(cp$environment$variables), report$environment), "Checkpoint selection mismatch.")
  recon_same_table(cp$coverage, report$coverage, "checkpoint coverage")
  recon_same_table(cp$predictions, report$predictions, "checkpoint predictions")
  recon_same_table(cp$metrics, report$metrics, "checkpoint metrics")
  recon_assert(length(cp$outer_train_ids) == as.integer(report$coverage$n_site_years[1]) && length(cp$outer_test_ids) == as.integer(report$coverage$n_site_years[3]), "Checkpoint outer row counts mismatch.")
  recon_assert(!anyDuplicated(cp$outer_train_ids) && !anyDuplicated(cp$outer_test_ids) && !length(intersect(cp$outer_train_ids, cp$outer_test_ids)), "Checkpoint row overlap/duplicates.")
  recon_assert(all(cp$final_train_ids %in% cp$outer_train_ids) && all(cp$final_test_ids %in% cp$outer_test_ids) &&
               length(cp$final_train_ids) == as.integer(report$coverage$n_site_years[2]) && length(cp$final_test_ids) == as.integer(report$coverage$n_site_years[4]), "Checkpoint matched rows inconsistent.")
  years <- function(ids) sub(".*__", "", ids)
  recon_assert(all(as.integer(report$partition$fold[match(years(cp$outer_test_ids), report$partition$block_value)]) == report$fold) &&
               all(as.integer(report$partition$fold[match(years(cp$outer_train_ids), report$partition$block_value)]) != report$fold), "Checkpoint year partition mismatch.")
  recon_assert(identical(as.character(cp$final_test_ids), unique(as.character(report$predictions$sample_id))), "Checkpoint test rows disagree with prediction exports.")
  if (!is.null(inputs)) {
    ids <- recon_partition_ids(inputs, report$partition, report$fold)
    recon_assert(identical(cp$outer_train_ids, ids$train) && identical(cp$outer_test_ids, ids$test), "Checkpoint partition IDs mismatch.")
    vars <- c(report$weather, report$environment)
    recon_assert(identical(cp$final_train_ids, recon_complete_ids(inputs, vars, ids$train)) && identical(cp$final_test_ids, recon_complete_ids(inputs, vars, ids$test)), "Checkpoint complete-case IDs mismatch.")
  }
  invisible(TRUE)
}
recon_inspect <- function(root, repository, fold_only = 5L, evidence_only = FALSE, inputs = NULL) {
  root <- recon_root(root)
  recon_assert(identical(as.integer(fold_only), 5L), "Only fold-5 mode is supported; folds 1-4 are immutable.")
  expected <- recon_read_expected(repository)
  recon_validate_inventory(root, repository)
  scheme <- file.path(root, "outer_year")
  dirs <- sort(basename(list.dirs(scheme, recursive = FALSE, full.names = TRUE)))
  recon_assert(identical(dirs, sprintf("fold_%02d", 1:5)), "Unexpected/missing outer-year fold directories.")
  partition <- recon_table(recon_path(root, "outer_year/outer_partition_blocks.csv2"))
  recon_same_table(partition, expected$partition, "saved outer partition")
  reports <- list()
  for (fold in 1:5) {
    rel <- sprintf("outer_year/fold_%02d", fold); fd <- file.path(root, rel); exp <- expected$folds[[as.character(fold)]]
    weather <- recon_values(root, paste0(rel, "/01_weather_selection/selected_weather_variables.csv2"), "variable")
    environment <- recon_values(root, paste0(rel, "/02_environment_selection/selected_environment_variables.csv2"), "variable")
    recon_assert(identical(weather, exp$weather) && identical(environment, exp$environment), "Selected variables mismatch.")
    recon_assert(identical(recon_values(root, paste0(rel, "/01_weather_selection/selected_weather_groups.csv2"), "group"), exp$weather_groups) && identical(recon_values(root, paste0(rel, "/02_environment_selection/selected_environment_groups.csv2"), "group"), exp$environment_groups), "Selected groups mismatch.")
    coverage <- recon_table(recon_path(root, paste0(rel, "/outer_fold_coverage.csv2")))
    recon_same_table(coverage, exp$coverage, paste("fold coverage", fold))
    train_years <- partition$block_value[as.integer(partition$fold) != fold]
    test_years <- partition$block_value[as.integer(partition$fold) == fold]
    recon_assert(sum(as.integer(partition$n[as.integer(partition$fold) == fold])) == as.integer(coverage$n_site_years[3]), "Partition/coverage count mismatch.")
    present <- file.exists(file.path(fd, c("outer_test_predictions.csv2", "outer_test_metrics.csv2", "OUTER_FOLD_COMPLETE.rds")))
    recon_assert(!xor(present[1], present[2]), "Partial prediction/metric outputs; refusing resume.")
    recon_assert(!present[3] || all(present[1:2]), "Completion checkpoint without final outputs.")
    complete <- all(present[1:2])
    recon_assert(fold == 5 || complete, "Previously complete folds 1-4 are incomplete: never recompute.")
    if (!evidence_only && complete) recon_assert(present[3], "Missing completion checkpoint; never silently refit.")
    report <- list(fold = fold, weather = weather, environment = environment, coverage = coverage, partition = partition,
      train_years = train_years, test_years = test_years, complete = complete, checkpoint_checked = FALSE,
      status = if (complete) "COMPLETE_LIGHTWEIGHT" else "SELECTION_COMPLETE_FINAL_PENDING",
      next_action = if (complete) "SKIP_IMMUTABLE_COMPLETE_FOLD" else "VERIFY_FINAL_PROFILE_THEN_FIT_WEATHER_AND_FULL_ON_916_TRAIN_PREDICT_222_TEST")
    if (!is.null(inputs)) {
      ids <- recon_partition_ids(inputs, partition, fold)
      vars <- c(weather, environment)
      ft <- recon_complete_ids(inputs, vars, ids$train); fv <- recon_complete_ids(inputs, vars, ids$test)
      derived <- rbind(recon_coverage(inputs, ids$train, coverage$label[1], fold), recon_coverage(inputs, ft, coverage$label[2], fold), recon_coverage(inputs, ids$test, coverage$label[3], fold), recon_coverage(inputs, fv, coverage$label[4], fold))
      recon_same_table(derived, coverage, "primary data-derived coverage")
      report$ids <- list(outer_train = ids$train, outer_test = ids$test, final_train = ft, final_test = fv)
    }
    if (complete) {
      report$predictions <- recon_table(recon_path(root, paste0(rel, "/outer_test_predictions.csv2")))
      report$metrics <- recon_table(recon_path(root, paste0(rel, "/outer_test_metrics.csv2")))
      recon_validate_predictions(report$predictions, report$metrics, partition, coverage, fold)
      if (!is.null(inputs)) {
        for (sp in unique(report$predictions$species)) {
          z <- report$predictions[report$predictions$species == sp, , drop = FALSE]
          observed <- as.numeric(gsub(",", ".", z$observed, fixed = TRUE))
          historical <- as.numeric(inputs$Y_annual_all[z$sample_id, sp])
          recon_assert(isTRUE(all.equal(observed, historical, tolerance = 1e-10)), "Primary observations disagree with completed prediction exports.")
        }
      }
      if (present[3] && !evidence_only) {
        cp <- readRDS(recon_path(root, paste0(rel, "/OUTER_FOLD_COMPLETE.rds")))
        recon_validate_checkpoint(cp, report, inputs); report$checkpoint_checked <- TRUE; report$status <- "COMPLETE_CHECKPOINT_VALIDATED"
      }
    }
    reports[[as.character(fold)]] <- report
  }
  list(root = root, folds = reports, data_checked = !is.null(inputs), evidence_only = evidence_only,
       selection_reusable = TRUE, safe_to_fit = FALSE,
       blocker = "Historical v2 final-fit package/RNG/MCMC/random-level settings are not established by lightweight outputs; require a verified local final-profile contract.")
}
recon_print_plan <- function(plan) {
  cat(recon_version, "DRY-RUN: no scientific outputs written, no model fitting.\n")
  for (r in plan$folds) {
    cat("Fold", r$fold, r$status, "\n  held-out years:", paste(r$test_years, collapse = ", "),
        "\n  weather:", if (length(r$weather)) paste(r$weather, collapse = ", ") else "<none>",
        "\n  environment:", if (length(r$environment)) paste(r$environment, collapse = ", ") else "<none>", "\n")
    print(r$coverage, row.names = FALSE)
    cat("  next:", r$next_action, "\n")
  }
  cat("Partition and all 166 frozen evidence files: MATCH.\n")
  cat("Fold 1-4: SKIP; selection: REUSE CSV exports, never recompute.\n")
  cat("Input/checkpoint validation:", if (plan$data_checked && !plan$evidence_only) "CHECKED" else "NOT FULLY CHECKED", "\n")
  cat("Fold 5 safely fit-ready: NO (selection reusable; historical final profile unverified).\n", plan$blocker, "\n")
  cat("Outer-site CV: DISABLED. No pooled/final master completion is claimed.\n")
  invisible(plan)
}

# The following backend functions preserve v1 final-fit semantics as a CANDIDATE.
# They are definitions only. Their historical v2 equivalence is NOT established.
remove_zero_variance_names <- function(dat, variables) {
  variables <- intersect(variables, names(dat))
  keep <- vapply(
    variables,
    function(v) {
      z <- dat[[v]]
      z <- z[is.finite(z)]
      length(z) > 1L && length(unique(z)) > 1L
    },
    logical(1)
  )
  list(kept = variables[keep], removed = variables[!keep])
}

posterior_subset <- function(model, maximum_draws) {
  post <- poolMcmcChains(model$postList, start = 1L, thin = 1L)
  if (length(post) > maximum_draws) {
    keep <- unique(round(seq(1, length(post), length.out = maximum_draws)))
    post <- post[keep]
  }
  post
}

prepare_train_model <- function(variables, train_ids, seed) {
  set.seed(seed)
  variables <- unique(as.character(variables))
  train_ids <- complete_ids(variables, train_ids)
  if (length(train_ids) < 20L) stop("TRAIN-rivejä jäi alle 20.")

  md <- sample_metadata[match(train_ids, sample_metadata$sample_id), , drop = FALSE]
  x_raw <- X_sample[match(train_ids, X_sample$sample_id), c("sample_id", variables), drop = FALSE]

  zv <- remove_zero_variance_names(x_raw, variables)
  kept <- zv$kept

  if (length(kept) > 0L) {
    train_means <- vapply(x_raw[, kept, drop = FALSE], mean, numeric(1), na.rm = TRUE)
    train_sds <- vapply(x_raw[, kept, drop = FALSE], sd, numeric(1), na.rm = TRUE)
    valid_scale <- is.finite(train_sds) & train_sds > 0
    kept <- kept[valid_scale]
    train_means <- train_means[kept]
    train_sds <- train_sds[kept]
  } else {
    train_means <- numeric(0)
    train_sds <- numeric(0)
  }

  if (length(kept) > 0L) {
    x_scaled <- as.data.frame(lapply(kept, function(v) {
      (x_raw[[v]] - train_means[[v]]) / train_sds[[v]]
    }))
    names(x_scaled) <- kept
    x_formula <- reformulate(kept)
  } else {
    x_scaled <- data.frame(intercept_helper = rep(0, nrow(x_raw)))
    x_formula <- ~ 1
  }
  rownames(x_scaled) <- train_ids

  y_train <- Y_annual_all[train_ids, , drop = FALSE]
  loff_train <- Loff_annual_all[train_ids, , drop = FALSE]

  # IMPORTANT: studyDesign factors contain only levels observed in this TRAIN
  # subset. Hmsc::Hmsc() turns factor levels into integer Pi codes but sets np
  # from the observed unique codes. Carrying unused full-data factor levels can
  # therefore create non-contiguous Pi codes and fail computeInitialParameters.
  # Random-level objects still retain all metadata units, as recommended by Hmsc.
  study_design <- data.frame(
    site = factor(as.character(md$site)),
    year = factor(as.character(md$year))
  )
  rownames(study_design) <- train_ids

  ran_levels <- list(
    site = HmscRandomLevel(units = all_site_levels),
    year = HmscRandomLevel(units = all_year_levels)
  )

  model <- Hmsc(
    Y = y_train,
    distr = rep(hmsc_distribution, ncol(y_train)),
    Loff = loff_train,
    XData = x_scaled,
    XScale = FALSE,
    YScale = FALSE,
    XFormula = x_formula,
    studyDesign = study_design,
    ranLevels = ran_levels
  )

  # Defensive check for the exact failure observed in reconstruction r1.
  for (r in seq_len(model$nr)) {
    pi_r <- model$Pi[, r]
    if (anyNA(pi_r) || min(pi_r) < 1L || max(pi_r) > model$np[r] ||
        !identical(sort(unique(as.integer(pi_r))), seq_len(model$np[r]))) {
      stop("Unsafe Hmsc random-level Pi coding before MCMC.")
    }
  }

  list(
    model = model,
    variables = kept,
    means = train_means,
    sds = train_sds,
    train_ids = train_ids,
    ran_levels = ran_levels
  )
}

fit_train_model <- function(variables, train_ids, mcmc, seed) {
  prepared <- prepare_train_model(variables, train_ids, seed)
  model <- sampleMcmc(
    prepared$model,
    samples = mcmc$samples,
    transient = mcmc$transient,
    thin = mcmc$thin,
    nChains = mcmc$chains,
    nParallel = mcmc$parallel,
    verbose = 0
  )
  prepared$model <- model
  prepared
}

predict_new_data <- function(fit, test_ids, seed, evaluation, model_type) {
  variables <- fit$variables
  test_ids <- complete_ids(variables, test_ids)
  if (length(test_ids) == 0L) {
    return(data.frame())
  }

  md <- sample_metadata[match(test_ids, sample_metadata$sample_id), , drop = FALSE]
  x_raw <- X_sample[match(test_ids, X_sample$sample_id), c("sample_id", variables), drop = FALSE]

  if (length(variables) > 0L) {
    x_scaled <- as.data.frame(lapply(variables, function(v) {
      (x_raw[[v]] - fit$means[[v]]) / fit$sds[[v]]
    }))
    names(x_scaled) <- variables
  } else {
    x_scaled <- data.frame(intercept_helper = rep(0, nrow(x_raw)))
  }
  rownames(x_scaled) <- test_ids

  y_test <- Y_annual_all[test_ids, , drop = FALSE]
  loff_test <- Loff_annual_all[test_ids, , drop = FALSE]
  # As in TRAIN, use only observed factor levels in the supplied
  # prediction studyDesign. All potential units remain represented in
  # fit$ran_levels.
  study_design_test <- data.frame(
    site = factor(as.character(md$site)),
    year = factor(as.character(md$year))
  )
  rownames(study_design_test) <- test_ids

  post <- posterior_subset(fit$model, max_prediction_draws)
  set.seed(seed)
  pred_list <- predict(
    fit$model,
    post = post,
    XData = x_scaled,
    Loff = loff_test,
    studyDesign = study_design_test,
    ranLevels = fit$ran_levels,
    expected = FALSE,
    predictEtaMean = TRUE,
    nParallel = 1L
  )
  pred <- simplify2array(pred_list)

  expected_dim <- c(nrow(y_test), ncol(y_test), length(post))
  if (!identical(as.integer(dim(pred)), as.integer(expected_dim))) {
    stop(
      "TEST-ennusteen dimensiot eivät täsmää. Saatiin ",
      paste(dim(pred), collapse = "x"),
      ", odotettiin ", paste(expected_dim, collapse = "x")
    )
  }

  point <- apply(pred, c(1, 2), median, na.rm = TRUE)
  presence_probability <- 1 - apply(pred == 0, c(1, 2), mean, na.rm = TRUE)

  rows <- vector("list", ncol(y_test))
  for (j in seq_len(ncol(y_test))) {
    rows[[j]] <- data.frame(
      evaluation = evaluation,
      model_type = model_type,
      sample_id = test_ids,
      site = as.character(md$site),
      year = as.character(md$year),
      species = colnames(y_test)[j],
      observed = as.numeric(y_test[, j]),
      predicted_median = as.numeric(point[, j]),
      presence_probability = as.numeric(presence_probability[, j]),
      stringsAsFactors = FALSE
    )
  }

  do.call(rbind, rows)
}

recon_v1_backend <- function(inputs, profile) {
  e <- new.env(parent = environment(recon_v1_backend))
  for (n in names(inputs)) assign(n, inputs[[n]], envir = e)
  e$complete_ids <- function(variables, within_ids = inputs$base_ids) recon_complete_ids(inputs, variables, within_ids)
  e$all_site_levels <- sort(unique(as.character(inputs$sample_metadata$site)))
  e$all_year_levels <- sort(unique(as.character(inputs$sample_metadata$year)))
  e$hmsc_distribution <- "lognormal poisson"
  e$max_prediction_draws <- profile$max_prediction_draws
  for (n in c("Hmsc", "HmscRandomLevel", "sampleMcmc", "poolMcmcChains")) assign(n, getExportedValue("Hmsc", n), envir = e)
  e$predict <- stats::predict
  for (n in c("remove_zero_variance_names", "posterior_subset", "prepare_train_model", "fit_train_model", "predict_new_data")) {
    fun <- get(n); environment(fun) <- e; assign(n, fun, envir = e)
  }
  list(prepare = e$prepare_train_model, fit = e$fit_train_model, predict = e$predict_new_data)
}
recon_profile_gate <- function(profile) {
  required <- c(
    "execution_profile_verified", "profile_basis", "historical_v2_exact",
    "evidence_reference", "R_version", "Hmsc_version", "coda_version",
    "rng_kind", "mcmc", "max_prediction_draws", "random_level_units",
    "distribution", "annual_index_standard_days"
  )
  recon_assert(is.list(profile) && all(required %in% names(profile)),
               "Missing verified reconstructed final-profile contract: execution blocked.")
  recon_assert(
    isTRUE(profile$execution_profile_verified) &&
      identical(profile$profile_basis, "v1_source_plus_v2_outputs_plus_local_runtime") &&
      identical(profile$historical_v2_exact, FALSE),
    "Profile must be an explicitly verified reconstructed compatibility profile, not a claim of exact historical v2 identity."
  )
  recon_assert(nzchar(profile$evidence_reference) && file.exists(profile$evidence_reference),
               "Missing local evidence document for reconstructed final-profile compatibility.")
  recon_assert(profile$random_level_units == "all_metadata" &&
                 profile$max_prediction_draws == 1000L &&
                 profile$distribution == "lognormal poisson" &&
                 identical(as.integer(profile$annual_index_standard_days), 7L),
               "Profile differs from retained v1 backend; further reconstruction required.")
  expected_mcmc <- c(samples = 5000L, transient = 10000L, thin = 20L, chains = 4L, parallel = 4L)
  observed_mcmc <- unlist(profile$mcmc, use.names = TRUE)
  recon_assert(identical(names(observed_mcmc), names(expected_mcmc)) &&
                 identical(as.integer(observed_mcmc), as.integer(expected_mcmc)),
               "MCMC profile differs from retained v1 outer-final settings.")
  recon_assert(identical(profile$rng_kind, c("Mersenne-Twister", "Inversion", "Rejection")),
               "RNG profile differs from verified local compatibility runtime.")
  recon_assert(as.character(getRversion()) == profile$R_version,
               "R version does not match reconstructed compatibility profile.")
  recon_assert(requireNamespace("Hmsc", quietly = TRUE) &&
                 as.character(utils::packageVersion("Hmsc")) == profile$Hmsc_version,
               "Hmsc package version does not match reconstructed compatibility profile.")
  recon_assert(requireNamespace("coda", quietly = TRUE) &&
                 as.character(utils::packageVersion("coda")) == profile$coda_version,
               "coda package version does not match reconstructed compatibility profile.")
  invisible(TRUE)
}
recon_exclusive_publish <- function(staged_file, destination) {
  link <- Sys.readlink(destination)
  recon_assert(!file.exists(destination) && !dir.exists(destination) && (is.na(link) || !nzchar(link)), "Refusing destination overwrite.")
  recon_assert(file.link(staged_file, destination), "Exclusive hard-link publication failed; no overwrite attempted.")
  recon_assert(unname(tools::md5sum(staged_file)) == unname(tools::md5sum(destination)), "Published bytes differ.")
  invisible(destination)
}
recon_check_final_fit <- function(fit, variables, train_ids, inputs) {
  required <- c("model", "variables", "means", "sds", "train_ids", "ran_levels")
  recon_assert(is.list(fit) && all(required %in% names(fit)) && identical(fit$variables, variables) && identical(fit$train_ids, train_ids) && inherits(fit$model, "Hmsc"), "Incompatible final-fit checkpoint; refusing refit.")
  x <- inputs$X_sample[match(train_ids, inputs$base_ids), variables, drop = FALSE]
  means <- vapply(x, mean, numeric(1)); sds <- vapply(x, sd, numeric(1))
  recon_assert(isTRUE(all.equal(fit$means, means, tolerance = 1e-12)) && isTRUE(all.equal(fit$sds, sds, tolerance = 1e-12)), "Final-fit checkpoint TRAIN scaling mismatch.")
  recon_assert(is.list(fit$ran_levels) && setequal(names(fit$ran_levels), c("site", "year")) && length(fit$model$postList) > 0L, "Missing random-level/posterior checkpoint structure.")
  invisible(TRUE)
}
recon_resume_fold5 <- function(root, repository, primary_file, verified_profile = NULL, fold = 5L) {
  # NOT invoked by CLI; intentionally no runnable scientific command is documented.
  recon_assert(identical(as.integer(fold), 5L), "Refusing to run or overwrite completed folds 1-4.")
  root <- recon_root(root, execution = TRUE)
  inputs <- recon_load_inputs(primary_file)
  plan <- recon_inspect(root, repository, fold_only = fold, inputs = inputs)
  r <- plan$folds[["5"]]
  if (r$complete) return(invisible(list(status = "SKIP_IMMUTABLE_COMPLETE_FOLD", plan = plan)))
  recon_profile_gate(verified_profile) # Before fitting, output creation or RNG changes.
  fd <- file.path(root, "outer_year/fold_05")
  outputs <- file.path(fd, c("outer_test_predictions.csv2", "outer_test_metrics.csv2", "OUTER_FOLD_COMPLETE.rds"))
  recon_assert(!any(file.exists(outputs)), "Partial/final fold-5 outputs exist; no overwrite or automatic repair.")
  vars <- c(r$weather, r$environment)
  # Selected predictor lists are immutable; no post-hoc zero-variance removal allowed.
  x <- inputs$X_sample[match(r$ids$final_train, inputs$base_ids), vars, drop = FALSE]
  recon_assert(all(vapply(x, function(z) is.finite(sd(z)) && sd(z) > 0, logical(1))), "Selected final predictors do not vary on recorded TRAIN rows.")
  stage <- file.path(fd, "RECONSTRUCTED_r2")
  provenance <- list(producer = recon_version, evidence_commit = "3176b29093d3bf0cc97252604c23522d390a36e2",
    profile = verified_profile, primary_md5 = unname(tools::md5sum(primary_file)), weather = r$weather, environment = r$environment,
    train_ids = r$ids$final_train, test_ids = r$ids$final_test, partition = r$partition)
  if (dir.exists(stage)) {
    recon_path(root, "outer_year/fold_05/RECONSTRUCTED_r2")
    recon_assert(file.exists(file.path(stage, "PROVENANCE.rds")), "Missing recovery provenance/checkpoint: refusal.")
    recon_assert(identical(readRDS(file.path(stage, "PROVENANCE.rds")), provenance), "Recovery provenance/profile mismatch.")
  } else {
    recon_assert(dir.create(stage), "Could not exclusively create recovery staging directory.")
    saveRDS(provenance, file.path(stage, "PROVENANCE.rds"))
  }
  lock <- file.path(stage, "EXECUTION_LOCK")
  lock_source <- tempfile("lock-", tmpdir = stage)
  writeLines(paste(recon_version, Sys.getpid()), lock_source)
  recon_exclusive_publish(lock_source, lock)
  on.exit(unlink(c(lock, lock_source)), add = TRUE) # Own transient locks only, never results.
  old_rng <- RNGkind(); on.exit(do.call(RNGkind, as.list(old_rng)), add = TRUE)
  do.call(RNGkind, as.list(verified_profile$rng_kind))
  backend <- recon_v1_backend(inputs, verified_profile)
  predictions <- list()
  seed_base <- as.integer(20260818L %% 100000L + 5L * 10000000L)
  for (model_type in c("WEATHER_ONLY", "WEATHER_PLUS_ENVIRONMENT")) {
    v <- if (model_type == "WEATHER_ONLY") r$weather else vars
    seed <- seed_base + if (model_type == "WEATHER_ONLY") 30000000L else 40000000L
    checkpoint <- file.path(stage, paste0(model_type, "_FINAL_FIT.rds"))
    if (file.exists(checkpoint)) {
      recon_path(root, paste0("outer_year/fold_05/RECONSTRUCTED_r2/", basename(checkpoint)))
      fit <- readRDS(checkpoint)
      recon_check_final_fit(fit, v, r$ids$final_train, inputs)
    } else {
      fit <- backend$fit(v, r$ids$final_train, verified_profile$mcmc, seed)
      recon_check_final_fit(fit, v, r$ids$final_train, inputs)
      tmp <- tempfile("fit-", tmpdir = stage); saveRDS(fit, tmp)
      recon_exclusive_publish(tmp, checkpoint)
    }
    predictions[[model_type]] <- backend$predict(fit, r$ids$final_test, seed + 1L, "outer_year", model_type)
    rm(fit)
  }
  pred <- do.call(rbind, predictions); pred$outer_fold <- 5L; pred$scheme <- "year"
  metrics <- recon_metrics(pred)
  recon_validate_predictions(pred, metrics, r$partition, r$coverage, 5L)
  weather <- list(groups = recon_read_expected(repository)$folds[["5"]]$weather_groups, variables = r$weather)
  environment <- list(groups = recon_read_expected(repository)$folds[["5"]]$environment_groups, variables = r$environment)
  result <- list(scheme = "year", outer_fold = 5L, outer_train_ids = r$ids$outer_train, outer_test_ids = r$ids$outer_test,
                 final_train_ids = r$ids$final_train, final_test_ids = r$ids$final_test, coverage = r$coverage,
                 weather = weather, environment = environment, predictions = pred, metrics = metrics, reconstructed_provenance = provenance)
  selection_table <- function(values, column) {
    table <- data.frame(scheme = rep("year", length(values)), outer_fold = rep(5L, length(values)), stringsAsFactors = FALSE)
    table[[column]] <- values; table
  }
  result$selected_weather_groups <- selection_table(weather$groups, "group")
  result$selected_weather_variables <- selection_table(weather$variables, "variable")
  result$selected_environment_groups <- selection_table(environment$groups, "group")
  result$selected_environment_variables <- selection_table(environment$variables, "variable")
  staged <- file.path(stage, basename(outputs))
  recon_assert(!any(file.exists(staged)), "Staged exports already exist; no overwrite.")
  write.table(pred, staged[1], sep = ";", dec = ",", quote = TRUE, row.names = FALSE, na = "")
  write.table(metrics, staged[2], sep = ";", dec = ",", quote = TRUE, row.names = FALSE, na = "")
  saveRDS(result, staged[3])
  # Recheck immutable selections/coverage/checkpoints immediately before publication.
  recon_inspect(root, repository, inputs = inputs)
  for (i in seq_along(outputs)) recon_exclusive_publish(staged[i], outputs[i])
  invisible(result)
}
recon_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  allowed <- c("--dry-run", "--validate", "--evidence-only", "--check-data", "--output-root", "--repository", "--primary-data", "--fold")
  recon_assert(length(args) > 0L && any(args %in% c("--dry-run", "--validate")), "CLI accepts DRY-RUN/VALIDATION only. Scientific execution is disabled.")
  value <- function(flag, default) {
    i <- which(args == flag)
    recon_assert(length(i) <= 1L, paste("Duplicate option:", flag))
    if (!length(i)) return(default)
    recon_assert(i < length(args) && !startsWith(args[i + 1L], "--"), paste("Missing option value:", flag))
    args[i + 1L]
  }
  consumed <- rep(FALSE, length(args))
  for (i in seq_along(args)) {
    if (consumed[i]) next
    recon_assert(args[i] %in% allowed, paste("Unexpected option:", args[i]))
    consumed[i] <- TRUE
    if (args[i] %in% c("--output-root", "--repository", "--primary-data", "--fold")) {
      recon_assert(i < length(args), "Missing option value."); consumed[i + 1L] <- TRUE
    }
  }
  repository <- normalizePath(value("--repository", getwd()), winslash = "/", mustWork = TRUE)
  root <- value("--output-root", "E:/EIFFEL uusi/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2")
  fold <- as.integer(value("--fold", "5"))
  primary <- value("--primary-data", file.path(dirname(root), "HMSC_ANNUAL_PRIMARY_PREDICTIVE_LOGNORMAL_POISSON_BLOCKED_CV_v1/HMSC_annual_three_species_weather_environment_buffers_results.RData"))
  inputs <- if ("--check-data" %in% args) recon_load_inputs(primary) else NULL
  plan <- recon_inspect(root, repository, fold, evidence_only = "--evidence-only" %in% args, inputs = inputs)
  recon_print_plan(plan)
}
if (sys.nframe() == 0L) recon_main()
