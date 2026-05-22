#!/usr/bin/env python3
import argparse
import csv
import statistics
from collections import OrderedDict, defaultdict
from pathlib import Path


def read_rows(path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def median(values):
    cleaned = []
    for value in values:
        try:
            cleaned.append(float(value))
        except (TypeError, ValueError):
            pass
    if not cleaned:
        return None
    return statistics.median(cleaned)


def fmt_number(value):
    if value is None:
        return "n/a"
    if abs(value) >= 1000:
        return f"{value:.2f}"
    if abs(value) >= 100:
        return f"{value:.2f}"
    if abs(value) >= 10:
        return f"{value:.3f}"
    return f"{value:.4f}"


def metric_key(row):
    return (row["group"], row["metric"], row["unit"], row["direction"])


def summarize(rows):
    grouped = OrderedDict()
    failures = defaultdict(int)

    for row in rows:
        key = metric_key(row)
        grouped.setdefault(key, [])
        if row.get("status") == "ok":
            grouped[key].append(row.get("value"))
        else:
            failures[key] += 1

    return {
        key: {
            "median": median(values),
            "failed": failures[key],
        }
        for key, values in grouped.items()
    }


def latest_baseline(results_dir, current_csv, label, profile, current_label):
    if not label or label == current_label:
        return None

    matches = []
    for path in sorted(results_dir.glob("*.csv")):
        if path.resolve() == current_csv.resolve():
            continue
        try:
            rows = read_rows(path)
        except Exception:
            continue
        if not rows:
            continue
        first = rows[0]
        if first.get("label") != label:
            continue
        if profile != "any" and first.get("profile") != profile:
            continue
        matches.append((first.get("timestamp", ""), path, rows))

    if not matches:
        return None
    return sorted(matches, key=lambda item: item[0])[-1]


def change_text(current, baseline, direction):
    if current is None or baseline is None or baseline == 0:
        return "n/a"
    if direction == "lower":
        change = ((baseline - current) / baseline) * 100
    else:
        change = ((current - baseline) / baseline) * 100
    suffix = "better" if change >= 0 else "worse"
    sign = "+" if change >= 0 else ""
    return f"{sign}{change:.2f}% {suffix}"


def render(args):
    current_csv = Path(args.csv)
    rows = read_rows(current_csv)
    if not rows:
        raise SystemExit(f"{current_csv} has no rows")

    first = rows[0]
    current = summarize(rows)
    baseline_match = latest_baseline(
        Path(args.results_dir),
        current_csv,
        args.baseline_label,
        args.baseline_profile,
        first["label"],
    )

    baseline_summary = {}
    baseline_line = "Compared to: `none`"
    if baseline_match:
        _, baseline_path, baseline_rows = baseline_match
        baseline_summary = summarize(baseline_rows)
        baseline_first = baseline_rows[0]
        baseline_line = (
            "Compared to: "
            f"`{baseline_first['label']}` on `{baseline_first['kernel']}` "
            f"from `{baseline_path.name}`"
        )

    groups = OrderedDict()
    for key in current:
        groups.setdefault(key[0], []).append(key)

    lines = [
        "# Kernel benchmark summary",
        "",
        f"- Timestamp: `{first['timestamp']}`",
        f"- Kernel: `{first['kernel']}`",
        f"- Label: `{first['label']}`",
        f"- Profile: `{first['profile']}`",
        f"- CSV: `{current_csv.name}`",
        f"- Baseline label: `{args.baseline_label}`",
        f"- Baseline profile: `{args.baseline_profile}`",
        f"- {baseline_line}",
        "",
        "Positive change means this run is better than the baseline after applying each metric's better direction.",
    ]

    if not baseline_match:
        lines.extend(
            [
                "",
                "No matching baseline CSV was found. Run the baseline first with the same profile, "
                "set `BENCH_BASELINE_LABEL` to an existing label, or set `BENCH_BASELINE_PROFILE=any`.",
            ]
        )

    for group, keys in groups.items():
        lines.extend(
            [
                "",
                f"## {group}",
                "",
                "| Metric | Current median | Baseline median | Change vs baseline | Unit | Failed |",
                "| --- | ---: | ---: | ---: | --- | ---: |",
            ]
        )
        for key in keys:
            _, metric, unit, direction = key
            current_median = current[key]["median"]
            baseline_median = baseline_summary.get(key, {}).get("median")
            failed = current[key]["failed"]
            lines.append(
                "| "
                f"{metric} | "
                f"{fmt_number(current_median)} | "
                f"{fmt_number(baseline_median)} | "
                f"{change_text(current_median, baseline_median, direction)} | "
                f"{unit} | "
                f"{failed} |"
            )

    output = Path(args.output)
    output.write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--results-dir", required=True)
    parser.add_argument("--baseline-label", default="cachyos-lts")
    parser.add_argument("--baseline-profile", default="balanced")
    args = parser.parse_args()
    render(args)


if __name__ == "__main__":
    main()
