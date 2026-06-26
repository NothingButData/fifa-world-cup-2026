# =============================================================================
# 01_load_data.R  --  Load all inputs into a single `state` list
# =============================================================================
# Reads from the three input_data sub-folders and returns a list the rest of
# the pipeline consumes. All team names are canonicalised on the way in.
#
# OPTIONAL LIVE IMPORT (when run with internet access):
#   The system is CSV-driven so any source can be wired in. Convenient feeds:
#     - football-data.co.uk        (historical results CSVs)
#     - fixturedownload.com        (WC2026 fixtures CSV/JSON)
#     - your own scraper of fifa.com standings
#   Drop the resulting tidy CSVs into the matching input_data folders using the
#   schemas documented in README.md, then re-run. No code change required.
# =============================================================================

load_state <- function(cfg = CFG) {
  log_msg("Loading inputs ...")

  # --- historical_stats ------------------------------------------------------
  ratings <- read_csv_safe(file.path(cfg$dir_historical, "team_ratings_seed.csv"))
  ratings$team <- canon_team(ratings$team)

  params_df <- read_csv_safe(file.path(cfg$dir_historical, "historical_params.csv"))
  params <- params_to_list(params_df)

  players <- read_csv_safe(file.path(cfg$dir_historical, "player_pool.csv"))
  players$team <- canon_team(players$team)

  # --- researched_info -------------------------------------------------------
  team_adj   <- read_csv_safe(file.path(cfg$dir_research, "team_adjustments.csv"),   required = FALSE)
  if (!is.null(team_adj))   team_adj$team   <- canon_team(team_adj$team)
  player_adj <- read_csv_safe(file.path(cfg$dir_research, "player_adjustments.csv"), required = FALSE)
  if (!is.null(player_adj)) player_adj$team <- canon_team(player_adj$team)

  # --- wc2026_outcomes -------------------------------------------------------
  groups <- read_csv_safe(file.path(cfg$dir_wc2026, "groups.csv"))
  groups$team <- canon_team(groups$team)

  results <- read_csv_safe(file.path(cfg$dir_wc2026, "results.csv"), required = FALSE)
  if (!is.null(results) && nrow(results) > 0) {
    results$home_team <- canon_team(results$home_team)
    results$away_team <- canon_team(results$away_team)
  }

  bracket <- read_csv_safe(file.path(cfg$dir_wc2026, "knockout_bracket.csv"), required = FALSE)
  if (!is.null(bracket)) {
    bracket$home_team <- canon_team(bracket$home_team)
    bracket$away_team <- canon_team(bracket$away_team)
  }

  top_scorers <- read_csv_safe(file.path(cfg$dir_wc2026, "top_scorers.csv"), required = FALSE)
  if (!is.null(top_scorers)) top_scorers$team <- canon_team(top_scorers$team)

  # tournament_state.json -- tiny string-value extractor (no jsonlite dependency)
  state_json_path <- file.path(cfg$dir_wc2026, "tournament_state.json")
  current_stage <- "R32"; as_of_date <- as.character(Sys.Date())
  if (file.exists(state_json_path)) {
    txt <- paste(readLines(state_json_path, warn = FALSE), collapse = " ")
    grab <- function(key) {
      m <- regmatches(txt, regexpr(paste0('"', key, '"\\s*:\\s*"[^"]*"'), txt))
      if (length(m)) sub(paste0('.*"', key, '"\\s*:\\s*"([^"]*)".*'), "\\1", m) else NA
    }
    cs <- grab("current_stage"); if (!is.na(cs)) current_stage <- cs
    ad <- grab("as_of_date");    if (!is.na(ad)) as_of_date <- ad
  }

  # --- validation ------------------------------------------------------------
  if (nrow(ratings) != 48L)
    log_msg("WARNING: expected 48 teams in ratings, found ", nrow(ratings))
  miss <- setdiff(groups$team, ratings$team)
  if (length(miss)) stop("Teams in groups.csv missing from ratings: ", paste(miss, collapse = ", "))

  # Restrict players to teams actually in the tournament.
  players <- players[players$team %in% ratings$team, , drop = FALSE]

  state <- list(
    cfg         = cfg,
    params      = params,
    ratings     = ratings,
    players     = players,
    team_adj    = team_adj,
    player_adj  = player_adj,
    groups      = groups,
    results     = results,
    bracket     = bracket,
    top_scorers = top_scorers,
    tournament_current_stage = current_stage,
    as_of_date  = as_of_date,
    run_date    = Sys.Date()
  )
  log_msg(sprintf("Loaded %d teams, %d players, %d played results.",
                  nrow(ratings), nrow(players),
                  if (is.null(results)) 0 else sum(results$status %in% "final", na.rm = TRUE)))
  state
}
