"""Run EA training for every included deck; each run merges into data/pilot_weights.json.

From the repo root:
    python train_all_decks.py

Equivalent per deck:
    python -m sim.train_ea --deck <slug> --generations 10 --population 100 --games 500 --seed 42
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main() -> None:
    from sim.decks import included_deck_slugs

    slugs = included_deck_slugs()
    ex = sys.executable
    base_cmd = [
        ex,
        "-m",
        "sim.train_ea",
        "--generations",
        "6",
        "--population",
        "100",
        "--games",
        "100",
        "--seed",
        "42",
    ]
    for i, deck in enumerate(slugs):
        print(f"\n========== [{i + 1}/{len(slugs)}] deck={deck!r} ==========\n", flush=True)
        r = subprocess.run([*base_cmd, "--deck", deck], cwd=ROOT)
        if r.returncode != 0:
            print(f"train_ea failed for {deck!r} (exit {r.returncode})", file=sys.stderr, flush=True)
            sys.exit(r.returncode)
    print(f"\nFinished all {len(slugs)} decks.", flush=True)


if __name__ == "__main__":
    main()
