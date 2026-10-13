#!/usr/bin/env python3
import argparse
import csv
import math
import re
import statistics
import sys
from pathlib import Path

VPROF = re.compile(r"FPS:\s*Avg=(\d+(?:\.\d+)?),\s*P1=(\d+(?:\.\d+)?)", re.IGNORECASE)
MIN_RUNS = 3


def vprof_runs(directory, warmup):
    runs = []
    for path in sorted([*directory.glob("*.log"), *directory.glob("*.txt")]):
        matches = VPROF.findall(path.read_text(errors="replace"))
        runs.extend({"avg": float(avg), "p1": float(p1)} for avg, p1 in matches[warmup:])
    return runs


def number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def percentile(ordered, q):
    return ordered[max(0, math.ceil(q * len(ordered)) - 1)]


def read_frames(path):
    with path.open(newline="") as handle:
        reader = csv.reader(handle)
        for header in reader:
            if header[:2] == ["fps", "frametime"]:
                break
        else:
            raise ValueError(f"{path}: no MangoHud frame header")
        return [dict(zip(header, row)) for row in reader if len(row) == len(header)]


def mangohud_run(path, trim):
    frames = [(number(row["frametime"]), number(row.get("gpu_load"))) for row in read_frames(path)]
    frames = [(ft, gpu) for ft, gpu in frames if ft is not None and ft > 0]
    total = sum(ft for ft, _ in frames)
    start, end, elapsed = trim * 1000, total - trim * 1000, 0.0
    kept, gpu = [], []
    for ft, load in frames:
        elapsed += ft
        if start < elapsed <= end:
            kept.append(ft)
            if load is not None:
                gpu.append(load)
    if len(kept) < 1000:
        raise ValueError(f"{path}: only {len(kept)} frames after trimming {trim}s per end")
    ordered = sorted(kept)
    typical = statistics.median(ordered)
    return {
        "avg": 1000 * len(kept) / sum(kept),
        "low1": 1000 / percentile(ordered, 0.99),
        "low01": 1000 / percentile(ordered, 0.999),
        "stutters": sum(ft > 2 * typical for ft in kept) / (sum(kept) / 60000),
        "gpu": statistics.median(gpu) if gpu else None,
    }


def mangohud_runs(directory, trim):
    paths = sorted(p for p in directory.glob("*.csv") if not p.name.endswith("_summary.csv"))
    return [mangohud_run(path, trim) for path in paths]


def spread(values):
    middle = statistics.median(values)
    return middle, min(values), max(values)


def cell(values, digits=1):
    middle, low, high = spread(values)
    return f"{middle:.{digits}f} ({low:.{digits}f}–{high:.{digits}f})"


def noise(values):
    middle, low, high = spread(values)
    return f"{(high - low) / middle * 100:.1f}%"


def versus(values, baseline):
    if baseline is None:
        return "n/a"
    if values is baseline:
        return "baseline"
    if len(values) < MIN_RUNS or len(baseline) < MIN_RUNS:
        return f"needs {MIN_RUNS}+ runs each"
    change = (statistics.median(values) - statistics.median(baseline)) / statistics.median(baseline) * 100
    overlap = min(values) <= max(baseline) and min(baseline) <= max(values)
    return f"{change:+.1f}% ({'within noise' if overlap else 'clear'})"


def table(title, configs, key, baseline_label, columns, notes):
    rows = {label: runs for label, runs in configs.items() if runs}
    if not rows:
        return []
    base = [run[key] for run in rows[baseline_label]] if baseline_label in rows else None
    if base is None:
        notes += f" {baseline_label} has no results here, so nothing is compared."
    lines = [
        f"## {title}",
        "",
        "| Config | Runs | " + " | ".join(name for name, _, _ in columns) + f" | Noise | vs {baseline_label} |",
        "| --- | ---: | " + " | ".join("---:" for _ in columns) + " | ---: | --- |",
    ]
    for label, runs in rows.items():
        values = base if label == baseline_label else [run[key] for run in runs]
        cells = []
        for _, metric, digits in columns:
            series = [run[metric] for run in runs if run[metric] is not None]
            cells.append(cell(series, digits) if series else "n/a")
        lines.append(f"| {label} | {len(runs)} | " + " | ".join(cells) + f" | {noise(values)} | {versus(values, base)} |")
    return lines + ["", notes, ""]


def main():
    parser = argparse.ArgumentParser(description="Compare game frame rates, one directory per config.")
    parser.add_argument("dirs", nargs="+", type=Path)
    parser.add_argument("--baseline", help="config to compare against (default: first directory)")
    parser.add_argument("--warmup", type=int, default=1, help="results dropped from the start of each console log")
    parser.add_argument("--trim", type=float, default=2.0, help="seconds dropped from each end of a MangoHud log")
    args = parser.parse_args()

    for directory in args.dirs:
        if not directory.is_dir():
            sys.exit(f"{directory}: not a directory")
    baseline = args.baseline or args.dirs[0].name
    if baseline not in {d.name for d in args.dirs}:
        sys.exit(f"Baseline {baseline!r} is not one of the directories")
    try:
        counter = {d.name: vprof_runs(d, args.warmup) for d in args.dirs}
        frames = {d.name: mangohud_runs(d, args.trim) for d in args.dirs}
    except ValueError as error:
        sys.exit(str(error))
    empty = [label for label in counter if not counter[label] and not frames[label]]
    if empty:
        sys.exit(f"No results in: {', '.join(empty)}")

    lines = ["# Game frame rates", ""]
    lines += table(
        "CS2 benchmark counter",
        counter,
        "p1",
        baseline,
        [("Avg FPS", "avg", 1), ("P1 FPS", "p1", 1)],
        f"Median (min–max) per config. Noise is the P1 range over its median. "
        f"The first {args.warmup} result(s) of each console log are dropped as warm-up.",
    )
    lines += table(
        "MangoHud frametimes",
        frames,
        "low1",
        baseline,
        [("Avg FPS", "avg", 1), ("1% low", "low1", 1), ("0.1% low", "low01", 1),
         ("Stutters/min", "stutters", 1), ("GPU load %", "gpu", 0)],
        f"1% / 0.1% low: 99th / 99.9th percentile frametime as FPS. Stutters: frames over twice the run's "
        f"median frametime. Noise and comparison use the 1% low. Logs are trimmed by {args.trim:g}s per end.",
    )
    print("\n".join(lines).rstrip())


if __name__ == "__main__":
    main()
