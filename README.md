# FIFA World Cup 2026 — Prediction System

A repeatable, R-based system for forecasting the **remaining stages** of the
2026 World Cup and maximising your score in a Scorito-style prediction game. It
researches team/player information, maintains historical and live data, fits a
goal-scoring model, simulates the bracket, and produces a **PDF report per
stage** with the latest match, progression, and top-scorer predictions.

Built entirely in **base R** (R ≥ 4.x, recommended packages only) — no external
package installs, no LaTeX/pandoc. Reports are drawn with R's native `pdf()`
device.

---

## 1. What it predicts

| Output | File(s) |
|--------|---------|
| Match outcomes (winner / 90′ result / likeliest score) | `outcomes/predictions/match_predictions_<stage>.csv` |
| Tournament progression (P reach R16 → champion) | `outcomes/predictions/progression_probabilities.csv` |
| Group-stage projection (win group / advance) | `outcomes/predictions/group_projection.csv` |
| Top scorers per stage | `outcomes/predictions/stage_top_scorers.csv` |
| Golden Boot projection | `outcomes/predictions/golden_boot_projection.csv` |
| **Stage PDF report** (dated, with recommendations) | `outcomes/reports/WC2026_<stage>_report.pdf` |

---

## 2. Project structure

```
input_data/
├── researched_info/      # qualitative research + model-readable adjustments
│   ├── team_form_notes.md
│   ├── team_adjustments.csv      # elo_adjustment / form_multiplier per team
│   ├── player_adjustments.csv    # availability + form per player (injuries etc.)
│   └── sources.md                # provenance: verified vs illustrative
├── historical_stats/     # model inputs & historical datasets
│   ├── team_ratings_seed.csv     # 48 teams, Elo priors
│   ├── historical_params.csv     # global calibration (goals, home adv, ...)
│   └── player_pool.csv           # scorers with goal-share priors
└── wc2026_outcomes/      # live tournament state (refresh as it progresses)
    ├── groups.csv                # the 12 groups
    ├── results.csv               # played matches (upserted incrementally)
    ├── knockout_bracket.csv      # bracket tree + known participants
    ├── top_scorers.csv           # current goal tallies
    └── tournament_state.json     # current stage + metadata

model/
├── config.R              # paths + simulation settings (edit knobs here)
└── R/
    ├── 00_utils.R         # CSV I/O, upsert, team-name canonicalisation
    ├── 01_load_data.R     # load everything into one `state` list
    ├── 02_ratings.R       # Elo + research -> attack/defense (penalised Poisson)
    ├── 03_match_model.R   # Dixon-Coles scoreline + knockout resolution
    ├── 04_simulate.R      # Monte Carlo: groups + bracket progression
    ├── 05_top_scorers.R   # player goal forecasts
    ├── 06_recommendations.R # game picks + strategy
    └── 07_report.R        # base-R PDF report generator

outcomes/
├── predictions/          # tidy CSV predictions (overwritten each run)
├── reports/              # WC2026_<stage>_report.pdf (overwritten each run)
└── .report_registry.csv  # remembers each report's first-created date

run_pipeline.R            # full run (initial / from scratch)
update_and_run.R          # incremental refresh + re-run (use during the cup)
```

---

## 3. Running it

From the project root:

```bash
# Full run for the stage in tournament_state.json (default 10,000 sims):
Rscript run_pipeline.R

# Force a specific stage:
Rscript run_pipeline.R R16

# Faster/slower simulations:
WC2026_NSIMS=20000 Rscript run_pipeline.R
```

Outputs land in `outcomes/`. Open `outcomes/reports/WC2026_<stage>_report.pdf`.

---

## 4. Incremental workflow (each stage of the tournament)

The system is designed to **update, not rebuild**. As results come in:

1. **Refresh live data** in `input_data/wc2026_outcomes/`:
   - Add played scores to `results.csv` *or* drop a `results_update.csv`
     (same schema) to be merged by `match_id` automatically.
   - Fill in `knockout_bracket.csv` participants as ties confirm.
   - Update `top_scorers.csv` goal tallies.
