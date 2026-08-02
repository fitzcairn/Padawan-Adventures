#!/usr/bin/env python3
"""Score baked floor atlases against cohesion gates and render synthetic rooms.

Usage:
  python3 scripts/score_floor_sets.py
  python3 scripts/score_floor_sets.py --set 1-tython
  python3 scripts/score_floor_sets.py --baseline   # write rooms without failing gates
  python3 scripts/score_floor_sets.py --relax-families  # skip family gates (pre-Stage-2)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from paths import ROOT
from floor_metrics import (
    discover_floor_sets,
    gate_failures,
    render_synthetic_room,
    score_set,
)

OUT_DIR = ROOT / "scripts" / "out"


def format_score(score: dict, fails: list[str]) -> str:
    fams = score["families"]
    fam_str = (
        ", ".join(f"{k}:{v}" for k, v in sorted(fams.items()))
        if fams
        else "(none)"
    )
    status = "FAIL" if fails else "OK"
    lines = [
        f"{score['set']}  floors={score['floors']}  [{status}]",
        (
            f"  edge delta (declared matches): "
            f"median={score['edge_median']:.1f} p75={score['edge_p75']:.1f} "
            f"p90={score['edge_p90']:.1f} max={score['edge_max']:.1f} "
            f"  [gate: median <= 8]"
        ),
        (
            f"  interior luma stdev:           {score['luma_stdev']:.1f}"
            f"                                     [gate: <= 6]"
        ),
        (
            f"  mean match-list fraction:      {score['mean_match_frac']*100:.0f}%"
            f"                                      [gate: <= 12%]"
        ),
        (
            f"  weights: min={score['weight_min']:.2f} max={score['weight_max']:.2f} "
            f"distinct={score['weight_distinct']}"
            f"                                   [gate: distinct >= 8]"
        ),
        (
            f"  families: {fam_str}"
            f"                                                        [gate: 3..6, min size 6]"
        ),
    ]
    for f in fails:
        lines.append(f"  !! {f}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--set", action="append", dest="sets", help="Score one set (repeatable)")
    p.add_argument(
        "--baseline",
        action="store_true",
        help="Write synthetic rooms even when gates fail; always exit 0",
    )
    p.add_argument(
        "--relax-families",
        action="store_true",
        help="Skip family-count/size gates (for pre-Stage-2 baselines)",
    )
    p.add_argument(
        "--no-render",
        action="store_true",
        help="Skip synthetic room PNGs",
    )
    args = p.parse_args(argv)

    all_sets = discover_floor_sets()
    if not all_sets:
        print("No baked floor sets found", file=sys.stderr)
        return 1
    selected = all_sets
    if args.sets:
        wanted = set(args.sets)
        selected = [n for n in all_sets if n in wanted]
        missing = wanted - set(selected)
        if missing:
            print("Unknown sets:", ", ".join(sorted(missing)), file=sys.stderr)
            return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    failed = 0
    for name in selected:
        score = score_set(name)
        fails = gate_failures(score, strict_families=not args.relax_families)
        print(format_score(score, fails))
        if fails:
            failed += 1
        if not args.no_render:
            out = OUT_DIR / f"{name}-room.png"
            render_synthetic_room(name, out)
            print(f"  room → {out.relative_to(ROOT)}")
        print()

    if args.baseline:
        return 0
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
