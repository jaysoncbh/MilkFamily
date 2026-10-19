#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Derive minimal runtime records without changing the project's art or provenance."""
import argparse
import hashlib
import json
import shutil
import struct
from pathlib import Path, PurePosixPath


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def subset(value, keys):
    return {key: value[key] for key in keys.split() if key in value}


def runtime_assets(root):
    root = root.resolve()
    resources = {}
    stats = {'characters': 0, 'staticActions': 0, 'cards': 0, 'animations': 0, 'frames': 0}

    def add(relative, data=None, size=None, expected_hash=None):
        path = PurePosixPath(relative)
        if path.is_absolute() or '..' in path.parts:
            raise ValueError('Invalid resource path: ' + relative)
        source = root / relative
        if data is None:
            if not source.is_file() or not source.resolve().is_relative_to(root):
                raise ValueError('Missing resource: ' + relative)
            if source.suffix == '.png':
                with source.open('rb') as stream:
                    header = stream.read(26)
                if len(header) < 26 or header[:8] != b'\x89PNG\r\n\x1a\n':
                    raise ValueError('Invalid PNG: ' + relative)
                if size and (struct.unpack('>II', header[16:24]) != size or header[25] != 6):
                    raise ValueError('Expected 256 RGBA animation/sprite: ' + relative)
            if expected_hash and hashlib.sha256(source.read_bytes()).hexdigest() != expected_hash:
                raise ValueError('Artwork hash mismatch: ' + relative)
            resources[relative] = source
        else:
            if b'/Users/' in data or b'sourceGeneratedImage' in data or b'usageLedger' in data:
                raise ValueError('Non-runtime metadata in resource: ' + relative)
            resources[relative] = data

    def read(relative):
        return json.loads((root / relative).read_text())

    source = read('05_配置与索引/角色记录.json')
    runtime = {'characters': [], 'cards': []}
    action_ids = set()
    for character in source['characters']:
        value = subset(character, 'id name rarityCode rarity aliases poseOrder')
        value['frames'] = {}
        for pose in character['poseOrder']:
            frame = character['frames'][pose]
            if frame['id'] in action_ids:
                raise ValueError('Duplicate action: ' + frame['id'])
            action_ids.add(frame['id'])
            value['frames'][pose] = subset(frame, 'id name file original cardId cardStyle cardFile animation')
            add(frame['file'], size=(256, 256))
            stats['staticActions'] += 1
            if frame.get('animation'):
                record = read(frame['animation'])
                count = record['frameCount']
                if record['actionId'] != frame['id'] or count < 1 or len(record['frames']) != count or len(record['frameDurationsMs']) != count or not all(16 <= n <= 10000 for n in record['frameDurationsMs']):
                    raise ValueError('Invalid animation: ' + frame['id'])
                animation = subset(record, 'actionId frameCount frameDurationsMs loop')
                animation['frames'] = [{'file': item['file']} for item in record['frames']]
                add(frame['animation'], encoded(animation))
                for item in record['frames']:
                    add(item['file'], size=(256, 256), expected_hash=item.get('gameSHA256'))
                stats['animations'] += 1
                stats['frames'] += count
        runtime['characters'].append(value)
    for card in source['cards']:
        runtime['cards'].append(subset(card, 'id characterId actionId actionName name rarity style file gamePoolOpen'))
        add(card['file'])
    stats['characters'] = len(runtime['characters'])
    stats['cards'] = len(runtime['cards'])
    add('05_配置与索引/角色记录.json', encoded(runtime))
    add('07_软件开发/macOS/02_配置/正式版规则.json')
    items = read('05_配置与索引/道具素材记录.json')
    minimal_items = []
    for item in items['items']:
        entry = subset(item, 'id name')
        entry['game'] = {'file': item['game']['file']}
        minimal_items.append(entry)
        add(item['game']['file'])
    add('05_配置与索引/道具素材记录.json', encoded({'items': minimal_items}))
    motion_path = '05_配置与索引/卡片动态记录.json'
    if (root / motion_path).exists():
        motion_cards = []
        for card in read(motion_path)['cards']:
            motion_cards.append(subset(card, 'cardId style config resources'))
            # Effect configs contain only rendering parameters and relative mask paths.
            add(card['config'], encoded(read(card['config'])))
            for item in card['resources']:
                if item['file'] != card['config']:
                    add(item['file'])
        add(motion_path, encoded({'cards': motion_cards}))
    inventory = []
    for relative, value in sorted(resources.items()):
        data = value if isinstance(value, bytes) else value.read_bytes()
        inventory.append({'file': relative, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    add('运行资源清单.json', encoded({'version': 1, **stats, 'files': inventory}))
    return resources, stats


def verify(root, destination):
    expected, stats = runtime_assets(root)
    actual = {p.relative_to(destination).as_posix() for p in destination.rglob('*') if p.is_file()}
    if actual != set(expected):
        raise ValueError('Runtime inventory mismatch: ' + str(actual.symmetric_difference(expected)))
    for relative, value in expected.items():
        data = value if isinstance(value, bytes) else value.read_bytes()
        if (destination / relative).read_bytes() != data:
            raise ValueError('Packaged bytes differ: ' + relative)
    return {'result': 'pass', **stats, 'bundledFiles': len(expected), 'runtimeMetadataSanitized': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.verify:
        print(json.dumps(verify(args.root, args.verify), ensure_ascii=False))
    else:
        assets, stats = runtime_assets(args.root)
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            for relative, value in assets.items():
                target = args.output / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if isinstance(value, bytes):
                    target.write_bytes(value)
                else:
                    shutil.copyfile(value, target)
        print(json.dumps({'result': 'pass', **stats, 'bundledFiles': len(assets)}, ensure_ascii=False))
