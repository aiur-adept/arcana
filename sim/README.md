# Arcana Monte Carlo Simulator

A Python multiprocess Monte Carlo simulator that mirrors the GDScript match engine
(`arcana_match_state.gd`) and plays two deck-specialized pilots against each other.
Both sides use the pilot registered for their deck slug (see `sim/pilots/`), optionally
overlaid with **trained floats** from `data/pilot_weights.json`, so matchups reflect
each archetype's plan rather than a single generic greedy policy.

## `sim.run` — one deck vs the field

```powershell
python -m sim.run --deck noble_test --runs 100000 [--seed 0] [--workers N]
```

- `--deck`: P0 deck slug (must appear in `included_decks/index.json`).
- `--runs`: total games for that P0; P1 deck is sampled uniformly each game.
- `--seed`, `--workers`: reproducibility and process count (`workers` defaults to CPU count).

To use **saved weights** (same JSON as Godot), add `--use-saved-weights`. For each slug,
if `weights_by_slug` has an entry, the sim builds a weighted `GreedyAI` subclass; otherwise
it uses the hand-tuned pilot class. Optional: `--weights path/to/pilot_weights.json`.

## `sim.meta` — full matchup matrix

Runs every included deck as P0 with the same shard/merge pipeline as `sim.run`, then writes a CSV
whose cell `(row, col)` is **expected match points for the column deck as P1** vs the row deck as P0,
using Swiss-style scoring **3 / 1 / 0** (win / draw / loss from the column player’s perspective).

```powershell
python -m sim.meta --runs 100000 --seed 42 [--out sim_meta_matrix.csv] [--use-saved-weights] [--workers N]
```

Optional `--games-out path.csv` writes per-cell sample sizes. See `sim/meta.py` for details.

## `sim.train_ea` — evolve pilot weights

Evolves all **float** class attributes on `GreedyAI` (see `sim.pilot_weights.greedy_ai_float_weight_keys`)
for one P0 deck and **merges** the best genome into `data/pilot_weights.json` (schema in
[`ea_pilot_training_implementation_guide.md`](../ea_pilot_training_implementation_guide.md) §6).
Godot loads the same file via `ArcanaCpuPilotRegistry.create_for_slug`.

```powershell
python -m sim.train_ea --deck bird_flock --generations 30 --population 24 --games 400 [--seed 0] [--workers N]
```

**Core flags**

- `--deck` (required), `--generations`, `--population`, `--games` (games **per genome per generation**).
- `--sigma`, `--sigma-floor`, `--sigma-decay`, `--tournament-k`.
- `--out`: JSON path; default `data/pilot_weights.json` under the repo root.

**Population initialization**

- `--init-spread`: multiplier on the Gaussian init sigma (default `1.0`).
- `--init-uniform-fraction`: fraction of individuals drawn uniformly in `[baseline ± δ]` per gene.
- `--init-uniform-delta`: half-width for that uniform draw; if `0`, uses `3 * --sigma`.

**Opponents during fitness**

- Default: P1 uses **baseline** `get_pilot(p1_slug)` (code defaults, no JSON).
- `--p1-trained-weights`: P1 uses `pilot_class_for_slug` against a **snapshot** JSON that merges
  `--out` with the **best-so-far** genome for the training slug after each generation.
- `--p1-snapshot`: path for that snapshot (default: `%TEMP%/arcana_ea_p1/<deck>.json`, i.e. outside
  synced `data/`, which avoids OneDrive permission errors on hidden files under `data/`).

Evaluation uses `sim.ea_eval.evaluate_genome` (same `_play_one_game` loop as `sim.run`). Fitness is
`(p0_wins + 0.5 * draws) / games`. Worker entry points live in `sim/ea_eval.py` for Windows-friendly
multiprocessing.

## What it does

1. Loads all decks from `included_decks/*.json` listed in `index.json`.
2. Spawns one worker process per CPU core and gives each worker `runs / workers`
   games to play.
3. Each game: shuffle, London-mulligan heuristic, random first player, then
   greedy AI pilots both sides until somebody hits 20 match power, decks out, or
   a 400-turn safety cap fires.
4. Each shard folds its games into a per-opponent bucket keyed by the P1 deck
   slug; the parent merges shards with elementwise sums.
5. Accounting invariants are asserted on the merged aggregate before reporting.
6. Reports per-opponent win/loss/draw table, match-power progression, and
   final-power histograms for P0 and P1.

## Modeled mechanics

All of Set 1 per `design_document.md` is implemented:

- Rituals 1–4 with the standard active-lane chain (value N active iff all k<N have
  an active ritual or lane-granting noble).
- Incantations: `seek`, `insight`, `burn`, `woe`, `wrath`, `revive 1`, `deluge
  2–4`, `tears 3`, `flight 3`.
- `dethrone 4`.
- All 15 nobles (Krss/Trss/Yrss/Xytzr/Yytzr/Zytzr/Aeoiu + 5 Incantation nobles +
  3 Scions).
- All 5 temples, including Eyrie ETB bird search
  bonus, Gotha draw-skip static,
  Delpha sac → burn → replay ritual, Ytria hand-cycle.
