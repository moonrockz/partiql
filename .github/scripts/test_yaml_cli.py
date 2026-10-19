#!/usr/bin/env python3
"""Exercise YAML at the native process boundary, including binary Ion output."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

def query(binary, args, source=None, status=0):
    result = subprocess.run([binary, "query", *args], input=source, capture_output=True)
    assert result.returncode == status, (args, result.returncode, result.stderr)
    if status == 0:
        assert result.stderr == b"", result.stderr
    return result


def main():
    binary = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="partiql-yaml-") as folder:
        root = Path(folder)
        manifest = root / "manifest.yaml"
        manifest.write_text("--- {name: first}\n--- {name: second}\n")
        env = root / "env.yaml"
        env.write_text("n: 4\n")
        flags = ["--input-format", "yaml", "--compact"]
        result = query(binary, [*flags, "--data", f"t={manifest}", "-e", "SELECT VALUE r.name FROM t AS r"])
        assert result.stdout == b'$bag::["first", "second"]\n', result.stdout
        result = query(binary, [*flags, "--data", "t=-", "--each", "t", "--output-format", "json", "-e", "t.name"], manifest.read_bytes())
        assert [json.loads(line) for line in result.stdout.splitlines()] == ["first", "second"]
        for args, data in [(["--env", str(env)], None), (["--env", "-"], env.read_bytes())]:
            assert query(binary, [*flags, *args, "-e", "n + 1"], data).stdout == b"5\n"
        exact = b"n: 9223372036854775808\nd: -0.00\nx: 1.2300\n"
        args = [*flags, "--data", "t=-", "-e", "t"]
        encoded = query(binary, [*args, "--output-format", "binary"], exact).stdout
        assert encoded.startswith(b"\xe0\x01\x00\xea")
        restored = query(binary, ["--data", "t=-", "--compact", "-e", "t"], encoded)
        assert restored.stdout == query(binary, args, exact).stdout
        expected_json = b'{"n":9223372036854775808,"d":-0e-2,"x":12300e-4}\n'
        assert query(binary, [*args, "--output-format", "json"], exact).stdout == expected_json
        for source in [b"--- 1\n--- [", b"{x: 1, x: 2}", b"&x [*x]", b"\xff"]:
            result = query(binary, [*args, "--each", "t"], source, status=1)
            assert result.stdout == b"", result.stdout
            assert b"<stdin>: YAML" in result.stderr, result.stderr
        for option in [["--env-schema", "missing.isl"], ["--data-schema", "t=missing.isl"], ["--schema-type", "x"], ["--schema-document"]]:
            result = query(binary, [*args, *option], b"invalid yaml [", status=2)
            assert result.stdout == b"" and b"Ion Schema" in result.stderr
        for source, expected in [(b"", b""), (b"[]", b""), (b"---", b"null\n")]:
            assert query(binary, [*args, "--each", "t"], source).stdout == expected
    print("Native YAML CLI smoke checks passed.")


if __name__ == "__main__":
    main()
