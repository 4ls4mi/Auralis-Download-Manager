#!/usr/bin/env python3
"""Verify release assets against the exact artifacts from a verified build."""
import argparse
import hashlib
import json
import sys
from pathlib import Path
from urllib.parse import quote


RELEASE_URL = "https://github.com/4ls4mi/Auralis-Download-Manager/releases/download"


def verify(release, version, commit, files, *, draft=True, partial=False):
    if release.get("draft") is not draft:
        raise ValueError("release is not a draft" if draft else "release is not public")
    if release.get("prerelease") is not False:
        raise ValueError("release status is not stable")
    if release.get("tag_name") != f"v{version}":
        raise ValueError("release tag does not match the build version")
    if release.get("target_commitish") != commit:
        raise ValueError("release target does not match the verified commit")
    assets = release.get("assets", [])
    by_name = {asset["name"]: asset for asset in assets}
    expected = {path.name for path in files}
    names = set(by_name)
    if len(assets) != len(by_name) or not (names <= expected if partial else names == expected):
        raise ValueError(f"asset names do not match: expected {sorted(expected)}, got {sorted(by_name)}")
    for path in files:
        asset = by_name.get(path.name)
        if partial and (asset is None or (asset.get("state") == "starter" and asset.get("size") == 0)):
            continue
        if asset.get("state") != "uploaded":
            raise ValueError(f"{path.name}: upload is not complete")
        # Draft downloads use a temporary GitHub tag until publication creates the version tag.
        if not draft and asset.get("browser_download_url") != f"{RELEASE_URL}/v{version}/{quote(path.name, safe='')}":
            raise ValueError(f"{path.name}: release download address does not match the asset")
        if asset.get("size") != path.stat().st_size:
            raise ValueError(f"{path.name}: size mismatch")
        with path.open("rb") as artifact:
            checksum = hashlib.sha256()
            for block in iter(lambda: artifact.read(1024 * 1024), b""):
                checksum.update(block)
            digest = "sha256:" + checksum.hexdigest()
        if asset.get("digest") != digest:
            raise ValueError(f"{path.name}: SHA-256 digest missing or mismatched")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--published", action="store_true")
    modes.add_argument("--partial", action="store_true")
    parser.add_argument("release", type=Path)
    parser.add_argument("version")
    parser.add_argument("commit")
    parser.add_argument("files", type=Path, nargs="+")
    args = parser.parse_args()
    try:
        release = json.loads(args.release.read_text())
        verify(release, args.version, args.commit, args.files, draft=not args.published, partial=args.partial)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Release verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
    print("Release target and artifact sizes and digests verified.")


if __name__ == "__main__":
    main()
