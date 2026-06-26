# CLAUDE.md — guidance for AI coding sessions

## What this is
A base-R prediction system for the FIFA World Cup 2026 Scorito-style game.
Forecasts match outcomes, scorelines, tournament progression, and top scorers;
emits one dated PDF report per stage. See `README.md` for the full picture.

## Hard constraints (do not break)
- **Base R only.** No CRAN installs — the target environment cannot reach CRAN.
  Use `stats`, `MASS`, `grDevices`, `graphics`, base utils. No tidyverse,
  rmarkdown, knitr, jsonlite, ggplot2.
- **PDF reports use the base `pdf()` device** (`model/R/07_report.R`). No
  pandoc/LaTeX is available.
- The pipeline must run with `Rscript run_pipeline.R` from the project root.

## Pipeline shape
`config.R` → `00_utils` → `01_load_data` (→ `state` list) → `02_ratings` →
`03_match_model` → `04_simulate` → `05_top_scorers` → `06_recommendations` →
`07_report`. Each `0X_*.R` defines functions that take/return `state`.

## Data is CSV-driven and append/upsert-friendly
- Live state in `input_data/wc2026_outcomes/`; model inputs in
  `historical_stats/`; research in `researched_info/`.
- Team names are canonicalised via `canon_team()` in `00_utils.R` — extend the
  `fixes` map there if a new spelling appears, so joins keep working.
- `results.csv` is upserted by `match_id`; staged `results_update.csv` is merged
  by `update_and_run.R` then archived.

## Incremental-update contract
- Ratings are **idempotent**: always derived from priors + all known results, so
  re-running never compounds. Shrinkage `n/(n+K)` + ridge penalty toward priors.
- Reports **overwrite** but the first-created date is preserved in
  `outcomes/.report_registry.csv`; the run date is shown alongside.

## Conventions
- Keep changes auditable: a research note only affects predictions if it’s
  encoded as a row in `team_adjustments.csv` / `player_adjustments.csv`.
- Preserve the `source` column convention (verified vs projected/illustrative).
- Tunable knobs live in `historical_params.csv` and `model/config.R`.

## Quick test
`WC2026_NSIMS=500 Rscript run_pipeline.R` (fast smoke test), then inspect
`outcomes/predictions/*.csv` and render the PDF with
`pdftoppm -png outcomes/reports/WC2026_*.pdf /tmp/p` to eyeball layout.
