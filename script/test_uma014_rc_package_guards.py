#!/usr/bin/env python3
"""Isolated refusal and linkage tests; no compiler, installed app, or provider use."""
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import struct
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
        self.assertEqual(rc.source_state(self.root, commit, tree,
                                         'codex/uma-0.14-surface-rebuild'),
                         'codex/uma-0.14-surface-rebuild')
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
            rc.source_state(self.root, commit, tree, 'codex/uma-0.14-surface-rebuild')
        original.write_text('accepted\n')
        untracked = self.root / 'untracked'
        untracked.write_text('wip\n')
        with self.assertRaisesRegex(rc.Refusal, 'NOT_CLEAN'):
            rc.source_state(self.root, commit, tree, 'codex/uma-0.14-surface-rebuild')
        untracked.unlink()
        original.write_text('staged\n')
        self.git('add', '--', 'file')
        with self.assertRaisesRegex(rc.Refusal, 'NOT_CLEAN'):
            rc.source_state(self.root, commit, tree, 'codex/uma-0.14-surface-rebuild')

    def test_commit_tree_and_branch_mismatch_refused(self):
        commit, tree = self.repository()
        for expected_commit, expected_tree, error in [('z'*40, tree, 'ID_INVALID'),
              ('0'*40, tree, 'COMMIT_MISMATCH'), (commit, '0'*40, 'TREE_MISMATCH')]:
            with self.subTest(error=error), self.assertRaisesRegex(rc.Refusal, error):
                rc.source_state(self.root, expected_commit, expected_tree,
                                'codex/uma-0.14-surface-rebuild')
        self.git('checkout', '-b', 'wrong-branch')
        with self.assertRaisesRegex(rc.Refusal, 'BRANCH_MISMATCH'):
            rc.source_state(self.root, commit, tree, 'codex/uma-0.14-surface-rebuild')

    def test_expected_branch_is_explicit_and_validated(self):
        commit, tree = self.repository()
        self.assertEqual(rc.source_state(self.root, commit, tree,
                                         'codex/uma-0.14-surface-rebuild'),
                         'codex/uma-0.14-surface-rebuild')
        with self.assertRaisesRegex(rc.Refusal, 'BRANCH_ID_INVALID'):
            rc.source_state(self.root, commit, tree, '../wrong')

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
        self.assertRegex(version, r'^\d+\.\d+\.\d+$')
        self.assertEqual(metadata['BuildNumber'], authority['ReleaseCandidate']['BuildNumber'])
        self.assertRegex(metadata['BuildNumber'], r'^[1-9]\d*$')
        self.assertEqual(metadata['BundleIdentifier'], 'com.silkrd.uma')
        (self.root / 'Configuration').mkdir()
        authority['ReleaseCandidate']['BuildNumber'] = '-1'
        (self.root / 'Configuration/UMAProductVersion.plist').write_bytes(plistlib.dumps(authority))
        with self.assertRaisesRegex(rc.Refusal, 'BUILD_INVALID'):
            rc.version_metadata(self.root)

    def test_version_stem_is_bound_to_canonical_major_minor(self):
        authority, _, _ = rc.version_metadata(rc.ROOT)
        (self.root / 'Configuration').mkdir()
        (self.root / 'Package.swift').write_text((rc.ROOT / 'Package.swift').read_text())
        metadata_path = self.root / 'Configuration/UMAProductVersion.plist'
        for version, stem in [('0.14.1', 'uma-0.14-rc'), ('0.15.0', 'uma-0.15-rc'),
                              ('0.16.4', 'uma-0.16-rc'), ('0.17.0', 'uma-0.17-rc')]:
            with self.subTest(version=version):
                authority['Development']['MarketingVersion'] = version
                authority['ReleaseCandidate']['PackageStem'] = stem
                metadata_path.write_bytes(plistlib.dumps(authority))
                _, accepted, observed = rc.version_metadata(self.root)
                self.assertEqual(observed, version)
                self.assertEqual(accepted['PackageStem'], stem)
                destination = self.root / (stem + '-20261009T120000Z')
                pattern = rc.re.escape(accepted['PackageStem']) + r'-\d{8}T\d{6}Z'
                self.assertEqual(rc.output_path(str(destination), self.root, pattern), destination)
                with self.assertRaises(rc.Refusal):
                    rc.output_path(str(self.root / 'uma-9.99-rc-20261009T120000Z'), self.root, pattern)
                self.assertFalse(destination.exists())
        authority['ReleaseCandidate']['PackageStem'] = 'uma-0.14-rc'
        metadata_path.write_bytes(plistlib.dumps(authority))
        with self.assertRaisesRegex(rc.Refusal, 'RC_STEM_INVALID'):
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

    def macho_fixture(self, *, minimum=(14, 0, 0), sdk=(27, 0, 0), platform=1,
                      command_count=1, legacy=False, architecture='arm64'):
        def packed(value):
            return value[0] << 16 | value[1] << 8 | value[2]
        command = (struct.pack('<4I', 0x24, 16, packed(minimum), packed(sdk)) if legacy else
                   struct.pack('<6I', 0x32, 24, platform, packed(minimum), packed(sdk), 0))
        body = command * command_count
        path = self.root / 'synthetic-mach-o'
        cpu, subtype = rc.MACHO_CPUS[architecture]
        path.write_bytes(struct.pack('<8I', 0xfeedfacf, cpu, subtype, 2,
                                     command_count, len(body), 0, 0) + body)
        return path

    def test_raw_build_version_accepts_matching_sdk_and_minimum(self):
        path = self.macho_fixture()
        before = path.read_bytes()
        report = rc.macho_build_version(path, '27.0', '14.0.0')
        self.assertEqual(report['verification'], 'PASS')
        self.assertEqual(report['sdk'], '27.0.0')
        self.assertEqual(report['minimum_os'], '14.0.0')
        self.assertEqual(path.read_bytes(), before)

    def test_raw_build_version_rejects_reproduced_sdk_fallback(self):
        path = self.macho_fixture(sdk=(14, 0, 0))
        before = path.read_bytes()
        with self.assertRaisesRegex(rc.Refusal, 'BUILD_VERSION_SDK_MISMATCH'):
            rc.macho_build_version(path, '27.0', '14.0')
        self.assertEqual(path.read_bytes(), before)

    def test_raw_build_version_rejects_wrong_minimum_platform_and_legacy(self):
        for options, reason in [({'minimum': (15, 0, 0)}, 'MINIMUM_OS_MISMATCH'),
                                ({'platform': 2}, 'PLATFORM_MISMATCH'),
                                ({'legacy': True}, 'LEGACY_MACOS_VERSION')]:
            with self.subTest(options=options), self.assertRaisesRegex(rc.Refusal, reason):
                rc.macho_build_version(self.macho_fixture(**options), '27.0', '14.0')

    def test_raw_build_version_requires_one_complete_command(self):
        for count in (0, 2):
            with self.subTest(count=count), self.assertRaisesRegex(rc.Refusal, 'MISSING_OR_DUPLICATE'):
                rc.macho_build_version(self.macho_fixture(command_count=count), '27.0', '14.0')
        path = self.macho_fixture()
        path.write_bytes(path.read_bytes()[:-1])
        with self.assertRaisesRegex(rc.Refusal, 'LOAD_COMMANDS_TRUNCATED'):
            rc.macho_build_version(path, '27.0', '14.0')
        path = self.macho_fixture()
        data = bytearray(path.read_bytes())
        struct.pack_into('<I', data, 36, 8)
        path.write_bytes(data)
        with self.assertRaisesRegex(rc.Refusal, 'BUILD_VERSION_TRUNCATED'):
            rc.macho_build_version(path, '27.0', '14.0')

    def test_raw_build_version_rejects_wrong_architecture_and_tool_records(self):
        for offset, value, reason in [(4, 0x00000007, 'UNSUPPORTED_CPU'),
                                      (52, 1, 'TOOL_RECORDS_INVALID')]:
            path = self.macho_fixture()
            data = bytearray(path.read_bytes())
            struct.pack_into('<I', data, offset, value)
            path.write_bytes(data)
            with self.subTest(reason=reason), self.assertRaisesRegex(rc.Refusal, reason):
                rc.macho_build_version(path, '27.0', '14.0')

    def universal_fixture(self, *, wide=False, endian='>', slices=None):
        if slices is None:
            slices = [(arch, self.macho_fixture(architecture=arch).read_bytes())
                      for arch in rc.MAC_ARCHITECTURES]
        record_size = 32 if wide else 20
        cursor = 8 + len(slices) * record_size
        data = bytearray(cursor)
        struct.pack_into(endian + 'II', data, 0, 0xcafebabf if wide else 0xcafebabe, len(slices))
        for index, (arch, image) in enumerate(slices):
            cursor = (cursor + 7) & ~7
            data.extend(b'\0' * (cursor - len(data)))
            cpu, subtype = rc.MACHO_CPUS[arch]
            record = (cpu, subtype, cursor, len(image), 3) + ((0,) if wide else ())
            struct.pack_into(endian + ('IIQQII' if wide else 'IIIII'), data,
                             8 + index * record_size, *record)
            data.extend(image)
            cursor += len(image)
        path = self.root / 'synthetic-universal'
        path.write_bytes(data)
        return path

    def assert_universal_refused(self, path, reason):
        with self.assertRaisesRegex(rc.Refusal, reason):
            rc.macho_build_version(path, '27.0', '14.0', rc.MAC_ARCHITECTURES)

    def test_raw_thin_intel_can_be_inspected_explicitly(self):
        path = self.macho_fixture(architecture='x86_64')
        report = rc.macho_build_version(path, '27.0', '14.0', ('x86_64',))
        self.assertEqual(report['slices']['x86_64']['minimum_os'], '14.0.0')
        with self.assertRaisesRegex(rc.Refusal, 'ARCHITECTURES_MISMATCH'):
            rc.macho_build_version(path, '27.0', '14.0')

    def test_universal_checks_both_slices_in_all_fat_formats_without_mutation(self):
        for wide in (False, True):
            for endian in ('>', '<'):
                with self.subTest(wide=wide, endian=endian):
                    path = self.universal_fixture(wide=wide, endian=endian)
                    before = path.read_bytes()
                    report = rc.macho_build_version(path, '27.0', '14.0', rc.MAC_ARCHITECTURES)
                    self.assertEqual(set(report['slices']), {'arm64', 'x86_64'})
                    self.assertTrue(all(item['verification'] == 'PASS' for item in report['slices'].values()))
                    self.assertEqual(path.read_bytes(), before)

    def test_universal_requires_exact_architectures_not_single_slice(self):
        for arch in rc.MAC_ARCHITECTURES:
            self.assert_universal_refused(self.macho_fixture(architecture=arch), 'ARCHITECTURES_MISMATCH')
            image = self.macho_fixture(architecture=arch).read_bytes()
            self.assert_universal_refused(self.universal_fixture(slices=[(arch, image)]), 'ARCHITECTURES_MISMATCH')

    def test_universal_refuses_missing_or_excessive_architecture_count(self):
        for count in (0, 3, 0xffffffff):
            path = self.universal_fixture()
            data = bytearray(path.read_bytes())
            struct.pack_into('>I', data, 4, count)
            path.write_bytes(data)
            self.assert_universal_refused(path, 'ARCHITECTURE_COUNT_INVALID')

    def test_universal_refuses_truncated_header_and_table(self):
        original = self.universal_fixture().read_bytes()
        for length, error in [(3, 'MACHO_HEADER_TRUNCATED'), (4, 'FAT_HEADER_TRUNCATED'),
                              (7, 'FAT_HEADER_TRUNCATED'), (47, 'FAT_TABLE_TRUNCATED')]:
            path = self.root / 'truncated'
            path.write_bytes(original[:length])
            self.assert_universal_refused(path, error)

    def test_universal_refuses_duplicate_architecture(self):
        image = self.macho_fixture().read_bytes()
        self.assert_universal_refused(self.universal_fixture(slices=[('arm64', image), ('arm64', image)]),
                                      'DUPLICATE_ARCHITECTURE')

    def test_universal_refuses_table_unknown_cpu(self):
        path = self.universal_fixture()
        data = bytearray(path.read_bytes())
        struct.pack_into('>I', data, 8, 0x12345678)
        path.write_bytes(data)
        self.assert_universal_refused(path, 'UNSUPPORTED_CPU')

    def test_universal_refuses_overlap(self):
        path = self.universal_fixture()
        data = bytearray(path.read_bytes())
        first_offset = struct.unpack_from('>I', data, 16)[0]
        struct.pack_into('>I', data, 36, first_offset)
        path.write_bytes(data)
        self.assert_universal_refused(path, 'SLICES_OVERLAP')

    def test_universal_refuses_offsets_into_header_truncated_and_empty_slices(self):
        for offset, value in [(16, 0), (16, 0xfffffff8), (20, 0), (20, 0xffffffff)]:
            path = self.universal_fixture()
            data = bytearray(path.read_bytes())
            struct.pack_into('>I', data, offset, value)
            path.write_bytes(data)
            self.assert_universal_refused(path, 'SLICE_OUT_OF_BOUNDS')

    def test_universal_refuses_misaligned_slices_and_invalid_alignment(self):
        for offset, value in [(16, 49), (24, 32)]:
            path = self.universal_fixture()
            data = bytearray(path.read_bytes())
            struct.pack_into('>I', data, offset, value)
            path.write_bytes(data)
            self.assert_universal_refused(path, 'ALIGNMENT_INVALID')

    def test_universal_fat64_refuses_reserved_and_overflow_values(self):
        for offset, fmt, value, reason in [(36, '>I', 1, 'RESERVED_FIELD_INVALID'),
                                           (16, '>Q', 0xfffffffffffffff8, 'SLICE_OUT_OF_BOUNDS'),
                                           (24, '>Q', 0xffffffffffffffff, 'SLICE_OUT_OF_BOUNDS'),
                                           (32, '>I', 64, 'ALIGNMENT_INVALID')]:
            path = self.universal_fixture(wide=True)
            data = bytearray(path.read_bytes())
            struct.pack_into(fmt, data, offset, value)
            path.write_bytes(data)
            self.assert_universal_refused(path, reason)

    def test_universal_refuses_table_and_slice_cpu_subtype_mismatch(self):
        path = self.universal_fixture()
        data = bytearray(path.read_bytes())
        struct.pack_into('>I', data, 12, 2)
        path.write_bytes(data)
        self.assert_universal_refused(path, 'SLICE_IDENTITY_MISMATCH')

    def test_universal_refuses_specialized_cpu_subtypes(self):
        for arch, subtype in [('arm64', 2), ('x86_64', 8)]:
            image = bytearray(self.macho_fixture(architecture=arch).read_bytes())
            struct.pack_into('<I', image, 8, subtype)
            slices = [(item, bytes(image) if item == arch else self.macho_fixture(architecture=item).read_bytes())
                      for item in rc.MAC_ARCHITECTURES]
            self.assert_universal_refused(self.universal_fixture(slices=slices), 'UNSUPPORTED_CPU_SUBTYPE')

    def test_universal_checks_sdk_minimum_platform_and_commands_for_each_architecture(self):
        for arch in rc.MAC_ARCHITECTURES:
            for options, reason in [({'minimum': (15, 0, 0)}, 'MINIMUM_OS_MISMATCH'),
                                     ({'sdk': (14, 0, 0)}, 'SDK_MISMATCH'),
                                     ({'platform': 2}, 'PLATFORM_MISMATCH'),
                                     ({'legacy': True}, 'LEGACY_MACOS_VERSION'),
                                     ({'command_count': 2}, 'MISSING_OR_DUPLICATE')]:
                with self.subTest(arch=arch, options=options):
                    slices = [(item, self.macho_fixture(architecture=item, **(options if item == arch else {})).read_bytes())
                              for item in rc.MAC_ARCHITECTURES]
                    self.assert_universal_refused(self.universal_fixture(slices=slices), reason)

    def test_universal_slice_load_commands_cannot_read_next_slice(self):
        image = bytearray(self.macho_fixture().read_bytes())
        struct.pack_into('<I', image, 20, len(image))
        slices = [('arm64', bytes(image)), ('x86_64', self.macho_fixture(architecture='x86_64').read_bytes())]
        self.assert_universal_refused(self.universal_fixture(slices=slices), 'LOAD_COMMANDS_TRUNCATED')

    def test_release_executable_contract_rejects_thin_before_dependency_tools(self):
        with patch.object(rc, 'linkage') as linkage:
            with self.assertRaisesRegex(rc.Refusal, 'ARCHITECTURES_MISMATCH'):
                rc.release_executable_report(self.macho_fixture(), '27.0', '14.0')
        linkage.assert_not_called()

    def test_release_executable_contract_validates_both_slices_before_linkage(self):
        path = self.universal_fixture()
        with patch.object(rc, 'linkage', return_value={'verification': 'fixture'}) as linkage:
            report = rc.release_executable_report(path, '27.0', '14.0')
        linkage.assert_called_once_with(path, rc.MAC_ARCHITECTURES)
        self.assertEqual(set(report['build_version']['slices']), {'arm64', 'x86_64'})

    def universal_linkage_runner(self, *, intel_dependency='/usr/lib/libSystem.B.dylib', architectures='x86_64 arm64'):
        def fake_run(args, **kwargs):
            if args[0] == '/usr/bin/lipo':
                return subprocess.CompletedProcess(args, 0, architectures.encode(), b'')
            if args[0] == '/usr/bin/otool':
                self.assertEqual(args[1], '-arch')
                arch = args[2]
                dependency = intel_dependency if arch == 'x86_64' else '/usr/lib/libSystem.B.dylib'
                result = (f'app (architecture {arch}):\n\t{dependency} (compatibility version 1.0.0)\n'
                          if args[3] == '-L' else 'cmd LC_RPATH\n cmdsize 32\n path /private/tmp/build (offset 12)\n')
                return subprocess.CompletedProcess(args, 0, result.encode(), b'')
            return subprocess.CompletedProcess(args, 0, b'', b'Signature=adhoc\n')
        return fake_run

    def test_universal_linkage_inspects_both_architectures_without_treating_headers_as_dependencies(self):
        with patch.object(rc, 'run', side_effect=self.universal_linkage_runner()):
            report = rc.linkage(self.root / 'app', rc.MAC_ARCHITECTURES)
        self.assertEqual(set(report['slices']), set(rc.MAC_ARCHITECTURES))
        self.assertEqual(report['dependencies'], ['/usr/lib/libSystem.B.dylib'])
        self.assertEqual({item['architecture'] for item in report['rpaths']}, set(rc.MAC_ARCHITECTURES))

    def test_universal_linkage_refuses_private_dependency_in_intel_slice(self):
        with patch.object(rc, 'run', side_effect=self.universal_linkage_runner(intel_dependency='@rpath/private.dylib')):
            with self.assertRaisesRegex(rc.Refusal, 'NON_SYSTEM_DEPENDENCY x86_64'):
                rc.linkage(self.root / 'app', rc.MAC_ARCHITECTURES)

    def test_universal_linkage_refuses_missing_duplicate_or_extra_lipo_architecture(self):
        for arches in ['arm64', 'arm64 arm64', 'arm64 x86_64 arm64e']:
            with self.subTest(architectures=arches), patch.object(rc, 'run', side_effect=self.universal_linkage_runner(architectures=arches)):
                with self.assertRaisesRegex(rc.Refusal, 'LINKAGE_ARCHITECTURES_MISMATCH'):
                    rc.linkage(self.root / 'app', rc.MAC_ARCHITECTURES)

    def test_manifest_hash_mode_and_link_target(self):
        path = self.root / 'file'
        path.write_bytes(b'fixture')
        path.chmod(0o600)
        (self.root / 'link').symlink_to('file')
        records = rc.manifest(self.root)
        self.assertEqual(records[0]['mode'], '0o600')
        self.assertEqual(records[0]['sha256'], rc.sha(path))
        self.assertEqual(records[1]['target'], 'file')

    def hesectorium_fixture(self):
        source = self.root / 'source'
        assets = source / 'Configuration/HESectorium'
        assets.mkdir(parents=True)
        identity = {
            'outerUUID': '2FE2A779-0DC8-3468-8E3C-E113598C46CE',
            'devUUID': '0476F9CC-86A3-40D8-A8D4-83D882522CAD',
            'outerMountPoint': '/Volumes/HE', 'devMountPoint': '/Volumes/HE/DEV',
            'devVolumeName': 'DEV_APFS', 'imagePath': '/Volumes/HE/.DEV-APFS.sparsebundle'}
        (assets / 'storage-identity.json').write_text(rc.json.dumps(identity))
        (assets / 'dev-apfs-mount').write_text('#!/bin/sh\nexit 0\n')
        (assets / 'he-eject').write_text('#!/bin/sh\nexit 0\n')
        (assets / 'com.juliushe.dev-apfs-mounter.plist').write_bytes(plistlib.dumps({
            'Label': 'com.juliushe.dev-apfs-mounter', 'RunAtLoad': True,
            'ProgramArguments': ['__UMA_CONTROL_PATH__', 'agent']}))
        bin_path = self.root / 'bin'
        bin_path.mkdir()
        (bin_path / 'HESectoriumControl').write_bytes(b'fixture executable')
        app = self.root / 'UMA.app'
        (app / 'Contents').mkdir(parents=True)
        return bin_path, app, source

    def test_hesectorium_assets_are_copied_with_identity_and_modes(self):
        bin_path, app, source = self.hesectorium_fixture()
        report = rc.copy_hesectorium_assets(bin_path, app, source)
        helper = app / 'Contents/Helpers/HESectoriumControl'
        resources = app / 'Contents/Resources/HESectorium'
        self.assertEqual(helper.read_bytes(), b'fixture executable')
        self.assertEqual((helper.stat().st_mode & 0o777), 0o755)
        self.assertEqual(report['control']['sha256'], rc.sha(helper))
        self.assertEqual((resources / 'storage-identity.json').read_text(),
                         (source / 'Configuration/HESectorium/storage-identity.json').read_text())
        self.assertEqual((resources / 'dev-apfs-mount').stat().st_mode & 0o777, 0o700)
        self.assertEqual((resources / 'storage-identity.json').stat().st_mode & 0o777, 0o600)

    def test_hesectorium_assets_reject_identity_mismatch(self):
        bin_path, app, source = self.hesectorium_fixture()
        path = source / 'Configuration/HESectorium/storage-identity.json'
        value = rc.json.loads(path.read_text())
        value['outerUUID'] = '00000000-0000-0000-0000-000000000000'
        path.write_text(rc.json.dumps(value))
        with self.assertRaisesRegex(rc.Refusal, 'HES_IDENTITY_ASSET_MISMATCH'):
            rc.copy_hesectorium_assets(bin_path, app, source)

    def catalog_fixture(self, root, *, revision_v2='sol-luna-20260922.1',
                        revision_v3='sol-luna-20261001.1', built_v2_marker='canonical',
                        built_v3_marker='canonical'):
        source = root / 'frozen-source'
        built_resources = root / 'bin' / 'CodexUsageMonitor_CodexUsageUI.bundle' / 'Contents' / 'Resources'
        source_catalogs = source / 'Sources/CodexUsageUI/Resources/ThreadOS'
        source_catalogs.mkdir(parents=True)
        built_resources.mkdir(parents=True)
        values = {
            'models.v1.json': {'schema': 'threados.model-catalog.v1',
                               'revision': 'astra-20260904.1', 'models': {}},
            'models.v2.json': {'schema': 'threados.model-catalog.v1',
                               'revision': revision_v2, 'models': {},
                               'marker': built_v2_marker},
            'models.v4.json': {'schema': 'threados.model-catalog.v1', 'revision': 'sol-luna-ultra-20261010.1', 'models': {}},
            'models.v3.json': {'schema': 'threados.model-catalog.v1',
                               'revision': revision_v3, 'models': {},
                               'marker': built_v3_marker},
        }
        for name, value in values.items():
            data = (rc.json.dumps(value, sort_keys=True) + '\n').encode()
            (source_catalogs / name).write_bytes(data)
            (built_resources / name).write_bytes(data)
        return source, built_resources

    def test_swiftpm_resource_bundle_requires_frozen_source_identity_and_copies_exact_bytes(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'UMA.app' / 'Contents' / 'Resources'
        source, built = self.catalog_fixture(self.root)
        resources.mkdir(parents=True)

        report = rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

        packaged = resources / 'CodexUsageMonitor_CodexUsageUI.bundle' / 'Contents' / 'Resources'
        for name in ('models.v1.json', 'models.v2.json', 'models.v3.json', 'models.v4.json'):
            source_file, built_file, copied = (source / 'Sources/CodexUsageUI/Resources/ThreadOS' / name,
                                                built / name, packaged / name)
            self.assertEqual(source_file.read_bytes(), built_file.read_bytes())
            self.assertEqual(copied.read_bytes(), source_file.read_bytes())
            self.assertEqual(report['catalogs'][name]['source_sha256'], rc.sha(source_file))
            self.assertEqual(report['catalogs'][name]['built_sha256'], rc.sha(built_file))
            self.assertEqual(report['catalogs'][name]['sha256'], rc.sha(copied))
            self.assertEqual(report['catalogs'][name]['revision'],
                             {'models.v1.json': 'astra-20260904.1',
                              'models.v2.json': 'sol-luna-20260922.1',
                              'models.v3.json': 'sol-luna-20261001.1', 'models.v4.json': 'sol-luna-ultra-20261010.1'}[name])
        self.assertEqual(report['bundle'], 'CodexUsageMonitor_CodexUsageUI.bundle')
        self.assertEqual(report['catalog'], 'Contents/Resources/models.v1.json')
        self.assertEqual(report['catalog_sha256'], rc.sha(packaged / 'models.v1.json'))

    def test_swiftpm_resource_bundle_rejects_wrong_v2_revision(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        source, _ = self.catalog_fixture(self.root, revision_v2='sol-luna-wrong')
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'SOURCE_CATALOG_IDENTITY_INVALID models.v2.json'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

    def test_swiftpm_resource_bundle_rejects_wrong_v3_revision(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        source, _ = self.catalog_fixture(self.root, revision_v3='sol-luna-wrong')
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'SOURCE_CATALOG_IDENTITY_INVALID models.v3.json'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

    def test_swiftpm_resource_bundle_rejects_bytes_different_from_frozen_source(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        source, built = self.catalog_fixture(self.root)
        value = rc.json.loads((built / 'models.v2.json').read_text())
        value['marker'] = 'different-built-byte'
        (built / 'models.v2.json').write_text(rc.json.dumps(value, sort_keys=True) + '\n')
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'SWIFTPM_SOURCE_CATALOG_BYTES_MISMATCH models.v2.json'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

    def test_swiftpm_resource_bundle_rejects_different_v3_built_bytes(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        source, built = self.catalog_fixture(self.root)
        value = rc.json.loads((built / 'models.v3.json').read_text())
        value['marker'] = 'different-built-byte'
        (built / 'models.v3.json').write_text(rc.json.dumps(value, sort_keys=True) + '\n')
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'SWIFTPM_SOURCE_CATALOG_BYTES_MISMATCH models.v3.json'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

    def test_swiftpm_resource_bundle_requires_v2_catalog(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        source, built = self.catalog_fixture(self.root)
        (built / 'models.v2.json').unlink()
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'BUILT_CATALOG_MISSING models.v2.json'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

    def test_swiftpm_resource_bundle_requires_v3_catalog(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        source, built = self.catalog_fixture(self.root)
        (built / 'models.v3.json').unlink()
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'BUILT_CATALOG_MISSING models.v3.json'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

    def test_swiftpm_resource_bundle_requires_v3_source_catalog(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        source, _ = self.catalog_fixture(self.root)
        (source / 'Sources/CodexUsageUI/Resources/ThreadOS/models.v3.json').unlink()
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'SOURCE_CATALOG_MISSING models.v3.json'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

    def test_swiftpm_resource_bundle_rejects_malformed_v3_catalog(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        source, _ = self.catalog_fixture(self.root)
        (source / 'Sources/CodexUsageUI/Resources/ThreadOS/models.v3.json').write_text('{broken\n')
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'SOURCE_CATALOG_INVALID models.v3.json'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

    def test_swiftpm_resource_bundle_rejects_malformed_v3_built_catalog(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        source, built = self.catalog_fixture(self.root)
        (built / 'models.v3.json').write_text('{broken\n')
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'BUILT_CATALOG_INVALID models.v3.json'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

    def test_swiftpm_resource_bundle_rejects_v3_catalog_symlinks(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        source, built = self.catalog_fixture(self.root)
        source_catalog = source / 'Sources/CodexUsageUI/Resources/ThreadOS/models.v3.json'
        source_target = self.root / 'source-v3-target.json'
        source_target.write_bytes(source_catalog.read_bytes())
        source_catalog.unlink()
        source_catalog.symlink_to(source_target)
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'SOURCE_CATALOG_MISSING models.v3.json'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

        source_catalog.unlink()
        source_catalog.write_bytes(source_target.read_bytes())
        built_catalog = built / 'models.v3.json'
        built_target = self.root / 'built-v3-target.json'
        built_target.write_bytes(built_catalog.read_bytes())
        built_catalog.unlink()
        built_catalog.symlink_to(built_target)
        with self.assertRaisesRegex(rc.Refusal, 'SYMLINK_REJECTED'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, source)

    def test_swiftpm_resource_bundle_refuses_missing_or_symlinked_catalog(self):
        bin_path = self.root / 'bin'
        resources = self.root / 'Resources'
        resources.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'RESOURCE_BUNDLE_MISSING'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, self.root / 'frozen-source')

        catalog = (bin_path / 'CodexUsageMonitor_CodexUsageUI.bundle' / 'Contents' /
                   'Resources' / 'models.v1.json')
        catalog.parent.mkdir(parents=True)
        target = self.root / 'catalog.json'
        target.write_text('{}')
        catalog.symlink_to(target)
        with self.assertRaisesRegex(rc.Refusal, 'SYMLINK_REJECTED'):
            rc.copy_swiftpm_resource_bundle(bin_path, resources, self.root / 'frozen-source')


class SnapshotGuards(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='auv-snapshot-guards-')
        self.base = Path(self.temp.name).resolve()
        self.addCleanup(self.temp.cleanup)
        self.root = self.base / 'source'
        self.root.mkdir()
        for name in rc.SNAPSHOT_DIRECTORIES:
            (self.root / name).mkdir()
        (self.root / 'Package.swift').write_text('fixture\n')
        (self.root / 'Sources/Main.swift').write_text('fixture source\n')
        (self.root / 'script/package_uma014_rc.py').write_bytes(Path(rc.__file__).read_bytes())
        (self.root / 'script/package_uma014_rc.py').chmod(0o755)
        self.records = rc.snapshot_manifest(self.root)
        self.freeze = self.base / 'snapshot.json'
        self.internal = {'DeviceNode': '/dev/disk3s5', 'Internal': True,
                         'FilesystemType': 'apfs', 'WritableVolume': True,
                         'MountPoint': '/System/Volumes/Data'}

    def frozen(self):
        with patch.object(rc, 'verify_internal_storage', return_value=self.internal):
            return rc.freeze_snapshot(self.root, self.freeze)

    def test_only_exact_mac_source_inventory_is_included(self):
        for name in ('UMA.app', '.build', 'outputs', 'ProductionSigning', '.codex'):
            (self.root / name).mkdir()
            (self.root / name / 'private.txt').write_text('must not be included')
        (self.root / 'personal.txt').write_text('excluded')
        (self.root / 'Sources/.DS_Store').write_bytes(b'generated')
        (self.root / 'script/__pycache__').mkdir()
        (self.root / 'script/__pycache__/cached.pyc').write_bytes(b'generated')
        self.assertEqual(rc.snapshot_manifest(self.root), self.records)

    def test_snapshot_roundtrip_binds_bytes_modes_and_has_no_fake_git_identity(self):
        frozen = self.frozen()
        accepted = rc.verify_snapshot(self.root, self.freeze, frozen['snapshot_sha256'])
        self.assertIsNone(accepted['git_identity'])
        copy = self.base / 'copy'
        rc.copy_snapshot(self.root, accepted, copy)
        self.assertEqual(rc.manifest(copy), self.records)
        self.assertEqual(rc.sha(copy / 'Sources/Main.swift'), rc.sha(self.root / 'Sources/Main.swift'))
        self.assertFalse((self.root / '.git').exists())

    def test_added_removed_changed_and_mode_changed_inputs_refused(self):
        frozen = self.frozen()
        source = self.root / 'Sources/Main.swift'
        for case in ('changed', 'mode', 'deleted', 'added'):
            with self.subTest(case=case):
                original, mode = source.read_bytes(), source.stat().st_mode & 0o777
                added = self.root / 'Sources/new.swift'
                if case == 'changed': source.write_text('mutated')
                if case == 'mode': source.chmod(0o700)
                if case == 'deleted': source.unlink()
                if case == 'added': added.write_text('new input')
                with self.assertRaisesRegex(rc.Refusal, 'SOURCE_CHANGED'):
                    rc.verify_snapshot(self.root, self.freeze, frozen['snapshot_sha256'])
                source.write_bytes(original)
                source.chmod(mode)
                if added.exists(): added.unlink()

    def test_wrong_digest_or_tampered_manifest_refused(self):
        frozen = self.frozen()
        for digest, reason in [('0' * 64, 'SOURCE_CHANGED'), ('bad', 'ID_INVALID')]:
            with self.assertRaisesRegex(rc.Refusal, reason):
                rc.verify_snapshot(self.root, self.freeze, digest)
        frozen['records'].append({'path': '../../private', 'type': 'file'})
        self.freeze.write_text(rc.json.dumps(frozen))
        with self.assertRaisesRegex(rc.Refusal, 'SOURCE_CHANGED'):
            rc.verify_snapshot(self.root, self.freeze, frozen['snapshot_sha256'])

    def test_symlink_source_and_source_ancestor_refused(self):
        link = self.base / 'linked'
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(rc.Refusal, 'SYMLINK'):
            rc.snapshot_manifest(link)
        (self.root / 'Sources/link').symlink_to('/etc/passwd')
        with self.assertRaisesRegex(rc.Refusal, 'SYMLINK'):
            rc.snapshot_manifest(self.root)

    def test_ignored_name_symlink_also_refused(self):
        (self.root / 'script/__pycache__').symlink_to('/tmp', target_is_directory=True)
        with self.assertRaisesRegex(rc.Refusal, 'SYMLINK'):
            rc.snapshot_manifest(self.root)

    def test_app_special_file_and_hardlink_inputs_refused(self):
        app = self.root / 'Sources/Unexpected.app'
        app.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'APP_PATH'):
            rc.snapshot_manifest(self.root)
        app.rmdir()
        fifo = self.root / 'Sources/pipe'
        os.mkfifo(fifo)
        with self.assertRaisesRegex(rc.Refusal, 'SPECIAL_FILE'):
            rc.snapshot_manifest(self.root)
        fifo.unlink()
        os.link(self.root / 'Sources/Main.swift', self.root / 'Sources/duplicate.swift')
        with self.assertRaisesRegex(rc.Refusal, 'HARDLINK'):
            rc.snapshot_manifest(self.root)

    def test_copy_rejects_intervening_source_change_and_destination_overwrite(self):
        frozen = self.frozen()
        destination = self.base / 'copy'
        destination.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'ALREADY_EXISTS'):
            rc.copy_snapshot(self.root, frozen, destination)
        destination.rmdir()
        (self.root / 'Sources/Main.swift').write_text('changed after freeze')
        with self.assertRaisesRegex(rc.Refusal, 'SOURCE_CHANGED'):
            rc.copy_snapshot(self.root, frozen, destination)
        self.assertFalse(destination.exists())

    def test_freeze_refuses_overwrite_and_source_input_overlap(self):
        self.frozen()
        with self.assertRaisesRegex(rc.Refusal, 'DESTINATION_INVALID'):
            self.frozen()
        with self.assertRaisesRegex(rc.Refusal, 'SOURCE_OVERLAP'):
            rc.freeze_snapshot(self.root, self.root / 'Sources/snapshot.json')

    def test_output_root_exact_names_and_no_overlap(self):
        packages = self.root / 'outputs'
        packages.mkdir()
        builds = self.base / 'builds'
        builds.mkdir()
        output = packages / 'uma-0.17-rc-20261019T120000Z'
        build = builds / 'rc-build-20261019T120000Z'
        self.assertEqual(rc.snapshot_output_layout(self.root, str(packages), str(builds),
                         str(output), str(build), 'uma-0.17-rc'), (output, build))
        with self.assertRaisesRegex(rc.Refusal, 'SOURCE_OVERLAP'):
            rc.snapshot_output_layout(self.root, str(self.root / 'Sources'), str(builds),
                str(self.root / 'Sources' / output.name), str(build), 'uma-0.17-rc')
        with self.assertRaisesRegex(rc.Refusal, 'OUTSIDE_RC_ESTATE'):
            rc.snapshot_output_layout(self.root, str(packages), str(builds),
                str(packages / 'wrong-name'), str(build), 'uma-0.17-rc')
        output.mkdir()
        with self.assertRaisesRegex(rc.Refusal, 'ALREADY_EXISTS'):
            rc.snapshot_output_layout(self.root, str(packages), str(builds),
                str(output), str(build), 'uma-0.17-rc')

    def test_output_root_symlink_and_app_destination_refused(self):
        packages = self.base / 'packages'
        packages.mkdir()
        alias = self.base / 'alias'
        alias.symlink_to(packages, target_is_directory=True)
        with self.assertRaisesRegex(rc.Refusal, 'SYMLINK'):
            rc.snapshot_path(str(alias))
        with self.assertRaisesRegex(rc.Refusal, 'APP_PATH'):
            rc.snapshot_path(str(self.base / 'Other.app'), must_exist=False)

    def test_internal_storage_requires_actual_device_internal_writable_apfs(self):
        def observe(info):
            def fake_run(args, **kwargs):
                if args[0] == '/bin/df':
                    return subprocess.CompletedProcess(args, 0,
                        b'Filesystem 512-blocks Used Available Capacity Mounted on\n/dev/disk3s5 1 1 1 1% /System/Volumes/Data\n', b'')
                self.assertEqual(args, ['/usr/sbin/diskutil', 'info', '-plist', '/dev/disk3s5'])
                return subprocess.CompletedProcess(args, 0, plistlib.dumps(info), b'')
            return patch.object(rc, 'run', side_effect=fake_run)
        with observe(self.internal):
            self.assertEqual(rc.verify_internal_storage(self.root)['Internal'], True)
        for key, value in [('Internal', False), ('WritableVolume', False),
                           ('FilesystemType', 'exfat'), ('DeviceNode', '/dev/disk9')]:
            with self.subTest(key=key), observe(dict(self.internal, **{key: value})):
                with self.assertRaisesRegex(rc.Refusal, 'INTERNAL_STORAGE_GATE'):
                    rc.verify_internal_storage(self.root)

    def test_freeze_cli_never_runs_git_or_external_storage_gate(self):
        argv = ['package_uma014_rc.py', '--source-mode', 'snapshot', '--source-root', str(self.root),
                '--freeze-snapshot', str(self.freeze)]
        with patch.object(rc.sys, 'argv', argv), patch.object(rc, 'verify_internal_storage', return_value=self.internal), \
                patch.object(rc, 'source_state', side_effect=AssertionError('must not inspect Git')), \
                patch.object(rc, 'verify_storage', side_effect=AssertionError('must not inspect HE')), \
                patch('builtins.print'):
            rc.main()
        self.assertTrue(self.freeze.is_file())
        self.assertFalse((self.root / '.git').exists())

    def test_snapshot_build_refuses_before_output_when_source_changed(self):
        frozen = self.frozen()
        packages, builds = self.base / 'packages', self.base / 'builds'
        packages.mkdir()
        builds.mkdir()
        output, build = packages / 'uma-0.17-rc-20261019T120000Z', builds / 'rc-build-20261019T120000Z'
        argv = ['package_uma014_rc.py', '--source-mode', 'snapshot', '--source-root', str(self.root),
                '--snapshot-manifest', str(self.freeze), '--snapshot-sha256', frozen['snapshot_sha256'],
                '--packages-root', str(packages), '--builds-root', str(builds),
                '--output', str(output), '--build-root', str(build)]
        (self.root / 'Sources/Main.swift').write_text('changed')
        with patch.object(rc.sys, 'argv', argv), self.assertRaisesRegex(rc.Refusal, 'SOURCE_CHANGED'):
            rc.main()
        self.assertFalse(output.exists())
        self.assertFalse(build.exists())

    def test_snapshot_and_git_argument_identity_cannot_be_mixed(self):
        cases = [(['--source-mode', 'snapshot', '--source-root', str(self.root), '--commit', 'a' * 40],
                  'NO_GIT_IDENTITY'),
                 (['--source-mode', 'git', '--source-root', str(self.root)], 'SNAPSHOT_ARGUMENTS_REJECTED'),
                 (['--source-mode', 'snapshot', '--source-root', str(self.root)], 'EXPLICIT_INPUTS_REQUIRED')]
        for arguments, reason in cases:
            with self.subTest(reason=reason), patch.object(rc.sys, 'argv', ['script'] + arguments):
                with self.assertRaisesRegex(rc.Refusal, reason):
                    rc.main()


if __name__ == '__main__':
    unittest.main(verbosity=2)
