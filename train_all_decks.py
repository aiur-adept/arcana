"""Train every included deck, keeping updates only if field win rate improves."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DEFAULT_WEIGHTS_PATH = ROOT / "data" / "pilot_weights.json"
TOTAL_WIN_RE = re.compile(r"^TOTAL\s+\d+\s+([0-9]+(?:\.[0-9]+)?)%")


def _ensure_weights_file(path: Path) -> None:
    if path.is_file():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump({"genome_version": 1, "weights_by_slug": {}}, f, indent=2, sort_keys=False)
        f.write("\n")


def _extract_total_win_rate(stdout: str) -> float:
    for line in stdout.splitlines():
        m = TOTAL_WIN_RE.match(line.strip())
        if m:
            return float(m.group(1))
    raise RuntimeError("Could not parse TOTAL P0 win% from sim.run output.")


def _weights_for_slug(path: Path, slug: str) -> dict[str, float]:
    if not path.is_file():
        return {}
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    wbs = data.get("weights_by_slug", {})
    if not isinstance(wbs, dict):
        return {}
    raw = wbs.get(slug)
    if not isinstance(raw, dict):
        return {}
    return {str(k): float(v) for k, v in raw.items() if isinstance(v, (int, float))}


def _print_weight_delta(deck: str, before_path: Path, after_path: Path) -> None:
    before = _weights_for_slug(before_path, deck)
    after = _weights_for_slug(after_path, deck)
    keys = sorted(set(before.keys()) | set(after.keys()))
    if not keys:
        print(f"Weight delta for {deck!r}: no per-slug genome present in either file.", flush=True)
        return
    changed: list[tuple[float, str, float, float]] = []
    for k in keys:
        b = float(before.get(k, 0.0))
        a = float(after.get(k, 0.0))
        d = a - b
        if abs(d) > 1e-12:
            changed.append((abs(d), k, b, a))
    if not changed:
        print(f"Weight delta for {deck!r}: no numeric changes.", flush=True)
        return
    changed.sort(reverse=True)
    print(f"Weight delta for {deck!r}: {len(changed)} changed key(s). Top deltas:", flush=True)
    for _, k, b, a in changed[:8]:
        print(f"  {k}: {b:.6f} -> {a:.6f} (delta {a - b:+.6f})", flush=True)


def _run_sim(deck: str, runs: int, seed: int, workers: int, weights_path: Path, pyexe: str) -> float:
    cmd = [
        pyexe,
        "-m",
        "sim.run",
        "--deck",
        deck,
        "--runs",
        str(runs),
        "--seed",
        str(seed),
        "--workers",
        str(workers),
        "--use-saved-weights",
        "--weights",
        str(weights_path),
    ]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.stdout:
        print(r.stdout, flush=True)
    if r.returncode != 0:
        if r.stderr:
            print(r.stderr, file=sys.stderr, flush=True)
        raise RuntimeError(f"sim.run failed for {deck!r} (exit {r.returncode})")
    return _extract_total_win_rate(r.stdout)


def _run_train(
    deck: str,
    pyexe: str,
    out_weights: Path,
    init_weights: Path,
    generations: int,
    population: int,
    games: int,
    seed: int,
    train_discard_weights_only: bool,
    train_sacrifice_cast_weights_only: bool,
) -> None:
    cmd = [
        pyexe,
        "-m",
        "sim.train_ea",
        "--deck",
        deck,
        "--generations",
        str(generations),
        "--population",
        str(population),
        "--games",
        str(games),
        "--seed",
        str(seed),
        "--p1-trained-weights",
        "--out",
        str(out_weights),
        "--init-weights",
        str(init_weights),
    ]
    if train_discard_weights_only:
        cmd.append("--train-discard-weights-only")
    if train_sacrifice_cast_weights_only:
        cmd.append("--train-sacrifice-cast-weights-only")
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        raise RuntimeError(f"sim.train_ea failed for {deck!r} (exit {r.returncode})")


def _copy_with_retry(src: Path, dst: Path, attempts: int = 6) -> None:
    last_exc: Exception | None = None
    for i in range(attempts):
        try:
            shutil.copy2(src, dst)
            return
        except PermissionError as exc:
            last_exc = exc
            if i == attempts - 1:
                break
            import time
            time.sleep(0.15 * (i + 1))
    if last_exc is not None:
        raise RuntimeError(f"Could not copy weights file due to file lock: {src}") from last_exc


def main() -> None:
    from sim.decks import included_deck_slugs

    ap = argparse.ArgumentParser(description="Train all decks with promote-on-improvement gating.")
    ap.add_argument("--generations", type=int, default=6)
    ap.add_argument("--population", type=int, default=500)
    ap.add_argument("--games", type=int, default=100, help="EA games per genome")
    ap.add_argument("--seed", type=int, default=108)
    ap.add_argument("--eval-runs", type=int, default=20_000, help="sim.run games for before/after comparison")
    ap.add_argument("--eval-seed", type=int, default=108)
    ap.add_argument("--eval-workers", type=int, default=0, help="sim.run workers (0 => cpu count)")
    ap.add_argument("--weights", type=str, default="", help="weights JSON path (default: data/pilot_weights.json)")
    ap.add_argument(
        "--train-discard-weights-only",
        action="store_true",
        help="forwarded to sim.train_ea: only train W_DISCARD_DRAW and DD_* weights",
    )
    ap.add_argument(
        "--train-sacrifice-cast-weights-only",
        action="store_true",
        help=(
            "forwarded to sim.train_ea: only train W_CAST_WITH_SAC_BASE, "
            "W_CAST_WITH_SAC_EXPECTED_MP_DELTA, and W_CAST_WITH_SAC_PAYMENT_MP_LOSS"
        ),
    )
    args = ap.parse_args()
    if args.train_discard_weights_only and args.train_sacrifice_cast_weights_only:
        raise SystemExit("Choose only one focused mode: discard-only or sacrifice-cast-only.")

    slugs = included_deck_slugs()
    ex = sys.executable
    eval_workers = args.eval_workers if args.eval_workers > 0 else (os.cpu_count() or 1)
    weights_path = Path(args.weights).resolve() if args.weights else DEFAULT_WEIGHTS_PATH.resolve()
    _ensure_weights_file(weights_path)

    for i, deck in enumerate(slugs):
        print(f"\n========== [{i + 1}/{len(slugs)}] deck={deck!r} ==========\n", flush=True)
        try:
            with tempfile.TemporaryDirectory(prefix=f"arcana_train_{deck}_") as td:
                td_path = Path(td)
                source_snapshot_path = td_path / "pilot_weights_source_snapshot.json"
                candidate_path = Path(td) / "pilot_weights_candidate.json"
                _copy_with_retry(weights_path, source_snapshot_path)
                _copy_with_retry(source_snapshot_path, candidate_path)

                print("Baseline evaluation (sim.run)...", flush=True)
                before_wr = _run_sim(deck, args.eval_runs, args.eval_seed, eval_workers, source_snapshot_path, ex)
                print(f"Baseline TOTAL win rate: {before_wr:.2f}%", flush=True)

                print("Training from existing weights...", flush=True)
                _run_train(
                    deck=deck,
                    pyexe=ex,
                    out_weights=candidate_path,
                    init_weights=source_snapshot_path,
                    generations=args.generations,
                    population=args.population,
                    games=args.games,
                    seed=args.seed,
                    train_discard_weights_only=args.train_discard_weights_only,
                    train_sacrifice_cast_weights_only=args.train_sacrifice_cast_weights_only,
                )
                _print_weight_delta(deck, source_snapshot_path, candidate_path)

                print("Post-train evaluation (sim.run)...", flush=True)
                after_wr = _run_sim(deck, args.eval_runs, args.eval_seed, eval_workers, candidate_path, ex)
                print(f"Post-train TOTAL win rate: {after_wr:.2f}%", flush=True)

                if after_wr > before_wr:
                    _copy_with_retry(candidate_path, weights_path)
                    print(
                        f"Promoted updated genome for {deck!r}: {before_wr:.2f}% -> {after_wr:.2f}%",
                        flush=True,
                    )
                else:
                    print(
                        f"Kept existing genome for {deck!r}: {before_wr:.2f}% -> {after_wr:.2f}% (no improvement)",
                        flush=True,
                    )
        except Exception as exc:
            print(str(exc), file=sys.stderr, flush=True)
            sys.exit(1)
    print(f"\nFinished all {len(slugs)} decks.", flush=True)


if __name__ == "__main__":
    main()
