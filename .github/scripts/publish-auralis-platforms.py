import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote


REPO = '4ls4mi/Auralis-Download-Manager'
RELEASES = f'repos/{REPO}/releases'
DESKTOP_SHA = '9ea57f80ac2eb28ab29e13c79e71a548b39e368e'
ANDROID_SHA = '082ccaee847520df41e8c9b9ab0a1078bee29b28'
WINDOWS = 'Auralis.Download.Manager_0.3.76_x64-setup.exe'
LINUX = 'Auralis.Download.Manager_0.3.76_debian13_amd64.deb'
ANDROID = 'Auralis.Android_0.1.0.apk'
ARTIFACTS = {
    'windows': (14844895147, 45222671311, DESKTOP_SHA, ('0d11b64da80f5a5c2513508c4c7f5665148edf76aa29a76eae35b280c638151b'), (WINDOWS,)),
    'extensions': (14844810232, 45222671311, DESKTOP_SHA, '44d4ff88e28cee8ea53c56c444e52c1ceacd93eb0aefe768b3a3cfa5f840a055', ('auralis-chromium.zip', 'auralis-firefox.zip')),
    'linux': (14841873507, 45222671636, DESKTOP_SHA, 'cd038f95ca75a61512841ecb07777f972f7de2af0e4e6311bb44f7d70272c51a', (LINUX, LINUX + '.sha256')),
    'android': (14846176872, 45228928897, ANDROID_SHA, 'd65365bcbad9f5c9dda3d58b8ca283fd269adfd1a7e8cf1ff24c79cbae710d92', (ANDROID, ANDROID + '.sha256')),
}


def gh(*args, check=True):
    result = subprocess.run(['gh', 'api', *args], capture_output=True, text=True)
    if result.returncode and check:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip()[:350])
    return result


def api(*args):
    return json.loads(gh(*args).stdout)


