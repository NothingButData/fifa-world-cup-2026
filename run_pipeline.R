#!/usr/bin/env Rscript
# =============================================================================
# run_pipeline.R  --  Full WC2026 prediction run (initial / from scratch)
#
# Usage:
#   Rscript run_pipeline.R [stage]
#       stage (optional) overrides the stage read from tournament_state.json
#                        e.g. R32, R16, QF, SF, final
#
# Produces:
#   outcomes/predictions/*.csv   (progression, golden boot, match preds, ...)
#   outcomes/reports/WC2026_<stage>_report.pdf
# =============================================================================

root <- Sys.getenv("WC2026_ROOT", unset = normalizePath(getwd()))
Sys.setenv(WC2026_ROOT = root)
source(file.path(root, "model", "config.R"))
rdir <- file.path(root, "model", "R")
for (f in sprintf("%02d_%s.R",
                  0:7,
                  c("utils", "load_data", "ratings", "match_model",
                    "simulate", "top_scorers", "recommendations", "report"))) {
  source(file.path(rdir, f))
}

args  <- commandArgs(trailingOnly = TRUE)
set.seed(CFG$seed)

log_msg("=== WC2026 prediction pipeline (full run) ===")
state <- load_state(CFG)
stage <- if (length(args) >= 1) args[1] else state$tournament_current_stage

state <- compute_ratings(state)
state <- simulate_groups(state)
state <- simulate_knockout(state)
state <- forecast_scorers(state)
state <- recommend(state)
generate_report(state, stage = stage)

log_msg("=== Done. See outcomes/ for predictions and the PDF report. ===")
