# =============================================================================
# 07_report.R  --  Self-contained PDF reports via base R's pdf() device
# =============================================================================
# No pandoc / LaTeX / rmarkdown required. Each stage gets one PDF that shows the
# RUN date and a retained CREATED date, the latest predictions, progression
# probabilities, and per-stage top-scorer forecasts. Also writes tidy CSVs to
# outcomes/predictions/ for programmatic use.
# =============================================================================

# ---- registry: remember each report's first-created date --------------------
.report_created_date <- function(cfg, stage, run_date) {
  reg <- if (file.exists(cfg$report_registry))
    read_csv_safe(cfg$report_registry, required = FALSE) else
    data.frame(stage = character(), created = character(), stringsAsFactors = FALSE)
  hit <- which(reg$stage == stage)
  if (length(hit)) return(reg$created[hit[1]])
  reg <- rbind(reg, data.frame(stage = stage, created = as.character(run_date),
                               stringsAsFactors = FALSE))
  write_csv_safe(reg, cfg$report_registry)
  as.character(run_date)
}

# ---- low-level drawing helpers ---------------------------------------------
.page <- function() { graphics::par(mar = c(0, 0, 0, 0)); graphics::plot.new()
  graphics::plot.window(xlim = c(0, 1), ylim = c(0, 1)) }

.header <- function(title, sub = NULL) {
  graphics::text(0.06, 0.965, title, adj = 0, cex = 1.7, font = 2)
  graphics::segments(0.06, 0.945, 0.94, 0.945, lwd = 2)
  if (!is.null(sub)) graphics::text(0.06, 0.925, sub, adj = 0, cex = 0.85, col = "grey30")
}

.footer <- function(run_date, created) {
  graphics::segments(0.06, 0.035, 0.94, 0.035, col = "grey70")
  graphics::text(0.06, 0.02, paste0("Run: ", run_date, "  |  Report created: ", created),
                 adj = 0, cex = 0.65, col = "grey40")
  graphics::text(0.94, 0.02, "WC2026 Prediction System", adj = 1, cex = 0.65, col = "grey40")
}

# Draw a data.frame as a table. widths sum to ~1; returns y below the table.
.table <- function(df, y_top, x_left = 0.06, x_right = 0.94, widths = NULL,
                   cex = 0.74, rh = 0.028, title = NULL, aligns = NULL) {
  if (!is.null(title)) { graphics::text(x_left, y_top, title, adj = 0, cex = 0.95, font = 2)
                         y_top <- y_top - 0.035 }
  nc <- ncol(df)
  if (is.null(widths)) {
    w <- vapply(seq_len(nc), function(j)
      max(nchar(c(names(df)[j], as.character(df[[j]]))), na.rm = TRUE), numeric(1))
    widths <- w / sum(w)
  }
  if (is.null(aligns)) aligns <- ifelse(vapply(df, is.numeric, logical(1)), "r", "l")
  span <- x_right - x_left
  edges <- x_left + span * c(0, cumsum(widths))
  pad <- 0.006
  cellx <- function(j, align) if (align == "r") edges[j + 1] - pad else edges[j] + pad
  # header
  graphics::rect(x_left, y_top - rh, x_right, y_top, col = "grey25", border = NA)
  for (j in seq_len(nc))
    graphics::text(cellx(j, aligns[j]), y_top - rh / 2, names(df)[j],
                   adj = c(if (aligns[j] == "r") 1 else 0, 0.5),
                   cex = cex, font = 2, col = "white")
  y <- y_top - rh
  for (i in seq_len(nrow(df))) {
    if (i %% 2 == 0) graphics::rect(x_left, y - rh, x_right, y, col = "grey93", border = NA)
    for (j in seq_len(nc))
      graphics::text(cellx(j, aligns[j]), y - rh / 2, as.character(df[[j]][i]),
                     adj = c(if (aligns[j] == "r") 1 else 0, 0.5), cex = cex)
    y <- y - rh
  }
  graphics::segments(x_left, y, x_right, y, col = "grey70")
  y - 0.01
}

# Horizontal probability bar chart.
.barchart <- function(labels, values, y_top, x_left = 0.06, x_right = 0.7,
                      bar_h = 0.03, gap = 0.012, col = "#1f6feb", title = NULL) {
  if (!is.null(title)) { graphics::text(x_left, y_top, title, adj = 0, cex = 0.95, font = 2)
                         y_top <- y_top - 0.04 }
  maxv <- max(values, 1e-9)
  y <- y_top
  for (i in seq_along(labels)) {
    graphics::text(x_left, y - bar_h / 2, labels[i], adj = 0, cex = 0.72)
    bx0 <- x_left + 0.18
    graphics::rect(bx0, y - bar_h, bx0 + (x_right - bx0) * values[i] / maxv, y,
                   col = col, border = NA)
    graphics::text(bx0 + (x_right - bx0) * values[i] / maxv + 0.01, y - bar_h / 2,
                   pct(values[i], 1), adj = 0, cex = 0.68, col = "grey30")
    y <- y - (bar_h + gap)
  }
  y - 0.01
}

