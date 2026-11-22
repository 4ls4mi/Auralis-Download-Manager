#!/usr/bin/env bash
# Run on a GitHub-hosted runner only after the exact Windows build passed.
set -euo pipefail
python3 -m unittest discover -s .github/scripts -p 'test_verify_auralis_release.py'
version="$(python3 - <<'PY'
import re
from pathlib import Path
project = Path("qt-ui/CMakeLists.txt").read_text()
match = re.search(r"project\s*\(\s*AuralisQt\s+VERSION\s+(\d+\.\d+\.\d+)\s", project)
if not match:
    raise SystemExit("AuralisQt project version not found")
print(match[1])
PY
)"
tag="v$version"
notes="docs/glass-releases/$tag.md"
asset="Auralis.Download.Manager_${version}_x64-setup.exe"
test -f "$notes"
if gh api "repos/$GH_REPO/git/ref/tags/$tag" >/dev/null 2>&1; then
    echo "Tag $tag already exists. Use a new version." >&2
    exit 1
fi
gh run download "$GITHUB_RUN_ID" --name auralis-download-manager-windows-x64 --dir installer
gh run download "$GITHUB_RUN_ID" --name auralis-browser-extensions --dir extensions
test "$(find installer -type f | wc -l)" -eq 1
test -f "installer/$asset"
test "$(find extensions -type f | wc -l)" -eq 3
for name in auralis-chromium.zip auralis-edge-store.zip auralis-firefox.zip; do
    test -f "extensions/$name"
done
draft_id() {
    gh api --paginate "repos/$GH_REPO/releases?per_page=100" --jq \
        ".[] | select(.tag_name==\"$tag\" and .draft==true) | .id"
}

release_id="$(draft_id 2>/dev/null || true)"
if [[ -z "$release_id" && "${AURALIS_ATTACH_ONLY:-0}" != 1 ]]; then
    gh release create "$tag" --draft --target "$GITHUB_SHA" \
        --title "Auralis Download Manager $version — Windows x64" --notes-file "$notes"
fi
for attempt in {1..15}; do
    release_id="$(draft_id 2>/dev/null || true)"
    if [[ "$release_id" =~ ^[0-9]+$ ]]; then break; fi
    sleep 3
done
if [[ ! "$release_id" =~ ^[0-9]+$ ]]; then
    echo "Could not uniquely identify the draft for $tag." >&2
    exit 1
fi
gh api "repos/$GH_REPO/releases/$release_id" > release.json
jq -e --arg sha "$GITHUB_SHA" --arg tag "$tag" \
    '.draft and .tag_name == $tag and .target_commitish == $sha' release.json > /dev/null
if ! gh release upload "$tag" "installer/$asset" extensions/*.zip; then
    echo '::warning::Upload command reported an error. Checking the stored asset digests.'
fi

for attempt in {1..15}; do
    if gh api "repos/$GH_REPO/releases/$release_id" > release.json &&
        python3 .github/scripts/verify-auralis-release.py release.json "$version" "$GITHUB_SHA" "installer/$asset" extensions/*.zip; then
        sha256sum "installer/$asset" extensions/*.zip
        if [[ "${AURALIS_ATTACH_ONLY:-0}" == 1 ]]; then
            echo "All assets verified on draft release $release_id."
            exit 0
        fi
        gh release edit "$tag" --draft=false --prerelease=false --latest
        test "$(gh api "repos/$GH_REPO/git/ref/tags/$tag" --jq .object.sha)" = "$GITHUB_SHA"
        exit
    fi
    echo "Waiting for verified assets ($attempt/15)."
    sleep 4
done
echo "::error::Release assets failed verification. $tag remains a draft."
exit 1
