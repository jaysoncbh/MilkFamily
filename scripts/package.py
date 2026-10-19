#!/usr/bin/env python3
"""Build local app/ZIP artifacts; never install, launch, or modify user data."""
import argparse
import hashlib
import importlib.util
import json
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('runtime_assets', REPO / 'macOS/03_脚本/打包运行素材.py')
PACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACK)


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def package(executable, assets, configuration):
    executable, assets = executable.resolve(), assets.resolve()
    # Validate the supplied manifest and every source byte before building.
    manifest = json.loads((assets / '运行资源清单.json').read_text())
    for item in manifest['files']:
        source = (assets / item['file']).resolve()
        if not source.is_relative_to(assets) or not source.is_file():
            raise ValueError('Invalid asset path: ' + item['file'])
        data = source.read_bytes()
        if len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']:
            raise ValueError('Asset checksum mismatch: ' + item['file'])
    version = json.loads((REPO / 'VERSION.json').read_text())
    debug = configuration == 'debug'
    name = '奶家族测试版' if debug else '奶家族'
    dist = REPO / 'dist'
    dist.mkdir(exist_ok=True)
    # Stage outside Desktop/iCloud so Finder cannot attach bundle metadata mid-signing.
    with tempfile.TemporaryDirectory(prefix='milk-family-package-') as temporary:
        stage = Path(temporary)
        app = stage / (name + '.app')
        resources = app / 'Contents/Resources'
        resources.mkdir(parents=True)
        binary = app / 'Contents/MacOS/Naijia'
        binary.parent.mkdir()
        shutil.copyfile(executable, binary)
        binary.chmod(0o755)
        # Remove build-only debug/object paths; retain runtime Swift metadata.
        run('strip', '-S', binary)
        if b'/Users/' in binary.read_bytes():
            raise ValueError('Personal build path remains in candidate binary')
        files, stats = PACK.runtime_assets(assets)
        for relative, value in files.items():
            target = resources / '项目素材' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if isinstance(value, bytes):
                target.write_bytes(value)
            else:
                shutil.copyfile(value, target)
        verification = PACK.verify(assets, resources / '项目素材')
        iconset = stage / 'AppIcon.iconset'
        run('swift', REPO / 'macOS/03_脚本/制作应用图标.swift',
            assets / '01_人物素材/稀有/A201_成年奶蛙/游戏素材/B20101.png', iconset)
        run('iconutil', '-c', 'icns', iconset, '-o', resources / 'AppIcon.icns')
        for source, target in [('docs/使用与隐私说明.md', '使用与隐私说明.md'),
                               ('docs/Usage_and_Privacy.md', 'Usage and Privacy.md'),
                               ('licenses/PokeTokenBar-MIT.txt', 'PokeTokenBar-MIT.txt'),
                               ('LICENSE', 'SOURCE-LICENSE.txt'),
                               ('ASSET_RIGHTS.md', 'ASSET_RIGHTS.md')]:
            shutil.copyfile(REPO / source, resources / target)
        metadata = {
            'CFBundleName': name, 'CFBundleDisplayName': name,
            'CFBundleIdentifier': 'local.naijia.live' if debug else 'local.naijia.family',
            'CFBundleVersion': str(version['build']),
            'CFBundleShortVersionString': version['version'],
            'CFBundleExecutable': 'Naijia', 'CFBundlePackageType': 'APPL',
            'CFBundleIconFile': 'AppIcon', 'LSUIElement': False,
            'LSMinimumSystemVersion': version['minimumMacOS'],
            'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
            'NaijiaDevelopmentToolsEnabled': debug,
            'NaijiaAppFlavor': 'test' if debug else 'user',
            'NaijiaDataDirectory': '奶家' if debug else '奶家族',
        }
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(metadata))
        for attribute in ['com.apple.FinderInfo', 'com.apple.ResourceFork']:
            subprocess.run(['xattr', '-rd', attribute, str(app)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        run('codesign', '--force', '--sign', '-', app)
        run('codesign', '--verify', '--deep', '--strict', app)
        architecture = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
        suffix = 'universal' if len(architecture) > 1 else architecture[0]
        stem = 'MilkFamily-Test' if debug else 'MilkFamily'
        archive = dist / (stem + '-' + version['version'] + '-macOS-' + suffix + '.zip')
        run('ditto', '-c', '-k', '--norsrc', '--keepParent', app, archive)
    result = {**verification, 'version': version['version'], 'build': version['build'],
              'configuration': configuration, 'architecture': architecture,
              'archive': archive.name, 'archiveSHA256': hashlib.sha256(archive.read_bytes()).hexdigest(),
              'signature': 'local-ad-hoc', 'notarized': False, 'installed': False}
    (dist / (stem + '-package-report.json')).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--configuration', choices=['debug', 'release'], required=True)
    options = parser.parse_args()
    package(options.executable, options.assets, options.configuration)
