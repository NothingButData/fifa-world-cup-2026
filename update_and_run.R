#!/usr/bin/env Rscript
# Deprecated: use run.R instead.
# Rscript run.R [stage] [--no-fetch]
root <- Sys.getenv("WC2026_ROOT", unset = normalizePath(getwd(), mustWork = FALSE))
source(file.path(root, "run.R"))
