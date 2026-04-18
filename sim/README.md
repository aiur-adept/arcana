# Arcana Monte Carlo Simulator

A Python multiprocess Monte Carlo simulator that mirrors the GDScript match engine
(`arcana_match_state.gd`) and plays two deck-specialized pilots against each other.
Both sides of every game use the pilot registered for their deck slug (see
`sim/pilots/`), so matchup win-rates reflect each archetype executing its real
meta plan rather than the generic greedy fallback.

## Usage

```powershell
python -m sim.run --deck noble_test --runs 100000 [--seed 0] [--workers N]
```

- `--deck`: P0 deck slug. Must be listed in `included_decks/index.json`.
- `--runs`: total simulated games (default 100k).
- `--seed`: master RNG seed for reproducibility. Each worker seeds from this.
- `--workers`: override worker count; defaults to `os.cpu_count()`.

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
- Incantations: `seek`, `insight`, `burn`, `woe`, `wrath 4`, `revive 1`, `deluge
  2–4`, `tears 3`.
- `dethrone 4`.
- All 15 nobles (Krss/Trss/Yrss/Xytzr/Yytzr/Zytzr/Aeoiu + 5 Incantation nobles +
  3 Scions).
- All 5 temples, including Eyrie ETB bird search, Gotha draw-skip static,
  Delpha sac → burn → replay ritual, Ytria hand-cycle.
- Birds with cost/power catalog, bird-lane activation from wild-bird power sum,
  simple bird combat, and nesting into temples.
- All 5 rings (Sybiline/Cymbil/Celadon/Serraf/Sinofia): lane-2 cost, attach to a
  noble or un-nested bird, additive cost reductions (floor 0) on spells/units
  matching each ring's reductions, shed to crypt when the host is destroyed,
  and block nesting for any bird carrying a ring.
- Pending-response FIFO for Woe (opponent target), Eyrie (bird pick), and the
  three Scion triggers (Rmrsk/Smrsk/Tmrsk).
- Win at ≥20 match power or on empty-deck draw attempt; draw on ties and on the
  turn cap.

## Pilots

Per-deck pilots live in `sim/pilots/<slug>.py` and all subclass
`GreedyAI` from `sim/ai.py`. The base class exposes scoring weights as
class constants (`W_RITUAL_BASE`, `W_NOBLE_BIG_TRIPLET`,
`W_EFFECT_WRATH_PER_KILLED`, …) and decision hooks
(`mulligan`, `score_ritual_play`, `score_noble_play`,
`score_incantation`, `score_temple_play`, `score_dethrone`,
`adjust_ring_score`, `choose_wrath_targets`, `choose_revive_target`,
`choose_burn_target`, `choose_insight_bottom`, `should_nest`,
`scion_response`, `woe_response`, `end_turn_discards`, …). Each pilot
overrides only the hooks that differentiate its archetype:

| Slug | Pilot class | Key behavior |
|---|---|---|
| `incantations` | `IncantationsPilot` | 1R+2R mulligan; save Wrath 4 vs weak boards; revive prefers Woe/Wrath/Burn. |
| `noble_test` | `NobleTestPilot` | Serraf-first; Power-noble play priority; aggressive Dethrone targeting. |
| `wrathseek-sac` | `WrathseekSacPilot` | Wrath gets +12 play bonus and revives first; lowered sac penalty. |
| `ritual_reanimator` | `RitualReanimatorPilot` | Aeoiu priority; self-Burn to seed crypt rituals; Phaedra-on-full-hand bonus. |
| `topheavy_annihilator` | `TopheavyAnnihilatorPilot` | Refuses incantation sacs (preserves 1/2/3 ladder to keep lane 4 live); Zytzr-only Wrath sac exception. |
| `occultation` | `OccultationPilot` | Yytzr/Cymbil priority; Burn-base weights doubled; revive prefers Burn. |
| `annihilation` | `AnnihilationPilot` | Celadon ring priority; Wrath and Woe base weights elevated; always accept Tmrsk. |
| `emanation` | `EmanationPilot` | Sybiline priority; always accept Rmrsk; save Dethrone for cost-6+ targets. |
| `scions` | `ScionsPilot` | Scion + Serraf priority; Smrsk always declined, Tmrsk always accepted. |
| `temples` | `TemplesPilot` | Explicit Phaedra>Delpha>Gotha>Ytria play ordering; Ytria needs hand ≥ 5. |
| `bird_test` | `BirdTestPilot` | Eyrie bonus boosted; Sinofia homes to a Raven; Ravens/Hawks never nest. |
| `void_temples` | `VoidTemplesPilot` | Temple play ordering (see `temples`); Void discard-cost left at default (lowest among incantations). |
| `revive` | `RevivePilot` | Rndrr priority; revive prefers highest-value Seek/Insight. |

The registry is exposed via `sim.pilots.get_pilot(slug)` and a shared
`PILOTS` dict. Any slug not registered falls back to the base
`GreedyAI` (pure greedy behavior, untuned).

## Known simplifications

- Bird combat uses single-attacker / single-defender pairings rather than the
  general "pick two sets" ruling — the greedy AI never benefits from complex
  multi-target combats.
- Revive chain is single-cast (no Yytzr extra-sac step).
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