.wrap_text <- function(txt, y, x_left = 0.06, x_right = 0.94, cex = 0.75, lh = 0.026) {
  width_chars <- floor((x_right - x_left) / (0.011 * cex / 0.75))
  for (ln in strwrap(txt, width = width_chars)) {
    graphics::text(x_left, y, ln, adj = 0, cex = cex); y <- y - lh
  }
  y
}

# =============================================================================
# Main entry: build the stage report + write prediction CSVs
# =============================================================================
generate_report <- function(state, stage = NULL) {
  cfg <- state$cfg
  stage <- if (is.null(stage)) state$tournament_current_stage else stage
  run_date <- as.character(state$run_date)
  created  <- .report_created_date(cfg, stage, state$run_date)
  label <- if (stage %in% names(cfg$stage_labels)) cfg$stage_labels[[stage]] else stage

  # ---- write prediction CSVs ------------------------------------------------
  write_csv_safe(state$progression,       file.path(cfg$dir_predictions, "progression_probabilities.csv"))
  write_csv_safe(state$scorer_projection, file.path(cfg$dir_predictions, "golden_boot_projection.csv"))
  if (!is.null(state$group_projection))
    write_csv_safe(state$group_projection, file.path(cfg$dir_predictions, "group_projection.csv"))
  if (!is.null(state$recommendations$match_predictions))
    write_csv_safe(state$recommendations$match_predictions,
                   file.path(cfg$dir_predictions, paste0("match_predictions_", stage, ".csv")))
  st_long <- do.call(rbind, lapply(names(state$stage_top_scorers), function(s) {
    d <- state$stage_top_scorers[[s]]; if (nrow(d)) cbind(stage = s, d) else NULL }))
  if (!is.null(st_long)) write_csv_safe(st_long, file.path(cfg$dir_predictions, "stage_top_scorers.csv"))

  # ---- open PDF -------------------------------------------------------------
  pdf_path <- file.path(cfg$dir_reports, paste0("WC2026_", stage, "_report.pdf"))
  grDevices::pdf(pdf_path, width = 8.27, height = 11.69, paper = "a4")
  on.exit(grDevices::dev.off(), add = TRUE)

  prog <- state$progression

  # ---- Page 1: cover + headlines -------------------------------------------
  .page()
  graphics::text(0.5, 0.86, "FIFA World Cup 2026", cex = 2.6, font = 2, adj = 0.5)
  graphics::text(0.5, 0.80, "Prediction Report", cex = 1.6, adj = 0.5, col = "grey20")
  graphics::text(0.5, 0.74, paste0("Stage: ", label), cex = 1.3, adj = 0.5, col = "#1f6feb")
  graphics::text(0.5, 0.70, paste0("Run date: ", run_date,
                                   "    (report created: ", created, ")"),
                 cex = 0.95, adj = 0.5, col = "grey30")
  champ <- prog$team[1]; champ_p <- prog$champion[1]
  gb <- state$scorer_projection[1, ]
  hl <- data.frame(
    Headline = c("Title pick", "Most likely finalists", "Golden Boot pick",
                 "Teams simulated", "Monte Carlo runs"),
    Value = c(sprintf("%s (%s)", champ, pct(champ_p, 1)),
              paste(utils::head(prog$team[order(-prog$reach_final)], 2), collapse = " & "),
              sprintf("%s (%s) - proj %.1f", gb$player, gb$team, gb$proj_total),
              as.character(nrow(prog)),
              format(cfg$n_sims, big.mark = ",")),
    stringsAsFactors = FALSE)
  .table(hl, y_top = 0.58, widths = c(0.32, 0.68), cex = 0.82, rh = 0.04, aligns = c("l", "l"))
  graphics::text(0.5, 0.20,
                 "Model: ridge-shrunk Poisson (Dixon-Coles) goal model + Monte Carlo bracket simulation",
                 cex = 0.72, adj = 0.5, col = "grey40")
  .footer(run_date, created)

  # ---- Page 2: progression probabilities -----------------------------------
  .page(); .header("Tournament Progression", paste0("As of ", state$as_of_date,
                   " - probabilities from ", format(cfg$n_sims, big.mark = ","), " simulations"))
  topN <- utils::head(prog, 16)
  ptab <- data.frame(
    Team = topN$team,
    R16  = pct(topN$reach_R16, 0), QF = pct(topN$reach_QF, 0),
    SF   = pct(topN$reach_SF, 0),  Final = pct(topN$reach_final, 0),
    Win  = pct(topN$champion, 1),
    stringsAsFactors = FALSE)
  endy <- .table(ptab, y_top = 0.9, widths = c(0.34, 0.13, 0.13, 0.13, 0.13, 0.14),
                 aligns = c("l", "r", "r", "r", "r", "r"))
  .barchart(utils::head(prog$team[order(-prog$champion)], 8),
            utils::head(prog$champion[order(-prog$champion)], 8),
            y_top = endy - 0.02, title = "Title-winning probability", col = "#1f6feb")
  .footer(run_date, created)

  # ---- Page 3: next-stage match predictions --------------------------------
  mp <- state$recommendations$match_predictions
  .page(); .header(paste0(label, " - Match Predictions"),
                   "Advancer = win the tie; 90' result and likeliest score also shown")
  if (!is.null(mp) && nrow(mp) > 0) {
    mtab <- data.frame(
      Match = paste(mp$home, "v", mp$away),
      Advance = paste0(mp$advancer, " (", pct(mp$p_advance, 0), ")"),
      `90' result` = mp$reg_result,
      Score = paste0(mp$score, " (", pct(mp$p_score, 0), ")"),
      check.names = FALSE, stringsAsFactors = FALSE)
    .table(mtab, y_top = 0.9, widths = c(0.40, 0.26, 0.18, 0.16),
           aligns = c("l", "l", "l", "l"), cex = 0.72)
  } else {
    .wrap_text(paste0("No fixed matchups available for ", label,
                      " yet (participants still probabilistic). See progression ",
                      "probabilities and recommendations for guidance."), y = 0.88)
  }
  .footer(run_date, created)

  # ---- Page 4: Golden Boot + per-stage top scorers -------------------------
  .page(); .header("Top-Scorer Forecast", "Projected final goals = current + expected remaining")
  gbt <- utils::head(state$scorer_projection, 12)
  gtab <- data.frame(
    Player = gbt$player, Team = gbt$team, Now = gbt$current,
    `Exp+` = gbt$exp_remaining, Proj = gbt$proj_total,
    check.names = FALSE, stringsAsFactors = FALSE)
  endy <- .table(gtab, y_top = 0.9, widths = c(0.34, 0.28, 0.10, 0.13, 0.15),
                 aligns = c("l", "l", "r", "r", "r"), cex = 0.74,
                 title = "Golden Boot projection")
  # next-stage top scorer picks
  ns <- state$recommendations$next_stage
  sd <- state$stage_top_scorers[[ns]]
  if (!is.null(sd) && nrow(sd) > 0) {
    stab <- data.frame(Player = sd$player, Team = sd$team,
                       `Exp goals` = sd$exp_goals, check.names = FALSE,
                       stringsAsFactors = FALSE)
    .table(utils::head(stab, 8), y_top = endy - 0.03, widths = c(0.45, 0.4, 0.15),
           aligns = c("l", "l", "r"), cex = 0.74,
           title = paste0("Top-scorer picks for ", label))
  }
  .footer(run_date, created)

  # ---- Page 5: recommendations + methodology --------------------------------
  .page(); .header("Recommendations & Method", "How to play these predictions")
  y <- 0.9
  y <- .wrap_text(paste0("STRATEGY: ", state$recommendations$strategy_note), y = y, cex = 0.78)
  y <- y - 0.015
  cp <- state$recommendations$progression_picks$champion
  picks_txt <- paste0("Champion pick: ", cp$team[1], " (", pct(cp$champion[1], 1), "). ",
    "Safe R16 backers: ",
    paste(utils::head(state$recommendations$progression_picks$reach_R16$team, 6), collapse = ", "), ".")
  y <- .wrap_text(picks_txt, y = y, cex = 0.78); y <- y - 0.02
  graphics::text(0.06, y, "Methodology", adj = 0, font = 2, cex = 0.95); y <- y - 0.03
  method <- paste(
    "1. Team strength starts from Elo priors adjusted by researched form/injury notes.",
    "2. A Dixon-Coles bivariate Poisson model turns strength into scoreline distributions;",
    "   parameters are refined by a ridge-penalised fit on observed results (shrinking to priors).",
    "3. A Monte Carlo simulation plays out the bracket many times -> progression probabilities,",
    "   with extra time and strength-tilted penalty shootouts for knockout ties.",
    "4. Each team's expected goals are shared among its players (form-adjusted) and weighted by",
    "   how far the team is projected to advance -> per-stage and Golden Boot scorer forecasts.",
    sep = "\n")
  for (ln in strsplit(method, "\n")[[1]]) { y <- .wrap_text(ln, y = y, cex = 0.72) }
  y <- y - 0.02
  graphics::text(0.06, y, "Data provenance", adj = 0, font = 2, cex = 0.95); y <- y - 0.03
  prov <- paste("Verified: group draw, reported group winners, R32 anchor ties, Golden Boot tallies.",
                "Illustrative/projected: unplayed scores and not-yet-confirmed bracket slots.",
                "Refresh input_data/ CSVs with official data and re-run to update everything.",
                sep = "\n")
  for (ln in strsplit(prov, "\n")[[1]]) { y <- .wrap_text(ln, y = y, cex = 0.72) }
  .footer(run_date, created)

  log_msg("Report written: ", pdf_path)
  invisible(pdf_path)
}
