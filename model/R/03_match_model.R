# =============================================================================
# 03_match_model.R  --  Bivariate (Dixon-Coles) Poisson match model
# =============================================================================
# Given team strengths, produces:
#   * expected goals for each side
#   * the full discrete scoreline distribution (with low-score correction)
#   * 1X2 outcome probabilities and the single most-likely scoreline
#   * a knockout winner probability (regulation -> extra time -> penalties)
# =============================================================================

# Expected goals for a fixture. Host nations get the home bump in either slot.
expected_goals <- function(state, home, away) {
  st <- state$strength; g <- state$globals
  ih <- match(home, st$team); ia <- match(away, st$team)
  if (is.na(ih) || is.na(ia)) stop("Unknown team in fixture: ", home, " vs ", away)
  host_h <- as.integer(home %in% g$hosts)
  host_a <- as.integer(away %in% g$hosts)
  lam_h <- exp(g$c + st$attack[ih] - st$defense[ia] + g$home * host_h)
  lam_a <- exp(g$c + st$attack[ia] - st$defense[ih] + g$home * host_a)
  c(home = lam_h, away = lam_a)
}

# Dixon-Coles low-score correction factor.
.dc_tau <- function(i, j, lh, la, rho) {
  if (i == 0 && j == 0) return(1 - lh * la * rho)
  if (i == 0 && j == 1) return(1 + lh * rho)
  if (i == 1 && j == 0) return(1 + la * rho)
  if (i == 1 && j == 1) return(1 - rho)
  1
}

# Full scoreline probability matrix P[i+1, j+1] = P(home i, away j).
scoreline_matrix <- function(lam_h, lam_a, rho = 0, max_goals = 8) {
  gi <- 0:max_goals
  ph <- stats::dpois(gi, lam_h)
  pa <- stats::dpois(gi, lam_a)
  M  <- outer(ph, pa)                      # independent Poisson
  if (rho != 0) {                          # apply DC correction to the 2x2 corner
    for (i in 0:1) for (j in 0:1)
      M[i + 1, j + 1] <- M[i + 1, j + 1] * .dc_tau(i, j, lam_h, lam_a, rho)
  }
  M / sum(M)
}

# 1X2 + most-likely scoreline from a scoreline matrix.
outcome_from_matrix <- function(M) {
  idx <- which(M == max(M), arr.ind = TRUE)[1, ]
  list(
    p_home  = sum(M[lower.tri(M)]),                 # home goals > away goals
    p_draw  = sum(diag(M)),
    p_away  = sum(M[upper.tri(M)]),
    ml_home = idx[1] - 1,
    ml_away = idx[2] - 1,
    ml_prob = M[idx[1], idx[2]]
  )
}

# Expected-value-optimal scoreline under Scorito-style exact/toto scoring.
# Predicting (i, j) earns `w_exact` if it is exactly right, else `w_toto` if only
# the result bucket (home win / draw / away win) is right. Expected points are
#   EV(i, j) = w_toto * P(bucket of (i,j)) + (w_exact - w_toto) * P(score = (i,j))
# The toto term dominates (big bucket probabilities), so the maximiser is the
# likeliest score *within the likeliest bucket* -- never a draw when a win is
# favoured, which is exactly the trap the bare mode falls into. Scans the grid.
ev_optimal_score <- function(M, w_exact, w_toto) {
  p_home <- sum(M[lower.tri(M)]); p_draw <- sum(diag(M)); p_away <- sum(M[upper.tri(M)])
  ng <- nrow(M) - 1L
  best <- list(home = 0L, away = 0L, ev = -Inf, p_exact = 0, p_bucket = 0)
  for (i in 0:ng) for (j in 0:ng) {
    pb <- if (i > j) p_home else if (i == j) p_draw else p_away
    pe <- M[i + 1L, j + 1L]
    ev <- w_toto * pb + (w_exact - w_toto) * pe
    if (ev > best$ev + 1e-12)
      best <- list(home = i, away = j, ev = ev, p_exact = pe, p_bucket = pb)
  }
  best
}

# Convenience: outcome probabilities directly from team names.
match_probs <- function(state, home, away) {
  lam <- expected_goals(state, home, away)
  M <- scoreline_matrix(lam["home"], lam["away"], state$globals$rho,
                        as.integer(state$params$max_goals_grid))
  o <- outcome_from_matrix(M)
  o$home <- home; o$away <- away
  o$lam_home <- unname(lam["home"]); o$lam_away <- unname(lam["away"])
  o$M <- M                                   # full scoreline grid for EV picks
  o
}

# Probability `home` advances past `away` in a knockout tie.
# Regulation 1X2 -> if draw, extra time (reduced lambdas) -> if still level,
# penalties tilted slightly by strength.
knockout_win_prob <- function(state, home, away) {
  p <- match_probs(state, home, away)
  et_frac <- as.numeric(state$params$extra_time_goal_fraction)
  tilt    <- as.numeric(state$params$penalty_strength_tilt)
  lam <- expected_goals(state, home, away)

  # Extra-time mini-match probabilities (30 min ~ et_frac of a full match).
  Met <- scoreline_matrix(lam["home"] * et_frac, lam["away"] * et_frac,
                          state$globals$rho, as.integer(state$params$max_goals_grid))
  oet <- outcome_from_matrix(Met)

  # Penalty shootout: 0.5 tilted by relative strength.
  st <- state$strength
  sh <- st$s[match(home, st$team)]; sa <- st$s[match(away, st$team)]
  p_pen_home <- 0.5 + tilt * tanh((sh - sa) / 200)
  p_pen_home <- min(max(p_pen_home, 0.05), 0.95)

  p$p_home +
    p$p_draw * (oet$p_home + oet$p_draw * p_pen_home)
}
