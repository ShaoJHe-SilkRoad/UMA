#!/usr/bin/env python3
"""Construct an unsigned, clean-source release candidate; never install or launch it."""
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


def macho_build_version(path, expected_sdk, expected_minimum):
    """Read the arm64 executable load commands; refuse ambiguous release metadata."""
    def version(value):
        require(isinstance(value, str) and re.fullmatch(r'\d+(?:\.\d+){0,2}', value),
                'BUILD_VERSION_EXPECTATION_INVALID')
        parts = [int(item) for item in value.split('.')]
        return tuple(parts + [0] * (3 - len(parts)))

    def unpack_version(value):
        return (value >> 16, (value >> 8) & 0xff, value & 0xff)

    data = path.read_bytes()
    require(len(data) >= 32, 'MACHO_HEADER_TRUNCATED')
    magic, cpu, _, filetype, count, size, _, _ = struct.unpack_from('<8I', data)
    require(magic == 0xfeedfacf and cpu == 0x0100000c and filetype == 2,
            'MACHO_NOT_ARM64_EXECUTABLE')
    end = 32 + size
    require(end <= len(data), 'MACHO_LOAD_COMMANDS_TRUNCATED')
    offset, versions = 32, []
    for _ in range(count):
        require(offset + 8 <= end, 'MACHO_LOAD_COMMAND_TRUNCATED')
        command, length = struct.unpack_from('<2I', data, offset)
        require(length >= 8 and length % 8 == 0 and offset + length <= end,
                'MACHO_LOAD_COMMAND_SIZE_INVALID')
        require(command != 0x24, 'LEGACY_MACOS_VERSION_COMMAND_REJECTED')
        if command == 0x32:  # LC_BUILD_VERSION, including its linker tool records.
            require(length >= 24, 'BUILD_VERSION_TRUNCATED')
            platform, minimum, sdk, tools = struct.unpack_from('<4I', data, offset + 8)
            require(length == 24 + tools * 8, 'BUILD_VERSION_TOOL_RECORDS_INVALID')
            versions.append((platform, unpack_version(minimum), unpack_version(sdk)))
        offset += length
    require(offset == end, 'MACHO_LOAD_COMMANDS_SIZE_MISMATCH')
    require(len(versions) == 1, 'BUILD_VERSION_MISSING_OR_DUPLICATE')
    platform, minimum, sdk = versions[0]
    require(platform == 1, 'BUILD_VERSION_PLATFORM_MISMATCH')
    require(minimum == version(expected_minimum), 'BUILD_VERSION_MINIMUM_OS_MISMATCH')
    require(sdk == version(expected_sdk), 'BUILD_VERSION_SDK_MISMATCH')
    return {'verification': 'PASS', 'command': 'LC_BUILD_VERSION', 'platform': 'macOS',
            'minimum_os': '.'.join(map(str, minimum)), 'sdk': '.'.join(map(str, sdk)),
            'expected_minimum_os': expected_minimum, 'expected_sdk': expected_sdk,
            'parser': 'RAW_MACHO_ARM64'}


