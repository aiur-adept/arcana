"""GreedyAI weight keys, dynamic pilot subclasses, and JSON I/O for Godot."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .ai import GreedyAI
from .pilots import get_pilot


def greedy_ai_float_weight_keys() -> tuple[str, ...]:
    return tuple(
        sorted(
            k
            for k, v in vars(GreedyAI).items()
            if isinstance(v, float)
        )
    )


def baseline_weights_for_slug(slug: str) -> dict[str, float]:
    cls = get_pilot(slug)
    out: dict[str, float] = {}
    for k in greedy_ai_float_weight_keys():
        if hasattr(cls, k):
            v = getattr(cls, k)
            if isinstance(v, float):
                out[k] = float(v)
    return out


def make_weighted_pilot(base_cls: type[GreedyAI], weights: dict[str, float]) -> type[GreedyAI]:
    d: dict[str, Any] = {}
    for k, v in weights.items():
        if k in greedy_ai_float_weight_keys():
            d[k] = float(v)
    return type("WeightedPilot", (base_cls,), d)


def pilot_class_for_slug(slug: str, weights_path: Path | None, use_saved: bool) -> type[GreedyAI]:
    """Return get_pilot(slug), or a weighted subclass if use_saved and JSON has weights_for_slug."""
    base = get_pilot(slug)
    if not use_saved or weights_path is None or not weights_path.is_file():
        return base
    data = load_weights_file(weights_path)
    wbs = data.get("weights_by_slug", {})
    if not isinstance(wbs, dict):
        return base
    raw = wbs.get(slug)
    if not isinstance(raw, dict) or not raw:
        return base
    weights = {str(k): float(v) for k, v in raw.items() if isinstance(v, (int, float))}
    if not weights:
        return base
    return make_weighted_pilot(base, weights)


def clamp_weight(name: str, v: float) -> float:
    lo, hi = -120.0, 400.0
    if name == "W_RITUAL_DUP_LANE_1":
        lo = -80.0
    return max(lo, min(hi, v))


def clamp_genome(weights: dict[str, float]) -> dict[str, float]:
    return {k: clamp_weight(k, float(v)) for k, v in weights.items()}


DEFAULT_PILOT_WEIGHTS_FILENAME = "pilot_weights.json"


def default_pilot_weights_path(project_root: Path | None = None) -> Path:
    root = project_root or Path(__file__).resolve().parent.parent
    return root / "data" / DEFAULT_PILOT_WEIGHTS_FILENAME


def load_weights_file(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {"genome_version": 1, "weights_by_slug": {}}
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        return {"genome_version": 1, "weights_by_slug": {}}
    data.setdefault("genome_version", 1)
    data.setdefault("weights_by_slug", {})
    return data


def merge_slug_into_weights_file(path: Path, slug: str, weights: dict[str, float], genome_version: int = 1) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = load_weights_file(path)
    data["genome_version"] = genome_version
    wbs = data["weights_by_slug"]
    assert isinstance(wbs, dict)
    wbs[slug] = {k: float(v) for k, v in sorted(weights.items())}
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")
