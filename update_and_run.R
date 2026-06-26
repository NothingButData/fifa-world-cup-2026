#!/usr/bin/env Rscript
# =============================================================================
# update_and_run.R  --  Incremental refresh + re-run (use this during the cup)
#
# What it does (without rebuilding inputs from scratch):
#   1. If input_data/wc2026_outcomes/results_update.csv exists, UPSERTS those
#      rows into results.csv by match_id (new/updated scores merged, others
#      kept), then archives the staging file.
#   2. Re-derives ratings from priors + ALL known results (idempotent), re-runs
#      the simulations and forecasts, and OVERWRITES predictions + the stage
#      report -- while the report's original creation date is RETAINED via
#      outcomes/.report_registry.csv.
#
# Typical tournament workflow:
#   - Edit input_data/wc2026_outcomes/{results.csv, knockout_bracket.csv,
#     top_scorers.csv} (or drop a results_update.csv) and the researched_info/*
#     CSVs with the latest news.
#   - Set "current_stage" in tournament_state.json to the stage you're predicting.
#   - Rscript update_and_run.R
# =============================================================================

root <- Sys.getenv("WC2026_ROOT", unset = normalizePath(getwd()))
Sys.setenv(WC2026_ROOT = root)
source(file.path(root, "model", "config.R"))
rdir <- file.path(root, "model", "R")
for (f in sprintf("%02d_%s.R", 0:7,
                  c("utils", "load_data", "ratings", "match_model",
                    "simulate", "top_scorers", "recommendations", "report"))) {
  source(file.path(rdir, f))
}
set.seed(CFG$seed)

log_msg("=== WC2026 incremental update + re-run ===")

# ---- 1. Merge staged result updates --------------------------------------
results_path <- file.path(CFG$dir_wc2026, "results.csv")
update_path  <- file.path(CFG$dir_wc2026, "results_update.csv")
if (file.exists(update_path)) {
  base <- read_csv_safe(results_path, required = FALSE)
  upd  <- read_csv_safe(update_path)
  merged <- upsert_by_key(base, upd, key = "match_id")
  merged <- merged[order(suppressWarnings(as.integer(merged$match_id))), ]
  write_csv_safe(merged, results_path)
  archive <- file.path(CFG$dir_wc2026,
                       paste0("results_update_applied_", Sys.Date(), ".csv"))
  file.rename(update_path, archive)
  log_msg(sprintf("Merged %d updated rows into results.csv (archived staging file).",
                  nrow(upd)))
} else {
  log_msg("No results_update.csv staged; using current results.csv as-is.")
}

# ---- 2. Re-run everything -------------------------------------------------
args  <- commandArgs(trailingOnly = TRUE)
state <- load_state(CFG)
stage <- if (length(args) >= 1) args[1] else state$tournament_current_stage

state <- compute_ratings(state)
state <- simulate_groups(state)
state <- simulate_knockout(state)
state <- forecast_scorers(state)
state <- recommend(state)
generate_report(state, stage = stage)

log_msg("=== Update complete. Predictions and report refreshed for stage: ", stage, " ===")
