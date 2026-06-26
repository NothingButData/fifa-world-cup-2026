# =============================================================================
# 00b_fetch.R  --  Web-fetch live WC2026 data (base R only)
# =============================================================================
# Downloads match results from fixturedownload.com and upserts them into
# input_data/wc2026_outcomes/results.csv.  Also auto-advances the current stage
# in tournament_state.json and confirms bracket ties that now have results.
#
# Every external call is wrapped in tryCatch.  The pipeline runs on whatever
# data is already present if the network is unavailable.
#
# Called by run.R before the staging-file merge and pipeline execution.
# Requires: 00_utils.R already sourced (log_msg, read/write_csv_safe, etc.)
# =============================================================================

# ---- Set CA bundle for environments that route HTTPS through a proxy --------
.init_fetch_env <- function() {
  bundle <- Sys.getenv("CURL_CA_BUNDLE", unset = "")
  if (bundle == "" && file.exists("/root/.ccr/ca-bundle.crt"))
    Sys.setenv(CURL_CA_BUNDLE = "/root/.ccr/ca-bundle.crt")
}

# ---- Fetch a CSV from a URL (download to tempfile, then read) ---------------
.fetch_csv <- function(u, timeout = 30L) {
  tryCatch({
    tf <- tempfile(fileext = ".csv")
    on.exit(unlink(tf), add = TRUE)
    utils::download.file(u, tf, quiet = TRUE, method = "auto", timeout = timeout)
    utils::read.csv(tf, stringsAsFactors = FALSE, check.names = FALSE,
                    strip.white = TRUE, fileEncoding = "UTF-8")
  }, warning = function(w) {
    log_msg("  [fetch] Warning from ", u, ": ", conditionMessage(w))
    NULL
  }, error = function(e) {
    log_msg("  [fetch] Could not reach ", u, ": ", conditionMessage(e))
    NULL
  })
}

# ---- Parse a "X - Y" (or "X-Y") goal string --------------------------------
.parse_score <- function(s) {
  # Handles "1 - 0", "2-1", "1 - 1 (AET)", "0 - 0 (5-4 p)" etc.
  # Returns integer c(home, away) or c(NA, NA).
  s <- trimws(as.character(s))
  m <- regmatches(s, regexpr("(\\d+)\\s*[–-]\\s*(\\d+)", s, perl = TRUE))
  if (!length(m) || is.na(m[1])) return(c(NA_integer_, NA_integer_))
  parts <- strsplit(m[1], "\\s*[–-]\\s*")[[1]]
  as.integer(trimws(parts[1:2]))
}

# ---- Map a fixturedownload round label to our internal stage code -----------
.fd_stage <- function(rnd) {
  r <- trimws(tolower(as.character(rnd)))
  if (grepl("group|matchday|md\\s*[1-3]|stage [1-3]|round [1-3]|group stage", r)) return("group")
  if (grepl("round of 32|r32|round 32|r-32|last 32",   r)) return("R32")
  if (grepl("round of 16|r16|round 16|r-16|last 16",   r)) return("R16")
  if (grepl("quarter",          r)) return("QF")
  if (grepl("semi",             r)) return("SF")
  if (grepl("third|3rd|bronze", r)) return("third_place")
  if (r == "final")                  return("final")
  NA_character_
}

# ---- Safely pull a column from a data.frame by trying multiple names --------
.col <- function(df, ...) {
  hit <- intersect(c(...), names(df))
  if (length(hit)) df[[hit[1]]] else rep(NA_character_, nrow(df))
}

# ---- Parse a fixturedownload.com CSV data.frame into our results schema -----
.parse_fixturedownload <- function(raw) {
  # Normalise column names to lowercase_with_underscores
  names(raw) <- tolower(trimws(gsub("[^A-Za-z0-9]+", "_", names(raw))))

  home <- .col(raw, "home_team", "home")
  away <- .col(raw, "away_team", "away")
  rnd  <- .col(raw, "round_number", "round", "round_name", "stage", "matchday")
  grp  <- .col(raw, "group")
  res  <- .col(raw, "result", "score", "result_full_time", "ft")
  dt   <- .col(raw, "date", "date_utc", "datetime", "match_date")

  df <- data.frame(home = home, away = away, round = rnd, group = grp,
                   result = res, date = dt, stringsAsFactors = FALSE)

  # Drop rows with missing teams
  valid <- !is.na(df$home) & df$home != "" & !is.na(df$away) & df$away != ""
  df <- df[valid, , drop = FALSE]
  if (nrow(df) == 0) { log_msg("  [fetch] No valid rows in fetched data."); return(NULL) }

  df$home <- vapply(df$home, canon_team, character(1))
  df$away <- vapply(df$away, canon_team, character(1))

  # Stage from round label; fall back to group column if round is ambiguous
  df$stage <- vapply(df$round, .fd_stage, character(1))
  fix_from_grp <- is.na(df$stage) & !is.na(df$group) & df$group != ""
  if (any(fix_from_grp))
    df$stage[fix_from_grp] <- vapply(df$group[fix_from_grp], .fd_stage, character(1))

  # Extract group letter (e.g. "Group A" → "A")
  gl <- gsub(".*\\b([A-L])\\b.*", "\\1", toupper(trimws(df$group)))
  df$grp_ltr <- ifelse(grepl("^[A-L]$", gl), gl, NA_character_)

  # Parse score strings
  sc <- t(vapply(df$result, .parse_score, integer(2)))
  df$hg <- sc[, 1]
  df$ag <- sc[, 2]
  df$status <- ifelse(!is.na(df$hg), "final", "scheduled")

  df
}

