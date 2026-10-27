#!/usr/bin/env python3
"""Construct an unsigned candidate from a clean Git archive or explicit source snapshot."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
ESTATE = Path('/Volumes/HE/DEV')
PACKAGES = ESTATE / 'UMA/Packages'
BUILDS = ESTATE / 'UMA/Build/uma014-m5c'
DEVELOPER = Path('/Applications/Xcode-beta.app/Contents/Developer')
MAC_ARCHITECTURES = ('arm64', 'x86_64')
MACHO_CPUS = {'arm64': (0x0100000c, 0), 'x86_64': (0x01000007, 3)}


class Refusal(Exception):
    pass


def require(condition, reason):
    if not condition:
        raise Refusal(reason)


def run(args, *, cwd=None, env=None, check=True):
    result = subprocess.run([str(x) for x in args], cwd=cwd, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode:
        raise Refusal(f'COMMAND_FAILED {args[0]}: {result.stderr.decode(errors="replace").strip()}')
    return result


def output_path(raw, parent, pattern):
    path = Path(raw)
    require(path.is_absolute() and '..' not in path.parts and '.' not in raw.split('/'),
            'OUTPUT_PATH_INVALID')
    require(path.parent == parent and re.fullmatch(pattern, path.name), 'OUTPUT_OUTSIDE_RC_ESTATE')
    current = Path('/')
    for part in path.parts[1:]:
        current /= part
        require(not current.is_symlink(), 'OUTPUT_SYMLINK_REJECTED')
        require(not part.lower().endswith('.app'), 'OUTPUT_APP_DESTINATION_REJECTED')
    require(not path.exists(), 'OUTPUT_ALREADY_EXISTS')
    return path


def source_state(root, commit, tree, expected_branch):
    require(re.fullmatch(r'[0-9a-f]{40}', commit) and re.fullmatch(r'[0-9a-f]{40}', tree),
            'SOURCE_ID_INVALID')
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', expected_branch),
            'SOURCE_BRANCH_ID_INVALID')
    def git(*args):
        return run(['git', '-C', root, *args]).stdout.decode().strip()
    require(git('rev-parse', 'HEAD') == commit, 'SOURCE_COMMIT_MISMATCH')
    require(git('rev-parse', 'HEAD^{tree}') == tree, 'SOURCE_TREE_MISMATCH')
    require(not git('status', '--porcelain=v1', '--untracked-files=all'), 'SOURCE_NOT_CLEAN')
    require(not git('diff', '--cached', '--name-only'), 'INDEX_NOT_EMPTY')
    branch = git('branch', '--show-current')
    require(branch == expected_branch, 'SOURCE_BRANCH_MISMATCH')
    return branch


def version_metadata(root):
    authority = root / 'Configuration/UMAProductVersion.plist'
    require(not authority.is_symlink(), 'VERSION_AUTHORITY_SYMLINK')
    value = plistlib.loads(authority.read_bytes())
    require(value.get('SchemaVersion') == 1, 'VERSION_SCHEMA_UNSUPPORTED')
    rc = value['ReleaseCandidate']
    version = value['Development']['MarketingVersion']
    require(re.fullmatch(r'\d+\.\d+\.\d+', version), 'VERSION_INVALID')
    require(re.fullmatch(r'[1-9]\d*', rc['BuildNumber']), 'BUILD_INVALID')
    require(rc['BundleIdentifier'] == 'com.silkrd.uma' and rc['ApplicationName'] == 'UMA',
            'RC_IDENTITY_INVALID')
    expected_stem = 'uma-' + '.'.join(version.split('.')[:2]) + '-rc'
    require(rc['PackageStem'] == expected_stem, 'RC_STEM_INVALID')
    require(re.fullmatch(r'\d+\.\d+', rc['MinimumSystemVersion']), 'MINIMUM_OS_INVALID')
    require(re.fullmatch(r'[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}',
                         rc['FrozenHostRuntimeGenerationID']), 'HOST_GENERATION_INVALID')
    package = (root / 'Package.swift').read_text()
    minimum_major = rc['MinimumSystemVersion'].split('.')[0]
    require(re.search(r'\.macOS\(\.v' + re.escape(minimum_major) + r'\)', package),
            'DEPLOYMENT_TARGET_AUTHORITY_MISMATCH')
    return value, rc, version


def verify_storage():
    info = plistlib.loads(run(['/usr/sbin/diskutil', 'info', '-plist', ESTATE]).stdout)
    require(info.get('VolumeName') == 'DEV_APFS' and
            info.get('FilesystemType', '').lower() == 'apfs' and
            info.get('MountPoint') == str(ESTATE) and
            info.get('GlobalPermissionsEnabled') is True and
            info.get('WritableVolume') is True, 'DEV_APFS_GATE_FAILED')
    return info


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def manifest(root):
    records = []
    for path in sorted(root.rglob('*')):
        metadata = path.lstat()
        record = {'path': path.relative_to(root).as_posix(),
                  'mode': oct(stat.S_IMODE(metadata.st_mode))}
        if stat.S_ISLNK(metadata.st_mode):
            record.update(type='symlink', target=os.readlink(path))
        elif stat.S_ISREG(metadata.st_mode):
            record.update(type='file', size=metadata.st_size, sha256=sha(path))
        elif stat.S_ISDIR(metadata.st_mode):
            record.update(type='directory')
        else:
            raise Refusal('UNSUPPORTED_FILE_TYPE')
        records.append(record)
    return records


def contains_symlink(root):
    return root.is_symlink() or any(path.is_symlink() for path in root.rglob('*'))


def copy_swiftpm_resource_bundle(bin_path, resources, source_root):
    """Copy SwiftPM resources only when they match the frozen source archive."""
    bundle = bin_path / 'CodexUsageMonitor_CodexUsageUI.bundle'
    resource_dir = bundle / 'Contents/Resources'
    source_dir = source_root / 'Sources/CodexUsageUI/Resources/ThreadOS'
    catalog_expectations = {
        'models.v1.json': ('threados.model-catalog.v1', 'astra-20260904.1'),
        'models.v2.json': ('threados.model-catalog.v1', 'sol-luna-20260922.1'),
        'models.v3.json': ('threados.model-catalog.v1', 'sol-luna-20261001.1'),
        'models.v4.json': ('threados.model-catalog.v1', 'sol-luna-ultra-20261010.1'),
    }
    require(bundle.is_dir(), 'SWIFTPM_RESOURCE_BUNDLE_MISSING')
    require(not contains_symlink(bundle), 'SWIFTPM_RESOURCE_BUNDLE_SYMLINK_REJECTED')

    def validate_catalog(path, name, origin):
        require(path.is_file() and not path.is_symlink(),
                f'{origin}_CATALOG_MISSING {name}')
        try:
            value = json.loads(path.read_text(encoding='utf-8'))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            raise Refusal(f'{origin}_CATALOG_INVALID {name}') from exc
        schema, revision = catalog_expectations[name]
        require(type(value) is dict and value.get('schema') == schema and
                value.get('revision') == revision,
                f'{origin}_CATALOG_IDENTITY_INVALID {name}')
        return value

    source_hashes, built_hashes = {}, {}
    for name in catalog_expectations:
        source_catalog = source_dir / name
        built_catalog = resource_dir / name
        validate_catalog(source_catalog, name, 'SOURCE')
        validate_catalog(built_catalog, name, 'BUILT')
        source_hashes[name], built_hashes[name] = sha(source_catalog), sha(built_catalog)
        require(source_hashes[name] == built_hashes[name],
                f'SWIFTPM_SOURCE_CATALOG_BYTES_MISMATCH {name}')

    packaged = resources / bundle.name
    require(not packaged.exists(), 'PACKAGED_RESOURCE_BUNDLE_ALREADY_EXISTS')
    shutil.copytree(bundle, packaged, symlinks=False)
    for name in catalog_expectations:
        packaged_catalog = packaged / 'Contents/Resources' / name
        require(packaged_catalog.is_file(), 'PACKAGED_THREADOS_CATALOG_MISSING ' + name)
        require(sha(built_catalog := resource_dir / name) == sha(packaged_catalog),
                'PACKAGED_THREADOS_CATALOG_MISMATCH ' + name)
    require(not contains_symlink(packaged), 'PACKAGED_RESOURCE_BUNDLE_SYMLINK_REJECTED')
    hashes = {name: sha(packaged / 'Contents/Resources' / name)
              for name in catalog_expectations}
    return {'bundle': bundle.name, 'catalog': 'Contents/Resources/models.v1.json',
            'catalog_sha256': hashes['models.v1.json'],
            'catalogs': {name: {'path': 'Contents/Resources/' + name,
                                'source_sha256': source_hashes[name],
                                'built_sha256': built_hashes[name],
                                'sha256': hashes[name],
                                'schema': catalog_expectations[name][0],
                                'revision': catalog_expectations[name][1]}
                         for name in catalog_expectations},
            'manifest': manifest(packaged)}


def copy_hesectorium_assets(bin_path, app, source_root):
    """Bundle the one shared controller and its explicit deployment assets."""
    control_source = bin_path / 'HESectoriumControl'
    require(control_source.is_file() and not control_source.is_symlink(),
            'HES_CONTROL_BINARY_MISSING')
    helper_dir = app / 'Contents/Helpers'
    helper_dir.mkdir(parents=True, exist_ok=True)
    control = helper_dir / 'HESectoriumControl'
    shutil.copyfile(control_source, control)
    control.chmod(0o755)

    source = source_root / 'Configuration/HESectorium'
    resources = app / 'Contents/Resources/HESectorium'
    resources.mkdir(parents=True, exist_ok=False)
    files = {
        'dev-apfs-mount': 0o700,
        'he-eject': 0o700,
        'com.juliushe.dev-apfs-mounter.plist': 0o600,
        'storage-identity.json': 0o600,
    }
    for name, mode in files.items():
        origin = source / name
        require(origin.is_file() and not origin.is_symlink(),
                f'HES_ASSET_MISSING {name}')
        target = resources / name
        shutil.copyfile(origin, target)
        target.chmod(mode)
    try:
        identity = json.loads((resources / 'storage-identity.json').read_text(encoding='utf-8'))
        agent = plistlib.loads((resources / 'com.juliushe.dev-apfs-mounter.plist').read_bytes())
    except (OSError, UnicodeError, json.JSONDecodeError, plistlib.InvalidFileException) as exc:
        raise Refusal('HES_ASSET_INVALID') from exc
    require(identity == {
        'outerUUID': '2FE2A779-0DC8-3468-8E3C-E113598C46CE',
        'devUUID': '0476F9CC-86A3-40D8-A8D4-83D882522CAD',
        'outerMountPoint': '/Volumes/HE', 'devMountPoint': '/Volumes/HE/DEV',
        'devVolumeName': 'DEV_APFS', 'imagePath': '/Volumes/HE/.DEV-APFS.sparsebundle'},
        'HES_IDENTITY_ASSET_MISMATCH')
    require(agent.get('Label') == 'com.juliushe.dev-apfs-mounter' and
            agent.get('RunAtLoad') is True and 'StartOnMount' not in agent and
            agent.get('ProgramArguments', [None])[0] == '__UMA_CONTROL_PATH__',
            'HES_LAUNCH_AGENT_ASSET_MISMATCH')
    return {'control': {'path': 'Contents/Helpers/HESectoriumControl', 'sha256': sha(control)},
            'resources': {'path': 'Contents/Resources/HESectorium', 'manifest': manifest(resources)}}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def extract_source(root, commit, destination):
    archive = run(['git', '-C', root, 'archive', '--format=tar', commit]).stdout
    destination.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:') as members:
        for member in members.getmembers():
            path = Path(member.name)
            require(not path.is_absolute() and '..' not in path.parts, 'ARCHIVE_PATH_INVALID')
            require(member.isdir() or member.isfile(), 'ARCHIVE_SPECIAL_FILE_REJECTED')
        members.extractall(destination)


def macho_slices(data):
    """Validate universal tables before allowing any load-command inspection."""
    require(len(data) >= 4, 'MACHO_HEADER_TRUNCATED')
    formats = {b'\xca\xfe\xba\xbe': ('>', False), b'\xbe\xba\xfe\xca': ('<', False),
               b'\xca\xfe\xba\xbf': ('>', True), b'\xbf\xba\xfe\xca': ('<', True)}
    fat = formats.get(data[:4])
    if fat is None:
        require(len(data) >= 32, 'MACHO_HEADER_TRUNCATED')
        return [(None, None, 0, len(data))]
    require(len(data) >= 8, 'FAT_HEADER_TRUNCATED')
    endian, wide = fat
    count = struct.unpack_from(endian + 'I', data, 4)[0]
    require(0 < count <= len(MAC_ARCHITECTURES), 'FAT_ARCHITECTURE_COUNT_INVALID')
    record_size = 32 if wide else 20
    header_end = 8 + count * record_size
    require(header_end <= len(data), 'FAT_TABLE_TRUNCATED')
    slices, cpus = [], set()
    for index in range(count):
        record = struct.unpack_from(endian + ('IIQQII' if wide else 'IIIII'),
                                    data, 8 + index * record_size)
        cpu, subtype, offset, size, align = record[:5]
        require(not wide or record[5] == 0, 'FAT_RESERVED_FIELD_INVALID')
        require(cpu not in cpus, 'FAT_DUPLICATE_ARCHITECTURE')
        cpus.add(cpu)
        require(cpu in {value[0] for value in MACHO_CPUS.values()}, 'MACHO_UNSUPPORTED_CPU')
        require(align <= (63 if wide else 31) and offset % (1 << align) == 0,
                'FAT_ALIGNMENT_INVALID')
        require(offset >= header_end and size >= 32 and offset + size <= len(data),
                'FAT_SLICE_OUT_OF_BOUNDS')
        require(all(offset + size <= start or offset >= start + length
                    for _, _, start, length in slices), 'FAT_SLICES_OVERLAP')
        slices.append((cpu, subtype, offset, size))
    return slices


def macho_build_version(path, expected_sdk, expected_minimum, expected_architectures=('arm64',)):
    """Check every slice against the requested CPU, platform and deployment contract."""
    def version(value):
        require(isinstance(value, str) and re.fullmatch(r'\d+(?:\.\d+){0,2}', value),
                'BUILD_VERSION_EXPECTATION_INVALID')
        parts = [int(item) for item in value.split('.')]
        return tuple(parts + [0] * (3 - len(parts)))

    def unpack_version(value):
        return (value >> 16, (value >> 8) & 0xff, value & 0xff)

    require(bool(expected_architectures) and len(set(expected_architectures)) == len(expected_architectures)
            and set(expected_architectures) <= set(MACHO_CPUS), 'MACHO_ARCHITECTURE_EXPECTATION_INVALID')
    expected_sdk_value, expected_minimum_value = version(expected_sdk), version(expected_minimum)
    data, reports = path.read_bytes(), {}
    for table_cpu, table_subtype, start, length in macho_slices(data):
        image = data[start:start + length]
        magic, cpu, subtype, filetype, count, size, _, _ = struct.unpack_from('<8I', image)
        require(magic == 0xfeedfacf and filetype == 2, 'MACHO_NOT_64BIT_EXECUTABLE')
        architecture = next((name for name, value in MACHO_CPUS.items() if value[0] == cpu), None)
        require(architecture is not None, 'MACHO_UNSUPPORTED_CPU')
        require((subtype & 0xffffff) == MACHO_CPUS[architecture][1], 'MACHO_UNSUPPORTED_CPU_SUBTYPE')
        require(table_cpu is None or (table_cpu == cpu and table_subtype == subtype),
                'FAT_SLICE_IDENTITY_MISMATCH')
        require(architecture not in reports, 'FAT_DUPLICATE_ARCHITECTURE')
        end = 32 + size
        require(end <= len(image), 'MACHO_LOAD_COMMANDS_TRUNCATED')
        offset, versions = 32, []
        for _ in range(count):
            require(offset + 8 <= end, 'MACHO_LOAD_COMMAND_TRUNCATED')
            command, command_length = struct.unpack_from('<2I', image, offset)
            require(command_length >= 8 and command_length % 8 == 0 and offset + command_length <= end,
                    'MACHO_LOAD_COMMAND_SIZE_INVALID')
            require(command != 0x24, 'LEGACY_MACOS_VERSION_COMMAND_REJECTED')
            if command == 0x32:
                require(command_length >= 24, 'BUILD_VERSION_TRUNCATED')
                platform, minimum, sdk, tools = struct.unpack_from('<4I', image, offset + 8)
                require(command_length == 24 + tools * 8, 'BUILD_VERSION_TOOL_RECORDS_INVALID')
                versions.append((platform, unpack_version(minimum), unpack_version(sdk)))
            offset += command_length
        require(offset == end, 'MACHO_LOAD_COMMANDS_SIZE_MISMATCH')
        require(len(versions) == 1, 'BUILD_VERSION_MISSING_OR_DUPLICATE')
        platform, minimum, sdk = versions[0]
        require(platform == 1, 'BUILD_VERSION_PLATFORM_MISMATCH ' + architecture)
        require(minimum == expected_minimum_value, 'BUILD_VERSION_MINIMUM_OS_MISMATCH ' + architecture)
        require(sdk == expected_sdk_value, 'BUILD_VERSION_SDK_MISMATCH ' + architecture)
        reports[architecture] = {'verification': 'PASS', 'cpu': cpu, 'cpu_subtype': subtype,
                                 'offset': start, 'size': length, 'platform': 'macOS',
                                 'minimum_os': '.'.join(map(str, minimum)), 'sdk': '.'.join(map(str, sdk))}
    require(set(reports) == set(expected_architectures), 'MACHO_ARCHITECTURES_MISMATCH')
    return {'verification': 'PASS', 'command': 'LC_BUILD_VERSION', 'platform': 'macOS',
            'minimum_os': '.'.join(map(str, expected_minimum_value)),
            'sdk': '.'.join(map(str, expected_sdk_value)),
            'expected_minimum_os': expected_minimum, 'expected_sdk': expected_sdk,
            'architectures': list(expected_architectures), 'slices': reports,
            'parser': 'RAW_MACHO_UNIVERSAL_OR_64'}


def linkage(path, expected_architectures=None):
    def inspect(architecture):
        flags = ['-arch', architecture] if architecture else []
        linked = run(['/usr/bin/otool', *flags, '-L', path]).stdout.decode()
        loads = run(['/usr/bin/otool', *flags, '-l', path]).stdout.decode()
        dependencies = [line.strip().split(' (compatibility version')[0]
                        for line in linked.splitlines()[1:] if line.strip()]
        require(bool(dependencies), 'LINKAGE_EMPTY ' + str(architecture))
        unsafe = [item for item in dependencies
                  if not item.startswith(('/System/Library/', '/usr/lib/'))]
        require(not unsafe, 'RUNTIME_NON_SYSTEM_DEPENDENCY ' + str(architecture) + ' ' + repr(unsafe))
        rpaths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', loads)
        # Absolute system load commands cannot select these development search paths.
        return {'dependencies': dependencies,
                'rpaths': [{'path': item, 'classification': 'UNUSED_NO_RPATH_LOAD_COMMANDS'} for item in rpaths],
                'otool_L': linked, 'otool_l': loads}

    observed_architectures = run(['/usr/bin/lipo', '-archs', path]).stdout.decode().strip()
    if expected_architectures is not None:
        observed = observed_architectures.split()
        require(len(observed) == len(expected_architectures) and set(observed) == set(expected_architectures),
                'LINKAGE_ARCHITECTURES_MISMATCH')
        slices = {arch: inspect(arch) for arch in expected_architectures}
        content = {'slices': slices,
                   'dependencies': sorted({dep for report in slices.values() for dep in report['dependencies']}),
                   'rpaths': [dict(item, architecture=arch) for arch, report in slices.items()
                              for item in report['rpaths']]}
    else:
        content = inspect(None)
    signature = run(['/usr/bin/codesign', '-d', '--verbose=4', path], check=False)
    entitlements = run(['/usr/bin/codesign', '-d', '--entitlements', ':-', path], check=False)
    signing_text = signature.stderr.decode(errors='replace')
    require('Authority=' not in signing_text and
            ((signature.returncode == 0 and 'Signature=adhoc' in signing_text) or
             (signature.returncode != 0 and 'code object is not signed at all' in signing_text)),
            'UNEXPECTED_DISTRIBUTION_SIGNATURE')
    return dict(content, signing_state=signing_text,
                signing_inspection_exit=signature.returncode,
                entitlements_inspection_exit=entitlements.returncode,
                effective_entitlements=entitlements.stdout.decode(errors='replace'),
                file=run(['/usr/bin/file', path]).stdout.decode().strip(),
                architectures=observed_architectures, runtime_development_dependency='NONE')


def release_executable_report(path, expected_sdk, expected_minimum):
    # All three packaged executables must meet this exact universal contract.
    metadata = macho_build_version(path, expected_sdk, expected_minimum, MAC_ARCHITECTURES)
    return dict(linkage(path, MAC_ARCHITECTURES), build_version=metadata)



# These are all inputs for the macOS Swift package, its tests and canonical
# packaging steps. Installed apps, outputs, caches, signing material, Windows
# sources and unrelated Desktop files never enter a snapshot.
SNAPSHOT_DIRECTORIES = ('Assets', 'Configuration', 'Sources', 'Tests', 'script')
SNAPSHOT_FILES = ('Package.swift', 'Package.resolved')
SNAPSHOT_IGNORED_NAMES = ('.DS_Store', '__pycache__')


def snapshot_path(raw, *, must_exist=True, directory=True):
    path = Path(raw)
    require(path.is_absolute() and '..' not in path.parts and '.' not in str(raw).split('/'),
            'SNAPSHOT_PATH_INVALID')
    current = Path('/')
    for part in path.parts[1:]:
        current /= part
        require(not current.is_symlink(), 'SNAPSHOT_SYMLINK_REJECTED')
        require(not part.lower().endswith('.app'), 'SNAPSHOT_APP_PATH_REJECTED')
    if must_exist:
        require(path.is_dir() if directory else path.is_file(), 'SNAPSHOT_PATH_MISSING')
    return path


def snapshot_manifest(root):
    root = snapshot_path(str(root))
    require((root / 'Package.swift').is_file(), 'SNAPSHOT_PACKAGE_MISSING')
    paths = []
    for name in SNAPSHOT_FILES:
        path = root / name
        if path.exists() or path.is_symlink():
            paths.append(path)
    for name in SNAPSHOT_DIRECTORIES:
        base = root / name
        require(base.is_dir() and not base.is_symlink(), 'SNAPSHOT_SOURCE_DIRECTORY_INVALID ' + name)
        paths.append(base)
        for current, dirs, files in os.walk(base, followlinks=False):
            # Refuse links even if their names would otherwise be excluded.
            for name in dirs + files:
                path = Path(current) / name
                require(not path.is_symlink(), 'SNAPSHOT_SYMLINK_REJECTED')
            dirs[:] = sorted(name for name in dirs if name not in SNAPSHOT_IGNORED_NAMES)
            paths.extend(Path(current) / name for name in dirs + files
                         if name not in SNAPSHOT_IGNORED_NAMES)
    records = []
    for path in sorted(paths):
        require(not any(part.lower().endswith('.app') for part in path.relative_to(root).parts),
                'SNAPSHOT_APP_PATH_REJECTED')
        metadata = path.lstat()
        require(metadata.st_dev == root.stat().st_dev, 'SNAPSHOT_CROSS_DEVICE_INPUT')
        require(not (metadata.st_mode & (stat.S_ISUID | stat.S_ISGID)), 'SNAPSHOT_SPECIAL_MODE')
        record = {'path': path.relative_to(root).as_posix(), 'mode': oct(stat.S_IMODE(metadata.st_mode))}
        if stat.S_ISREG(metadata.st_mode):
            require(metadata.st_nlink == 1, 'SNAPSHOT_HARDLINK_REJECTED')
            record.update(type='file', size=metadata.st_size, sha256=sha(path))
        else:
            require(stat.S_ISDIR(metadata.st_mode), 'SNAPSHOT_SPECIAL_FILE_REJECTED')
            record.update(type='directory')
        records.append(record)
    return records


def snapshot_digest(records):
    return hashlib.sha256(json.dumps(records, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def verify_internal_storage(path):
    """Observe the actual backing device, without probing any external volumes."""
    path = snapshot_path(str(path))
    lines = run(['/bin/df', '-P', path]).stdout.decode().splitlines()
    require(len(lines) == 2 and bool(lines[1].split()), 'INTERNAL_STORAGE_DEVICE_UNKNOWN')
    device = lines[1].split()[0]
    require(re.fullmatch(r'/dev/disk\d+(?:s\d+)*', device), 'INTERNAL_STORAGE_DEVICE_UNKNOWN')
    info = plistlib.loads(run(['/usr/sbin/diskutil', 'info', '-plist', device]).stdout)
    require(info.get('DeviceNode') == device and info.get('Internal') is True and
            info.get('WritableVolume') is True and info.get('FilesystemType', '').lower() == 'apfs',
            'INTERNAL_STORAGE_GATE_FAILED')
    return {key: info.get(key) for key in ('DeviceNode', 'Internal', 'VolumeUUID',
            'VolumeName', 'FilesystemType', 'MountPoint', 'WritableVolume')}


def snapshot_output_layout(root, packages_root, builds_root, output_raw, build_raw, stem):
    packages = snapshot_path(packages_root)
    builds = snapshot_path(builds_root)
    output = output_path(output_raw, packages, re.escape(stem) + r'-\d{8}T\d{6}Z')
    build = output_path(build_raw, builds, r'rc-build-\d{8}T\d{6}Z')
    for location in (packages, builds, output, build):
        require(location != root and location not in root.parents, 'SNAPSHOT_OUTPUT_SOURCE_OVERLAP')
        if root in location.parents:
            require(location.relative_to(root).parts[0] == 'outputs', 'SNAPSHOT_OUTPUT_SOURCE_OVERLAP')
    require(output != build and output not in build.parents and build not in output.parents,
            'SNAPSHOT_OUTPUT_BUILD_OVERLAP')
    return output, build


def freeze_snapshot(root, destination):
    root = snapshot_path(str(root))
    target = snapshot_path(str(destination), must_exist=False, directory=False)
    require(not target.exists() and target.parent.is_dir(), 'SNAPSHOT_MANIFEST_DESTINATION_INVALID')
    require(root not in target.parents or target.relative_to(root).parts[0] == 'outputs',
            'SNAPSHOT_MANIFEST_SOURCE_OVERLAP')
    storage = verify_internal_storage(root)
    verify_internal_storage(target.parent)
    records = snapshot_manifest(root)
    value = {'schema_version': 1, 'identity_type': 'SOURCE_SNAPSHOT_SHA256',
             'source_root': str(root), 'snapshot_sha256': snapshot_digest(records),
             'included_directories': list(SNAPSHOT_DIRECTORIES),
             'included_files': list(SNAPSHOT_FILES), 'ignored_names': list(SNAPSHOT_IGNORED_NAMES),
             'records': records, 'storage': storage, 'git_identity': None}
    with target.open('x') as stream:
        json.dump(value, stream, sort_keys=True, indent=2)
        stream.write('\n')
    return value


def verify_snapshot(root, manifest_path, expected_digest):
    path = snapshot_path(str(manifest_path), directory=False)
    require(re.fullmatch(r'[0-9a-f]{64}', expected_digest or ''), 'SNAPSHOT_ID_INVALID')
    value = json.loads(path.read_text())
    require(value.get('schema_version') == 1 and value.get('identity_type') == 'SOURCE_SNAPSHOT_SHA256' and
            value.get('source_root') == str(root) and value.get('git_identity') is None and
            value.get('included_directories') == list(SNAPSHOT_DIRECTORIES) and
            value.get('included_files') == list(SNAPSHOT_FILES) and
            value.get('ignored_names') == list(SNAPSHOT_IGNORED_NAMES), 'SNAPSHOT_MANIFEST_INVALID')
    records = snapshot_manifest(root)
    require(value.get('records') == records and snapshot_digest(records) == expected_digest and
            value.get('snapshot_sha256') == expected_digest, 'SNAPSHOT_SOURCE_CHANGED')
    return value


def copy_snapshot(root, snapshot, destination):
    require(not destination.exists() and not destination.is_symlink(), 'SNAPSHOT_COPY_ALREADY_EXISTS')
    # Reobserve before copying and compare each resulting byte/mode afterwards.
    require(snapshot['records'] == snapshot_manifest(root), 'SNAPSHOT_SOURCE_CHANGED')
    destination.mkdir()
    for record in snapshot['records']:
        origin, target = root / record['path'], destination / record['path']
        if record['type'] == 'directory':
            target.mkdir()
            target.chmod(int(record['mode'], 8))
        else:
            shutil.copyfile(origin, target, follow_symlinks=False)
            target.chmod(int(record['mode'], 8))
    require(manifest(destination) == snapshot['records'], 'SNAPSHOT_COPY_MISMATCH')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-mode', choices=('git', 'snapshot'), default='git')
    parser.add_argument('--source-root', help='explicit source directory for snapshot mode')
    parser.add_argument('--snapshot-manifest', help='previously frozen exact macOS source inventory')
    parser.add_argument('--snapshot-sha256', help='expected frozen source snapshot identity')
    parser.add_argument('--freeze-snapshot', help='write a new manifest only; never build')
    parser.add_argument('--packages-root', help='explicit existing internal output parent')
    parser.add_argument('--builds-root', help='explicit existing internal staging parent')
    parser.add_argument('--commit')
    parser.add_argument('--tree')
    parser.add_argument('--branch', default='codex/threados-as3-setup',
                        help='exact clean source branch expected for this candidate')
    parser.add_argument('--output')
    parser.add_argument('--build-root')
    args = parser.parse_args()
    # All guards run before any output directory or compiler process is created.
    snapshot = None
    if args.source_mode == 'snapshot':
        require(args.source_root and not args.commit and not args.tree,
                'SNAPSHOT_EXPLICIT_SOURCE_REQUIRED_NO_GIT_IDENTITY')
        root = snapshot_path(args.source_root)
        require(sha(root / 'script/package_uma014_rc.py') == sha(Path(__file__)),
                'SNAPSHOT_PACKAGER_BYTES_MISMATCH')
        if args.freeze_snapshot:
            require(not any((args.output, args.build_root, args.snapshot_manifest, args.snapshot_sha256,
                             args.packages_root, args.builds_root)), 'SNAPSHOT_FREEZE_ARGUMENT_CONFLICT')
            value = freeze_snapshot(root, args.freeze_snapshot)
            print(json.dumps({'manifest': args.freeze_snapshot,
                              'snapshot_sha256': value['snapshot_sha256'],
                              'record_count': len(value['records'])}, sort_keys=True))
            return
        require(all((args.snapshot_manifest, args.snapshot_sha256, args.output, args.build_root,
                     args.packages_root, args.builds_root)), 'SNAPSHOT_EXPLICIT_INPUTS_REQUIRED')
        snapshot = verify_snapshot(root, args.snapshot_manifest, args.snapshot_sha256)
        authority, rc, version = version_metadata(root)
        output, build = snapshot_output_layout(root, args.packages_root, args.builds_root,
                                              args.output, args.build_root, rc['PackageStem'])
        storage = {'source': verify_internal_storage(root),
                   'package': verify_internal_storage(output.parent),
                   'build': verify_internal_storage(build.parent)}
        provenance = {'source_mode': 'snapshot', 'snapshot_sha256': args.snapshot_sha256,
                      'snapshot_manifest_sha256': sha(Path(args.snapshot_manifest)),
                      'original_source_root': str(root), 'commit': None, 'tree': None,
                      'branch': None, 'worktree': 'NOT_APPLICABLE', 'index': 'NOT_APPLICABLE'}
    else:
        require(not any((args.source_root, args.snapshot_manifest, args.snapshot_sha256,
                         args.freeze_snapshot, args.packages_root, args.builds_root)),
                'GIT_MODE_SNAPSHOT_ARGUMENTS_REJECTED')
        require(all((args.commit, args.tree, args.output, args.build_root)), 'GIT_EXPLICIT_INPUTS_REQUIRED')
        root = ROOT
        branch = source_state(root, args.commit, args.tree, args.branch)
        authority, rc, version = version_metadata(root)
        output = output_path(args.output, PACKAGES, re.escape(rc['PackageStem']) + r'-\d{8}T\d{6}Z')
        build = output_path(args.build_root, BUILDS, r'rc-build-\d{8}T\d{6}Z')
        observed_storage = verify_storage()
        storage = {key: observed_storage[key] for key in ('VolumeName', 'FilesystemType', 'MountPoint',
                                                        'GlobalPermissionsEnabled', 'WritableVolume')}
        provenance = {'source_mode': 'git', 'commit': args.commit, 'tree': args.tree, 'branch': branch,
                      'worktree': 'CLEAN', 'index': 'EMPTY'}
    require(DEVELOPER.is_dir(), 'XCODE_TOOLCHAIN_UNAVAILABLE')
    env = dict(os.environ, DEVELOPER_DIR=str(DEVELOPER))
    swift = run(['/usr/bin/xcrun', '--find', 'swift'], env=env).stdout.decode().strip()
    sdk = run(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'], env=env).stdout.decode().strip()
    sdk_version = run(['/usr/bin/xcrun', '--sdk', sdk, '--show-sdk-version'], env=env).stdout.decode().strip()
    os.umask(0o077)
    output.mkdir()  # Atomic reservation; an incomplete build is retained as evidence.
    build.parent.mkdir(parents=True, exist_ok=True)
    build.mkdir()
    source = build / 'source'
    if snapshot:
        copy_snapshot(root, snapshot, source)
        write_json(output / 'snapshot-input.json', snapshot)
    else:
        extract_source(root, args.commit, source)
    source_manifest = manifest(source)
    write_json(output / 'source-manifest.json', source_manifest)
    for name in ('tmp', 'cache/clang', 'cache/swiftpm', 'config', 'security'):
        (build / name).mkdir(parents=True, exist_ok=True)
    # Keep HOME unchanged. Explicit SwiftPM cache/config/security paths avoid
    # borrowing user package credentials; keychain and netrc are disabled.
    env.update(SDKROOT=sdk, TMPDIR=str(build / 'tmp'),
               CLANG_MODULE_CACHE_PATH=str(build / 'cache/clang'),
               SWIFTPM_MODULECACHE_OVERRIDE=str(build / 'cache/swiftpm'))
    # SwiftBuild sanitizes SDKROOT from child linker environments. Swift's
    # --sysroot forwarding alone leaves this clang's SDK metadata at the minimum
    # OS. Forward the same selected SDK explicitly as clang's -isysroot.
    options = ['--build-system', 'swiftbuild', '--arch', 'arm64', '--arch', 'x86_64', '--disable-sandbox', '--disable-keychain', '--disable-netrc',
               '--manifest-cache', 'local', '--cache-path', build / 'cache/swiftpm',
               '--config-path', build / 'config', '--security-path', build / 'security',
               '--sdk', sdk, '-Xswiftc', '-sdk', '-Xswiftc', sdk,
               '-Xswiftc', '-Xclang-linker', '-Xswiftc', '-isysroot',
               '-Xswiftc', '-Xclang-linker', '-Xswiftc', sdk,
               '-Xswiftc', '-D', '-Xswiftc', 'UMA_PRODUCTION_RELEASE',
               '--scratch-path', build / 'swift', '--configuration', 'release']
    commands = []
    for product in ('CodexUsageMonitor', 'ClaudeStatusLineRelay', 'HESectoriumControl'):
        command = [swift, 'build', *options, '--product', product]
        commands.append([str(x) for x in command])
        with (output / f'build-{product}.log').open('wb') as log:
            result = subprocess.run([str(x) for x in command], cwd=source, env=env,
                                    stdout=log, stderr=subprocess.STDOUT)
        require(result.returncode == 0, f'RELEASE_BUILD_FAILED {product}')
    bin_path = Path(run([swift, 'build', *options, '--show-bin-path'], cwd=source,
                        env=env).stdout.decode().strip())
    app = output / 'UMA.app'
    for subpath in ('Contents/MacOS', 'Contents/Helpers', 'Contents/Resources'):
        (app / subpath).mkdir(parents=True, exist_ok=True)
    executables = {'main': app / 'Contents/MacOS/CodexUsageMonitor',
                   'relay': app / 'Contents/Helpers/ClaudeStatusLineRelay',
                   'hesectorium_control': app / 'Contents/Helpers/HESectoriumControl'}
    for target in executables.values():
        shutil.copyfile(bin_path / target.name, target)
        target.chmod(0o755)
    swiftpm_resources = copy_swiftpm_resource_bundle(bin_path, app / 'Contents/Resources', source)
    hesectorium = copy_hesectorium_assets(bin_path, app, source)
    shutil.copyfile(source / 'Assets/AppIcon.icns', app / 'Contents/Resources/AppIcon.icns')
    (app / 'Contents/Resources/AppIcon.icns').chmod(0o644)
    logos = app / 'Contents/Resources/AgentLogos'
    logos.mkdir()
    for name in ('codex', 'claude-code', 'workbuddy', 'antigravity'):
        target = logos / f'{name}.svg'
        shutil.copyfile(source / 'Assets/AgentLogos' / target.name, target)
        target.chmod(0o644)
    info = {'CFBundleExecutable': 'CodexUsageMonitor', 'CFBundleIdentifier': rc['BundleIdentifier'],
            'CFBundleName': rc['ApplicationName'], 'CFBundleDisplayName': 'AUV',
            'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version,
            'CFBundleVersion': rc['BuildNumber'], 'LSMinimumSystemVersion': rc['MinimumSystemVersion'],
            'NSPrincipalClass': 'NSApplication', 'CFBundleIconFile': 'AppIcon',
            'UMAPackagingMode': 'PRODUCTION_SPLIT_APP', 'UMARuntimeChannel': 'production-safari-host',
            'UMATeamIdentifier': rc['HostTeamIdentifier'],
            'UMARuntimeGenerationID': str(uuid.uuid4()),
            'UMASafariHostBundleIdentifier': rc['HostBundleIdentifier'],
            'UMASafariHostExtensionBundleIdentifier': rc['HostExtensionBundleIdentifier'],
            'UMAAppGroupIdentifier': rc['HostAppGroupIdentifier'],
            'UMASafariHostRuntimeGenerationID': rc['FrozenHostRuntimeGenerationID'],
            'UMASafariHostExtensionVersion': rc['FrozenHostExtensionVersion'],
            'UMASafariHostExtensionBuild': rc['FrozenHostBuild']}
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info, sort_keys=True))
    (app / 'Contents/Info.plist').chmod(0o644)
    reports = {name: release_executable_report(path, sdk_version, rc['MinimumSystemVersion'])
               for name, path in executables.items()}
    write_json(output / 'linkage-report.json', reports)
    write_json(output / 'hash-manifest.json', manifest(app))
    if snapshot:
        verify_snapshot(root, args.snapshot_manifest, args.snapshot_sha256)
    else:
        source_state(root, args.commit, args.tree, args.branch)
    require(source_manifest == manifest(source), 'ARCHIVED_SOURCE_CHANGED_DURING_BUILD')
    toolchain = {'commands': commands, 'swift_version': run([swift, '--version'], env=env).stdout.decode(),
                 'xcode_version': run(['/usr/bin/xcodebuild', '-version'], env=env).stdout.decode(),
                 'developer_directory': str(DEVELOPER), 'sdk': sdk,
                 'sdk_version': sdk_version, 'build_system': 'swiftbuild',
                 'architectures': list(MAC_ARCHITECTURES),
                 'linker_sdk_selection': 'EXPLICIT_CLANG_ISYSROOT',
                 'deployment_target': rc['MinimumSystemVersion'], 'configuration': 'release',
                 'swift_path': swift, 'swift_sha256': sha(Path(swift)),
                 'compile_definitions': ['UMA_PRODUCTION_RELEASE'],
                 'entitlements_used': [], 'signing_command_run': False,
                 'build_root': str(build), 'source_root': str(source)}
    write_json(output / 'build-toolchain-manifest.json', toolchain)
    result = {'schema_version': 1,
              'classification': ('SNAPSHOT_CANDIDATE_UNSIGNED' if snapshot else 'CLEAN_RELEASE_CANDIDATE_UNSIGNED'),
              **provenance, 'product_version': version,
              'build_number': rc['BuildNumber'], 'bundle_identifier': rc['BundleIdentifier'],
              'architectures': list(MAC_ARCHITECTURES),
              'package': str(output), 'application': str(app),
              'package_script_sha256': sha(source / 'script/package_uma014_rc.py'),
              'version_authority_sha256': sha(source / 'Configuration/UMAProductVersion.plist'),
              'swiftpm_resources': swiftpm_resources,
              'main_executable_sha256': sha(executables['main']),
              'relay_sha256': sha(executables['relay']),
              'hesectorium_control_sha256': sha(executables['hesectorium_control']),
              'hesectorium': hesectorium, 'signing': 'NO_SIGNING_COMMAND',
              'notarization': 'NOT_RUN', 'runtime_development_dependency': 'NONE',
              'host_compatibility': {'state': 'METADATA_ONLY_LIVE_GATE',
                                     'version': authority['SafariCompatibility']['HostMarketingVersion'],
                                     'build': rc['FrozenHostBuild'],
                                     'generation': rc['FrozenHostRuntimeGenerationID'],
                                     'protocol': authority['SafariCompatibility']['ProtocolVersion']},
              'storage': storage}
    write_json(output / 'RC-manifest.json', result)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (Refusal, OSError, ValueError, KeyError) as error:
        print(f'UMA014_RC_REFUSED: {error}', file=sys.stderr)
        sys.exit(2)
