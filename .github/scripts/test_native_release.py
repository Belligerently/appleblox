import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('native_release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def ref(tag, sha='a' * 40):
    return {'ref': 'refs/tags/' + tag, 'object': {'sha': sha}}


class VersionTests(unittest.TestCase):
    def test_reset_ignores_upstream_tags(self):
        self.assertEqual(release.choose_tag([ref('v0.9.0')], 'b'*40, True, '0.1.0'), 'native-v0.1.0')

    def test_patch_increases_numerically_and_dev_does_not_consume_stable(self):
        refs = [ref('native-v0.1.9'), ref('native-v0.1.10'), ref('native-v0.1.99-dev.gabcdef')]
        self.assertEqual(release.choose_tag(refs, 'b'*40, True, '0.1.0'), 'native-v0.1.11')

    def test_retry_reuses_commit_and_channel(self):
        sha = 'a'*40
        refs = [ref('native-v0.1.0-dev.g' + sha), ref('native-v0.1.2')]
        self.assertEqual(release.choose_tag(refs, sha, True, '0.1.0'), 'native-v0.1.2')
        self.assertEqual(release.choose_tag(refs, sha, False, '0.1.0'), 'native-v0.1.0-dev.g' + sha)

    def test_development_numbers_advance_without_using_stable_patch(self):
        refs = [ref('native-v0.1.0-dev.1')]
        self.assertEqual(release.choose_tag(refs, 'b'*40, False, '0.1.0'), 'native-v0.1.0-dev.2')
        refs.append(ref('native-v0.1.0'))
        self.assertEqual(release.choose_tag(refs, 'b'*40, False, '0.1.0'), 'native-v0.1.1-dev.1')

    def test_new_minor_floor(self):
        self.assertEqual(release.choose_tag([ref('native-v0.1.10')], 'b'*40, True, '0.2.0'), 'native-v0.2.0')

    def test_atomic_collision_allocates_next_patch(self):
        class API:
            def __init__(self):
                self.refs = []
                self.calls = 0
            def tags(self):
                return self.refs
            def request(self, method, path, data):
                self.calls += 1
                if self.calls == 1:
                    self.refs = [ref('native-v0.1.0')]
                    raise urllib.error.HTTPError('', 422, 'already exists', {}, None)
                self.refs.append(ref(data['ref'].removeprefix('refs/tags/'), data['sha']))
        api = API()
        self.assertEqual(release.reserve_tag(api, 'b'*40, True), 'native-v0.1.1')

    def test_bundle_stamp_keeps_numeric_short_version(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app/'Contents').mkdir()
            with (app/'Contents/Info.plist').open('wb') as stream:
                plistlib.dump({'CFBundleIdentifier': 'keep.me'}, stream)
            release.stamp(app, '0.1.0-dev.gabc', '123456.1')
            with (app/'Contents/Info.plist').open('rb') as stream:
                result = plistlib.load(stream)
            self.assertEqual(result['CFBundleShortVersionString'], '0.1.0')
            self.assertEqual(result['AppleBloxReleaseVersion'], '0.1.0-dev.gabc')
            self.assertEqual(result['CFBundleIdentifier'], 'keep.me')


class PlanningTests(unittest.TestCase):
    def test_paths(self):
        for path in ['native/Sources/App.swift', 'native/Resources/Info.plist', 'native/build.sh', 'LICENSE', '.github/workflows/build.yml']:
            self.assertTrue(release.app_related(path), path)
        for path in ['README.md', 'native/README.md', 'frontend/src/main.ts', '.github/assets/logo.png',
                     'legacy/frontend/src/main.ts', 'legacy/scripts/package/dev.ts', 'legacy/package.json',
                     'legacy/.github/assets/logo.png']:
            self.assertFalse(release.app_related(path), path)

    def test_real_history_multi_commit_docs_merge_and_new_branch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
            git('init', '-b', 'main')
            git('config', 'user.name', 'Release test')
            git('config', 'user.email', 'test@example.invalid')
            def commit(path, text):
                target = root/path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)
                git('add', '.')
                git('commit', '-qm', text)
                return git('rev-parse', 'HEAD')
            baseline = commit('README.md', 'baseline')
            first = commit('native/Sources/App.swift', 'first')
            commit('native/README.md', 'docs only')
            second = commit('native/Sources/App.swift', 'second')
            with patch.object(release, 'ROOT', root), patch.dict(release.CONFIG, history_start=baseline):
                # run's default cwd is bound at definition; route it to this real scratch repo.
                with patch.object(release, 'run', side_effect=lambda *args: git(*args[1:])):
                    event = {'before': baseline, 'after': second}
                    self.assertEqual(release.plan(event, 'push', second), [first, second])
                    event['before'] = '0'*40
                    self.assertEqual(release.plan(event, 'push', second), [first, second])
                    git('checkout', '-qb', 'feature')
                    commit('native/Sources/New.swift', 'feature work')
                    git('checkout', 'main')
                    git('merge', '--no-ff', '-m', 'merge feature', 'feature')
                    merge = git('rev-parse', 'HEAD')
                    self.assertEqual(release.plan({'before': second, 'after': merge}, 'push', merge), [merge])

    def test_manual_and_delete(self):
        self.assertEqual(release.plan({}, 'workflow_dispatch', 'abc'), ['abc'])
        self.assertEqual(release.plan({'deleted': True}, 'push', 'abc'), [])
        self.assertEqual(release.plan({}, 'pull_request', 'abc'), [])


class PublicationTests(unittest.TestCase):
    def test_assets_are_uploaded_before_release_is_published(self):
        class API:
            def __init__(self):
                self.calls = []
            def request(self, method, path, data=None, binary=None):
                self.calls.append((method, path, data))
                if method == 'POST' and path == '/releases':
                    return {'id': 4, 'draft': True, 'assets': [], 'upload_url': 'https://uploads.github.com/test{?name}'}
                return {'html_url': 'https://github.com/test/release'}
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory)/'app.zip'
            file.write_bytes(b'bundle')
            api = API()
            release.publish(api, 'native-v0.1.0-dev.1', 'a'*40, 'feature', [file], None)
            self.assertTrue(api.calls[0][2]['draft'])
            self.assertEqual(api.calls[1][0], 'POST')
            self.assertEqual(api.calls[-1][0], 'PATCH')
            self.assertEqual(api.calls[-1][2]['make_latest'], 'false')
            self.assertTrue(api.calls[-1][2]['prerelease'])

    def test_upload_failure_leaves_release_in_draft(self):
        class API:
            def __init__(self):
                self.published = False
            def request(self, method, path, data=None, binary=None):
                if method == 'PATCH':
                    self.published = True
                if binary is not None:
                    raise OSError('Upload interrupted')
                return {'id': 4, 'draft': True, 'assets': [], 'upload_url': 'https://uploads.github.com/test{?name}'}
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory)/'app.zip'
            file.write_bytes(b'bundle')
            api = API()
            with self.assertRaises(OSError):
                release.publish(api, 'native-v0.1.0', 'a'*40, 'main', [file], None)
            self.assertFalse(api.published)


if __name__ == '__main__':
    unittest.main()