# ---- Resolve match_ids for fetched rows against existing data ---------------
# Preference order: (1) existing results.csv match for same team-pair,
# (2) bracket match_id for knockout ties, (3) generated stable string ID.
.resolve_match_ids <- function(rows_df, existing_results, bracket) {
  ids <- character(nrow(rows_df))
  for (i in seq_len(nrow(rows_df))) {
    h <- rows_df$home_team[i]; a <- rows_df$away_team[i]
    stg <- rows_df$stage[i]

    # 1. Check existing results.csv for same pair (either orientation)
    if (!is.null(existing_results) && nrow(existing_results) > 0) {
      hit <- which(
        (existing_results$home_team == h & existing_results$away_team == a) |
        (existing_results$home_team == a & existing_results$away_team == h)
      )
      if (length(hit)) { ids[i] <- as.character(existing_results$match_id[hit[1]]); next }
    }

    # 2. For knockout stages, look up bracket match_id
    if (!is.null(bracket) && nrow(bracket) > 0 && stg != "group") {
      hit <- which(
        (bracket$home_team == h & bracket$away_team == a) |
        (bracket$home_team == a & bracket$away_team == h)
      )
      if (length(hit)) { ids[i] <- as.character(bracket$match_id[hit[1]]); next }
    }

    # 3. Generate a stable string ID from stage + canonical team pair
    grp <- rows_df$group[i]
    prefix <- if (stg == "group" && !is.na(grp) && grp != "") paste0("GS_", grp)
              else stg
    ids[i] <- paste0(prefix, "_", pmin(h, a), "_", pmax(h, a))
  }
  ids
}

# ---- Auto-detect the current tournament stage from results ------------------
# Returns the first stage that has fewer confirmed results than its full quota.
auto_detect_stage <- function(results, stages) {
  quota <- c(group = 72L, R32 = 16L, R16 = 8L, QF = 4L, SF = 2L,
             third_place = 1L, final = 1L)
  for (stg in stages) {
    q <- quota[stg]
    if (is.na(q)) next
    n <- if (is.null(results) || nrow(results) == 0) 0L else
         sum(results$stage == stg & results$status == "final", na.rm = TRUE)
    if (n < q) return(stg)
  }
  "final"
}

# ---- Update knockout_bracket.csv: mark ties as confirmed when results exist -
.confirm_bracket_ties <- function(bracket, results) {
  if (is.null(results) || nrow(results) == 0) return(bracket)
  today <- as.character(Sys.Date())
  src_tag <- paste0("reported_", today)
  for (i in seq_len(nrow(bracket))) {
    h <- bracket$home_team[i]; a <- bracket$away_team[i]
    if (is.na(h) || h == "" || is.na(a) || a == "") next
    hit <- which(
      (results$home_team == h & results$away_team == a) |
      (results$home_team == a & results$away_team == h)
    )
    if (length(hit) && results$status[hit[1]] == "final" &&
        !grepl("^reported", bracket$source[i]))
      bracket$source[i] <- src_tag
  }
  bracket
}

