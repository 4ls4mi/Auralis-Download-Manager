#!/usr/bin/env bash
# Publish verified build artifacts, optionally including the Linux and macOS packages.
set -euo pipefail

: "${GH_REPO:?Set GH_REPO to the build repository}"
: "${GITHUB_RUN_ID:?Missing workflow run ID}"
: "${GITHUB_SHA:?Missing verified build commit}"
[[ "$GITHUB_RUN_ID" =~ ^[0-9]+$ && "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]]
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
python3 -m unittest discover -s .github/scripts -p 'test_verify_auralis_release.py'

build_run="$GITHUB_RUN_ID"
build_commit="$GITHUB_SHA"
desktop="${AURALIS_DESKTOP_RELEASE:-0}"
[[ "$desktop" == 0 || ( "$desktop" == 1 && -z "${AURALIS_VERIFIED_RUN_ID:-}" ) ]]
if [[ -n "${AURALIS_VERIFIED_RUN_ID:-}" ]]; then
    build_run="$AURALIS_VERIFIED_RUN_ID"
    [[ "$build_run" =~ ^[0-9]+$ && "$build_run" != "$GITHUB_RUN_ID" ]]
    build_commit="$(gh api "repos/$GH_REPO/actions/runs/$build_run" | jq -er '
        select(.status == "completed" and .path == ".github/workflows/auralis-qt-windows.yml" and
               .head_branch == "wip/auralis-qt-shell" and .head_repository.id == .repository.id) |
        .head_sha | select(test("^[0-9a-f]{40}$"))
    ')"
    attempt="$(gh api --paginate "repos/$GH_REPO/actions/runs/$build_run/jobs?filter=all&per_page=100" |
        jq -ser --arg sha "$build_commit" '
            [.[] .jobs[] | select(.head_sha == $sha and .conclusion == "success" and
                 .name == "Build and verify the installed Qt application" and
                 any(.steps[]; .name == "Upload the verified installer" and .conclusion == "success") and
                 any(.steps[]; .name == "Upload the browser extension packages" and .conclusion == "success"))] |
            max_by(.run_attempt) | .run_attempt | select(type == "number" and . >= 1)
        ')"
    suffix=""
    if (( attempt > 1 )); then suffix="-attempt-$attempt"; fi
    artifacts="$(gh api --paginate "repos/$GH_REPO/actions/runs/$build_run/artifacts?per_page=100")"
    artifact_id_and_digest() {
        jq -ser --arg name "$1$suffix" '
            [.[] .artifacts[] | select(.name == $name and .expired == false)] |
            select(length == 1) | .[0] | "\(.id) \(.digest)"
        ' <<< "$artifacts"
    }
    read -r AURALIS_INSTALLER_ARTIFACT_ID AURALIS_INSTALLER_ARTIFACT_DIGEST \
        <<< "$(artifact_id_and_digest auralis-download-manager-windows-x64)"
    read -r AURALIS_EXTENSIONS_ARTIFACT_ID AURALIS_EXTENSIONS_ARTIFACT_DIGEST \
        <<< "$(artifact_id_and_digest auralis-browser-extensions)"
    echo "Publishing verified Windows artifacts from run $build_run, attempt $attempt, commit $build_commit."
    git fetch --no-tags --depth=1 origin "$build_commit"
fi
: "${AURALIS_INSTALLER_ARTIFACT_ID:?Missing installer artifact ID}"
: "${AURALIS_INSTALLER_ARTIFACT_DIGEST:?Missing installer artifact digest}"
: "${AURALIS_EXTENSIONS_ARTIFACT_ID:?Missing extension artifact ID}"
: "${AURALIS_EXTENSIONS_ARTIFACT_DIGEST:?Missing extension artifact digest}"

version="$(python3 - "$(git show "$build_commit:qt-ui/CMakeLists.txt")" <<'PY'
import re
import sys

match = re.search(r"project\s*\(\s*AuralisQt\s+VERSION\s+(\d+\.\d+\.\d+)\s", sys.argv[1])
if not match:
    raise SystemExit("AuralisQt project version not found")
print(match[1])
PY
)"
tag="v$version"
asset="Auralis.Download.Manager_${version}_x64-setup.exe"
release_name="Auralis Download Manager $version — Windows x64"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
notes="$work/release-notes.md"
git show "$build_commit:docs/glass-releases/$tag.md" > "$notes"
test -s "$notes" || { echo "Release notes are missing for $tag." >&2; exit 1; }
release_json="$work/release.json"
files=(
    "$work/installer/$asset"
    "$work/extensions/auralis-chromium.zip"
    "$work/extensions/auralis-firefox.zip"
)
if [[ "$desktop" == 1 ]]; then
    release_name="Auralis Download Manager $version"
    for platform in debian13_amd64.deb macos-arm64.dmg macos-x86_64.dmg; do
        file="$work/$platform/Auralis.Download.Manager_${version}_$platform"
        files+=("$file" "$file.sha256")
    done
fi

fetch_artifact() {
    local id="$1" digest="${2#sha256:}" name="$3" destination="$4"
    [[ "$id" =~ ^[0-9]+$ && "$digest" =~ ^[0-9a-f]{64}$ ]] || {
        echo "Invalid artifact ID or digest for $name." >&2
        return 1
    }
    gh api "repos/$GH_REPO/actions/artifacts/$id" |
        jq -e --arg sha "$build_commit" --arg digest "sha256:$digest" \
            --arg name "$name" --argjson artifact "$id" --argjson run "$build_run" '
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

if [[ "$desktop" == 1 ]]; then
    artifacts="$(gh api --paginate "repos/$GH_REPO/actions/runs/$build_run/artifacts?per_page=100")"
    fetch_desktop_artifact() {
        local name="$1" platform="$2" id digest
        read -r id digest <<< "$(jq -ser --arg name "$name" '
            [.[] .artifacts[] | select(.expired == false and
                (.name | test("^" + $name + "(-attempt-[0-9]+)?$")))] |
            max_by(.id) | select(. != null) | "\(.id) \(.digest)"
        ' <<< "$artifacts")"
        fetch_artifact "$id" "$digest" "$name" "$work/$platform.zip"
    }
    fetch_desktop_artifact auralis-download-manager-linux-debian13-amd64 debian13_amd64.deb
    fetch_desktop_artifact auralis-macos-arm64 macos-arm64.dmg
    fetch_desktop_artifact auralis-macos-x86_64 macos-x86_64.dmg
fi

python3 - "$work" "${files[@]}" <<'PY'
import hashlib
import shutil
import sys
import zipfile
from pathlib import Path

work = Path(sys.argv[1])
files = [Path(path) for path in sys.argv[2:]]
limits_mib = {"installer": 256, "extensions": 16, "debian13_amd64.deb": 128,
              "macos-arm64.dmg": 512, "macos-x86_64.dmg": 512}
for folder in dict.fromkeys(path.parent.name for path in files):
    archive_name = f"{'windows' if folder == 'installer' else folder}.zip"
    limit = limits_mib[folder] * 1024 * 1024
    destination = work / folder
    expected = [path.name for path in files if path.parent == destination]
    destination.mkdir()
    with zipfile.ZipFile(work / archive_name) as archive:
        if sorted(archive.namelist()) != sorted(expected):
            raise SystemExit(f"Unexpected file names in {archive_name}")
        for name in expected:
            asset_limit = 512 if name.endswith(".sha256") else limit
            if not 0 < archive.getinfo(name).file_size <= asset_limit:
                raise SystemExit(f"Invalid asset size: {name}")
            with archive.open(name) as source, (destination / name).open("xb") as target:
                shutil.copyfileobj(source, target)

for checksum in (path for path in files if path.suffix == ".sha256"):
    package = checksum.with_suffix("")
    with package.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    if checksum.read_text() != f"{digest}  {package.name}\n":
        raise SystemExit(f"Invalid checksum for {package.name}")
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
    python3 .github/scripts/verify-auralis-release.py "$@" "$release_json" "$version" "$build_commit" "${files[@]}"
}

verify_public_tag() {
    tag_exists && jq -e --arg sha "$build_commit" '.object.type == "commit" and .object.sha == $sha' "$work/tag.json" >/dev/null
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
        -f tag_name="$tag" -f target_commitish="$build_commit" \
        -f name="$release_name" \
        -F body="@$notes" -F draft=true -F prerelease=false > "$release_json"
    release_id="$(jq -er '.id | select(type == "number")' "$release_json")"
fi

refresh_verified_draft() {
    local attempt
    for attempt in {1..7}; do
        fetch_release
        jq -e --arg tag "$tag" --arg sha "$build_commit" \
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
echo "::error::Could not verify publication of $tag at $build_commit."
exit 1
