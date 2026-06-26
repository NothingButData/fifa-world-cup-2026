# =============================================================================
# 05_top_scorers.R  --  Player goal forecasts (per stage + Golden Boot)
# =============================================================================
# Logic:
#   team_xg  = expected goals a team scores in a generic knockout match
#   E[matches in stage S] = P(team participates in stage S)  (from the sim)
#   player share = goal_share_prior x form_multiplier x availability (research)
#   stage goals  = team_xg * P(play stage S) * player_share
#   projected total = current WC goals + sum of remaining-stage goals
# Produces a per-stage top-scorer table AND an overall Golden Boot projection.
# =============================================================================

forecast_scorers <- function(state) {
  log_msg("Forecasting top scorers ...")
  st <- state$strength
  g  <- state$globals
  prog <- state$progression
  rownames(prog) <- prog$team

  mean_def <- mean(st$defense)
  team_xg <- stats::setNames(
    exp(g$c + st$attack - mean_def + g$home * as.integer(st$team %in% g$hosts)),
    st$team)

  pl <- state$players
  padj <- state$player_adj

  fmult <- rep(1, nrow(pl)); avail <- rep(1, nrow(pl))
  if (!is.null(padj) && nrow(padj) > 0) {
    m <- match(pl$player, padj$player)
    fmult <- ifelse(is.na(m), 1, padj$form_multiplier[m]); fmult[is.na(fmult)] <- 1
    avail <- ifelse(is.na(m), 1, padj$availability[m]);    avail[is.na(avail)] <- 1
  }
  pl$share <- pmin(pl$goal_share_prior * fmult * avail, 0.9)
  pl$current <- ifelse(is.na(pl$current_wc_goals), 0, pl$current_wc_goals)

  # Stage participation probabilities per team (third place = SF losers).
  sp <- function(team, col) if (team %in% rownames(prog)) prog[team, col] else 0
  stage_cols <- c(R32 = "reach_R32", R16 = "reach_R16", QF = "reach_QF",
                  SF = "reach_SF", final = "reach_final")

  remaining_stages <- c("R32", "R16", "QF", "SF", "final", "third_place")
  stage_goals <- matrix(0, nrow(pl), length(remaining_stages),
                        dimnames = list(NULL, remaining_stages))
  # Fixture-aware expected goals from the knockout simulation: each cell is
  # E[goals in that stage] already marginalised over P(team reaches that stage)
  # and the actual strength of the opponents they faced. Falls back to the
  # flat average-opponent formula if the matrix isn't available.
  egs <- state$exp_goals_by_stage

  for (i in seq_len(nrow(pl))) {
    t <- pl$team[i]
    if (!is.null(egs) && t %in% rownames(egs)) {
      for (s in remaining_stages)
        if (s %in% colnames(egs)) stage_goals[i, s] <- egs[t, s] * pl$share[i]
    } else {
      txg <- if (t %in% names(team_xg)) team_xg[[t]] else 0
      pf_reach_sf    <- sp(t, "reach_SF")
      pf_reach_final <- sp(t, "reach_final")
      pp <- c(
        R32         = sp(t, "reach_R32"),
        R16         = sp(t, "reach_R16"),
        QF          = sp(t, "reach_QF"),
        SF          = sp(t, "reach_SF"),
        final       = pf_reach_final,
        third_place = max(pf_reach_sf - pf_reach_final, 0)
      )
      stage_goals[i, ] <- txg * pp * pl$share[i]
    }
  }

  pl$exp_remaining <- rowSums(stage_goals)
  pl$proj_total    <- pl$current + pl$exp_remaining

  scorer_projection <- pl[order(-pl$proj_total),
                          c("player", "team", "position", "current",
                            "exp_remaining", "proj_total")]
  scorer_projection$exp_remaining <- round(scorer_projection$exp_remaining, 2)
  scorer_projection$proj_total    <- round(scorer_projection$proj_total, 2)
  rownames(scorer_projection) <- NULL

  # Per-stage top scorers: expected goals scored *in that stage*.
  stage_top <- lapply(remaining_stages, function(s) {
    d <- data.frame(player = pl$player, team = pl$team,
                    exp_goals = round(stage_goals[, s], 3),
                    stringsAsFactors = FALSE)
    d <- d[order(-d$exp_goals), ]
    head(d[d$exp_goals > 0, ], 10)
  })
  names(stage_top) <- remaining_stages

  state$scorer_projection <- scorer_projection
  state$stage_top_scorers <- stage_top
  state
}
