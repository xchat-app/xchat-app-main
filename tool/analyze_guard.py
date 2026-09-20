#!/usr/bin/env python3
"""Stop the analyzer backlog from growing.

There are 3544 outstanding analyzer findings, so a build that fails on any of
them fails always, which is the same as no check at all. One of those findings
had been reported on every run for sixteen months: a timer that woke the app
every five seconds to read its memory usage and throw the number away. Nobody
saw it, because a warning among thousands is not a signal.

So this does not ask for the backlog to be paid off. It records what is there
today and fails only when a run reports something that was not in that record —
a new rule in a file, or more of a rule than the file had before. Existing debt
is frozen; new debt is refused.

    python3 tool/analyze_guard.py            # check against the baseline
    python3 tool/analyze_guard.py --update   # re-record it

Findings are counted per (severity, rule, file), deliberately without line
numbers, so moving code around does not set it off.
"""

import argparse
import collections
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = Path(__file__).with_name("analyze_baseline.txt")

# Everything that ships. Generated code and build output are not ours to fix.
PATHS = ["lib", "packages"]
SKIP = (".dart_tool/", "/build/", ".g.dart", ".freezed.dart", "frb_generated")


def findings():
    """{(severity, rule, file): count} for the current tree."""
    result = subprocess.run(
        ["dart", "analyze", "--format=machine", *PATHS],
        cwd=ROOT, capture_output=True, text=True,
    )
    # dart analyze exits non-zero whenever it finds anything at all, which here
    # is always, so the exit code says nothing. The output is what matters.
    if not result.stdout.strip() and result.returncode not in (0, 1, 2, 3):
        sys.exit(f"dart analyze could not run:\n{result.stderr[:2000]}")

    counts = collections.Counter()
    for line in result.stdout.splitlines():
        # SEVERITY|TYPE|CODE|FILE|LINE|COL|LENGTH|MESSAGE
        parts = line.split("|")
        if len(parts) < 8:
            continue
        severity, _, rule, path = parts[0], parts[1], parts[2], parts[3]
        if any(skip in path for skip in SKIP):
            continue
        try:
            relative = os.path.relpath(path, ROOT)
        except ValueError:
            relative = path
        counts[(severity, rule, relative)] += 1
    return counts


def read_baseline():
    if not BASELINE.is_file():
        return None
    counts = collections.Counter()
    for line in BASELINE.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        severity, rule, count, path = line.split("|", 3)
        counts[(severity, rule, path)] = int(count)
    return counts


def write_baseline(counts):
    lines = [
        "# Analyzer findings as they stand, by (severity, rule, file).",
        "# Frozen debt, not a target. tool/analyze_guard.py refuses anything",
        "# above these numbers; lowering them is always welcome.",
    ]
    lines += [
        f"{severity}|{rule}|{count}|{path}"
        for (severity, rule, path), count in sorted(counts.items())
    ]
    BASELINE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--update", action="store_true",
                        help="re-record the baseline from the current tree")
    args = parser.parse_args()

    current = findings()
    total = sum(current.values())

    if args.update or read_baseline() is None:
        write_baseline(current)
        print(f"Recorded {total} findings across {len(current)} (rule, file) pairs.")
        return

    baseline = read_baseline()
    added = []
    for key, count in sorted(current.items()):
        was = baseline.get(key, 0)
        if count > was:
            severity, rule, path = key
            added.append(f"  {path}\n    {severity.lower()} {rule}: {was} -> {count}")

    fixed = sum(max(0, was - current.get(key, 0)) for key, was in baseline.items())

    print(f"{total} findings, baseline {sum(baseline.values())}")
    if fixed:
        print(f"{fixed} fewer than the baseline — run --update to bank that.")

    if added:
        print(f"\n{len(added)} new finding(s), which this change introduced:\n")
        print("\n".join(added))
        print("\nFix these rather than re-recording the baseline. The backlog is "
              "frozen on purpose; adding to it is how it got to this size.")
        sys.exit(1)

    print("No new analyzer findings.")


if __name__ == "__main__":
    main()
