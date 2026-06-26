#!/usr/bin/env Rscript
# =============================================================================
# run.R  --  Single entry point for all WC2026 pipeline runs
# =============================================================================
# Handles first runs and subsequent incremental runs identically.
#
# Usage:
#   Rscript run.R                    # auto-detect stage; fetch live data
#   Rscript run.R R16                # force a specific stage
#   Rscript run.R --no-fetch         # skip web fetch (offline / manual data)
#   Rscript run.R --clean            # wipe all outputs first; full clean run
#   WC2026_NSIMS=500 Rscript run.R   # fast smoke test
#
# Flags can be combined:
#   Rscript run.R --clean --no-fetch R16
#
# What happens on every run:
#   1. [Optional] Fetches live results from the web (cfg$fetch_url_results),
#      upserts them into results.csv, auto-advances tournament_state.json,
#      and confirms bracket ties that now have official results.
#   2. Merges any staged results_update.csv (by match_id) into results.csv,
#      then archives it.  Manual edits always override the web fetch.
#   3. Re-derives ratings from priors + all known results (idempotent).
#   4. Re-simulates group stage + knockout bracket + scorer forecasts.
#   5. Overwrites outcomes/ predictions and stage PDF (retaining report's
#      original creation date in outcomes/.report_registry.csv).
# =============================================================================

root <- Sys.getenv("WC2026_ROOT", unset = normalizePath(getwd(), mustWork = FALSE))
Sys.setenv(WC2026_ROOT = root)
source(file.path(root, "model", "config.R"))
rdir <- file.path(root, "model", "R")

source(file.path(rdir, "00_utils.R"))
source(file.path(rdir, "00b_fetch.R"))
for (f in sprintf("%02d_%s.R", 1:7,
                  c("load_data", "ratings", "match_model",
                    "simulate", "top_scorers", "recommendations", "report"))) {
  source(file.path(rdir, f))
}
set.seed(CFG$seed)

# ---- Parse arguments ---------------------------------------------------------
args      <- commandArgs(trailingOnly = TRUE)
do_fetch  <- !("--no-fetch" %in% args)
do_clean  <- "--clean" %in% args
args      <- args[!args %in% c("--no-fetch", "--clean")]
stage_arg <- if (length(args) >= 1) args[1] else NULL

log_msg("=== WC2026 Prediction Pipeline ===")

# ---- Step 0: Clean outputs if requested --------------------------------------
# Removes all generated files in outcomes/ so the run starts from scratch.
# Input data (input_data/) is never touched.
if (do_clean) {
  log_msg("[run] --clean: wiping outcomes/ ...")
  invisible(lapply(list.files(CFG$dir_predictions, full.names = TRUE), unlink))
  invisible(lapply(list.files(CFG$dir_reports,     full.names = TRUE), unlink))
  unlink(CFG$report_registry)
  log_msg("[run] outcomes/ cleared. Proceeding with fresh run.")
}

# ---- Step 1: Web fetch (updates results.csv, tournament_state.json, bracket) -
if (do_fetch) {
  fetch_live_data(CFG)
} else {
  log_msg("[run] Web fetch skipped (--no-fetch).")
}

# ---- Step 2: Merge staged results_update.csv if present ----------------------
results_path <- file.path(CFG$dir_wc2026, "results.csv")
update_path  <- file.path(CFG$dir_wc2026, "results_update.csv")
if (file.exists(update_path)) {
  base   <- read_csv_safe(results_path, required = FALSE)
  upd    <- read_csv_safe(update_path)
  merged <- upsert_by_key(base, upd, key = "match_id")
  merged <- merged[order(suppressWarnings(as.integer(
    gsub("[^0-9]", "", merged$match_id)))), ]
  write_csv_safe(merged, results_path)
  archive <- file.path(CFG$dir_wc2026,
                       paste0("results_update_applied_", Sys.Date(), ".csv"))
  file.rename(update_path, archive)
  log_msg(sprintf("[run] Merged %d row(s) from results_update.csv (archived).", nrow(upd)))
}

# ---- Step 3–5: Run the full pipeline -----------------------------------------
state <- load_state(CFG)
stage <- if (!is.null(stage_arg)) stage_arg else state$tournament_current_stage

state <- compute_ratings(state)
state <- simulate_groups(state)
state <- simulate_knockout(state)
state <- forecast_scorers(state)
state <- recommend(state)
generate_report(state, stage = stage)

log_msg(sprintf("=== Done. Stage: %s | Sims: %s | Report: outcomes/reports/ ===",
                stage, format(CFG$n_sims, big.mark = ",")))
