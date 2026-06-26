# =============================================================================
# 04_simulate.R  --  Monte Carlo: group standings + knockout progression
# =============================================================================

# ---- Group round-robin fixtures (6 per group) -------------------------------
group_fixtures <- function(groups) {
  do.call(rbind, lapply(split(groups, groups$group), function(g) {
    cm <- t(utils::combn(g$team, 2))
    data.frame(group = g$group[1], home_team = cm[, 1], away_team = cm[, 2],
               stringsAsFactors = FALSE)
  }))
}

# ---- Standings from a set of played group matches ---------------------------
# matches: data.frame(group, home_team, away_team, home_goals, away_goals)
compute_standings <- function(matches, teams_by_group, strength = NULL) {
  rows <- lapply(names(teams_by_group), function(gr) {
    tm <- teams_by_group[[gr]]
    pts <- gf <- ga <- pl <- stats::setNames(numeric(length(tm)), tm)
    mg <- matches[matches$group == gr, , drop = FALSE]
    for (i in seq_len(nrow(mg))) {
      h <- mg$home_team[i]; a <- mg$away_team[i]
      hg <- mg$home_goals[i]; ag <- mg$away_goals[i]
      if (is.na(hg) || is.na(ag)) next
      pl[h] <- pl[h] + 1; pl[a] <- pl[a] + 1
      gf[h] <- gf[h] + hg; ga[h] <- ga[h] + ag
      gf[a] <- gf[a] + ag; ga[a] <- ga[a] + hg
      if (hg > ag) pts[h] <- pts[h] + 3
      else if (hg < ag) pts[a] <- pts[a] + 3
      else { pts[h] <- pts[h] + 1; pts[a] <- pts[a] + 1 }
    }
    gd <- gf - ga
    tie <- if (!is.null(strength)) strength$s[match(tm, strength$team)] else 0
    ord <- order(-pts, -gd, -gf, -tie)
    data.frame(group = gr, team = tm[ord], pos = seq_along(tm),
               played = pl[ord], pts = pts[ord], gf = gf[ord], ga = ga[ord], gd = gd[ord],
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# ---- Simulate the group stage ----------------------------------------------
# Uses final results where present; simulates the rest from the goal model.
simulate_groups <- function(state, n = NULL) {
  log_msg("Simulating group stage ...")
  n <- if (is.null(n)) min(state$cfg$n_sims, 3000L) else n
  groups <- state$groups
  teams_by_group <- split(groups$team, groups$group)
  fx <- group_fixtures(groups)

  # Attach known final results to fixtures.
  res <- state$results
  fin <- if (is.null(res)) NULL else res[which(res$status == "final" & res$stage == "group"), , drop = FALSE]
  key <- function(a, b) paste(pmin(a, b), pmax(a, b), sep = "|")
  fx$key <- key(fx$home_team, fx$away_team)
  fx$hg <- NA_real_; fx$ag <- NA_real_
  if (!is.null(fin) && nrow(fin) > 0) {
    fk <- key(fin$home_team, fin$away_team)
    for (i in seq_len(nrow(fx))) {
      j <- which(fk == fx$key[i])
      if (length(j)) {
        # orient goals to fixture's home/away
        if (fin$home_team[j[1]] == fx$home_team[i]) {
          fx$hg[i] <- fin$home_goals[j[1]]; fx$ag[i] <- fin$away_goals[j[1]]
        } else {
          fx$hg[i] <- fin$away_goals[j[1]]; fx$ag[i] <- fin$home_goals[j[1]]
        }
      }
    }
  }

  # Pre-compute expected goals per fixture (for the simulated ones).
  lam <- t(vapply(seq_len(nrow(fx)), function(i)
    expected_goals(state, fx$home_team[i], fx$away_team[i]), numeric(2)))

  tm_all <- groups$team
  acc <- list(
    p1 = stats::setNames(numeric(length(tm_all)), tm_all),
    p2 = stats::setNames(numeric(length(tm_all)), tm_all),
    p3 = stats::setNames(numeric(length(tm_all)), tm_all),
    adv = stats::setNames(numeric(length(tm_all)), tm_all)
  )

  for (s in seq_len(n)) {
    sim <- fx
    miss <- is.na(sim$hg)
    sim$hg[miss] <- stats::rpois(sum(miss), lam[miss, 1])
    sim$ag[miss] <- stats::rpois(sum(miss), lam[miss, 2])
    st <- compute_standings(
      data.frame(group = sim$group, home_team = sim$home_team, away_team = sim$away_team,
                 home_goals = sim$hg, away_goals = sim$ag, stringsAsFactors = FALSE),
      teams_by_group, state$strength)
    w  <- st$team[st$pos == 1]; r <- st$team[st$pos == 2]; thr <- st[st$pos == 3, ]
    acc$p1[w] <- acc$p1[w] + 1; acc$p2[r] <- acc$p2[r] + 1
    acc$p3[thr$team] <- acc$p3[thr$team] + 1
    # 8 best third-placed teams advance.
    ord3 <- thr[order(-thr$pts, -thr$gd, -thr$gf), ]
    best3 <- head(ord3$team, 8)
    acc$adv[c(w, r, best3)] <- acc$adv[c(w, r, best3)] + 1
  }

  proj <- data.frame(
    team        = tm_all,
    group       = groups$group[match(tm_all, groups$team)],
    p_win_group = acc$p1 / n,
    p_runnerup  = acc$p2 / n,
    p_third     = acc$p3 / n,
    p_advance   = acc$adv / n,
    stringsAsFactors = FALSE
  )
  proj <- proj[order(proj$group, -proj$p_advance), ]
  rownames(proj) <- NULL

  # Deterministic "current" standings from final results only (for the report).
  cur <- compute_standings(
    data.frame(group = fx$group, home_team = fx$home_team, away_team = fx$away_team,
               home_goals = fx$hg, away_goals = fx$ag, stringsAsFactors = FALSE),
    teams_by_group, state$strength)

  state$group_projection <- proj
  state$standings        <- cur
  state
}

# ---- Pairwise knockout advancement matrix (precompute once) -----------------
precompute_adv_matrix <- function(state, teams) {
  teams <- unique(teams)
  k <- length(teams)
  A <- matrix(0.5, k, k, dimnames = list(teams, teams))
  for (i in seq_len(k)) for (j in seq_len(k)) {
    if (i == j) next
    A[i, j] <- knockout_win_prob(state, teams[i], teams[j])
  }
  A
}

# Precompute expected goals for every ordered pair of teams (home vs away).
precompute_eg_matrix <- function(state, teams) {
  k <- length(teams)
  EGh <- matrix(0, k, k, dimnames = list(teams, teams))
  EGa <- matrix(0, k, k, dimnames = list(teams, teams))
  for (i in seq_len(k)) for (j in seq_len(k)) {
    if (i == j) next
    eg <- expected_goals(state, teams[i], teams[j])
    EGh[i, j] <- eg[1]   # lambda for the home side
    EGa[i, j] <- eg[2]   # lambda for the away side
  }
  list(home = EGh, away = EGa)
}

# ---- Fill blank R32 participants from the group projection ------------------
# Graceful fallback: if a not-yet-confirmed R32 tie has an empty home/away team,
# resolve it to the MOST-LIKELY team for that slot (W_x / RU_x / 3RD pool) from
# simulate_groups(), de-duplicating against teams already named in the bracket.
# Confirmed/known participants are never overwritten. Returns the bracket plus a
# `filled` vector recording which participants were model-derived.
fill_open_r32 <- function(br, gp) {
  r32_idx <- which(br$stage == "R32")
  filled <- character(0)
  if (is.null(gp)) return(list(br = br, filled = filled))
  used <- unique(c(br$home_team[r32_idx], br$away_team[r32_idx]))
  used <- used[!is.na(used) & used != ""]
  pick_slot <- function(slot) {
    if (is.na(slot) || slot == "") return(NA_character_)
    if (grepl("^W_", slot)) {
      g <- gp[gp$group == sub("^W_", "", slot), ]
      cand <- g[order(-g$p_win_group), ]
    } else if (grepl("^RU_", slot)) {
      g <- gp[gp$group == sub("^RU_", "", slot), ]
      cand <- g[order(-g$p_runnerup), ]
    } else if (grepl("3RD", slot)) {
      cand <- gp[order(-gp$p_third), ]
    } else return(NA_character_)
    cand <- cand[!(cand$team %in% used), ]
    if (nrow(cand) == 0) NA_character_ else cand$team[1]
  }
  for (i in r32_idx) {
    if (is.na(br$home_team[i]) || br$home_team[i] == "") {
      t <- pick_slot(br$home_slot[i]); br$home_team[i] <- t
      if (!is.na(t)) { used <- c(used, t); filled <- c(filled, t) }
    }
    if (is.na(br$away_team[i]) || br$away_team[i] == "") {
      t <- pick_slot(br$away_slot[i]); br$away_team[i] <- t
      if (!is.na(t)) { used <- c(used, t); filled <- c(filled, t) }
    }
  }
  list(br = br, filled = filled)
}

# ---- Simulate the knockout bracket -----------------------------------------
simulate_knockout <- function(state, n = NULL) {
  log_msg("Simulating knockout bracket ...")
  n <- if (is.null(n)) state$cfg$n_sims else n
  br <- state$bracket
  if (is.null(br)) stop("knockout_bracket.csv not loaded.")
  br <- br[order(as.integer(br$match_id)), ]

  # Resolve any blank R32 ties from the group projection (graceful fallback).
  fo <- fill_open_r32(br, state$group_projection)
  br <- fo$br; state$bracket <- br; state$r32_filled <- fo$filled
  if (length(fo$filled))
    log_msg(sprintf("  Filled %d open R32 slot(s) from group projection: %s",
                    length(fo$filled), paste(fo$filled, collapse = ", ")))

  r32 <- br[br$stage == "R32", ]
  teams <- unique(c(r32$home_team, r32$away_team))
  teams <- teams[!is.na(teams) & teams != ""]
  if (length(teams) < 2) stop("R32 participants not populated in knockout_bracket.csv")

  A     <- precompute_adv_matrix(state, teams)
  EGmat <- precompute_eg_matrix(state, teams)

  ko_stages <- c("R32", "R16", "QF", "SF", "final", "third_place")
  EG_acc    <- matrix(0, length(teams), length(ko_stages),
                      dimnames = list(teams, ko_stages))

  metrics <- c("reach_R32", "reach_R16", "reach_QF", "reach_SF", "reach_final",
               "champion", "runner_up", "third_place")
  C <- matrix(0, length(teams), length(metrics), dimnames = list(teams, metrics))

  resolve <- function(slot, winners, losers) {
    if (is.na(slot) || slot == "") return(NA_character_)
    pre <- substr(slot, 1, 1); id <- substr(slot, 2, nchar(slot))
    if (pre == "W") return(winners[[id]])
    if (pre == "L") return(losers[[id]])
    NA_character_
  }

  for (s in seq_len(n)) {
    winners <- list(); losers <- list()
    reached <- stats::setNames(logical(length(teams)), teams)  # reach_R16+ buckets handled per stage
    stage_part <- list(R32 = character(), R16 = character(), QF = character(),
                       SF = character(), final = character())
    for (i in seq_len(nrow(br))) {
      mid <- as.character(br$match_id[i]); stg <- br$stage[i]
      if (stg == "R32") { h <- br$home_team[i]; a <- br$away_team[i] }
      else { h <- resolve(br$home_slot[i], winners, losers)
             a <- resolve(br$away_slot[i], winners, losers) }
      if (is.na(h) || is.na(a)) next
      if (stg %in% ko_stages && h %in% teams && a %in% teams) {
        EG_acc[h, stg] <- EG_acc[h, stg] + EGmat$home[h, a]
        EG_acc[a, stg] <- EG_acc[a, stg] + EGmat$away[h, a]
      }
      if (stg %in% names(stage_part)) stage_part[[stg]] <- c(stage_part[[stg]], h, a)
      p <- A[h, a]
      if (stats::runif(1) < p) { w <- h; l <- a } else { w <- a; l <- h }
      winners[[mid]] <- w; losers[[mid]] <- l
      if (stg == "final")       { C[w, "champion"]   <- C[w, "champion"]   + 1
                                  C[l, "runner_up"]  <- C[l, "runner_up"]  + 1 }
      if (stg == "third_place")   C[w, "third_place"] <- C[w, "third_place"] + 1
    }
    C[unique(stage_part$R32),   "reach_R32"]   <- C[unique(stage_part$R32),   "reach_R32"]   + 1
    C[unique(stage_part$R16),   "reach_R16"]   <- C[unique(stage_part$R16),   "reach_R16"]   + 1
    C[unique(stage_part$QF),    "reach_QF"]    <- C[unique(stage_part$QF),    "reach_QF"]    + 1
    C[unique(stage_part$SF),    "reach_SF"]    <- C[unique(stage_part$SF),    "reach_SF"]    + 1
    C[unique(stage_part$final), "reach_final"] <- C[unique(stage_part$final), "reach_final"] + 1
  }

  prog <- as.data.frame(C / n)
  prog$team <- rownames(prog)
  prog <- prog[order(-prog$champion, -prog$reach_final, -prog$reach_SF),
               c("team", metrics)]
  rownames(prog) <- NULL
  state$progression        <- prog
  state$adv_matrix         <- A
  state$exp_goals_by_stage <- EG_acc / n
  state
}