# =============================================================================
# Main entry point: fetch, parse, upsert, update stage
# =============================================================================
fetch_live_data <- function(cfg) {
  .init_fetch_env()
  today <- as.character(Sys.Date())
  fetched <- list(results = 0L, stage = NA_character_, bracket_confirmed = 0L)

  if (!isTRUE(cfg$fetch_enabled)) {
    log_msg("[fetch] Disabled (cfg$fetch_enabled = FALSE). Skipping.")
    return(invisible(fetched))
  }
  url <- cfg$fetch_url_results
  if (is.null(url) || trimws(url) == "") {
    log_msg("[fetch] No URL configured (cfg$fetch_url_results). Skipping.")
    return(invisible(fetched))
  }

  log_msg("[fetch] Fetching results from: ", url)
  raw <- .fetch_csv(url, timeout = cfg$fetch_timeout %||% 30L)
  if (is.null(raw)) return(invisible(fetched))

  df <- .parse_fixturedownload(raw)
  if (is.null(df) || nrow(df) == 0) {
    log_msg("[fetch] Could not parse fetched CSV — skipping update.")
    return(invisible(fetched))
  }
  log_msg(sprintf("[fetch] Parsed %d fixtures (%d with final scores).",
                  nrow(df), sum(df$status == "final")))

  # Load existing state files
  results_path  <- file.path(cfg$dir_wc2026, "results.csv")
  bracket_path  <- file.path(cfg$dir_wc2026, "knockout_bracket.csv")
  existing_res  <- read_csv_safe(results_path,  required = FALSE)
  bracket       <- read_csv_safe(bracket_path,  required = FALSE)

  # Build result rows in our schema
  src_tag <- paste0("reported_", today)
  rows <- lapply(seq_len(nrow(df)), function(i) {
    stg <- df$stage[i]; if (is.na(stg)) return(NULL)
    h <- df$home[i]; a <- df$away[i]
    data.frame(
      match_id   = NA_character_,          # resolved below
      stage      = stg,
      group      = if (!is.na(df$grp_ltr[i])) df$grp_ltr[i] else NA_character_,
      date       = df$date[i],
      home_team  = h, away_team = a,
      home_goals = df$hg[i], away_goals = df$ag[i],
      pens_home  = NA_integer_, pens_away = NA_integer_,
      decided_by = if (df$status[i] == "final") "regular" else NA_character_,
      status     = df$status[i],
      source     = if (df$status[i] == "final") src_tag else "scheduled",
      stringsAsFactors = FALSE)
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (!length(rows)) return(invisible(fetched))

  new_res <- do.call(rbind, rows)
  new_res$match_id <- .resolve_match_ids(new_res, existing_res, bracket)

  # Upsert into results.csv
  merged <- upsert_by_key(existing_res, new_res, key = "match_id")
  # Sort: numeric match_ids first (bracket ties 73-104), then string group IDs
  num_ids <- suppressWarnings(as.integer(merged$match_id))
  merged <- merged[order(!is.na(num_ids), num_ids, merged$match_id), ]
  write_csv_safe(merged, results_path)
  n_final <- sum(merged$status == "final", na.rm = TRUE)
  log_msg(sprintf("[fetch] results.csv updated: %d rows, %d final.", nrow(merged), n_final))
  fetched$results <- n_final

  # Auto-detect stage and update tournament_state.json
  detected <- auto_detect_stage(merged, cfg$stages)
  fetched$stage <- detected
  ts_path <- file.path(cfg$dir_wc2026, "tournament_state.json")
  if (file.exists(ts_path)) {
    ts <- readLines(ts_path, warn = FALSE)
    cur <- regmatches(ts, regexpr('"current_stage"\\s*:\\s*"([^"]+)"', ts))
    cur <- if (length(cur)) gsub('.*"([^"]+)"\\s*$', "\\1", cur[1]) else ""
    ts <- gsub('"current_stage"\\s*:\\s*"[^"]+"',
               paste0('"current_stage": "', detected, '"'), ts)
    ts <- gsub('"as_of_date"\\s*:\\s*"[^"]+"',
               paste0('"as_of_date": "', today, '"'), ts)
    ts <- gsub('"last_updated"\\s*:\\s*"[^"]+"',
               paste0('"last_updated": "', today, '"'), ts)
    writeLines(ts, ts_path)
    if (cur != detected)
      log_msg(sprintf("[fetch] Stage advanced: %s -> %s", cur, detected))
    else
      log_msg(sprintf("[fetch] Stage unchanged: %s", detected))
  }

  # Confirm bracket ties that now have results
  if (!is.null(bracket)) {
    bracket2 <- .confirm_bracket_ties(bracket, merged)
    n_conf <- sum(bracket2$source != bracket$source, na.rm = TRUE)
    if (n_conf > 0) {
      write_csv_safe(bracket2, bracket_path)
      log_msg(sprintf("[fetch] Confirmed %d bracket tie(s) in knockout_bracket.csv.", n_conf))
      fetched$bracket_confirmed <- n_conf
    }
  }

  # Reminder if top_scorers.csv is stale
  ts_csv <- file.path(cfg$dir_wc2026, "top_scorers.csv")
  if (file.exists(ts_csv)) {
    sc <- read_csv_safe(ts_csv, required = FALSE)
    if (!is.null(sc) && nrow(sc) > 0) {
      last_src <- sc$source[1]
      if (is.na(last_src) || !grepl(today, last_src))
        log_msg("[fetch] NOTE: top_scorers.csv last updated ", last_src,
                " — update manually if goals have changed.")
    }
  }

  invisible(fetched)
}

# ---- NULL-coalescing helper (base R doesn't have %||%) ----------------------
`%||%` <- function(a, b) if (!is.null(a)) a else b
