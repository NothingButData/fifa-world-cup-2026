# FIFA World Cup 2026 — Prediction System

A prediction tool for the 2026 World Cup built for a Scorito-style fantasy game.
It pulls in live match results, estimates how strong each team is, and works out
the most likely outcomes for every remaining match and stage — then produces a
PDF report with the picks you need.

You run one command, get a PDF. That's the workflow.

---

## 1. What you get

Every run produces a PDF report and a set of CSV files in `outcomes/`:

| What | File |
|------|------|
| Who wins each upcoming match, most likely scoreline | `outcomes/predictions/match_predictions_<stage>.csv` |
| Each team's chance of reaching the quarters, semis, final, winning it | `outcomes/predictions/progression_probabilities.csv` |
| Group stage predictions (who wins each group, who advances) | `outcomes/predictions/group_projection.csv` |
| Golden Boot prediction (projected total goals per player) | `outcomes/predictions/golden_boot_projection.csv` |
| Top scorer picks broken down by stage | `outcomes/predictions/stage_top_scorers.csv` |
| **The PDF report** | `outcomes/reports/WC2026_<stage>_report.pdf` |

The PDF is the main deliverable. Open it after each run to see all picks in one place.

---

## 2. How to run it

There is **one script** for everything — first run, daily refresh, or stage update:

```bash
# Normal run (fetches latest results from the web, then generates predictions):
Rscript run.R

# Run for a specific stage (e.g. if you want R16 predictions before R32 finishes):
Rscript run.R R16

# Run without internet access (uses whatever data you already have):
Rscript run.R --no-fetch

# Force a completely fresh start (clears all output files, then re-runs):
Rscript run.R --clean

# Combine flags as needed:
Rscript run.R --clean --no-fetch R16

# Quick test run (fewer simulations, finishes in seconds):
WC2026_NSIMS=500 Rscript run.R --no-fetch
```

**When to use `--clean`:** if the output files look wrong or you've made big
changes to the input data and want everything recalculated from scratch. It only
deletes the `outcomes/` folder — your match data and settings are never touched.

> **To also wipe match results** (full reset, rare): run this first, then `Rscript run.R`:
> ```bash
> head -1 input_data/wc2026_outcomes/results.csv > /tmp/r.csv && mv /tmp/r.csv input_data/wc2026_outcomes/results.csv
> ```

---

## 3. Keeping it up to date

Every time you run `run.R`, it automatically:

1. **Fetches the latest results** from fixturedownload.com and updates the match
   results file
2. **Works out which stage you're on** based on how many matches have been played
3. **Recalculates everything** — team strengths, match predictions, progression
   odds, top scorer forecasts
4. **Writes the PDF report** (the original creation date is kept; the run date
   is also shown)

So for most of the tournament, you just run `Rscript run.R` and you're done.

**What still needs a manual update after each round:**

| What to update | File to edit | Why it's manual |
|---|---|---|
| Goal tallies (Golden Boot) | `input_data/wc2026_outcomes/top_scorers.csv` | No clean data feed available |
| Injury / suspension news | `input_data/researched_info/team_adjustments.csv` | Needs judgement, not just data |
| Player availability | `input_data/researched_info/player_adjustments.csv` | Same |

**If the web fetch misses something** (e.g. penalty shootout details), you can
correct it manually: create a file called `results_update.csv` in the same
folder as `run.R`, using the same columns as `results.csv`, and drop in the
corrected rows. The next run will merge them in and archive the file automatically.
Your manual corrections always override what was fetched from the web.

---

## 4. Folder structure

```
input_data/               ← YOUR DATA (never auto-deleted)
├── researched_info/      ← analyst notes and adjustments
│   ├── team_adjustments.csv     ← team strength tweaks + form multipliers
│   └── player_adjustments.csv  ← player availability and form
├── historical_stats/     ← starting strength estimates and model settings
│   ├── team_ratings_seed.csv    ← each team's pre-tournament strength score
│   ├── historical_params.csv    ← model tuning knobs (goals, home advantage…)
│   └── player_pool.csv          ← each player's typical goal-scoring share
└── wc2026_outcomes/      ← live tournament data (updated each run)
    ├── results.csv              ← all match scores played so far
    ├── knockout_bracket.csv     ← who's playing who in the knockout rounds
    ├── top_scorers.csv          ← current Golden Boot standings
    └── tournament_state.json    ← which stage we're currently predicting

model/                    ← the R code (you don't need to touch this)

outcomes/                 ← GENERATED OUTPUT (safe to delete, re-created each run)
├── predictions/          ← CSV prediction files
└── reports/              ← PDF reports
```

---

## 5. How it works (plain English)

**Step 1 — Team strength scores**
Every team starts with a strength score based on their FIFA ranking and recent
international results (stored in `team_ratings_seed.csv`). You can manually
boost or reduce any team's score in `team_adjustments.csv` — for example, if a
key player is injured or a team is on a strong run of form that isn't yet
reflected in the rankings.

**Step 2 — Match predictions**
Given two team strength scores, the model works out how many goals each side
is likely to score — and from that, the probability of every possible scoreline
(0-0, 1-0, 1-1, etc.). Home nations (USA, Mexico, Canada) get a small boost
when playing at their own venues. Once enough real matches have been played,
the model updates its estimates using the actual scores, but doesn't
overreact to small samples — early results nudge the estimates, they don't
override them.

**Step 3 — Tournament simulation**
The model plays out the entire remaining tournament thousands of times, each
time drawing random results according to the match probabilities. It counts
how often each team wins, reaches the final, etc. The percentages you see in
the report are simply how often each outcome happened across all those runs.
For knockout matches that go to extra time or penalties, those are modelled
too.

**Step 4 — Top scorer forecasts**
Each player has a historical share of their team's goals. The model multiplies
their team's expected goals by that share, adjusted for current form and
availability, and then by how far the team is likely to advance. Players on
strong teams that go deep in the tournament come out on top.

**Step 5 — Picks and report**
The best bets are ranked by confidence. The PDF shows match predictions (with
a "Confirmed" or "Projected" label if the fixture isn't officially announced
yet), progression probabilities, top scorer forecasts, and a short strategy note.

---

## 6. What's confirmed vs projected

Not all bracket matchups are finalised before you need to make picks.
The report is transparent about this:

- **Confirmed** — the matchup is official (locked from published results)
- **Projected** — the model's best guess at who will be in that slot, based
  on the group stage probabilities

Projected fixtures are marked with `*` in the report. Once a fixture is
officially announced, update `knockout_bracket.csv` and re-run to lock it in.

Every `source` column in the data files tracks where each piece of
information came from (`reported_YYYY-MM-DD` = verified, `projected` = estimated).

---

## 7. Requirements

- **R version 4.0 or later** with a standard installation. No extra packages
  needed — everything uses built-in R tools.
- Check your version: `Rscript -e 'cat(R.version.string)'`
- Internet access is needed for the web fetch step (fixturedownload.com).
  Run with `--no-fetch` if you're offline.
