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

recommend <- function(state) {
  log_msg("Building recommendations ...")
  br <- state$bracket
  prog <- state$progression

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
      src <- if ("source" %in% names(ms)) ms$source[i] else NA_character_
      filled_here <- (!is.null(state$r32_filled)) && (h %in% state$r32_filled || a %in% state$r32_filled)
      tie_status <- if (!is.na(src) && grepl("^reported", src) && !filled_here) "Confirmed" else "Projected"
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
