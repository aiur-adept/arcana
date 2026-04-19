# EA pilot training — implementation guide

This document guides implementation of evolutionary training for AI pilot parameters using the Python `sim/` harness, with a path to sync results into Godot `cpu/pilots/`.

---

## 1. Purpose and non-goals

**Purpose (v1):** Evolve a vector of floating-point weights that parameterize the greedy scorer (`GreedyAI` in `sim/ai.py`) for a **single chosen deck slug** at a time, while keeping that deck’s pilot **hooks** (mulligan, `score_*` overrides, ring bonuses, etc.) unchanged unless explicitly extended.

**In scope:**

- Training runs entirely in Python against `sim.match.MatchState` and `sim.run._play_one_game`.
- Population-based search with mutation, selection, and optional crossover.
- Export of trained weights as a JSON manifest for Godot.

**Non-goals (v1):**

- Evolving discrete strategy code (when to mulligan beyond weight-driven scoring) or neural policies.
- Joint evolution of **both** players’ policies (non-stationary self-play) unless explicitly justified.
- Perfect parity with Godot for mechanics not modeled in sim (e.g. `VERB_VOID` — see `sim/README.md` and `cpu/cpu_base.gd` header).

---

## 2. Parameter inventory

### 2.1 Shared base weights (`GreedyAI` / `ArcanaCpuBase`)

These names are identical between [`sim/ai.py`](sim/ai.py) and [`cpu/cpu_base.gd`](cpu/cpu_base.gd). Defaults below are the `GreedyAI` class defaults.

| Name | Default | Role (summary) |
|------|---------|------------------|
| `W_RITUAL_BASE` | 10.0 | Base score for playing a ritual |
| `W_RITUAL_VALUE_BONUS` | 1.0 | × ritual value |
| `W_RITUAL_NEW_LANE` | 60.0 | Bonus when play opens a new lane |
| `W_RITUAL_DUP_LANE_1` | -4.0 | Penalty for duplicate lane-1 value |
| `W_NOBLE_BASE` | 60.0 | Base score for nobles |
| `W_NOBLE_COST_BONUS` | 1.0 | × noble cost |
| `W_NOBLE_GRANT_NEW_LANE` | 40.0 | Bonus when noble grants a new lane |
| `W_NOBLE_BIG_TRIPLET` | 20.0 | Boost for xytzr/yytzr/zytzr static |
| `W_BIRD_BASE` | 15.0 | Base score for birds |
| `W_BIRD_POWER_BONUS` | 1.0 | × bird power |
| `W_TEMPLE_BASE` | 55.0 | Base score for temples |
| `W_TEMPLE_COST_BONUS` | 1.0 | × temple cost |
| `W_TEMPLE_EYRIE_BONUS` | 30.0 | Eyrie-specific bias |
| `W_RING_BASE` | 18.0 | Base score for rings |
| `W_DETHRONE_BASE` | 40.0 | Dethrone base |
| `W_DETHRONE_PER_COST` | 3.0 | × cost for dethrone |
| `SAC_PENALTY_PER_RITUAL` | 2.0 | Base penalty per ritual sacrificed (count multiplier) |
| `SAC_W_FIELD_POWER` | 0.0 | × sum of ritual values on our field (adds to sac penalty; train negative to resist sacing a heavy board) |
| `SAC_W_HIGH_RITUAL` | 0.0 | × max ritual value on our field |
| `INC_BASE_BONUS` | 5.0 | Bonus when casting incantations on-lane |
| `W_NOBLE_ACTIVATION` | 30.0 | Noble activation ability |
| `W_NOBLE_ACTIVATION_DISCARD_PENALTY` | 8.0 | Penalty when activation costs discard |
| `W_AEOIU_ACTIVATION_BASE` | 45.0 | Aeoiu activation base |
| `W_TEMPLE_PHAEDRA_ACT` | 38.0 | Phaedra temple activation |
| `W_TEMPLE_DELPHA_ACT_BASE` | 25.0 | Delpha activation |
| `W_TEMPLE_GOTHA_ACT_BASE` | 20.0 | Gotha activation |
| `W_TEMPLE_YTRIA_ACT_BASE` | 25.0 | Ytria activation |
| `W_NEST_BASE` | 8.0 | Nesting birds |
| `W_FIGHT_KILL_BASE` | 4.0 | Bird combat |
| `W_DISCARD_DRAW` | 3.0 | Bias for the discard-then-draw main-phase action |
| `DD_W_FIELD_CONTRIB` | 0.0 | × `_card_discard_score` of the worst card (keep-affinity; negative values make discard-draw worse when the bin target is “good”) |
| `DD_W_CARD_COST` | 0.0 | × card cost (ritual/incant value, noble/temple/bird cost, ring lane cost) for that same worst card |
| `W_EFFECT_SEEK_BASE` | 8.0 | Seek effect base |
| `W_EFFECT_SEEK_VALUE` | 3.0 | × seek value |
| `W_EFFECT_INSIGHT_BASE` | 4.0 | Insight effect base |
| `W_EFFECT_INSIGHT_VALUE` | 1.0 | × insight value |
| `W_EFFECT_BURN_BASE` | 2.0 | Burn effect base |
| `W_EFFECT_BURN_VALUE` | 1.0 | × burn value |
| `W_EFFECT_WOE_BASE` | 5.0 | Woe effect base |
| `W_EFFECT_WOE_PER_DISCARD` | 3.0 | × discards per woe |
| `W_EFFECT_WRATH_BASE` | 10.0 | Wrath effect base |
| `W_EFFECT_WRATH_PER_KILLED` | 2.5 | × rituals killed |
| `W_EFFECT_REVIVE_BASE` | 12.0 | Revive effect base |
| `W_EFFECT_DELUGE_BASE` | 5.0 | Deluge base |
| `W_EFFECT_DELUGE_PER_NET` | 4.0 | × net cards |
| `W_EFFECT_TEARS_BASE` | 10.0 | Tears base |

