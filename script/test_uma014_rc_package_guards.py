#!/usr/bin/env python3
"""Isolated refusal and linkage tests; no compiler, installed app, or provider use."""
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('rc_packager', Path(__file__).with_name('package_uma014_rc.py'))
rc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rc)


class RCGuards(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='uma014-rc-guards-')
        self.root = Path(self.temp.name).resolve()
        self.addCleanup(self.temp.cleanup)

    def test_output_guards_refuse_without_creation(self):
        parent = self.root / 'Packages'
        parent.mkdir()
        pattern = r'uma-0\.14-rc-\d{8}T\d{6}Z'
        good = parent / 'uma-0.14-rc-20260905T010000Z'
        self.assertEqual(rc.output_path(str(good), parent, pattern), good)
        cases = ['relative', '/', str(parent / '../uma-0.14-rc-20260905T010000Z'),
                 str(parent / './x'), str(parent / 'UMA.app'), str(parent / 'existing'),
                 str(self.root / 'uma-0.14-rc-20260905T010000Z')]
        for candidate in cases:
            with self.subTest(candidate=candidate), self.assertRaises(rc.Refusal):
                rc.output_path(candidate, parent, pattern)
        self.assertFalse(good.exists())
        good.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'ALREADY_EXISTS'):
            rc.output_path(str(good), parent, pattern)

    def test_symlink_parent_refused(self):
        real = self.root / 'real'
        real.mkdir()
        alias = self.root / 'Packages'
        alias.symlink_to(real, target_is_directory=True)
        with self.assertRaisesRegex(rc.Refusal, 'SYMLINK'):
            rc.output_path(str(alias / 'uma-0.14-rc-20260905T010000Z'), alias,
                           r'uma-0\.14-rc-\d{8}T\d{6}Z')
        self.assertEqual(list(real.iterdir()), [])

    def test_dangling_output_refused(self):
        output = self.root / 'uma-0.14-rc-20260905T010000Z'
        output.symlink_to(self.root / 'absent')
        with self.assertRaisesRegex(rc.Refusal, 'SYMLINK'):
            rc.output_path(str(output), self.root, r'uma-0\.14-rc-\d{8}T\d{6}Z')

    def test_app_ancestor_refused(self):
        parent = self.root / 'Installed.app' / 'Packages'
        with self.assertRaisesRegex(rc.Refusal, 'APP_DESTINATION'):
            rc.output_path(str(parent / 'uma-0.14-rc-20260905T010000Z'), parent,
                           r'uma-0\.14-rc-\d{8}T\d{6}Z')

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.root), *args], check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode().strip()

    def repository(self):
        self.git('init', '-b', 'codex/uma-0.14-surface-rebuild')
        self.git('config', 'user.name', 'Isolated Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        (self.root / 'file').write_text('accepted\n')
        self.git('add', '--', 'file')
        self.git('commit', '-m', 'fixture', '--no-gpg-sign')
        return self.git('rev-parse', 'HEAD'), self.git('rev-parse', 'HEAD^{tree}')

    def test_clean_source_and_archive_bound_to_commit(self):
        commit, tree = self.repository()
        self.assertEqual(rc.source_state(self.root, commit, tree), 'codex/uma-0.14-surface-rebuild')
        destination = self.root.parent / (self.root.name + '-archive')
        self.addCleanup(lambda: __import__('shutil').rmtree(destination, ignore_errors=True))
        rc.extract_source(self.root, commit, destination)
        self.assertEqual((destination / 'file').read_text(), 'accepted\n')
        self.assertFalse((destination / '.git').exists())

    def test_dirty_untracked_and_staged_each_refused(self):
        commit, tree = self.repository()
        original = self.root / 'file'
        original.write_text('dirty\n')
        with self.assertRaisesRegex(rc.Refusal, 'NOT_CLEAN'):
            rc.source_state(self.root, commit, tree)
        original.write_text('accepted\n')
        untracked = self.root / 'untracked'
        untracked.write_text('wip\n')
        with self.assertRaisesRegex(rc.Refusal, 'NOT_CLEAN'):
            rc.source_state(self.root, commit, tree)
        untracked.unlink()
        original.write_text('staged\n')
        self.git('add', '--', 'file')
        with self.assertRaisesRegex(rc.Refusal, 'NOT_CLEAN'):
            rc.source_state(self.root, commit, tree)

    def test_commit_tree_and_branch_mismatch_refused(self):
        commit, tree = self.repository()
        for expected_commit, expected_tree, error in [('z'*40, tree, 'ID_INVALID'),
              ('0'*40, tree, 'COMMIT_MISMATCH'), (commit, '0'*40, 'TREE_MISMATCH')]:
            with self.subTest(error=error), self.assertRaisesRegex(rc.Refusal, error):
                rc.source_state(self.root, expected_commit, expected_tree)
        self.git('checkout', '-b', 'wrong-branch')
        with self.assertRaisesRegex(rc.Refusal, 'BRANCH_MISMATCH'):
            rc.source_state(self.root, commit, tree)

    def test_archive_rejects_symlink(self):
        commit, _ = self.repository()
        (self.root / 'escape').symlink_to('/etc/passwd')
        self.git('add', '--', 'escape')
        self.git('commit', '-m', 'symlink fixture', '--no-gpg-sign')
        commit = self.git('rev-parse', 'HEAD')
        with self.assertRaisesRegex(rc.Refusal, 'SPECIAL_FILE'):
            rc.extract_source(self.root, commit, self.root / 'archive')

    def test_canonical_metadata_and_invalid_build(self):
        authority, metadata, version = rc.version_metadata(rc.ROOT)
        self.assertEqual(version, '0.14.0')
        self.assertEqual(metadata['BuildNumber'], '2026090501')
        self.assertEqual(metadata['BundleIdentifier'], 'com.silkrd.uma')
        (self.root / 'Configuration').mkdir()
        authority['ReleaseCandidate']['BuildNumber'] = '-1'
        (self.root / 'Configuration/UMAProductVersion.plist').write_bytes(plistlib.dumps(authority))
        with self.assertRaisesRegex(rc.Refusal, 'BUILD_INVALID'):
            rc.version_metadata(self.root)

    def test_storage_requires_every_gate(self):
        accepted = dict(VolumeName='DEV_APFS', FilesystemType='apfs', MountPoint=str(rc.ESTATE),
                        GlobalPermissionsEnabled=True, WritableVolume=True)
        for key, wrong in [('VolumeName', 'HE'), ('FilesystemType', 'exfat'),
                           ('MountPoint', '/Volumes/HE'), ('GlobalPermissionsEnabled', False),
                           ('WritableVolume', False)]:
            rejected = dict(accepted, **{key: wrong})
            with self.subTest(key=key), patch.object(rc, 'run', return_value=
                    subprocess.CompletedProcess([], 0, plistlib.dumps(rejected), b'')):
                with self.assertRaisesRegex(rc.Refusal, 'DEV_APFS_GATE'):
                    rc.verify_storage()
        with patch.object(rc, 'run', return_value=subprocess.CompletedProcess([], 0,
                plistlib.dumps(accepted), b'')):
            self.assertEqual(rc.verify_storage(), accepted)

    def test_linkage_classifies_unused_search_paths_and_rejects_actual_dependency(self):
        def fake_run(args, **kwargs):
            if args[0] == '/usr/bin/otool':
                result = ('app:\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n'
                          if args[1] == '-L' else
                          'cmd LC_RPATH\n cmdsize 88\n path /Volumes/HE/DEV/UMA/Build/PackageFrameworks (offset 12)\n')
                return subprocess.CompletedProcess(args, 0, result.encode(), b'')
            return subprocess.CompletedProcess(args, 0, b'', b'Signature=adhoc\n')
        with patch.object(rc, 'run', side_effect=fake_run):
            report = rc.linkage(self.root / 'app')
        self.assertEqual(report['runtime_development_dependency'], 'NONE')
        self.assertEqual(report['rpaths'][0]['classification'], 'UNUSED_NO_RPATH_LOAD_COMMANDS')
        for dependency in ['@rpath/private.dylib', '/Volumes/HE/DEV/library.dylib',
                           '/Users/developer/source.dylib', '@loader_path/helper.dylib']:
            with self.subTest(dependency=dependency), patch.object(rc, 'run', return_value=
                    subprocess.CompletedProcess([], 0, f'app:\n\t{dependency} (compatibility version 1.0)\n'.encode(), b'')):
                with self.assertRaisesRegex(rc.Refusal, 'NON_SYSTEM_DEPENDENCY'):
                    rc.linkage(self.root / 'app')

    def test_manifest_hash_mode_and_link_target(self):
        path = self.root / 'file'
        path.write_bytes(b'fixture')
        path.chmod(0o600)
        (self.root / 'link').symlink_to('file')
        records = rc.manifest(self.root)
        self.assertEqual(records[0]['mode'], '0o600')
        self.assertEqual(records[0]['sha256'], rc.sha(path))
        self.assertEqual(records[1]['target'], 'file')


if __name__ == '__main__':
    unittest.main(verbosity=2)
