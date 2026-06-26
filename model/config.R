# =============================================================================
# config.R  --  Central configuration for the WC2026 prediction system
# Sourced by every pipeline script. Edit paths / knobs here, not in the scripts.
# =============================================================================

# Project root: set WC2026_ROOT to override; otherwise use the current dir.
PROJECT_ROOT <- Sys.getenv("WC2026_ROOT", unset = normalizePath(getwd(), mustWork = FALSE))

CFG <- list(
  root = PROJECT_ROOT,

  # ---- Input directories ----------------------------------------------------
  dir_research   = file.path(PROJECT_ROOT, "input_data", "researched_info"),
  dir_historical = file.path(PROJECT_ROOT, "input_data", "historical_stats"),
  dir_wc2026     = file.path(PROJECT_ROOT, "input_data", "wc2026_outcomes"),

  # ---- Output directories ---------------------------------------------------
  dir_predictions = file.path(PROJECT_ROOT, "outcomes", "predictions"),
  dir_reports     = file.path(PROJECT_ROOT, "outcomes", "reports"),
  report_registry = file.path(PROJECT_ROOT, "outcomes", ".report_registry.csv"),

  # ---- Simulation settings --------------------------------------------------
  n_sims   = as.integer(Sys.getenv("WC2026_NSIMS", "10000")),  # Monte Carlo runs
  seed     = 2026L,

  # Stage order used throughout the system.
  stages = c("group", "R32", "R16", "QF", "SF", "third_place", "final"),

  # Pretty labels for reports.
  stage_labels = c(
    group       = "Group Stage",
    R32         = "Round of 32",
    R16         = "Round of 16",
    QF          = "Quarter-finals",
    SF          = "Semi-finals",
    third_place = "Third-place Play-off",
    final       = "Final"
  )
)

# Make sure output dirs exist.
for (d in c(CFG$dir_predictions, CFG$dir_reports)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}
