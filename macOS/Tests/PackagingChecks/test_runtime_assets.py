# -*- coding: utf-8 -*-
import importlib.util
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / '03_脚本/打包运行素材.py'
SPEC = importlib.util.spec_from_file_location('runtime_assets', SCRIPT)
PACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACK)


class RuntimeAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='naijia-packaging-check-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'source'
        self.root.mkdir()
        def chunk(kind, body):
            return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
        self.png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 256, 256, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0' + b'\0\0\0\0' * 256) * 256)) + chunk(b'IEND', b'')
        self.manifest = {'characters': [{'id': 'A101', 'name': 'Fixture', 'rarityCode': 1, 'rarity': '普通', 'poseOrder': ['idle'], 'frames': {'idle': {'id': 'B10101', 'name': '待机', 'file': 'sprite.png', 'original': 'master.png', 'cardId': 'C10101', 'cardStyle': '普通卡', 'animation': 'animation.json', 'sourceGeneratedImage': '/Users/private/example.png'}}}], 'cards': [{'id': 'C10101', 'characterId': 'A101', 'actionId': 'B10101', 'actionName': '待机', 'name': 'Fixture', 'rarity': '普通', 'style': '普通卡', 'file': 'card.png', 'gamePoolOpen': False, 'generationRecord': '/Users/private/example.json'}]}
        self.write('05_配置与索引/角色记录.json', self.manifest)
        self.write('animation.json', {'actionId': 'B10101', 'frameCount': 1, 'frameDurationsMs': [160], 'loop': False, 'frames': [{'file': 'frame.png', 'source': '/Users/private/original.png'}], 'sourceGeneratedImage': '/Users/private/frame.png'})
        self.write('05_配置与索引/道具素材记录.json', {'items': [{'id': 'fixture', 'game': {'file': 'item.png'}}]})
        self.write('07_软件开发/macOS/02_配置/正式版规则.json', {'fixture': True})
        for name in ['sprite.png', 'card.png', 'frame.png', 'item.png']:
            (self.root / name).write_bytes(self.png)

    def write(self, path, value):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(PACK.encoded(value))

    def packaged(self):
        destination = Path(self.temp.name) / 'package'
        assets, _ = PACK.runtime_assets(self.root)
        for relative, value in assets.items():
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value if isinstance(value, bytes) else value.read_bytes())
        return destination

    def test_private_provenance_is_removed_and_art_bytes_are_unchanged(self):
        package = self.packaged()
        self.assertEqual(PACK.verify(self.root, package)['result'], 'pass')
        for path in package.rglob('*.json'):
            self.assertNotIn(b'/Users/', path.read_bytes())
            self.assertNotIn(b'sourceGeneratedImage', path.read_bytes())
        self.assertEqual((package / 'card.png').read_bytes(), self.png)
        self.assertIn(b'/Users/private/', (self.root / 'animation.json').read_bytes())

    def test_changed_packaged_art_fails_verification(self):
        package = self.packaged()
        (package / 'card.png').write_bytes(self.png + b'changed')
        with self.assertRaises(ValueError):
            PACK.verify(self.root, package)

    def test_missing_frame_fails_before_installation(self):
        (self.root / 'frame.png').unlink()
        with self.assertRaises(ValueError):
            PACK.runtime_assets(self.root)

    def test_path_escape_is_rejected(self):
        self.manifest['characters'][0]['frames']['idle']['file'] = '../private.png'
        self.write('05_配置与索引/角色记录.json', self.manifest)
        with self.assertRaises(ValueError):
            PACK.runtime_assets(self.root)


if __name__ == '__main__':
    unittest.main()
