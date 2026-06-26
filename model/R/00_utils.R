# =============================================================================
# 00_utils.R  --  Small, dependency-free helpers (base R only)
# =============================================================================

# ---- Logging ----------------------------------------------------------------
log_msg <- function(...) {
  cat(sprintf("[%s] %s\n", format(Sys.time(), "%H:%M:%S"), paste0(...)))
}

# ---- Robust CSV I/O ---------------------------------------------------------
read_csv_safe <- function(path, required = TRUE) {
  if (!file.exists(path)) {
    if (required) stop("Missing required file: ", path)
    return(NULL)
  }
  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                        strip.white = TRUE, encoding = "UTF-8")
  # Trim whitespace on character columns.
  for (j in seq_along(df)) {
    if (is.character(df[[j]])) df[[j]] <- trimws(df[[j]])
  }
  df
}

write_csv_safe <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(df, path, row.names = FALSE, na = "")
  invisible(path)
}

# ---- Parameter table helper -------------------------------------------------
# Reads historical_params.csv (param,value,...) into a named list of values,
# coercing numerics where possible.
params_to_list <- function(df) {
  out <- as.list(stats::setNames(df$value, df$param))
  for (k in names(out)) {
    num <- suppressWarnings(as.numeric(out[[k]]))
    if (!is.na(num)) out[[k]] <- num
  }
  out
}

# ---- Upsert rows by key (used for incremental result updates) ---------------
# Replaces rows in `base` whose key matches `new`, appends the rest.
upsert_by_key <- function(base, new, key = "match_id") {
  if (is.null(base) || nrow(base) == 0) return(new)
  if (is.null(new)  || nrow(new)  == 0) return(base)
  # Align columns.
  all_cols <- union(names(base), names(new))
  for (c in setdiff(all_cols, names(base))) base[[c]] <- NA
  for (c in setdiff(all_cols, names(new)))  new[[c]]  <- NA
  base <- base[, all_cols, drop = FALSE]
  new  <- new[,  all_cols, drop = FALSE]
  keep <- !(base[[key]] %in% new[[key]])
  rbind(base[keep, , drop = FALSE], new)
}

# ---- Safe team-name normalisation ------------------------------------------
# Keeps a single canonical spelling so joins across files always line up.
canon_team <- function(x) {
  x <- trimws(x)
  fixes <- c(
    "Korea Republic" = "Korea Republic", "South Korea" = "Korea Republic",
    "USA" = "USA", "United States" = "USA", "United States of America" = "USA",
    "Turkiye" = "Turkiye", "Turkey" = "Turkiye", "Türkiye" = "Turkiye",
    "Cape Verde" = "Cape Verde", "Cabo Verde" = "Cape Verde",
    "Cote d'Ivoire" = "Cote d'Ivoire", "Ivory Coast" = "Cote d'Ivoire",
    "Cote d’Ivoire" = "Cote d'Ivoire",
    "Côte d'Ivoire" = "Cote d'Ivoire", "Côte d’Ivoire" = "Cote d'Ivoire",
    "Curacao" = "Curacao", "Curaçao" = "Curacao",
    "Bosnia and Herzegovina" = "Bosnia and Herzegovina", "Bosnia" = "Bosnia and Herzegovina",
    "DR Congo" = "DR Congo", "Congo DR" = "DR Congo",
    "IR Iran" = "Iran", "Iran" = "Iran",
    "Czechia" = "Czechia", "Czech Republic" = "Czechia"
  )
  out <- ifelse(x %in% names(fixes), fixes[x], x)
  unname(out)
}

# ---- Pretty number formatting for reports ----------------------------------
pct <- function(x, digits = 0) paste0(formatC(100 * x, format = "f", digits = digits), "%")
