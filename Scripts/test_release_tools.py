"""Tests for release_notes.py and check_release_sync.py. Run: python3 -I Scripts/test_release_tools.py"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_release_sync as check
import release_notes as notes

CHANGELOG = """# Changelog

Intro.

## 0.2.0

*6 November 2026.* The summary.

### New

- A thing.

## 0.1.0

*1 November 2026.* First.
"""
PBX = "MARKETING_VERSION = 0.2.0;\n\t\tMARKETING_VERSION = 0.2.0;\n"


class ReleaseNotesTests(unittest.TestCase):
    def test_a_version_s_section_stops_at_the_next(self):
        body = notes.section(CHANGELOG, "0.2.0")
        self.assertIn("### New", body)
        self.assertNotIn("First.", body)
        self.assertTrue(notes.section(CHANGELOG, "0.1.0").endswith("First."))

    def test_an_unknown_version_has_no_section(self):
        self.assertIsNone(notes.section(CHANGELOG, "0.3.0"))
        self.assertIsNone(notes.section(CHANGELOG, "0.2"), "0.2 is not 0.2.0")

    def test_the_notes_carry_the_changelog_the_checksum_and_the_limits(self):
        text = notes.compose("0.2.0", notes.section(CHANGELOG, "0.2.0"), "ab" * 32, 49_661_589, "c3185c8", "- A limit.\n")
        self.assertIn("## Kikimi 0.2.0 (beta)", text)
        self.assertIn("The summary.", text)
        self.assertNotIn("*6 November 2026.*", text, "the date is on the release page")
        self.assertIn("(50 MB)", text)
        self.assertIn("ab" * 32, text)
        self.assertIn("commit `c3185c8`", text)
        self.assertIn("- A limit.", text)
        self.assertNotIn("Under the hood", text)

    def test_tests_get_their_own_line_when_given(self):
        text = notes.compose("0.2.0", "x", "0" * 64, 1, "abc", "- l\n", tests="394 tests pass")
        self.assertIn("### Under the hood\n394 tests pass", text)

    def test_the_checksum_is_of_the_file(self):
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(b"abc")
        try:
            digest, size = notes.checksum(f.name)
        finally:
            os.remove(f.name)
        self.assertEqual(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        self.assertEqual(size, 3)


class SyncCheckTests(unittest.TestCase):
    def test_everything_agreeing_is_fine(self):
        self.assertEqual(check.problems(PBX, CHANGELOG, {"version": "0.2.0"}), [])

    def test_latest_json_may_be_a_release_behind(self):
        self.assertEqual(check.problems(PBX, CHANGELOG, {"version": "0.1.0"}), [])

    def test_a_release_without_notes_is_caught(self):
        issues = check.problems("MARKETING_VERSION = 0.3.0;\n", CHANGELOG, {"version": "0.2.0"})
        self.assertTrue(any("no section for 0.3.0" in i for i in issues))

    def test_stale_notes_are_caught(self):
        issues = check.problems("MARKETING_VERSION = 0.1.0;\n", CHANGELOG, {"version": "0.1.0"})
        self.assertTrue(any("newest section is 0.2.0" in i for i in issues))

    def test_latest_json_may_not_be_ahead_or_unexplained(self):
        issues = check.problems(PBX, CHANGELOG, {"version": "0.3.0"})
        self.assertEqual(len(issues), 2)

    def test_two_different_project_versions_are_caught(self):
        issues = check.problems("MARKETING_VERSION = 0.2.0;\nMARKETING_VERSION = 0.1.0;\n", CHANGELOG, {"version": "0.2.0"})
        self.assertTrue(any("different MARKETING_VERSION" in i for i in issues))


if __name__ == "__main__":
    unittest.main()
