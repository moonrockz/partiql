import unittest

from test_docs import checked_blocks


class CheckedBlocksTest(unittest.TestCase):
    def test_extracts_only_checked_examples_in_source_order(self):
        source = """# Examples
```mbt nocheck
import { "example/package" }
```
```moonbit
ignored()
```
```mbt check
test { first() }
```
````mbt check
test { second() }
````
"""
        self.assertEqual(checked_blocks(source), [
            "test { first() }\n", "test { second() }\n",
        ])

    def test_short_fence_does_not_close_a_longer_fence(self):
        self.assertEqual(checked_blocks("````text\n```mbt check\nignored\n```\n````\n"), [])

    def test_rejects_unclosed_checked_example(self):
        with self.assertRaisesRegex(ValueError, "unclosed"):
            checked_blocks("```mbt check\ntest { first() }\n")

    def test_accepts_closing_fence_without_final_newline(self):
        self.assertEqual(checked_blocks("```mbt check\ntest {}\n```"), ["test {}\n"])


if __name__ == "__main__":
    unittest.main()
