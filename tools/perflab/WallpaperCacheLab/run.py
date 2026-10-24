#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PHOTO = 'packages/TelegramTheme/Sources/TelegramTheme/PhotoCache.swift'
TABLE = 'packages/TGUIKit/Sources/TableView.swift'
IMAGE = 'packages/TGUIKit/Sources/Image.swift'


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True)


def extract(photo, table, image):
    record = block(photo, 'private final class WallpaperCachedRecord').replace('private final class', 'final class', 1)
    cache = block(photo, 'private class WallpaperCache').replace('private class', 'final class', 1).replace('fileprivate func', 'func')
    mode = block(table, 'public enum TableBackgroundMode')
    decode = block(image, 'public func downsampledImage')
    bitmap = block(image, 'private func decodedBitmapImage')
    return '\n\n'.join(['import Cocoa\nimport ImageIO',
        'public struct SVG_SlotsMetadata: Equatable { public let fixture: Int }',
        'struct PhotoCacheKeyEntry: Hashable { let id: Int }', mode, record, cache, decode, bitmap])


def run(command, log):
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log.write_text(completed.stdout)
    if completed.returncode:
        raise RuntimeError(str(command) + '\n' + completed.stdout[-8000:])
    return completed.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['test', 'bench'])
    parser.add_argument('--baseline-ref', default='origin/master')
    parser.add_argument('--work-dir', type=Path, default=Path(tempfile.gettempdir()) / 'telegram-wallpaper-cache-lab')
    parser.add_argument('--repetitions', type=int, default=5)
    args = parser.parse_args()
    if args.repetitions < 1:
        parser.error('--repetitions must be positive')
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    table = (ROOT / TABLE).read_text()
    image = (ROOT / IMAGE).read_text()
    baseline = git('rev-parse', args.baseline_ref).strip()
    provenance = {'baseline': baseline, 'head': git('rev-parse', 'HEAD').strip(),
                  'baseline_cache_sha256': hashlib.sha256(git('show', baseline + ':' + PHOTO).encode()).hexdigest(),
                  'production_sha256': hashlib.sha256((ROOT / PHOTO).read_bytes()).hexdigest(),
                  'decoder_sha256': hashlib.sha256((ROOT / IMAGE).read_bytes()).hexdigest(),
                  'hardware': subprocess.check_output(['sysctl', '-n', 'hw.model', 'hw.memsize', 'hw.ncpu'], text=True).splitlines(),
                  'swift': subprocess.check_output(['swift', '--version'], text=True, stderr=subprocess.STDOUT),
                  'macos': subprocess.check_output(['sw_vers'], text=True)}
    (work / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    candidate = extract((ROOT / PHOTO).read_text(), table, image)
    (work / 'Candidate.swift').write_text(candidate)
    if args.mode == 'test':
        package = work / 'tests'
        (package / 'Sources/Production').mkdir(parents=True, exist_ok=True)
        (package / 'Tests/WallpaperCacheTests').mkdir(parents=True, exist_ok=True)
        (package / 'Package.swift').write_text('// swift-tools-version:5.5\nimport PackageDescription\nlet package = Package(name: "WallpaperCacheLab", platforms: [.macOS(.v12)], targets: [.target(name: "Production"), .testTarget(name: "WallpaperCacheTests", dependencies: ["Production"])])\n')
        (package / 'Sources/Production/Cache.swift').write_text(candidate)
        (package / 'Tests/WallpaperCacheTests/Tests.swift').write_text('@testable import Production\n' + (HERE / 'Tests.swift').read_text())
        for name in ['debug', 'release']:
            output = run(['swift', 'test', '--disable-sandbox', '--package-path', str(package),
                          '--scratch-path', str(work / 'test-build'), '-c', name], work / ('tests-' + name + '.log'))
            print(output[-900:])
        return
    previous = extract(git('show', baseline + ':' + PHOTO), table, image)
    (work / 'Before.swift').write_text(previous)
    (work / 'main.swift').write_text((HERE / 'Bench.swift').read_text())
    for name, source in [('before', 'Before.swift'), ('after', 'Candidate.swift')]:
        run(['swiftc', '-O', str(work / source), str(work / 'main.swift'), '-o', str(work / name)], work / ('compile-' + name + '.log'))
    run([str(work / 'after'), 'fixtures', str(work / 'fixtures')], work / 'fixtures.log')
    verified_hashes = []
    for variant in ['before', 'after']:
        verified_hashes.append(json.loads(run([str(work / variant), 'verify', str(work / 'fixtures')], work / ('pixels-' + variant + '.json')))['render_hashes'])
    if verified_hashes[0] != verified_hashes[1]:
        raise RuntimeError('Decoded pixel data changed')
    records = []
    render_hashes = {}
    for repetition in range(args.repetitions):
        for scenario in ['browse', 'active-owner', 'recent', 'thumbnails', 'revisit']:
            for variant in (['before', 'after'] if repetition % 2 == 0 else ['after', 'before']):
                log = work / ('%s-%s-%s.json' % (scenario, variant, repetition))
                record = json.loads(run([str(work / variant), scenario, str(work / 'fixtures')], log))
                expected = render_hashes.setdefault(scenario, record['render_hashes'])
                if record['render_hashes'] != expected:
                    raise RuntimeError('Rendered output changed in ' + scenario)
                record.update(variant=variant, repetition=repetition)
                records.append(record)
                print('%s %s %s: %.1f MiB, %s decodes, %.1f ms' % (repetition, scenario, variant, record['footprint_delta'] / 1048576, record['decodes'], record['decode_ms']))
    summary = []
    for scenario in ['browse', 'active-owner', 'recent', 'thumbnails', 'revisit']:
        for variant in ['before', 'after']:
            samples = [r for r in records if r['scenario'] == scenario and r['variant'] == variant]
            summary.append(dict(scenario=scenario, variant=variant, **{key: statistics.median(r[key] for r in samples) for key in ['footprint_delta', 'retained_bitmap_bytes', 'live_images', 'hits', 'decodes', 'decode_ms', 'cache_ms', 'live_after_clear', 'footprint_after_clear_delta']}))
    method = {'repetitions': args.repetitions, 'alternating_order': True, 'fresh_process_each_run': True,
              'fixture': '20 deterministic JPEGs, 2080x3160 pixels, quality 0.85',
              'decode': 'production downsampledImage, maxPixelSize 3160 or 132 for thumbnails',
              'footprint': 'TASK_VM_INFO.phys_footprint after minus before workload',
              'byte_cost': 'selected CGImage.bytesPerRow * height', 'cache_budget_bytes': 67108864,
              'budget_is_advisory': True, 'full_app_memory_measurement': False}
    for record in records:
        hashes = record.pop('render_hashes')
        record['render_hashes_digest'] = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
    (work / 'summary.json').write_text(json.dumps({'provenance': provenance, 'pixel_equivalence_count': len(verified_hashes[0]), 'medians': summary, 'method': method}, indent=2) + '\n')
    (work / 'runs.jsonl').write_text(''.join(json.dumps(record, sort_keys=True) + '\n' for record in records))
    (work / 'pixels.json').write_text(json.dumps({'equal': True, 'before_after_bitmap_sha256': verified_hashes[0]}, indent=2) + '\n')


if __name__ == '__main__':
    main()
