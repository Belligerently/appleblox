#!/usr/bin/env python3
"""Select native app commits and publish tested macOS bundles. Standard library only."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
CONFIG = json.loads(Path(__file__).with_name('release_config.json').read_text())


def run(*args, cwd=ROOT, env=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True).strip()


def app_related(path):
    if path in {'LICENSE', '.github/workflows/build.yml'}:
        return True
    if path.startswith('.github/scripts/'):
        return not path.endswith('.md')
    return path.startswith('native/') and not path.lower().endswith('.md')


def plan(event, event_name, sha):
    if event_name in {'workflow_dispatch', 'pull_request'}:
        return [sha] if event_name == 'workflow_dispatch' else []
    if event.get('deleted'):
        return []
    after = event.get('after', sha)
    before = event.get('before', '')
    revisions = [after, '^' + CONFIG['history_start']]
    if before and set(before) != {'0'}:
        # A force-push may remove the old tip from the checkout's reachable refs.
        try:
            run('git', 'cat-file', '-e', before + '^{commit}')
        except subprocess.CalledProcessError:
            run('git', 'fetch', '--no-tags', 'origin', before)
        revisions.append('^' + before)
    commits = run('git', 'rev-list', '--reverse', '--first-parent', *revisions).splitlines()
    selected = []
    for commit in commits:
        # Compare merges with their first parent rather than an empty combined diff.
        paths = run('git', 'diff-tree', '--root', '--no-commit-id', '--name-only',
                    '-r', '-m', '--first-parent', commit).splitlines()
        if any(app_related(path) for path in paths):
            selected.append(commit)
    return selected


class GitHub:
    def __init__(self, repository, token):
        self.base = f'https://api.github.com/repos/{repository}'
        self.token = token

    def request(self, method, path, data=None, binary=None):
        url = path if path.startswith('https://') else self.base + path
        body = binary if binary is not None else (json.dumps(data).encode() if data is not None else None)
        headers = {'Authorization': 'Bearer ' + self.token,
                   'Accept': 'application/vnd.github+json',
                   'X-GitHub-Api-Version': '2022-11-28',
                   'Content-Type': 'application/octet-stream' if binary is not None else 'application/json'}
        with urllib.request.urlopen(urllib.request.Request(url, body, headers, method=method), timeout=120) as response:
            return json.load(response) if response.status != 204 else None

    def optional(self, path):
        try:
            return self.request('GET', path)
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            return None

    def tags(self):
        # This endpoint returns all matching refs (not the paginated releases list).
        return self.optional('/git/matching-refs/tags/native-v') or []


def choose_tag(refs, sha, stable, floor):
    """Reuse the same commit/channel on rerun; otherwise advance stable patch only."""
    stable_re = re.compile(r'^refs/tags/native-v(\d+)\.(\d+)\.(\d+)$')
    floor_tuple = tuple(map(int, floor.split('.')))
    versions = []
    for ref in refs:
        name = ref['ref']
        match = stable_re.fullmatch(name)
        same_channel = bool(match) if stable else name.startswith('refs/tags/native-v') and '-dev.' in name
        if same_channel and ref['object']['sha'] == sha:
            return name.removeprefix('refs/tags/')
        if match:
            versions.append(tuple(map(int, match.groups())))
    highest = max(versions, default=(0, 0, 0))
    version = floor_tuple if highest < floor_tuple else (highest[0], highest[1], highest[2] + 1)
    base = 'native-v' + '.'.join(map(str, version))
    if stable:
        return base
    dev_re = re.compile(r'^refs/tags/' + re.escape(base) + r'-dev\.(\d+)$')
    numbers = [int(match.group(1)) for ref in refs if (match := dev_re.fullmatch(ref['ref']))]
    return base + '-dev.' + str(max(numbers, default=0) + 1)


def reserve_tag(api, sha, stable):
    for _ in range(30):
        refs = api.tags()
        tag = choose_tag(refs, sha, stable, CONFIG['version_floor'])
        if any(ref['ref'] == 'refs/tags/' + tag for ref in refs):
            return tag
        try:
            api.request('POST', '/git/refs', {'ref': 'refs/tags/' + tag, 'sha': sha})
            return tag
        except urllib.error.HTTPError as error:
            if error.code not in {409, 422}:
                raise
            # Another push reserved this version. Refresh refs and choose again.
    raise RuntimeError('Could not reserve a release tag after 30 attempts')


def stamp(app, version, build):
    path = app / 'Contents/Info.plist'
    with path.open('rb') as stream:
        info = plistlib.load(stream)
    info['CFBundleShortVersionString'] = version.split('-')[0]
    info['CFBundleVersion'] = str(build)
    info['AppleBloxReleaseVersion'] = version
    with path.open('wb') as stream:
        plistlib.dump(info, stream)


def package(app, version, build, destination):
    stamp(app, version, build)
    run('codesign', '--force', '--sign', '-', str(app))
    run('codesign', '--verify', '--deep', '--strict', str(app))
    architectures = set(run('lipo', '-archs', str(app / 'Contents/MacOS/AppleBloxNative')).split())
    if architectures != {'arm64', 'x86_64'}:
        raise RuntimeError('Release executable must contain arm64 and x86_64')
    destination.mkdir(parents=True, exist_ok=True)
    prefix = 'AppleBlox-Native-' + version + '-universal'
    archive = destination / (prefix + '.zip')
    run('ditto', '-c', '-k', '--keepParent', str(app), str(archive))
    image = destination / (prefix + '.dmg')
    # Separate staging directory keeps zip/checksums out of the disk image.
    import tempfile
    with tempfile.TemporaryDirectory() as staging:
        run('ditto', str(app), str(Path(staging) / app.name))
        (Path(staging) / 'Applications').symlink_to('/Applications')
        run('hdiutil', 'create', '-ov', '-format', 'UDZO', '-volname', 'AppleBlox Native',
            '-srcfolder', staging, str(image))
    sums = destination / (prefix + '-SHA256SUMS.txt')
    sums.write_text(''.join(f'{hashlib.sha256(file.read_bytes()).hexdigest()}  {file.name}\n'
                            for file in (archive, image)))
    return [archive, image, sums]


def publish(api, tag, sha, branch, files, existing):
    stable = branch == CONFIG['stable_branch']
    version = tag.removeprefix('native-v')
    body = (f'Automated native build from `{branch}` at `{sha}`.\n\n'
            'Universal app for Apple Silicon and Intel; macOS 14 or later. '
            'Download the DMG or ZIP below.\n\n'
            'This build is ad-hoc signed and is not Apple notarized. '
            'Original AppleBlox and logo attribution are included in the app.\n')
    release = existing
    if release is None:
        try:
            release = api.request('POST', '/releases', {
                'tag_name': tag, 'target_commitish': sha,
                'name': 'AppleBlox Native ' + version,
                'body': body, 'draft': True, 'prerelease': not stable})
        except urllib.error.HTTPError as error:
            if error.code != 422:
                raise
            release = api.request('GET', '/releases/tags/' + tag)
    if not release['draft']:
        return release
    upload_url = release['upload_url'].split('{')[0]
    # Recover interrupted draft uploads without modifying a published release.
    for file in files:
        prior = next((asset for asset in release['assets'] if asset['name'] == file.name), None)
        if prior:
            api.request('DELETE', '/releases/assets/' + str(prior['id']))
        api.request('POST', upload_url + '?name=' + urllib.parse.quote(file.name), binary=file.read_bytes())
    return api.request('PATCH', '/releases/' + str(release['id']), {
        'draft': False, 'prerelease': not stable,
        'make_latest': 'legacy' if stable else 'false'})


def release_all(commits):
    repository = os.environ['GITHUB_REPOSITORY']
    branch = os.environ['GITHUB_REF_NAME']
    api = GitHub(repository, os.environ.pop('GH_TOKEN'))
    # Build subprocesses never receive the release credential.
    child_env = dict(os.environ)
    child_env.pop('GITHUB_TOKEN', None)
    child_env['APPLEBLOX_UNIVERSAL'] = '1'
    destination = ROOT / 'release-packages'
    failures = []
    for index, sha in enumerate(commits, 1):
        if not re.fullmatch(r'[0-9a-f]{40}', sha):
            raise ValueError('Invalid commit SHA')
        worktree = Path(os.environ['RUNNER_TEMP']) / ('native-' + sha)
        stable = branch == CONFIG['stable_branch']
        # Skip already published commit/channel builds, including workflow retries.
        refs = api.tags()
        known_tag = choose_tag(refs, sha, stable, CONFIG['version_floor'])
        owns_tag = any(ref['ref'] == 'refs/tags/' + known_tag and ref['object']['sha'] == sha for ref in refs)
        existing = api.optional('/releases/tags/' + known_tag) if owns_tag else None
        if existing and not existing['draft']:
            print('Already published: ' + existing['html_url'], flush=True)
            continue
        try:
            run('git', 'worktree', 'add', '--detach', str(worktree), sha)
            child_env['APPLEBLOX_NATIVE_ROOT'] = str(worktree / 'native')
            subprocess.run(['bash', 'native/test.sh'], cwd=worktree, env=child_env, check=True)
            subprocess.run(['bash', str(ROOT / 'native/build.sh')], cwd=worktree, env=child_env, check=True)
            # Allocate only after tests/build succeed. Atomic tag creation handles overlapping pushes.
            tag = reserve_tag(api, sha, stable)
            existing = api.optional('/releases/tags/' + tag)
            if existing and not existing['draft']:
                continue
            version = tag.removeprefix('native-v')
            # Run ID is increasing across workflow files; suffix distinguishes commits in one push.
            build = f"{os.environ['GITHUB_RUN_ID']}.{index}"
            files = package(worktree / 'native/dist/AppleBlox Native.app', version, build, destination)
            published = publish(api, tag, sha, branch, files, existing)
            print('Published: ' + published['html_url'], flush=True)
            summary = os.environ.get('GITHUB_STEP_SUMMARY')
            if summary:
                with open(summary, 'a') as stream:
                    stream.write(f"- [{version}]({published['html_url']}) — `{sha[:12]}`\n")
        except Exception as error:
            print(f'::error::Release failed for {sha}: {error}', flush=True)
            failures.append(sha)
        finally:
            if worktree.exists():
                run('git', 'worktree', 'remove', '--force', str(worktree))
    if failures:
        raise RuntimeError('Rerun failed jobs to retry these commits: ' + ', '.join(failures))


def main():
    if sys.argv[1:] == ['plan']:
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        commits = plan(event, os.environ['GITHUB_EVENT_NAME'], os.environ['GITHUB_SHA'])
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            stream.write('commits=' + json.dumps(commits) + '\n')
            stream.write('has_commits=' + str(bool(commits)).lower() + '\n')
        print(f'{len(commits)} native app commit(s) selected')
    elif sys.argv[1:] == ['release']:
        release_all(json.loads(os.environ['RELEASE_COMMITS']))
    else:
        raise SystemExit('Usage: native_release.py plan|release')


if __name__ == '__main__':
    main()
