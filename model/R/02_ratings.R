# =============================================================================
# 02_ratings.R  --  Team strength -> attack/defense log-goal effects
# =============================================================================
# Pipeline:
#   1. Start from Elo priors (team_ratings_seed.csv).
#   2. Apply researched team adjustments (symmetric elo_adjustment + form, then
#      asymmetric attack_adjustment / defense_adjustment for lopsided sides).
#   3. Derive prior attack/defense effects (both scale with centered Elo).
#   4. If enough match results exist, refine attack/defense with a
#      ridge-penalised Poisson fit that SHRINKS toward the priors -- so early
#      in the tournament you mostly trust priors, and the data takes over as
#      games accumulate (weight ~ n/(n+K)).
# Output: state$strength (per-team effects) and state$globals (c, home, rho).
# =============================================================================

compute_ratings <- function(state) {
  log_msg("Computing team ratings ...")
  p   <- state$params
  rt  <- state$ratings
  adj <- state$team_adj

  scale  <- as.numeric(p$elo_to_loggoals_scale)
  c0     <- log(as.numeric(p$base_goals_per_team))
  home0  <- as.numeric(p$home_advantage_loggoals)
  lambda <- as.numeric(p$penalty_lambda)
  Kshrink<- as.numeric(p$shrinkage_k)
  hosts  <- trimws(strsplit(as.character(p$host_teams), ";")[[1]])
  hosts  <- canon_team(hosts)

  # --- 1-2: research-adjusted Elo -------------------------------------------
  rt$elo_adj <- rt$elo_prior
  if (!is.null(adj) && nrow(adj) > 0) {
    m <- match(rt$team, adj$team)
    add <- ifelse(is.na(m), 0, adj$elo_adjustment[m])
    add[is.na(add)] <- 0
    rt$elo_adj <- rt$elo_prior + add
  }

  # --- 3: centered-Elo strength & prior effects ------------------------------
  mean_elo <- mean(rt$elo_adj)
  rt$s          <- rt$elo_adj - mean_elo
  rt$att_prior  <- scale * rt$s
  rt$def_prior  <- scale * rt$s   # stronger team => more attack AND meaner defense

  teams <- rt$team
  n <- length(teams)
  att <- stats::setNames(rt$att_prior, teams)
  def <- stats::setNames(rt$def_prior, teams)

  # Apply form_multiplier: log-additive on both attack and defense effects.
  # fm > 1 -> more attack AND tighter defense (in-form); fm < 1 -> the reverse.
  # Also updates the ridge penalty targets so the Poisson fit shrinks toward
  # the form-adjusted priors, not the raw Elo priors.
  if (!is.null(adj) && "form_multiplier" %in% names(adj) && nrow(adj) > 0) {
    m2  <- match(teams, adj$team)
    fm  <- ifelse(!is.na(m2), suppressWarnings(as.numeric(adj$form_multiplier[m2])), 1.0)
    fm[is.na(fm) | fm <= 0] <- 1.0
    lf  <- stats::setNames(log(fm), teams)
    att <- att + lf
    def <- def + lf
    rt$att_prior <- unname(att)   # ridge target = form-adjusted prior
    rt$def_prior <- unname(def)
  }

  # Asymmetric attack/defense research adjustments (Elo-equivalent points). The
  # symmetric elo_adjustment and form_multiplier move attack AND defense together,
  # so neither can express "great going forward, shaky at the back" (or a strong
  # GK/back line on a low-ceiling side). These columns add an asymmetric term on
  # top: +attack_adjustment => scores more; +defense_adjustment => concedes fewer
  # (better defence/keeper). Scaled by elo_to_loggoals_scale like elo_adjustment,
  # and folded into the ridge targets so the Poisson fit shrinks toward them.
  if (!is.null(adj) && nrow(adj) > 0) {
    m3   <- match(teams, adj$team)
    aadj <- if ("attack_adjustment"  %in% names(adj))
              ifelse(!is.na(m3), suppressWarnings(as.numeric(adj$attack_adjustment[m3])),  0) else 0
    dadj <- if ("defense_adjustment" %in% names(adj))
              ifelse(!is.na(m3), suppressWarnings(as.numeric(adj$defense_adjustment[m3])), 0) else 0
    aadj[is.na(aadj)] <- 0; dadj[is.na(dadj)] <- 0
    att <- att + scale * aadj
    def <- def + scale * dadj
    rt$att_prior <- unname(att)
    rt$def_prior <- unname(def)
  }

  globals <- list(c = c0, home = home0, rho = as.numeric(p$dixon_coles_rho), hosts = hosts)

  # --- 4: penalised Poisson refinement from results --------------------------
  res <- state$results
  played <- if (is.null(res)) NULL else res[which(res$status == "final"), , drop = FALSE]
  played <- played[!is.na(played$home_goals) & !is.na(played$away_goals), , drop = FALSE]

  if (!is.null(played) && nrow(played) >= 10) {
    log_msg(sprintf("  Refining ratings from %d played matches (ridge -> priors).", nrow(played)))
    idx <- stats::setNames(seq_len(n), teams)
    hi  <- idx[played$home_team]; ai <- idx[played$away_team]
    ok  <- !is.na(hi) & !is.na(ai)
    hi <- hi[ok]; ai <- ai[ok]
    gh <- as.numeric(played$home_goals)[ok]; ga <- as.numeric(played$away_goals)[ok]
    host_home <- as.integer(played$home_team[ok] %in% hosts)

    att0 <- rt$att_prior; def0 <- rt$def_prior

    nll <- function(theta) {
      a <- theta[1:n]; d <- theta[(n + 1):(2 * n)]
      cc <- theta[2 * n + 1]; hh <- theta[2 * n + 2]
      lam_h <- exp(cc + hh * host_home + a[hi] - d[ai])
      lam_a <- exp(cc           + a[ai] - d[hi])
      ll <- sum(stats::dpois(gh, lam_h, log = TRUE)) +
            sum(stats::dpois(ga, lam_a, log = TRUE))
      pen <- lambda * (sum((a - att0)^2) + sum((d - def0)^2)) +
             10 * ((cc - c0)^2 + (hh - home0)^2)
      -ll + pen
    }
    init <- c(att0, def0, c0, home0)
    fit <- tryCatch(
      stats::optim(init, nll, method = "BFGS",
                   control = list(maxit = 400, reltol = 1e-8)),
      error = function(e) { log_msg("  optim failed (", conditionMessage(e), "); using priors."); NULL })

    if (!is.null(fit) && fit$convergence %in% c(0L, 1L)) {
      th <- fit$par
      att_fit <- th[1:n]; def_fit <- th[(n + 1):(2 * n)]
      # Per-team shrink weight by games played (belt-and-braces on top of ridge).
      ng <- tabulate(c(hi, ai), nbins = n)
      w  <- ng / (ng + Kshrink)
      att <- stats::setNames(w * att_fit + (1 - w) * att0, teams)
      def <- stats::setNames(w * def_fit + (1 - w) * def0, teams)
      globals$c    <- th[2 * n + 1]
      globals$home <- th[2 * n + 2]
    }
  } else {
    log_msg("  Few/no results; using Elo-derived priors directly.")
  }

  strength <- data.frame(
    team    = teams,
    elo_adj = rt$elo_adj,
    s       = rt$s,
    attack  = as.numeric(att[teams]),
    defense = as.numeric(def[teams]),
    stringsAsFactors = FALSE
  )
  strength <- strength[order(-strength$elo_adj), ]

  state$strength <- strength
  state$globals  <- globals
  log_msg(sprintf("  Globals: intercept=%.3f home=%.3f rho=%.3f",
                  globals$c, globals$home, globals$rho))
  state
}
