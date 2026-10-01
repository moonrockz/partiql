import json
import os
import tempfile
import unittest

import conformance_summary as cs

LOG = """\
some other output
CONFORMANCE {"suite":"syntax","total":425,"passed":10,"not_applicable":183,"regressions":0,"new_passes":2,"regression_ids":[]}
CONFORMANCE {"suite":"codec","total":5000,"passed":40,"not_applicable":0,"regressions":1,"new_passes":0,"regression_ids":["a::b#env"]}
Total tests: 1, passed: 1, failed: 0.
"""


class ParseTest(unittest.TestCase):
    def test_parses_only_conformance_lines(self):
        results = cs.parse_log(LOG)
        self.assertEqual([r["suite"] for r in results], ["syntax", "codec"])
        self.assertEqual(results[1]["regression_ids"], ["a::b#env"])

    def test_ignores_malformed_json(self):
        self.assertEqual(cs.parse_log("CONFORMANCE {not json"), [])


class MarkdownTest(unittest.TestCase):
    def test_table_has_one_row_per_suite_and_percentages(self):
        md = cs.to_markdown(cs.parse_log(LOG))
        self.assertIn("| syntax | 10 | 425 | 183 | 4.1% | 0 | 2 |", md)
        self.assertIn("| codec | 40 | 5000 | 0 | 0.8% | 1 | 0 |", md)
        self.assertIn("`a::b#env`", md)

    def test_percentage_ignores_not_applicable(self):
        # 10 passed of (425 - 183) applicable tests = 4.1%
        self.assertEqual(cs.percent(10, 425, 183), "4.1%")
        self.assertEqual(cs.percent(0, 5, 5), "n/a")

    def test_empty_log(self):
        self.assertIn("No CONFORMANCE results", cs.to_markdown([]))


class MainTest(unittest.TestCase):
    def test_writes_json_and_summary(self):
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "log.txt")
            out = os.path.join(d, "out.json")
            summary = os.path.join(d, "summary.md")
            with open(log, "w") as f:
                f.write(LOG)
            os.environ["GITHUB_STEP_SUMMARY"] = summary
            try:
                cs.main([log, "--json", out])
            finally:
                del os.environ["GITHUB_STEP_SUMMARY"]
            with open(out) as f:
                self.assertEqual(len(json.load(f)), 2)
            with open(summary) as f:
                self.assertIn("PartiQL conformance", f.read())


if __name__ == "__main__":
    unittest.main()
