#!/usr/bin/env python3
"""Verify a draft release against the exact artifacts from this build."""
import hashlib
import json
import sys
from pathlib import Path


def verify(release, version, commit, files):
    if release.get("draft") is not True:
        raise ValueError("release is not a draft")
    if release.get("tag_name") != f"v{version}":
        raise ValueError("release tag does not match the build version")
    if release.get("target_commitish") != commit:
        raise ValueError("release target does not match the verified commit")
    assets = release.get("assets", [])
    by_name = {asset["name"]: asset for asset in assets}
    expected = {path.name for path in files}
    if len(assets) != len(by_name) or set(by_name) != expected:
        raise ValueError(f"asset names do not match: expected {sorted(expected)}, got {sorted(by_name)}")
    for path in files:
        asset = by_name[path.name]
        if asset.get("state") != "uploaded":
            raise ValueError(f"{path.name}: upload is not complete")
        if asset.get("size") != path.stat().st_size:
            raise ValueError(f"{path.name}: size mismatch")
        digest = "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
        if asset.get("digest") != digest:
            raise ValueError(f"{path.name}: SHA-256 digest missing or mismatched")


def main():
    if len(sys.argv) < 5:
        raise SystemExit("usage: verify-auralis-release.py RELEASE_JSON VERSION COMMIT FILE...")
    try:
        release = json.loads(Path(sys.argv[1]).read_text())
        verify(release, sys.argv[2], sys.argv[3], [Path(p) for p in sys.argv[4:]])
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Release verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
    print("Release target and artifact sizes and digests verified.")


if __name__ == "__main__":
    main()