def linkage(path):
    linked = run(['/usr/bin/otool', '-L', path]).stdout.decode()
    loads = run(['/usr/bin/otool', '-l', path]).stdout.decode()
    dependencies = [line.strip().split(' (compatibility version')[0]
                    for line in linked.splitlines()[1:] if line.strip()]
    require(bool(dependencies), 'LINKAGE_EMPTY')
    unsafe = [item for item in dependencies
              if not item.startswith(('/System/Library/', '/usr/lib/'))]
    require(not unsafe, 'RUNTIME_NON_SYSTEM_DEPENDENCY ' + repr(unsafe))
    rpaths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', loads)
    # With exclusively absolute system LC_LOAD_DYLIB entries, no @rpath load can
    # select these search directories. Retain this evidence instead of rewriting binaries.
    classified = [{'path': item, 'classification': 'UNUSED_NO_RPATH_LOAD_COMMANDS'}
                  for item in rpaths]
    signature = run(['/usr/bin/codesign', '-d', '--verbose=4', path], check=False)
    entitlements = run(['/usr/bin/codesign', '-d', '--entitlements', ':-', path], check=False)
    signing_text = signature.stderr.decode(errors='replace')
    require('Authority=' not in signing_text and
            ((signature.returncode == 0 and 'Signature=adhoc' in signing_text) or
             (signature.returncode != 0 and 'code object is not signed at all' in signing_text)),
            'UNEXPECTED_DISTRIBUTION_SIGNATURE')
    return {'dependencies': dependencies, 'rpaths': classified, 'otool_L': linked,
            'otool_l': loads, 'signing_state': signing_text,
            'signing_inspection_exit': signature.returncode,
            'entitlements_inspection_exit': entitlements.returncode,
            'effective_entitlements': entitlements.stdout.decode(errors='replace'),
            'file': run(['/usr/bin/file', path]).stdout.decode().strip(),
            'architectures': run(['/usr/bin/lipo', '-archs', path]).stdout.decode().strip(),
            'runtime_development_dependency': 'NONE'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--tree', required=True)
    parser.add_argument('--branch', default='codex/threados-as3-setup',
                        help='exact clean source branch expected for this candidate')
    parser.add_argument('--output', required=True)
    parser.add_argument('--build-root', required=True)
    args = parser.parse_args()
    # All guards run before any output directory or compiler process is created.
    branch = source_state(ROOT, args.commit, args.tree, args.branch)
    authority, rc, version = version_metadata(ROOT)
    output = output_path(args.output, PACKAGES, re.escape(rc['PackageStem']) + r'-\d{8}T\d{6}Z')
    build = output_path(args.build_root, BUILDS, r'rc-build-\d{8}T\d{6}Z')
    storage = verify_storage()
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
    extract_source(ROOT, args.commit, source)
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
    options = ['--build-system', 'swiftbuild', '--disable-sandbox', '--disable-keychain', '--disable-netrc',
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
    for name in ('codex', 'claude-code', 'workbuddy'):
        target = logos / f'{name}.svg'
        shutil.copyfile(source / 'Assets/AgentLogos' / target.name, target)
        target.chmod(0o644)
    info = {'CFBundleExecutable': 'CodexUsageMonitor', 'CFBundleIdentifier': rc['BundleIdentifier'],
            'CFBundleName': rc['ApplicationName'], 'CFBundleDisplayName': rc['ApplicationName'],
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
    reports = {name: dict(linkage(path), build_version=macho_build_version(
        path, sdk_version, rc['MinimumSystemVersion'])) for name, path in executables.items()}
    write_json(output / 'linkage-report.json', reports)
    write_json(output / 'hash-manifest.json', manifest(app))
    source_state(ROOT, args.commit, args.tree, args.branch)
    require(source_manifest == manifest(source), 'ARCHIVED_SOURCE_CHANGED_DURING_BUILD')
    toolchain = {'commands': commands, 'swift_version': run([swift, '--version'], env=env).stdout.decode(),
                 'xcode_version': run(['/usr/bin/xcodebuild', '-version'], env=env).stdout.decode(),
                 'developer_directory': str(DEVELOPER), 'sdk': sdk,
                 'sdk_version': sdk_version, 'build_system': 'swiftbuild',
                 'linker_sdk_selection': 'EXPLICIT_CLANG_ISYSROOT',
                 'deployment_target': rc['MinimumSystemVersion'], 'configuration': 'release',
                 'swift_path': swift, 'swift_sha256': sha(Path(swift)),
                 'compile_definitions': ['UMA_PRODUCTION_RELEASE'],
                 'entitlements_used': [], 'signing_command_run': False,
                 'build_root': str(build), 'source_root': str(source)}
    write_json(output / 'build-toolchain-manifest.json', toolchain)
    result = {'schema_version': 1, 'classification': 'CLEAN_RELEASE_CANDIDATE_UNSIGNED',
              'commit': args.commit, 'tree': args.tree, 'branch': branch,
              'worktree': 'CLEAN', 'index': 'EMPTY', 'product_version': version,
              'build_number': rc['BuildNumber'], 'bundle_identifier': rc['BundleIdentifier'],
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
              'storage': {key: storage[key] for key in ('VolumeName', 'FilesystemType', 'MountPoint', 'GlobalPermissionsEnabled', 'WritableVolume')}}
    write_json(output / 'RC-manifest.json', result)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (Refusal, OSError, ValueError, KeyError) as error:
        print(f'UMA014_RC_REFUSED: {error}', file=sys.stderr)
        sys.exit(2)
