# =============================================================================
# 06_recommendations.R  --  Turn model output into game picks
# =============================================================================
# Produces the selections a Scorito-style player makes:
#   * next-stage match predictions (winner / 90-min result / likeliest score)
#   * progression picks (who to back to each stage; champion & finalists)
#   * top-scorer picks (per stage + overall Golden Boot)
#   * a short strategy note (favourites vs. differentiators)
# Exact league scoring varies, so picks are ranked by probability/expected
# value; tune `points` weights below to match your pool's rules.
# =============================================================================

# Teams whose group placement is mathematically LOCKED by played results.
# A knockout matchup is only "Confirmed" when both its participants come from
# here -- never from a hand-edited `source` string, which can be stale or wrong.
#   * 1st / 2nd of a group are locked once that group is fully played (6/6).
#   * 3rd-place qualifiers are only locked once EVERY group is complete (the
#     8-best-thirds pool can't be ranked until then).
confirmed_advancer_set <- function(state) {
  res <- state$results; groups <- state$groups
  if (is.null(res) || nrow(res) == 0 || is.null(groups)) return(character(0))
  fin <- res[which(res$status == "final" & res$stage == "group"), , drop = FALSE]
  fin <- fin[!is.na(fin$home_goals) & !is.na(fin$away_goals), , drop = FALSE]
  if (nrow(fin) == 0) return(character(0))

  teams_by_group <- split(groups$team, groups$group)
  played_per_grp <- vapply(names(teams_by_group),
                           function(g) sum(fin$group == g), integer(1))
  complete <- names(teams_by_group)[played_per_grp >= 6]   # 4 teams -> 6 matches
  if (length(complete) == 0) return(character(0))

  st <- compute_standings(
    data.frame(group = fin$group, home_team = fin$home_team, away_team = fin$away_team,
               home_goals = fin$home_goals, away_goals = fin$away_goals,
               stringsAsFactors = FALSE),
    teams_by_group[complete], state$strength)

  confirmed <- st$team[st$pos %in% c(1L, 2L)]               # group winners + runners-up
  if (length(complete) == length(teams_by_group)) {         # all groups done -> thirds lock
    thirds <- st[st$pos == 3L, , drop = FALSE]
    ord3   <- thirds[order(-thirds$pts, -thirds$gd, -thirds$gf), ]
    confirmed <- c(confirmed, utils::head(ord3$team, 8))
  }
  unique(confirmed)
}

recommend <- function(state) {
  log_msg("Building recommendations ...")
  br <- state$bracket
  prog <- state$progression
  conf_set <- confirmed_advancer_set(state)

  # ---- Next-stage match predictions (known matchups) ----------------------
  next_stage <- state$cfg$stages[match(state$tournament_current_stage, state$cfg$stages)]
  if (is.na(next_stage)) next_stage <- "R32"
  ms <- br[br$stage == next_stage & !is.na(br$home_team) & br$home_team != "", ]
  preds <- NULL
  if (nrow(ms) > 0) {
    rows <- lapply(seq_len(nrow(ms)), function(i) {
      h <- ms$home_team[i]; a <- ms$away_team[i]
      p <- match_probs(state, h, a)
      adv_h <- knockout_win_prob(state, h, a)
      res <- c("Home win", "Draw", "Away win")[which.max(c(p$p_home, p$p_draw, p$p_away))]
      # Confirmed only when BOTH participants are locked by played group results.
      # The `source` column is provenance metadata, not proof -- a hand-edited
      # "reported_*" tag on an unplayed group must not show as Confirmed.
      tie_status <- if (h %in% conf_set && a %in% conf_set) "Confirmed" else "Projected"
      data.frame(
        match_id = ms$match_id[i], stage = next_stage,
        home = h, away = a,
        tie_status = tie_status,
        advancer = if (adv_h >= .5) h else a,
        p_advance = round(max(adv_h, 1 - adv_h), 3),
        reg_result = res,
        p_reg = round(max(p$p_home, p$p_draw, p$p_away), 3),
        score = sprintf("%d-%d", p$ml_home, p$ml_away),
        p_score = round(p$ml_prob, 3),
        stringsAsFactors = FALSE)
    })
    preds <- do.call(rbind, rows)
  }

  # ---- Progression picks ---------------------------------------------------
  safe_pick <- function(col, k = 8) {
    d <- prog[order(-prog[[col]]), c("team", col)]
    head(d, k)
  }
  prog_picks <- list(
    champion        = head(prog[order(-prog$champion), c("team", "champion")], 5),
    finalists       = head(prog[order(-prog$reach_final), c("team", "reach_final")], 6),
    semifinalists   = safe_pick("reach_SF", 6),
    quarterfinalists= safe_pick("reach_QF", 8),
    reach_R16       = safe_pick("reach_R16", 16)
  )

  # ---- Top-scorer picks ----------------------------------------------------
  scorer_picks <- list(
    golden_boot = head(state$scorer_projection, 8),
    per_stage   = lapply(state$stage_top_scorers, function(d) head(d, 3))
  )

  # ---- Strategy note -------------------------------------------------------
  champ <- prog_picks$champion$team[1]
  champ_p <- prog_picks$champion$champion[1]
  note <- paste0(
    "Back clear favourites where the model is confident (>60% advance) to bank ",
    "safe points; differentiate on tighter ties and on the Golden Boot, where a ",
    "well-placed contender on a deep team can outscore the favourite. ",
    "Model's title pick: ", champ, " (", pct(champ_p, 1), ").")

  state$recommendations <- list(
    next_stage        = next_stage,
    match_predictions = preds,
    progression_picks = prog_picks,
    scorer_picks      = scorer_picks,
    strategy_note     = note
  )
  state
}
