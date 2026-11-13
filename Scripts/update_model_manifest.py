"""Writes LangCore's ModelManifest.json: the fixed version of each speech model and a SHA-256 value for each large file.

Run it when the model changes: python3 -I Scripts/update_model_manifest.py [--commit <sha>]
It reads file lists from the Hugging Face API. It downloads no model. Only files stored with Git LFS have a SHA-256 value,
so only those files are listed. The variants come from ModelCatalog.swift, so the catalog stays the one list.
"""
import argparse
import json
import os
import re
import sys
import urllib.request

REPO = "argmaxinc/whisperkit-coreml"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "LangCore/Sources/LangCore/Models/ModelCatalog.swift")
MANIFEST = os.path.join(ROOT, "LangCore/Sources/LangCore/Resources/ModelManifest.json")
API = "https://huggingface.co/api/models/{repo}/tree/{commit}/{variant}?recursive=true"
# A full commit name only. A branch name would move.
COMMIT = re.compile(r"^[0-9a-f]{40}$")


def catalog_variants(swift):
    return re.findall(r'ModelInfo\(variant: "([^"]+)"', swift)


def variant_files(entries, variant):
    """Path (relative to the variant folder), size and SHA-256 of each LFS file, sorted by path."""
    prefix = variant + "/"
    files = []
    for entry in entries:
        lfs = entry.get("lfs")
        if entry.get("type") != "file" or not lfs:
            continue
        if not entry["path"].startswith(prefix):
            raise ValueError("%s is outside %s" % (entry["path"], variant))
        if not re.fullmatch(r"[0-9a-f]{64}", lfs["oid"]):
            raise ValueError("%s has no SHA-256 value" % entry["path"])
        if lfs["size"] != entry["size"]:
            raise ValueError("%s: file size and LFS size differ" % entry["path"])
        files.append({"path": entry["path"][len(prefix):], "size": entry["size"], "sha256": lfs["oid"]})
    if not files:
        raise ValueError("%s has no LFS files" % variant)
    return sorted(files, key=lambda f: f["path"])


def build_manifest(commit, listings):
    """`listings` maps each variant to its file list from the API."""
    if not COMMIT.match(commit):
        raise ValueError("The commit must be a full 40-character name, not a branch")
    return {"repo": REPO, "commit": commit,
            "variants": {v: variant_files(listings[v], v) for v in sorted(listings)}}


def fetch(variant, commit):
    url = API.format(repo=REPO, commit=commit, variant=variant)
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--commit", help="Full commit name. The default is the one in the current manifest.")
    args = parser.parse_args()
    commit = args.commit
    if not commit:
        with open(MANIFEST) as f:
            commit = json.load(f)["commit"]
    with open(CATALOG) as f:
        variants = catalog_variants(f.read())
    manifest = build_manifest(commit, {v: fetch(v, commit) for v in variants})
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print("Wrote %s: %d variants at %s" % (os.path.relpath(MANIFEST, ROOT), len(variants), commit))


if __name__ == "__main__":
    sys.exit(main())
