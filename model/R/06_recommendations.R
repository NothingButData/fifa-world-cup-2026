# =============================================================================
# 06_recommendations.R  --  Turn model output into game picks
# =============================================================================
# Produces the selections a Scorito-style player makes:
#   * next-stage match predictions (winner / 90-min result / EV-optimal score)
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
  # The stage whose ties are upcoming is the current stage itself; fall back to
  # R32 if the state file names something not in our stage list.
  cur_stage  <- state$tournament_current_stage
  next_stage <- if (cur_stage %in% state$cfg$stages) cur_stage else "R32"
  ms <- br[br$stage == next_stage & !is.na(br$home_team) & br$home_team != "", ]
  preds <- NULL
  if (nrow(ms) > 0) {
    # Scorito match points for this round (fall back to pure most-likely score
    # if the round isn't in the scoring table -> w_toto = 0 reduces EV to mode).
    sc <- state$cfg$scorito
    w_exact <- if (next_stage %in% names(sc$match_exact)) sc$match_exact[[next_stage]] else 1
    w_toto  <- if (next_stage %in% names(sc$match_toto))  sc$match_toto[[next_stage]]  else 0
    rows <- lapply(seq_len(nrow(ms)), function(i) {
      h <- ms$home_team[i]; a <- ms$away_team[i]
      p <- match_probs(state, h, a)
      adv_h <- knockout_win_prob(state, h, a)
      res <- c("Home win", "Draw", "Away win")[which.max(c(p$p_home, p$p_draw, p$p_away))]
      # EV-optimal scoreline to submit on Scorito (maximises expected match
      # points), rather than the bare modal score which clusters on 1-1.
      ev <- ev_optimal_score(p$M, w_exact, w_toto)
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
        score = sprintf("%d-%d", ev$home, ev$away),
        p_score = round(ev$p_exact, 3),
        ev_points = round(ev$ev, 1),
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
    champion        = safe_pick("champion", 5),
    finalists       = safe_pick("reach_final", 6),
    semifinalists   = safe_pick("reach_SF", 6),
    quarterfinalists= safe_pick("reach_QF", 8),
    reach_R16       = safe_pick("reach_R16", 16)
  )

  # ---- Top-scorer picks ----------------------------------------------------
  scorer_picks <- list(
    golden_boot = head(state$scorer_projection, 8),                 # most goals
    scorito     = head(state$scorito_scorers, 8),                   # most Scorito pts
    per_stage   = lapply(state$stage_top_scorers, function(d) head(d, 3))
  )

  # ---- Strategy note -------------------------------------------------------
  champ <- prog_picks$champion$team[1]
  champ_p <- prog_picks$champion$champion[1]
  sc_top <- if (!is.null(scorer_picks$scorito) && nrow(scorer_picks$scorito) > 0)
              scorer_picks$scorito$player[1] else NA
  gb_top <- if (!is.null(scorer_picks$golden_boot) && nrow(scorer_picks$golden_boot) > 0)
              scorer_picks$golden_boot$player[1] else NA
  note <- paste0(
    "Submit the EV-optimal score per tie (max expected Scorito points), not the ",
    "bare most-likely score -- the toto term dominates, so never pick a draw when ",
    "a win is favoured. For top scorers, pick by Scorito value (goals x position x ",
    "stage: a defender/keeper goal pays 4x a forward's), not raw goals",
    if (!is.na(sc_top) && !is.na(gb_top) && sc_top != gb_top)
      paste0(" -- e.g. Scorito favours ", sc_top, " over Golden-Boot lead ", gb_top) else "",
    ". Model's title pick: ", champ, " (", pct(champ_p, 1), ", worth 250 bonus pts).")

  state$recommendations <- list(
    next_stage        = next_stage,
    match_predictions = preds,
    progression_picks = prog_picks,
    scorer_picks      = scorer_picks,
    strategy_note     = note
  )
  state
}
