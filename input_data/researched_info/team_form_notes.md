# WC2026 Research Notes — Team Form, Injuries, Suspensions

> Snapshot compiled **2026-06-26** from public reporting (see `sources.md`).
> Qualitative notes here are distilled into machine-readable model inputs in
> `team_adjustments.csv` and `player_adjustments.csv`. Update both when you refresh research.

## How to use this file
1. Add/curate notes per team below as the tournament progresses.
2. Translate anything that should move the model into a row in
   `team_adjustments.csv` (team strength / form) or `player_adjustments.csv`
   (availability + scoring form). The model only reads the CSVs, so a note
   without a CSV row has **no** effect on predictions — by design, to keep the
   model auditable.

## Title contenders
- **Argentina (J):** Messi in vintage form, leads Golden Boot (5). Efficient, experienced. Main risk: squad age in a hot-weather knockout run.
- **France (I):** Mbappé firing (4). Deepest attacking talent in the field; clear favourites by squad value.
- **Spain (H):** Yamal/Williams pace + Morata finishing. Balanced and deep.
- **Brazil (C):** Won group convincingly; Vinícius (4) and Raphinha sharp.

## Dark horses
- **Norway (I):** Haaland (4) dragging them; first WC in a generation — beatable defensively.
- **Morocco (C):** Elite defensive structure, 2022 pedigree; drawn to face Netherlands in R32.
- **USA / Mexico / Canada:** Host advantage is real (crowd, travel, familiarity) — encoded as +Elo and form bumps.

## Underperformers / fade risks
- **Belgium (G):** Limped through as a third-place qualifier; aging spine.
- **England (L):** Won group but flat; Kane on only 2.

## Injuries / suspensions watchlist
- _None confirmed as of snapshot._ Add here as news breaks, then set the player's
  `availability` (0 = out, 1 = full) and/or `form_multiplier` in
  `player_adjustments.csv`, and apply a team `elo_adjustment` if a key absence
  materially weakens a side.

## Knockout-specific factors
- Extra time and penalty shootouts matter from R32 onward — the model simulates
  ET (reduced expected goals) and strength-tilted shootouts (see `historical_params.csv`).
- Penalty takers flagged in `player_pool.csv` (`penalty_taker = 1`) get a small
  expected-goals bump in knockout simulations.