**Structured (non-float) genes:**

| Name | Type | Notes |
|------|------|--------|
| `REVIVE_VERB_PRIORITY` | `dict[str, int]` | Verb → priority for revive-from-crypt targets. Base defaults in `sim/ai.py`. |
| `REVIVE_PICK_VERB_PRIORITY` | `dict[str, int]` | Present in Python `GreedyAI` only; **not** mirrored in [`cpu/cpu_base.gd`](cpu/cpu_base.gd). |

**v1 recommendation:** Evolve **only the float weights** above. Keep `REVIVE_VERB_PRIORITY` at per-pilot class defaults (or copy from `get_pilot(slug)`). Optionally add integer-gene support later (ordinal constraints on verbs).

### 2.2 Per-pilot class weight overrides (`sim/pilots/*.py`)

| Slug | Weight overrides |
|------|------------------|
| `bird_test` | `W_TEMPLE_EYRIE_BONUS=50`, `W_BIRD_POWER_BONUS=2` |
| `emanation` | `W_EFFECT_SEEK_VALUE=4`, `W_EFFECT_INSIGHT_VALUE=2` |
| `noble_test` | `W_NOBLE_BASE=75`, `W_NOBLE_GRANT_NEW_LANE=55`, `W_DETHRONE_PER_COST=5` |
| `wrathseek-sac` | `SAC_PENALTY_PER_RITUAL=1` |
| `ritual_reanimator` | `W_AEOIU_ACTIVATION_BASE=70`, `W_TEMPLE_BASE=65`, `W_NOBLE_BIG_TRIPLET=25` |
| `topheavy_annihilator` | `W_NOBLE_BIG_TRIPLET=40` |
| `occultation` | `W_NOBLE_BIG_TRIPLET=55`, `W_EFFECT_BURN_BASE=4`, `W_EFFECT_BURN_VALUE=2` |
| `annihilation` | `W_NOBLE_BIG_TRIPLET=55`, `W_EFFECT_WOE_PER_DISCARD=4.5`, `W_EFFECT_WRATH_PER_KILLED=3.2` |
| `scions` | `W_NOBLE_BASE=70` |
| `temples` | `W_TEMPLE_BASE=55`, `W_TEMPLE_COST_BONUS=0` |
| `void_temples` | `W_TEMPLE_COST_BONUS=0`, `W_TEMPLE_EYRIE_BONUS=35` |

Pilots with **only** `REVIVE_VERB_PRIORITY` overrides (no float changes): `incantations`, `wrathseek-sac`, `revive` (custom dict).

### 2.3 Hook literals and non-vector behavior (classification)

| Tag | Meaning |
|-----|---------|
| **Frozen** | Logic only; no numeric literal exposed as a gene in v1. |
| **Parameterize later** | Replace hardcoded `score += X` with a named constant or genome slot in a future iteration. |

| Pilot | Item | Tag |
|-------|------|-----|
| `ritual_reanimator` | `+50` Aeoiu noble play, `+15` Phaedra with hand ≥4 | Parameterize later |
| `noble_test` | `+25` power nobles, `+25` Serraf ring | Parameterize later |
| `occultation` | `+15` Cymbil ring, `+30` Aeoiu noble | Parameterize later |
| `annihilation` | `+20` Celadon ring; `wrath_score_adjust` +10 if Zytzr | Parameterize later |
| `wrathseek-sac` | `+12` on Wrath incantation score; `wrath_score_adjust` +6 | Parameterize later |
| `incantations` | `wrath_score_adjust` −20 / +4 | Parameterize later |
| `scions` | `+15` scion nobles, `+22` Serraf ring | Parameterize later |
| `emanation` | `+25` Sybiline ring; `score_dethrone` gate `cost < 6` | Frozen / Parameterize later |
| `temples` / `void_temples` | `TEMPLE_PLAY_PRIORITY` dict adds to `score_temple_play` | Parameterize later (separate dict genes) |
| `topheavy_annihilator` | Custom `_score_incantation` (no sac except Wrath+Zytzr case) | Frozen (structural) |

