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

  # ---- Web-fetch settings (edit these to point at your preferred source) ----
  fetch_enabled      = TRUE,
  # fixturedownload.com provides a clean CSV for WC2026 fixtures + results.
  # Set to "" or fetch_enabled=FALSE to run fully offline.
  fetch_url_results  = "https://fixturedownload.com/download/csv/fifa-world-cup-2026",
  fetch_timeout      = 30L,   # seconds before giving up on the download

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
  ),

  # ---- Scorito scoring (WK 2026) -------------------------------------------
  # The point values the picks are optimised against. Turning probabilities into
  # EV-optimal selections requires the *scoring*, not just the most-likely
  # outcome. Sources: Scorito's published rules (blog.scorito.com) cross-checked
  # against pouletips.nl / squawka.
  #   CONFIRMED: match exact/toto per round, 25 pts/correct group position,
  #              250-pt champion bonus, and the group & final top-scorer values.
  #   ASSUMED (re-verify before locking picks): the per-goal top-scorer "base"
  #              for R32/R16/QF/SF is interpolated proportionally (group 8 ->
  #              final 48), and the third_place row mirrors SF.
  # A goal is worth base[stage] * pos_mult[position]; a defender/keeper goal is
  # therefore 4x an attacker's.
  scorito = list(
    # Match prediction: exact score vs correct toto (winner/draw), by stage.
    match_exact = c(group = 45, R32 = 90, R16 = 135, QF = 180, SF = 225,
                    third_place = 225, final = 270),
    match_toto  = c(group = 30, R32 = 60, R16 =  90, QF = 120, SF = 150,
                    third_place = 150, final = 180),
    standings_per_position = 25,   # max 100 / group (4 positions)
    champion_bonus         = 250,
    # Per-goal top-scorer points = base[stage] * pos_mult[position].
    topscorer_base     = c(group = 8, R32 = 16, R16 = 24, QF = 32, SF = 40,
                           third_place = 40, final = 48),
    topscorer_pos_mult = c(FW = 1, MF = 2, DF = 4, GK = 4)
  )
)

# Make sure output dirs exist.
for (d in c(CFG$dir_predictions, CFG$dir_reports)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}
