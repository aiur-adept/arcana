from __future__ import annotations

import argparse
import csv
from pathlib import Path


def load_points_matrix(csv_path: Path) -> dict[str, dict[str, float]]:
    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    if not rows or len(rows[0]) < 2:
        raise ValueError(f"CSV has no matchup columns: {csv_path}")

    columns = rows[0][1:]
    matrix: dict[str, dict[str, float]] = {}

    for row in rows[1:]:
        if not row:
            continue
        row_deck = row[0]
        values = row[1:]
        if len(values) != len(columns):
            raise ValueError(
                f"Row {row_deck!r} has {len(values)} values, expected {len(columns)}."
            )
        matrix[row_deck] = {col: float(v) for col, v in zip(columns, values)}

    return matrix


def build_edges(matrix: dict[str, dict[str, float]], eps: float) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    decks = sorted(set(matrix.keys()))
    edges: list[tuple[str, str]] = []
    ties: list[tuple[str, str]] = []

    for i in range(len(decks)):
        for j in range(i + 1, len(decks)):
            a = decks[i]
            b = decks[j]
            a_vs_b = matrix[b][a]
            b_vs_a = matrix[a][b]
            diff = a_vs_b - b_vs_a
            if abs(diff) <= eps:
                ties.append((a, b))
            elif diff > 0:
                edges.append((a, b))
            else:
                edges.append((b, a))

    return edges, ties


def main() -> None:
    ap = argparse.ArgumentParser(
        description=(
            "Build directed edges A->B when deck A has higher expected match points "
            "against B than B has against A."
        )
    )
    ap.add_argument("--csv", default="meta_trained.csv", help="Path to matchup CSV matrix.")
    ap.add_argument(
        "--eps",
        type=float,
        default=1e-9,
        help="Treat absolute differences <= eps as ties.",
    )
    ap.add_argument(
        "--show-ties",
        action="store_true",
        help="Also print tied pairs.",
    )
    args = ap.parse_args()

    matrix = load_points_matrix(Path(args.csv))
    edges, ties = build_edges(matrix, args.eps)

    print("edges")
    for src, dst in edges:
        print(f"{src} -> {dst}")

    if args.show_ties and ties:
        print("\nties")
        for a, b in ties:
            print(f"{a} == {b}")


if __name__ == "__main__":
    main()
