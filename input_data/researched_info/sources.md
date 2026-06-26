# Research Sources & Data Provenance

Snapshot date: **2026-06-26**

## What is verified vs. illustrative
| Data | Status | Where |
|------|--------|-------|
| 12 group compositions (48 teams) | **Verified** (official draw, 2025-12-05) | `groups.csv`, `team_ratings_seed.csv` |
| Golden Boot leaders & goal tallies | **Verified** (reporting, 2026-06-26) | `top_scorers.csv`, `player_pool.csv` |
| Reported group winners / R32 anchor ties | **Verified** (reporting, 2026-06-26) | `knockout_bracket.csv` (`source=reported_*`) |
| Some R32 ties + all R16→Final pairings | **Projected** (model/bracket tree) | `knockout_bracket.csv` (`source=projected` / `bracket_tree`) |
| Team Elo priors | **Analyst priors** (≈ mid-2026 FIFA ranking + form) | `team_ratings_seed.csv` |
| Individual group match scores | **Not populated** — seed via model or refresh with official scores | `results.csv` |

## Primary sources consulted (2026-06-26)
- FIFA official — World Cup 2026 standings, brackets, Golden Boot tracker (fifa.com)
- Wikipedia — 2026 FIFA World Cup, draw, and knockout-stage pages
- ESPN / NBC Sports / Sky Sports / Yahoo Sports / FOX Sports — standings, bracket, schedule
- Olympics.com / CBS Sports — Round of 32 schedule and seeding

## How to refresh (each tournament stage)
1. Update `wc2026_outcomes/results.csv` with official scores (status=final).
2. Update `wc2026_outcomes/knockout_bracket.csv` participants as ties confirm.
3. Update `wc2026_outcomes/top_scorers.csv` with the latest goal tallies.
4. Add any injury/suspension/form news to `researched_info/*` (notes + CSV rows).
5. Re-run `Rscript update_and_run.R` (see project README).

> Network note: this build environment cannot reach football data sites directly,
> so the live snapshot was compiled via web search summaries. When you run locally
> with internet access, `model/R/01_load_data.R` documents optional CSV import
> endpoints (e.g. football-data.co.uk, fixturedownload.com) you can wire in.