2. **Refresh research** in `input_data/researched_info/`: add injury/suspension/
   form news to the notes **and** the `*_adjustments.csv` files (the model only
   reads the CSVs).
3. Set `"current_stage"` in `tournament_state.json` to the stage you’re predicting.
4. Re-run:

```bash
Rscript update_and_run.R
```

This merges staged results, re-derives ratings from priors + **all** known
results (idempotent), re-simulates, and **overwrites** predictions and the stage
report — while the report’s original **creation date is retained** (run date is
also shown). Ratings shrink toward priors early and trust the data more as games
accumulate (`weight ≈ n/(n+K)`).

---

## 5. Methodology

1. **Strength** — each team starts from an Elo prior (`team_ratings_seed.csv`),
   adjusted by researched form/injury notes (`team_adjustments.csv`).
2. **Goal model** — a **Dixon-Coles bivariate Poisson** turns strength into a
   full scoreline distribution. Each team has an attack and a defense effect that
   scale with its (research-adjusted) Elo. Hosts (USA/Mexico/Canada) get a home
   bump. When ≥10 results exist, a **ridge-penalised Poisson fit** refines the
   effects, shrinking toward the priors.
3. **Simulation** — a **Monte Carlo** plays the bracket thousands of times.
   Knockout ties resolve via regulation → extra time (reduced expected goals) →
   strength-tilted penalty shootout. Aggregating gives each team’s probability of
   reaching every stage. A pairwise advancement matrix is precomputed so the sim
   is fast.
4. **Top scorers** — each team’s expected goals are shared among its players
   (`goal_share_prior` × researched form × availability) and weighted by how far
   the team is projected to advance → per-stage and Golden Boot forecasts.
5. **Recommendations** — picks ranked by probability/expected value, with a
   short strategy note. Tune the model in `model/config.R` and
   `historical_params.csv`.

---

## 6. Data provenance & honesty

This repo ships a **snapshot compiled 2026-06-26** from public reporting. Rows
carry a `source` column so verified facts are distinguishable from placeholders:

- **Verified** — the 12-group draw, reported group winners, Round-of-32 anchor
  ties, and Golden Boot tallies (`source = reported_2026-06-26`).
- **Analyst priors** — team Elo ratings (`team_ratings_seed.csv`).
- **Projected / illustrative** — not-yet-confirmed bracket slots
  (`source = projected`) and unplayed scores. `results.csv` ships **empty** by
  design — populate it with official scores.

See `input_data/researched_info/sources.md`. **Always refresh with official data
before relying on predictions.**

### Not-yet-finalised R32 ties

The bracket is treated as a fixed **input** you update as ties confirm — the
knockout sim simulates *results*, not *participants*. To keep this honest while
the group stage finishes:

- Every R32 tie is tagged **Confirmed** (locked from reported results) or
  **Projected** (model-estimated participants) in
  `match_predictions_<stage>.csv` and on the report's match-predictions page
  (Projected ties are marked `*` with an explanatory footnote).
- If you blank a tie's `home_team`/`away_team` in `knockout_bracket.csv`, the
  sim fills it with the **most-likely** team for that slot (`W_x` / `RU_x` /
  third-place pool) from the group projection, rather than silently dropping the
  match. Once the real matchup is known, enter it and re-run to lock it in.

---

## 7. Refreshing from live sources

The build environment used to author this had no access to football data sites,
so the snapshot was compiled via web-search summaries. When you run locally with
internet access, the system is fully CSV-driven, so wiring in a feed is just a
matter of producing tidy CSVs that match the schemas above and dropping them in
`input_data/`. Convenient public sources:

- `football-data.co.uk` — historical results CSVs (for richer rating priors)
- `fixturedownload.com` — WC2026 fixtures CSV/JSON
- `fifa.com` standings / Golden Boot pages — current results & scorers

No code changes are required; see the header of `model/R/01_load_data.R`.

---

## 8. Requirements

- R ≥ 4.0 with base + recommended packages (`stats`, `MASS`, `grDevices`,
  `graphics` — all bundled with a standard R install). No CRAN downloads needed.
- Verify with: `Rscript -e 'cat(R.version.string)'`
