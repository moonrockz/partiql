"""Exercise release versioning against real git history and git-cliff."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ReleaseVersionTest(unittest.TestCase):
    def test_breaking_changes_and_failed_major_tag(self):
        # Resolve the pinned executable before leaving the project directory:
        # mise's CI shim cannot find this project's tool versions in a fixture.
        cliff_binary = subprocess.run(
            ["mise", "which", "git-cliff"],
            cwd=ROOT, check=True, text=True, capture_output=True,
        ).stdout.strip()
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)

            def run(*args):
                result = subprocess.run(
                    args, cwd=repo, text=True, capture_output=True
                )
                self.assertEqual(result.returncode, 0, f"{args}: {result.stderr}")
                return result.stdout.strip()

            run("git", "init", "-q")
            run("git", "config", "user.name", "Release test")
            run("git", "config", "user.email", "release@example.invalid")
            run("git", "-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "-m", "feat: initial")
            run("git", "tag", "v0.1.0")
            run("git", "-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "-m", "feat(eval)!: change session API")

            def cliff(*args):
                return run(cliff_binary, "--config", str(ROOT / "cliff.toml"), *args)

            self.assertEqual(cliff("--bumped-version"), "v0.2.0")
            # A failed publication left an immutable tag on a separate commit.
            run("git", "-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "-m", "chore(build): prepare 1.0.0 release")
            run("git", "tag", "v1.0.0")
            run("git", "-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "-m", "fix(build): keep releases below 1.0")
            self.assertEqual(cliff("--bumped-version"), "v0.2.0")
            notes = cliff("--unreleased", "--bump", "--strip", "header")
            self.assertIn("[0.2.0]", notes)
            self.assertIn("Change session API", notes)
            self.assertNotIn("[1.0.0]", notes)


if __name__ == "__main__":
    unittest.main()
