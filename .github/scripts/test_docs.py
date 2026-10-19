#!/usr/bin/env python3
"""Run the module README examples in their packages' blackbox test environments."""

from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = {
    "README.md": "modules/partiql-eval/src",
    "modules/partiql-value/README.mbt.md": "modules/partiql-value/src",
    "modules/partiql-syntax/README.mbt.md": "modules/partiql-syntax/src",
    "modules/partiql-eval/README.mbt.md": "modules/partiql-eval/src",
    "modules/partiql/README.mbt.md": "modules/partiql/src/cli",
}


def checked_blocks(source: str) -> list[str]:
    """Collect explicitly checked fences; reject unclosed checked blocks."""
    blocks = []
    active = None
    fence = None
    for line in source.splitlines(keepends=True):
        match = re.fullmatch(r"(`{3,})([^`\n]*)\n?", line)
        if fence is None:
            if match:
                fence = match[1]
                active = [] if match[2].strip() == "mbt check" else None
        elif match and len(match[1]) >= len(fence) and not match[2].strip():
            if active is not None:
                blocks.append("".join(active))
            active = None
            fence = None
        elif active is not None:
            active.append(line)
    if active is not None:
        raise ValueError("unclosed mbt check fence")
    return blocks


def main() -> int:
    generated = []
    try:
        for document, package in PACKAGES.items():
            readme = ROOT / document
            blocks = checked_blocks(readme.read_text())
            if not blocks:
                raise ValueError(f"{readme}: no checked examples")
            # The files live beside existing tests to use the same test imports.
            # Unique names allow simultaneous test runs; always remove them below.
            with tempfile.NamedTemporaryFile(
                mode="w", prefix="readme_", suffix="_test.mbt",
                dir=ROOT / package, delete=False,
            ) as output:
                generated.append(Path(output.name))
                output.write(f"// Generated from {readme.relative_to(ROOT)}.\n")
                output.write("\n///|\n".join(blocks))
        return subprocess.run(
            ["moon", "test", *map(str, generated), *sys.argv[1:]], cwd=ROOT,
            check=False,
        ).returncode
    finally:
        for path in generated:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