def sha256(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def stage(key, output):
    artifact_id, run_id, commit, digest, names = ARTIFACTS[key]
    chosen = api(f'repos/{REPO}/actions/artifacts/{artifact_id}')
    assert not chosen['expired'] and chosen['id'] == artifact_id
    assert chosen['workflow_run']['id'] == run_id and chosen['workflow_run']['head_sha'] == commit
    assert chosen['digest'] == f'sha256:{digest}'
    archive_path = output / f'{key}.zip'
    with archive_path.open('xb') as destination:
        result = subprocess.run(['gh', 'api', f'repos/{REPO}/actions/artifacts/{artifact_id}/zip'],
                                stdout=destination, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f'GitHub could not download the verified {key} artifact')
    assert sha256(archive_path) == digest, f'{key} artifact SHA-256 differs'
    with zipfile.ZipFile(archive_path) as archive:
        assert sorted(archive.namelist()) == sorted(names), f'Unexpected files in {key} artifact'
        for name in names:
            info = archive.getinfo(name)
            assert 0 < info.file_size <= 256 * 1024 * 1024
            with archive.open(info) as source, (output / name).open('xb') as destination:
                shutil.copyfileobj(source, destination)
    archive_path.unlink()
    print(f'Verified {key} from Actions run {run_id}', flush=True)
    return [output / name for name in names]


def verify_checksum(path):
    expected, file = path.with_name(path.name + '.sha256').read_text().strip().split(maxsplit=1)
    assert Path(file.lstrip('*')).name == path.name and sha256(path) == expected


def verify_downloadables(kind, output):
    if kind == 'android':
        verify_checksum(output / ANDROID)
        with zipfile.ZipFile(output / ANDROID) as apk:
            assert 'AndroidManifest.xml' in apk.namelist()
            assert all(f'lib/{abi}/libauralis_android.so' in apk.namelist() for abi in ('arm64-v8a', 'x86_64'))
    else:
        verify_checksum(output / LINUX)
        with (output / LINUX).open('rb') as package:
            assert package.read(8) == b'!<arch>\n'
        with (output / WINDOWS).open('rb') as installer:
            assert installer.read(2) == b'MZ'
        for name in ARTIFACTS['extensions'][-1]:
            with zipfile.ZipFile(output / name) as extension:
                assert 'manifest.json' in extension.namelist()
                assert extension.testzip() is None


def publish(kind, files):
    android = kind == 'android'
    if android:
        tag, commit = 'android-v0.1.0', ANDROID_SHA
        title = 'Auralis for Android 0.1.0 — Public preview'
        notes = '''Auralis for Android supports direct HTTP and HTTPS downloads on Android 10 and later (ARM64 and x86-64).

- Use up to eight connections when the server supports byte ranges.
- Pause and resume a transfer using data already saved on the device.
- Keep a persistent download queue and save finished files to Downloads/Auralis.

Download the APK below for a fresh install. This preview APK uses debug signing. The Android 15 x86-64 emulator test verified segmented transfers, queue order, resumption, and the exact bytes of both completed files.
'''
    else:
        tag, commit = 'v0.3.76', DESKTOP_SHA
        title = 'Auralis Download Manager 0.3.76'
        notes = subprocess.check_output(['git', 'show', f'{commit}:docs/glass-releases/{tag}.md'], text=True)
        notes += '\n## Downloads\n\n- Windows x64 installer and Chromium and Firefox extension packages.\n'
        notes += '- Debian 13 AMD64 package and SHA-256 checksum.\n'

    existing = [item for item in api(f'{RELEASES}?per_page=100') if item['tag_name'] == tag]
    if existing:
        assert len(existing) == 1, f'Multiple releases for {tag}'
        release = existing[0]
    else:
        assert gh(f'repos/{REPO}/git/ref/tags/{tag}', check=False).returncode, f'Tag {tag} already exists'
        release = api('--method', 'POST', RELEASES, '-f', f'tag_name={tag}', '-f', f'target_commitish={commit}',
                      '-f', f'name={title}', '-f', f'body={notes}', '-F', 'draft=true',
                      '-F', f'prerelease={str(android).lower()}')
    assert release['tag_name'] == tag and release['target_commitish'] == commit
    assert release['prerelease'] is android
    release_id = release['id']
    endpoint = f'{RELEASES}/{release_id}'
    expected = {file.name: (file.stat().st_size, 'sha256:' + sha256(file)) for file in files}

    def assets():
        current = api(endpoint)
        assert current['tag_name'] == tag and current['target_commitish'] == commit
        assert current['prerelease'] is android
        by_name = {candidate['name']: candidate for candidate in current['assets']}
        assert len(by_name) == len(current['assets']) and (by_name.keys() <= expected.keys())
        return current, by_name

    for file in files:
        for attempt in range(3):
            current, by_name = assets()
            entry = by_name.get(file.name)
            if entry and entry['state'] == 'uploaded':
                assert (entry['size'], entry['digest']) == expected[file.name]
                break
            assert current['draft'], f'{tag} is already public with missing assets'
            if entry:
                assert entry['state'] == 'starter' and entry['size'] == 0
                gh('--method', 'DELETE', f'{RELEASES}/assets/{entry["id"]}')
            upload = gh('--method', 'POST', '-H', 'Content-Type: application/octet-stream',
                       '--input', str(file), f'https://uploads.github.com/{RELEASES}/{release_id}/assets?name={quote(file.name)}',
                       check=False)
            if upload.returncode == 0:
                entry = json.loads(upload.stdout)
                if entry['state'] == 'uploaded' and (entry['size'], entry['digest']) == expected[file.name]:
                    print(f'Uploaded {file.name}', flush=True)
                    break
            if attempt < 2:
                time.sleep(3)
        else:
            raise RuntimeError(f'{file.name} upload failed: {upload.stderr.strip()}')

    def verify(public):
        current, by_name = assets()
        assert current['draft'] is not public
        assert by_name.keys() == expected.keys()
        for name, entry in by_name.items():
            assert entry['state'] == 'uploaded' and (entry['size'], entry['digest']) == expected[name]
            if public:
                assert entry['browser_download_url'] == f'https://github.com/{REPO}/releases/download/{tag}/{quote(name)}'
        return current

    current = api(endpoint)
    if current['draft']:
        verify(public=False)
        api('--method', 'PATCH', endpoint, '-F', 'draft=false', '-f', 'make_latest=' + str(not android).lower())
    checked = verify(public=True)
    ref = api(f'repos/{REPO}/git/ref/tags/{tag}')
    assert ref['object']['type'] == 'commit' and ref['object']['sha'] == commit
    if not android:
        assert api(f'{RELEASES}/latest')['id'] == release_id
    print(f'Public release verified {checked["html_url"]}', flush=True)


def main():
    kind = sys.argv[1]
    assert kind in ('desktop', 'android')
    keys = ('android',) if kind == 'android' else ('windows', 'linux', 'extensions')
    with tempfile.TemporaryDirectory(prefix='auralis-public-release-') as temp:
        output = Path(temp)
        with ThreadPoolExecutor(max_workers=len(keys)) as pool:
            jobs = [pool.submit(stage, key, output) for key in keys]
            files = [path for job in jobs for path in job.result()]
        verify_downloadables(kind, output)
        publish(kind, files)


if __name__ == '__main__':
    main()
