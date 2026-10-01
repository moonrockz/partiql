"""Summarize CONFORMANCE lines from `moon test` output for GitHub Actions.

Each line is `CONFORMANCE {json}`, written by
modules/partiql-conformance/src/report_test.mbt.
"""

import argparse
import json
import os
import sys
from typing import List, Optional

PREFIX = "CONFORMANCE "


def parse_log(text: str) -> List[dict]:
    results = []
    for line in text.splitlines():
        if not line.startswith(PREFIX):
            continue
        try:
            results.append(json.loads(line[len(PREFIX):]))
        except json.JSONDecodeError:
            continue
    return results


def percent(passed: int, total: int, not_applicable: int) -> str:
    applicable = total - not_applicable
    if applicable <= 0:
        return "n/a"
    return "{:.1f}%".format(100.0 * passed / applicable)


def to_markdown(results: List[dict]) -> str:
    if not results:
        return "## PartiQL conformance\n\nNo CONFORMANCE results in the log.\n"
    lines = [
        "## PartiQL conformance",
        "",
        "| Check | Passed | Total | N/A | Pass rate | Regressions | New passes |",
        "|---|---|---|---|---|---|---|",
    ]
    for r in results:
        lines.append(
            "| {suite} | {passed} | {total} | {na} | {pct} | {reg} | {new} |".format(
                suite=r["suite"],
                passed=r["passed"],
                total=r["total"],
                na=r["not_applicable"],
                pct=percent(r["passed"], r["total"], r["not_applicable"]),
                reg=r["regressions"],
                new=r["new_passes"],
            )
        )
    regressed = [r for r in results if r["regressions"]]
    for r in regressed:
        lines += ["", "### Regressions in {}".format(r["suite"]), ""]
        lines += ["- `{}`".format(i) for i in r.get("regression_ids", [])]
    if any(r["new_passes"] for r in results):
        lines += ["", "New passes: run `mise run conformance:ratchet` and commit the baseline."]
    return "\n".join(lines) + "\n"


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log")
    parser.add_argument("--json", dest="json_out")
    args = parser.parse_args(argv)
    with open(args.log, encoding="utf-8") as f:
        results = parse_log(f.read())
    markdown = to_markdown(results)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(markdown)
    else:
        sys.stdout.write(markdown)
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
