#!/usr/bin/env bash
# Publish only the installer and extensions uploaded by this run's verified Windows job.
set -euo pipefail

: "${GH_REPO:?Set GH_REPO to the build repository}"
: "${GITHUB_RUN_ID:?Missing workflow run ID}"
: "${GITHUB_SHA:?Missing verified build commit}"
: "${AURALIS_INSTALLER_ARTIFACT_ID:?Missing installer artifact ID}"
: "${AURALIS_INSTALLER_ARTIFACT_DIGEST:?Missing installer artifact digest}"
: "${AURALIS_EXTENSIONS_ARTIFACT_ID:?Missing extension artifact ID}"
: "${AURALIS_EXTENSIONS_ARTIFACT_DIGEST:?Missing extension artifact digest}"
[[ "$GITHUB_RUN_ID" =~ ^[0-9]+$ && "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]]
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
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
test -s "$notes" || { echo "Release notes are missing: $notes" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
release_json="$work/release.json"
files=(
    "$work/installer/$asset"
    "$work/extensions/auralis-chromium.zip"
    "$work/extensions/auralis-edge-store.zip"
    "$work/extensions/auralis-firefox.zip"
)

fetch_artifact() {
    local id="$1" digest="${2#sha256:}" name="$3" destination="$4"
    [[ "$id" =~ ^[0-9]+$ && "$digest" =~ ^[0-9a-f]{64}$ ]] || {
        echo "Invalid artifact ID or digest for $name." >&2
        return 1
    }
    gh api "repos/$GH_REPO/actions/artifacts/$id" |
        jq -e --arg sha "$GITHUB_SHA" --arg digest "sha256:$digest" \
            --arg name "$name" --argjson artifact "$id" --argjson run "$GITHUB_RUN_ID" '
            .id == $artifact and .expired == false and .digest == $digest and
            (.name | test("^" + $name + "(-attempt-[0-9]+)?$")) and
            .workflow_run.id == $run and .workflow_run.head_sha == $sha
        ' >/dev/null
    if ! gh api "repos/$GH_REPO/actions/artifacts/$id/zip" > "$destination" 2> "$work/artifact-error"; then
        echo "Could not download the verified $name artifact." >&2
        return 1
    fi
    printf '%s  %s\n' "$digest" "$destination" | sha256sum --check
}

fetch_artifact "$AURALIS_INSTALLER_ARTIFACT_ID" "$AURALIS_INSTALLER_ARTIFACT_DIGEST" \
    auralis-download-manager-windows-x64 "$work/windows.zip"
fetch_artifact "$AURALIS_EXTENSIONS_ARTIFACT_ID" "$AURALIS_EXTENSIONS_ARTIFACT_DIGEST" \
    auralis-browser-extensions "$work/extensions.zip"

python3 - "$work" "$asset" <<'PY'
import shutil
import sys
import zipfile
from pathlib import Path

work = Path(sys.argv[1])
for archive_name, folder, expected, limit in (
    ("windows.zip", "installer", [sys.argv[2]], 256 * 1024 * 1024),
    ("extensions.zip", "extensions", ["auralis-chromium.zip", "auralis-edge-store.zip", "auralis-firefox.zip"], 16 * 1024 * 1024),
):
    destination = work / folder
    destination.mkdir()
    with zipfile.ZipFile(work / archive_name) as archive:
        if sorted(archive.namelist()) != sorted(expected):
            raise SystemExit(f"Unexpected file names in {archive_name}")
        for name in expected:
            if not 0 < archive.getinfo(name).file_size <= limit:
                raise SystemExit(f"Invalid asset size: {name}")
            with archive.open(name) as source, (destination / name).open("xb") as target:
                shutil.copyfileobj(source, target)
PY

find_release_id() {
    gh api --paginate "repos/$GH_REPO/releases?per_page=100" \
        --jq ".[] | select(.tag_name==\"$tag\") | .id"
}

fetch_release() {
    gh api "repos/$GH_REPO/releases/$release_id" > "$release_json"
}

tag_exists() {
    if gh api "repos/$GH_REPO/git/ref/tags/$tag" > "$work/tag.json" 2> "$work/tag-error"; then
        return 0
    fi
    if jq -e '(.status | tostring) == "404"' "$work/tag.json" >/dev/null; then
        return 1
    fi
    echo "Unable to determine whether $tag already exists." >&2
    exit 1
}

verify_release() {
    python3 .github/scripts/verify-auralis-release.py "$@" "$release_json" "$version" "$GITHUB_SHA" "${files[@]}"
}

verify_public_tag() {
    tag_exists && jq -e --arg sha "$GITHUB_SHA" '.object.type == "commit" and .object.sha == $sha' "$work/tag.json" >/dev/null
}

release_id="$(find_release_id)"
if [[ -n "$release_id" ]]; then
    [[ "$release_id" =~ ^[0-9]+$ ]] || { echo "Multiple releases exist for $tag." >&2; exit 1; }
    fetch_release
    if jq -e '.draft == false' "$release_json" >/dev/null; then
        verify_release --published
        verify_public_tag
        echo "$tag is already published with the verified assets."
        exit 0
    fi
fi

if tag_exists; then
    echo "Tag $tag already exists without a matching published release. Leaving it unchanged." >&2
    exit 1
fi

if [[ -z "$release_id" ]]; then
    gh api --method POST "repos/$GH_REPO/releases" \
        -f tag_name="$tag" -f target_commitish="$GITHUB_SHA" \
        -f name="Auralis Download Manager $version — Windows x64" \
        -F body="@$notes" -F draft=true -F prerelease=false > "$release_json"
    release_id="$(jq -er '.id | select(type == "number")' "$release_json")"
fi

refresh_verified_draft() {
    local attempt
    for attempt in {1..7}; do
        fetch_release
        jq -e --arg tag "$tag" --arg sha "$GITHUB_SHA" \
            '.draft and .tag_name == $tag and .target_commitish == $sha' "$release_json" >/dev/null
        if verify_release --partial; then return 0; fi
        if (( attempt < 7 )); then sleep 2; fi
    done
    echo "Existing draft assets could not be verified. Leaving $tag unpublished." >&2
    return 1
}

for file in "${files[@]}"; do
    refresh_verified_draft
    name="${file##*/}"
    state="$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .state' "$release_json")"
    if [[ "$state" == uploaded ]]; then
        continue
    fi
    if [[ "$state" == starter ]]; then
        # GitHub may leave a zero-byte placeholder after an interrupted upload.
        starter_id="$(jq -er --arg name "$name" '
            .assets[] | select(.name == $name and .state == "starter" and .size == 0) | .id | select(type == "number")
        ' "$release_json")"
        gh api --method DELETE "repos/$GH_REPO/releases/assets/$starter_id" >/dev/null
    fi
    if ! gh api --method POST -H 'Content-Type: application/octet-stream' --input "$file" \
        "https://uploads.github.com/repos/$GH_REPO/releases/$release_id/assets?name=$name" > "$work/upload.json"; then
        echo "::warning::The upload reported an error for $name. Verifying the actual stored assets."
    fi
done

verified=0
for attempt in {1..10}; do
    if fetch_release && verify_release; then
        verified=1
        break
    fi
    if (( attempt < 10 )); then sleep 3; fi
done
if (( ! verified )); then
    echo "::error::Release assets failed verification. $tag remains a draft."
    exit 1
fi
sha256sum "${files[@]}"

if tag_exists; then
    echo "Tag $tag appeared before publication. Leaving the release draft unchanged." >&2
    exit 1
fi
if ! gh api --method PATCH "repos/$GH_REPO/releases/$release_id" \
    -F draft=false -f make_latest=true > "$work/published.json"; then
    echo "::warning::Publication reported an error. Checking the actual release state."
fi
for attempt in {1..10}; do
    if fetch_release && verify_release --published && verify_public_tag &&
        [[ "$(gh api "repos/$GH_REPO/releases/latest" --jq .id)" == "$release_id" ]]; then
        jq -er '.html_url' "$release_json"
        exit 0
    fi
    if (( attempt < 10 )); then sleep 3; fi
done
echo "::error::Could not verify publication of $tag at $GITHUB_SHA."
exit 1
