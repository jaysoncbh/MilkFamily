#!/usr/bin/env python3
"""Exercise the actual Swift localization function, including composed labels."""
import json
import os
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = HERE.parents[1] / '01_源码/NaijiaApp/Localization.swift'

with tempfile.TemporaryDirectory(prefix='milk-localization-') as temporary:
    root = Path(temporary)
    runner = root / 'Checks.swift'
    runner.write_text(r'''import Foundation
@MainActor final class AppStore {}
struct NamePair: Decodable { let zh, en: String }
struct Fixture: Decodable { let characters, actions: [NamePair] }
@main struct Checks {
    @MainActor static func main() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        precondition(fixture.characters.count == 32)
        for language in ["en", "zh-Hans"] {
            UIStrings.language = language
            for entry in fixture.characters + fixture.actions {
                let expected = language == "en" ? entry.en : entry.zh
                precondition(L(entry.zh) == expected, "Missing or incorrect translation: \(entry.zh)")
                precondition(L("\(entry.zh) · A101") == "\(expected) · A101", "Composed label failed")
                if language == "en" { precondition(!expected.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) }) }
            }
        }
        UIStrings.language = "en"
        precondition(L("奶大星，已拥有") == "Milk Starfish，Owned")
        precondition(L("奶星石") == "Milk Star")
        precondition(L("奶家族测试版") == "Milk Family Test")
        print("Localization passed: \(fixture.characters.count) characters, \(fixture.actions.count) actions, both languages and composed labels")
    }
}
''')
    executable = root / 'checks'
    subprocess.run(['swiftc', '-parse-as-library', str(APP), str(runner), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(HERE / 'names.json')], check=True)
    if os.environ.get('NAIJIA_ASSET_ROOT'):
        manifest = json.loads((Path(os.environ['NAIJIA_ASSET_ROOT']) / '05_配置与索引/角色记录.json').read_text())
        fixture = json.loads((HERE / 'names.json').read_text())
        assert {c['name'] for c in manifest['characters']} == {c['zh'] for c in fixture['characters']}
        action_names = {frame['name'] for c in manifest['characters'] for frame in c['frames'].values()}
        assert action_names <= {a['zh'] for a in fixture['actions']}, action_names - {a['zh'] for a in fixture['actions']}
        print('All runtime character and action names covered')