**Extended genome (optional):** For a pilot that plateaus with base weights only, add **bonus slots** for that archetype’s literals (e.g. `BONUS_AEOIU_NOBLE`) rather than mixing all pilots into one global vector.

---

## 3. Fitness and evaluation protocol

### 3.1 Opponent model

| Option | Pros | Cons |
|--------|------|------|
| **A. Fixed greedy P1** — sample `p1_slug` uniformly from all included decks (`sim.run.run_shard` behavior) | Same as current Monte Carlo; one number summarizes “general strength”. | High variance; hard to interpret per-matchup. |
| **B. Stratified** — fixed games per opponent slug | Lower variance per archetype; easier debugging. | More games needed for total coverage. |
| **C. Self-play** — P1 also uses evolving genome | Can drift; interesting for research. | Non-stationary; not recommended for v1. |

**Recommended default:** **A** with **fixed P1 pilots** from `get_pilot(p1_slug)` (not evolving). Optionally add a **held-out** validation set: same protocol but different seed and no selection pressure.

### 3.2 Primary metric

- **Win rate:** `p0_wins / (p0_wins + p1_wins + draws)` or exclude draws from denominator if draws are rare.
- **Draws:** Treat as **0.5** win equivalent for a single scalar fitness, or **exclude** from fitness (only count decisive games). Document the choice; `sim` reports all three counts.

**Optional secondary terms** (multi-objective or weighted sum):

- Negative weight on mean `turns` (faster wins).
- Penalty weight on `end_reason == "turn_cap"` from `_play_one_game` result.
- Average `p0_final_power` on wins.

### 3.3 Sample size and variance

- Win rate from Bernoulli trials: standard error scales as `sqrt(p(1-p)/n)`. For rough 95% CI width ±0.01 on `p≈0.5`, order of **10k** decisive games per genome estimate; for noisy early search, **100–1k** games with **tournament selection** (compare relative rank, not absolute fitness).

**Common random numbers:** For comparing two genomes in the same generation, reuse the same opponent schedule and seeds (paired comparison) to reduce variance.

### 3.4 One-deck vs full roster

| Mode | Description |
|------|-------------|
| **Single slug** | Evolve weights for P0 = `slug` only; genome initialized from `get_pilot(slug)` class attributes. |
| **Full roster** | Separate population or separate genome per slug; much more compute. |

**Recommended default:** Single slug until pipeline is stable.

---

## 4. Evolutionary algorithm specification

### 4.1 Representation

- **Genome:** Ordered map `weight_name → float` for the chosen gene set (typically all shared floats in §2.1).
- **Bounds:** Lower/upper per gene (e.g. `W_RITUAL_DUP_LANE_1` may be negative; most bonuses non-negative). Clamp after mutation.
- **Optional:** Log-scale parameterization for wide ranges: store `x` where `w = exp(x)` for strictly positive weights.

### 4.2 Initialization

- Seed each individual by copying **defaults from the target pilot class** (`get_pilot(slug)`), then add Gaussian noise with small σ (e.g. 1–5% relative or absolute scale per gene).

### 4.3 Mutation

- Gaussian drift: `w' = w + N(0, σ_g)` per gene or shared σ.
- **Annealing:** Decrease σ over generations or when fitness plateaus.

### 4.4 Crossover (optional)

- **Uniform:** Each gene from parent A or B at random.
- **Blend:** `w = α * w_A + (1-α) * w_B` with α random or 0.5.

Pure mutation + selection is **valid** if crossover adds little for continuous weights.

### 4.5 Selection / survivor policy

| Method | Use case |
|--------|----------|
| **μ + λ** | Generate λ children from μ parents; select best μ for next generation. |
| **Truncation** | Keep top-k% by fitness. |
| **Tournament** | Pick k random; winner reproduces; good with noisy fitness. |

**Elitism:** Always copy the best 1 genome unchanged to avoid regression.

### 4.6 Stopping criteria

- Max generations **or** compute budget (wall time / total games simulated).
- Fitness improvement below ε for G consecutive generations.

### 4.7 Pseudocode

