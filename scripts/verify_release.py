#!/usr/bin/env python3
"""Validate the public source boundary and local documentation references."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    'README.md', 'README.zh-CN.md', 'LICENSE', 'ASSET_RIGHTS.md', 'NOTICE.md',
    'VERSION.json', 'docs/BUILD.md', 'docs/RELEASE_CHECKLIST.md',
    'docs/使用与隐私说明.md', 'docs/Usage_and_Privacy.md',
    'licenses/PokeTokenBar-MIT.txt', '.github/workflows/checks.yml',
    'scripts/build.sh', 'scripts/check.sh', 'scripts/package.py',
    'macOS/03_脚本/构建.command', 'macOS/Tests/LocalizationChecks/names.json',
]
for name in REQUIRED:
    assert (ROOT / name).is_file(), 'Missing release file: ' + name
version = json.loads((ROOT / 'VERSION.json').read_text())
assert version['version'] == '1.0.0' and version['build'] == 22
rules = json.loads((ROOT / 'macOS/02_配置/正式版规则.json').read_text())
assert rules['unlockThresholds'] == [0, 20_000_000]
assert rules['eggThresholds'] == {str(n): 50_000_000 for n in range(1, 5)}
fixture = json.loads((ROOT / 'macOS/Tests/LocalizationChecks/names.json').read_text())
assert len(fixture['characters']) == 32
assert len({n['id'] for n in fixture['characters']}) == 32
strings = (ROOT / 'macOS/01_源码/NaijiaApp/Localization.swift').read_text()
pairs = re.findall(r'"([^"\n]+)": "([^"\n]*)"', strings)
keys = [key for key, _ in pairs]
assert len(keys) == len(set(keys)), 'Duplicate translation keys'
translations = dict(pairs)
for entry in fixture['characters'] + fixture['actions']:
    assert translations[entry['zh']] == entry['en']
links = 0
for document in ROOT.rglob('*.md'):
    if any(part in {'.git', '.build', 'dist', 'Resources', '__pycache__'} for part in document.relative_to(ROOT).parts):
        continue
    value = document.read_text()
    targets = re.findall(r'\]\(([^)\n]+)\)', value) + re.findall(r'(?:src|href)="([^"]+)"', value)
    for target in targets:
        target = target.strip('<>').split('#', 1)[0]
        if not target or '://' in target or target.startswith('mailto:'):
            continue
        assert not target.startswith('/'), 'Absolute local documentation link: ' + str(document)
        assert (document.parent / target).resolve().is_file(), 'Broken link: ' + target
        links += 1
for path in ROOT.rglob('*'):
    relative = path.relative_to(ROOT)
    if any(part in {'.git', '.build', '.swiftpm', 'dist', 'Resources', '__pycache__'} for part in relative.parts):
        continue
    if not path.is_file():
        continue
    assert path.suffix.lower() not in {'.p12', '.mobileprovision', '.pem'}, 'Signing secret in source export'
    assert path.name not in {'正式存档.json', '开发测试存档.json', '用量元数据缓存.json'}, 'Personal data in source export'
    assert path.name != '.env', 'Environment secret in source export'
    assert path.stat().st_size < 25 * 1024 * 1024, 'Large file in source export: ' + str(relative)
    if path.suffix in {'.swift', '.py', '.sh', '.md', '.json', '.yml', '.command', '.txt'}:
        text = path.read_text()
        assert not re.search('/' + r'Users/(?!private(?:/|\b))[^/\s]+/', text), 'Personal absolute path in source: ' + str(relative)
print(f'Release source boundary, 32 names, rules and {links} local documentation links passed')
