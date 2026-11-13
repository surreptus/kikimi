"""Tests for update_model_manifest.py. Run: python3 -I Scripts/test_model_manifest.py"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import update_model_manifest as manifest

SHA = "a" * 64
COMMIT = "0f63a7800b00dd0226abd051b906c246e1907482"


def lfs(path, size=10, oid=SHA):
    return {"type": "file", "path": path, "size": size, "lfs": {"oid": oid, "size": size, "pointerSize": 130}}


PLAIN = {"type": "file", "path": "m/config.json", "size": 5, "oid": "b" * 40}
FOLDER = {"type": "directory", "path": "m/AudioEncoder.mlmodelc"}


class ManifestTests(unittest.TestCase):
    def test_only_lfs_files_are_listed_and_paths_are_relative_to_the_variant(self):
        files = manifest.variant_files([PLAIN, FOLDER, lfs("m/b.bin"), lfs("m/a/weight.bin", 7)], "m")
        self.assertEqual([f["path"] for f in files], ["a/weight.bin", "b.bin"])
        self.assertEqual(files[0], {"path": "a/weight.bin", "size": 7, "sha256": SHA})

    def test_a_bad_value_is_refused(self):
        with self.assertRaises(ValueError):
            manifest.variant_files([lfs("m/a.bin", oid="xyz")], "m")
        with self.assertRaises(ValueError):
            manifest.variant_files([lfs("other/a.bin")], "m")
        with self.assertRaises(ValueError):
            manifest.variant_files([PLAIN], "m")

    def test_sizes_that_differ_are_refused(self):
        entry = lfs("m/a.bin")
        entry["lfs"]["size"] = 11
        with self.assertRaises(ValueError):
            manifest.variant_files([entry], "m")

    def test_a_branch_name_is_not_a_commit(self):
        with self.assertRaises(ValueError):
            manifest.build_manifest("main", {"m": [lfs("m/a.bin")]})

    def test_the_manifest_names_repo_commit_and_variants_in_order(self):
        result = manifest.build_manifest(COMMIT, {"y": [lfs("y/a.bin")], "x": [lfs("x/a.bin")]})
        self.assertEqual(result["repo"], "argmaxinc/whisperkit-coreml")
        self.assertEqual(result["commit"], COMMIT)
        self.assertEqual(list(result["variants"]), ["x", "y"])

    def test_variants_are_read_from_the_catalog(self):
        swift = 'ModelInfo(variant: "openai_whisper-tiny", name: "tiny"),\n ModelInfo(variant: "openai_whisper-base", name: "b")'
        self.assertEqual(manifest.catalog_variants(swift), ["openai_whisper-tiny", "openai_whisper-base"])


if __name__ == "__main__":
    unittest.main()