- Birds with cost/power catalog, bird-lane activation from wild-bird power sum,
  simple bird combat, and nesting into temples.
- All 5 rings (Sybiline/Cymbil/Celadon/Serraf/Sinofia): lane-2 cost, attach to a
  noble or wild bird, additive cost reductions (floor 0) on spells/units
  matching each ring's reductions, shed to crypt when the host is destroyed,
  and block nesting for any bird carrying a ring.
- Pending-response FIFO for Woe (opponent target), Eyrie (bird pick), and the
  three Scion triggers (Rmrsk/Smrsk/Tmrsk).
- Win at ≥20 match power or on empty-deck draw attempt; draw on ties and on the
  turn cap.

## Pilots

Per-deck pilots live in `sim/pilots/<slug>.py` and all subclass
`GreedyAI` from `sim/ai.py`. The base class exposes a large set of tunable **floats**
(evolved by EA when present on the class), including play scoring (`W_*` / `INC_*` / `SAC_*`),
discard and discard-draw helpers (`DD_*`), ring savings (`W_RING_SAVE_*`), temple activation
slopes (`W_TEMPLE_*` …), revive verb priorities (`W_REVIVE_PRIO_*`), and optional state
“sensor” terms (`W_SF_*`, default `0`). It also provides decision hooks
(`mulligan`, `score_ritual_play`, `score_noble_play`,
`score_temple_play`, `score_dethrone`,
`adjust_incantation_score`, `adjust_ring_score`, `choose_wrath_targets`, `choose_revive_target`,
`choose_burn_target`, `choose_insight_bottom`, `should_nest`,
`scion_response`, `woe_response`, `end_turn_discards`, …). Each pilot
overrides only the hooks (and selectively overrides weight defaults) that matter for its archetype:

| Slug | Pilot class | Key behavior |
|---|---|---|
| `incantations` | `IncantationsPilot` | 1R+2R mulligan; save Wrath vs weak boards; revive priorities via `W_REVIVE_PRIO_*` (Woe/Wrath/Burn biased). |
| `noble_test` | `NobleTestPilot` | Serraf-first; Power-noble play priority; aggressive Dethrone targeting. |
| `ritual_reanimator` | `RitualReanimatorPilot` | Aeoiu priority; self-Burn to seed crypt rituals; Phaedra-on-full-hand bonus. |
| `topheavy_annihilator` | `TopheavyAnnihilatorPilot` | Refuses incantation sacs (preserves 1/2/3 ladder to keep lane 4 live); Zytzr-only Wrath sac exception. |
| `occultation` | `OccultationPilot` | Yytzr/Cymbil priority; Burn-base weights doubled; revive prio favors Burn. |
| `annihilation` | `AnnihilationPilot` | Celadon ring priority; Wrath and Woe base weights elevated; always accept Tmrsk. |
| `emanation` | `EmanationPilot` | Sybiline priority; always accept Rmrsk; save Dethrone for cost-6+ targets. |
| `temples` | `TemplesPilot` | Explicit Phaedra>Delpha>Gotha>Ytria play ordering; Ytria needs hand ≥ 5. |
| `bird_flock` | `BirdTestPilot` | Eyrie bonus boosted; Sinofia homes to a Raven; Ravens/Hawks never nest. |
| `void_temples` | `VoidTemplesPilot` | Temple play ordering (see `temples`); Void discard-cost left at default (lowest among incantations). |
| `revive` | `RevivePilot` | Rndrr priority; revive prio favors Seek/Insight over other verbs. |

The registry is exposed via `sim.pilots.get_pilot(slug)` and a shared
`PILOTS` dict. Any slug not registered falls back to the base
`GreedyAI` (pure greedy behavior, untuned).

## Known simplifications

- Bird combat uses single-attacker / single-defender pairings rather than the
  general "pick two sets" ruling — the greedy AI never benefits from complex
  multi-target combats.
- Revive chain is single-cast (no Yytzr extra-sac step). The **Yytzr Renew**
  bonus (second ritual from crypt after sacrifice) is implemented in Godot only;
  Renew in sim still plays a single ritual.
- Insight reordering picks "send N to bottom" only; it does not attempt to
  permute the top stack. The AI uses this to bottom known-useless cards from
  the opponent.
- Mulligan heuristics live on each pilot; the base default is the same
  ritual-count heuristic as before.
- The 400-turn cap is not in the rules; it guards against pathological stalls.
- **Void is not modeled.** `VERB_VOID` is declared in `sim/cards.py` but the
  engine has no effect handler for it, so Void cards sit dead in hand. This
  structurally under-powers `void_temples`; matchup numbers for that deck
  should be read as a lower bound relative to the real meta.

## Per-slug accounting

Each worker returns a dict keyed by `p1_slug`, with an identical schema produced
by `_empty_bucket()`. Fields are integers or lists of integers; merging shards
is an elementwise `+=`. After merging, the runner asserts:

- `p0_wins + p1_wins + draws == games` per bucket.
- `sum(end_reason_counts.values()) == games` per bucket.
- `sum(final_power_hist_p0) == games` per bucket (same for P1).
- `Σ games == total_runs` globally.

If any invariant is violated the runner fails loudly before printing.
