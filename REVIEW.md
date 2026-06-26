# Code Review — WC2026 Prediction System

A critical review of the base-R FIFA World Cup 2026 prediction pipeline: correctness,
robustness, and simplification. Every finding below was verified by reading the source
directly (not just an automated sweep); claims that did not survive that check are listed
under **Rejected claims** so they aren't re-raised later.

This review changes **no source code** — it is a recommendations document only.

---

## Use case (as built)

`Rscript run.R` → fetch live results from fixturedownload.com → upsert `results.csv` →
derive idempotent ridge-shrunk Poisson team ratings → Monte Carlo the group stage and the
knockout bracket → forecast top scorers → emit one base-`pdf()` report per stage. Base R
only (no CRAN); PDF via `grDevices::pdf()`.

The predictions are consumed **in the gap between one stage ending and the next beginning**
(e.g. after R32 is complete, before R16 starts). That usage context matters for how to read
finding **A** below.

---

## Findings

Severity: 🔴 material · 🟡 robustness · ⚪ cleanup.

### A. 🔴→🟡 Played knockout results don't constrain the progression simulation
**`model/R/04_simulate.R:225-247` (`simulate_knockout`).**
Every run re-simulates the whole bracket from R32 using win-probabilities (`A[h,a]` +
`runif`). It never locks an already-played knockout result:
- R32 teams come from `bracket$home_team/away_team`, but the **outcome** is always
  re-randomised — so a team eliminated in R32 still shows a non-zero champion %.
- R16+ matchups always resolve via `resolve()` of **simulated** winners (lines 232-234);
  actual results, or manually-populated R16+ team names, are ignored.

**Re-framed against the stated usage (important):**
- The **next-stage match predictions** you actually act on — `model/R/06_recommendations.R`
  → `match_predictions`, computed by `match_probs()` on the real bracket teams — are
  **accurate and unaffected**, *provided* `knockout_bracket.csv` holds the real participants
  for the upcoming stage.
- Only the longer-range **progression / champion / deep-run** numbers in
  `progression_probabilities.csv` (and the depth-weighted Golden Boot) are distorted
  mid-knockout, because they re-randomise from R32.

**Verdict:** Low practical impact for the between-stages use case. Documented as a known
limitation, not fixed. If progression/champion odds are ever read mid-knockout, treat them as
"from R32 onward," not "from the current bracket state."

*If you later want to fix it:* read knockout finals from `results.csv` and force those
winners in the bracket walk instead of sampling them.

### B. 🟡 Penalty / extra-time detail is discarded on fetch
**`model/R/00b_fetch.R:219-234` and `.parse_score` (lines 40-48).**
`decided_by` is hardcoded to `"regular"` and `pens_home/pens_away` are set to `NA`.
`.parse_score` matches the **first** `X-Y` in the string, so `"0 - 0 (5-4 p)"` is stored as a
regulation 0-0 draw with no shootout winner recorded. Knockout decision detail is lost on
ingest. (Compounds A: even if knockout results were locked, the true winner of a penalty tie
isn't captured.)

### C. 🟡 Robustness gaps (low effort)
1. **`.confirm_bracket_ties` assumes a `source` column** —
   `model/R/00b_fetch.R:163-179` indexes `bracket$source[i]`. A `knockout_bracket.csv`
   without that column would error. Guard with a column-exists check.
2. **JSON write is brittle** — `model/R/00b_fetch.R:255-265` updates
   `tournament_state.json` via per-key `gsub`. If a key (`current_stage`, `as_of_date`,
   `last_updated`) is absent it's silently a no-op (not added), and a value with regex-special
   characters isn't escaped. Fine for the known file; at minimum log when a key isn't found.
   *(Note: the JSON **reader** in `01_load_data.R:58` is fine — it collapses lines first.)*
3. **`auto_detect_stage` uses exact quotas** — `model/R/00b_fetch.R:149-160` requires
   `group == 72` finals etc. A single never-finalised group match (postponement, missing row)
   pins the stage at `"group"` indefinitely. Consider a tolerance or `>=` semantics.

### D. ⚪ Simplifications / dead code (safe)
1. **`model/R/04_simulate.R:215`** — `stage_of_match` is computed but never used. Remove.
2. **`model/R/03_match_model.R:56-57`** — `exp_home`/`exp_away` are returned by
   `outcome_from_matrix()` but consumed nowhere. Remove, or comment why retained.
3. **`model/R/06_recommendations.R:54`** — `next_stage <- stages[match(current, stages)]` is
   an identity no-op that just returns the current stage (or the R32 fallback). Replace with
   the clearer `if (current %in% stages) current else "R32"`.
4. **`model/R/04_simulate.R:165-166`** — `pick_slot` re-filters `gp` inside the `order()`
   call; compute the candidate subset once for readability.
5. **`model/R/06_recommendations.R:84-94`** — `safe_pick` is used for 3 of 5 picks while
   `champion`/`finalists` are inlined. Make consistent (minor).

### E. ⚪ Defensive (optional — won't trigger on current data)
- **`model/R/07_report.R:138-145`** — if `scorer_projection`/`prog` were ever empty, the
  cover page prints `"NA (NA) - proj NA"` and `prog$team[1]` is `NA`. Add empty-input guards
  only if you want resilience to degenerate inputs; current data never hits this.

---

## Rejected claims (verified false — do not action)

These were surfaced by an automated pass and then disproven against the source. Listed so
they aren't re-investigated:

- **"Group tiebreaker ignores head-to-head / material bug."** `order(-pts, -gd, -gf, -tie)`
  in `04_simulate.R:34` matches FIFA's first three criteria exactly (points → goal difference
  → goals for). Only the rare final fallback (drawing of lots / fair play) is approximated by
  team strength. Acceptable.
- **"`stage_part` omits `third_place` → under-count."** There is no `reach_third_place`
  metric to under-count; third place is counted separately at `04_simulate.R:246`. Correct.
- **"globals `c`/`home` break idempotency."** They are anchored to priors via the ridge
  penalty (`02_ratings.R:89-90`); identical inputs produce identical output (seed = 2026).
- **"Poisson truncation bias at `max_goals = 8`."** The matrix is renormalised by
  `M / sum(M)` (`03_match_model.R:42`), so the truncated tail is redistributed. Fine.
- **"`.table` overflows the page / needs pagination."** Every caller caps rows with `head()`
  (≤16, the R32 case). No overflow occurs.
- **"Multi-line JSON breaks the reader."** `01_load_data.R:58` collapses lines with
  `paste(..., collapse = " ")` before matching. Works.
- **"`canon_team` has a duplicate entry."** `"Cote d'Ivoire"` (straight apostrophe) and
  `"Cote d’Ivoire"` (curly apostrophe) are distinct keys; both are needed.
- **"`confirmed_advancer_set` lacks a partial-completion guard."** It explicitly restricts
  standings to `complete` groups (`06_recommendations.R:29-36`) and only locks thirds when
  every group is done. Correct.

---

## How to verify (if any of the above is later implemented)

- **Offline smoke test:** `WC2026_NSIMS=500 Rscript run.R --no-fetch`, then inspect
  `outcomes/predictions/*.csv` and render the PDF.
- **Finding A:** stage a played R32 result in `results.csv`, re-run, and confirm the losing
  team's `champion`/`reach_*` in `progression_probabilities.csv` drop to 0.
- **Idempotency:** run twice and diff `outcomes/predictions/` — output should be identical
  (seed fixed at 2026 in `config.R`).