```text
Initialize population P from pilot(slug) defaults + noise
For gen = 1 .. G_max:
    For each individual i in P:
        fitness[i] = Evaluate(i)   # mean win rate over N games
    P_survivors = Select(P, fitness)
    P_next = Elitism(P_survivors)
    While |P_next| < pop_size:
        parents = Sample(P_survivors)
        child = Crossover(parents) if use_crossover else Copy(parents[0])
        child = Mutate(child, sigma)
        P_next.append(Clamp(child))
    P = P_next
Return best individual in P
```

### 4.8 Diversity (optional)

- Track pairwise L2 distance in genome space; if max distance < threshold, inject **random immigrants** or increase σ.

---

## 5. `sim/` integration and performance

### 5.1 Parameterized pilot factory

Current API: `get_pilot(slug)` returns `type[GreedyAI]` with class-level weights.

**Required pattern:** Build a **new subclass** per evaluation or per individual:

```python
def make_weighted_pilot(base_cls: type[GreedyAI], weights: dict[str, float]) -> type[GreedyAI]:
    return type("WeightedPilot", (base_cls,), {**{k: v for k, v in weights.items() if hasattr(base_cls, k)}})
```

Instantiate with `WeightedPilot(pid)` as today. Creating a fresh `type(...)` per genome avoids mutating shared class state across **multiprocessing** workers (each worker should construct its own subclass or copy weights into a fresh class).

**Thread-safety:** If workers reuse one process for many genomes, **never** assign `GreedyAI.W_*` on the base class; always use a dedicated subclass per genome evaluation.

### 5.2 Evaluation harness

- Reuse `sim.run._play_one_game` in [`sim/run.py`](sim/run.py) with arguments `(p0_deck, p1_deck, rng, p0_cls, p1_cls)`.
- Deck loading: [`sim.decks.load_all_included_decks`](sim/decks.py), [`included_deck_slugs`](sim/decks.py).
- Factor `evaluate_genome(weights, slug, n_games, seed_base) -> dict` returning wins, losses, draws, and optional aggregates from the game result dict.

### 5.3 Parallelism

- **Across individuals:** Each worker evaluates a batch of genomes in one generation (fewer IPC round trips).
- **Across games:** Within one genome, mirror `run_shard` with chunked RNG seeds (same as `sim.run`).

### 5.4 Reproducibility

- Log: `slug`, full weight dict, master seed, `n_games`, and list of `(p1_slug, game_seed)` if deterministic scheduling is used.

---

## 6. Export to `cpu/` and testing

### 6.1 Manifest format

```json
{
  "slug": "bird_test",
  "genome_version": 1,
  "weights": {
    "W_TEMPLE_EYRIE_BONUS": 50.0,
    "W_BIRD_POWER_BONUS": 2.0
  }
}
```

Only keys present need to be listed; others stay at `ArcanaCpuBase` defaults in the pilot.

### 6.2 Application in Godot

1. **Pilot `_init`:** After `super` or in the pilot’s `_init`, apply `weights` from a `Resource` or loaded JSON (merge into instance vars on `ArcanaCpuBase`).
2. **Registry:** Optionally [`cpu/pilot_registry.gd`](cpu/pilot_registry.gd) loads a manifest path once and passes it into `create_for_slug`.

### 6.3 Parity checks

- **Python-only:** Assert manifest keys match `ArcanaCpuBase` property names.
- **Gameplay:** If headless deterministic games exist in Godot, compare win/draw counts on a small fixed seed set; otherwise rely on sim + manual QA.
- **Known gap:** `REVIVE_PICK_VERB_PRIORITY` exists in Python only; document that Godot uses the single `REVIVE_VERB_PRIORITY` dict until ported.

---

## 7. Risk register and validation checklist

| Risk | Mitigation |
|------|------------|
| Sim–Godot divergence | List unmodeled mechanics; avoid training void-heavy metrics for `void_temples` until sim catches up. |
| Overfitting to greedy opponents | Periodic eval on a **fixed** opponent mix; optional `sim.meta`-style matrix on best genomes only. |
| Hook literals dominate | If fitness ignores manual bonuses, parameterize literals (§2.3) or freeze hooks and only train base weights. |
| Statistical noise | Increase games for final champion; report Wilson or normal approx CI on win rate. |
| Class mutation in workers | Use per-genome subclass factory (§5.1). |

**Pre-ship checklist:**

- [ ] Genome keys are subset of `GreedyAI` / `ArcanaCpuBase` floats.
- [ ] Evaluation uses same `MatchState` rules as `python -m sim.run`.
- [ ] Best genome JSON loads in Godot without typos.
- [ ] At least one regression: same `slug` + weights runs in sim without exceptions.

---

## 8. Open questions

- **Multi-objective:** If speed and win rate conflict, use Pareto selection or scalarize with tuned weights.
- **Per-deck genomes:** Train all slugs sequentially vs shared base + fine-tune — product decision.
- **Integer revive priorities:** Evolve only after float genome is stable.
