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
THEME = 'packages/TelegramTheme/Sources/TelegramTheme/TelegramPresentationTheme.swift'
SCENARIOS = ['browse', 'active-owner', 'recent', 'thumbnails', 'revisit', 'live-themes', 'released-themes', 'same-themes', 'close-themes', 'return-to-open']


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
    weak = ''
    if 'private final class WeakWallpaperCachedRecord' in photo:
        weak = block(photo, 'private final class WeakWallpaperCachedRecord').replace('private final class', 'final class', 1)
    mode = block(table, 'public enum TableBackgroundMode')
    metadata = block((ROOT / 'packages/TGUIKit/Sources/Extensions.swift').read_text(), 'public struct SVG_SlotsMetadata')
    decode = block(image, 'public func downsampledImage')
    bitmap = block(image, 'private func decodedBitmapImage')
    return '\n\n'.join(['import Cocoa\nimport ImageIO',
        metadata,
        'public func metadataFixture() -> SVG_SlotsMetadata { SVG_SlotsMetadata(version: 1, imageSize: .init(w: 32, h: 32), scale: 2, offset: .init(x: 0, y: 0), slots: [.init(i: 42, pixel: .init(x: 1, y: 2, w: 3, h: 4))], neatSpot: 0) }',
        'struct PhotoCacheKeyEntry: Hashable { let id: Int }', mode, record, weak, cache, decode, bitmap])


def theme_probe():
    getter = block((ROOT / THEME).read_text(), 'open var backgroundMode: TableBackgroundMode').replace('open var', 'var', 1)
    return '''
enum ProbeWallpaper { case image(Int); case emoticon }
struct ProbeThemeWallpaper { let wallpaper: ProbeWallpaper }
final class WallpaperThemeProbe {
    private let backgroundModeLock = NSLock()
    private var _backgroundMode: TableBackgroundMode?
    let wallpaper: ProbeThemeWallpaper
    let colors = 0
    let backgroundSize = NSSize(width: 1040, height: 1580)
    let emoticonThemes: [Int] = []
    init(_ id: Int) { wallpaper = ProbeThemeWallpaper(wallpaper: .image(id)) }
''' + getter + '\n}\n'


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
    parser.add_argument('--current-ref')
    parser.add_argument('--test-ref')
    parser.add_argument('--scenarios', nargs='+', choices=SCENARIOS, default=SCENARIOS)
    parser.add_argument('--work-dir', type=Path, default=Path(tempfile.gettempdir()) / 'telegram-wallpaper-cache-lab')
    parser.add_argument('--repetitions', type=int, default=5)
    args = parser.parse_args()
    if args.repetitions < 1:
        parser.error('--repetitions must be positive')
    if args.test_ref and args.mode != 'test':
        parser.error('--test-ref applies only to test')
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    table = (ROOT / TABLE).read_text()
    image = (ROOT / IMAGE).read_text()
    baseline = git('rev-parse', args.baseline_ref).strip()
    tested_ref = git('rev-parse', args.test_ref).strip() if args.test_ref else None
    tested_photo = git('show', tested_ref + ':' + PHOTO) if tested_ref else (ROOT / PHOTO).read_text()
    provenance = {'baseline': baseline, 'head': git('rev-parse', 'HEAD').strip(),
                  'baseline_cache_sha256': hashlib.sha256(git('show', baseline + ':' + PHOTO).encode()).hexdigest(),
                  'production_sha256': hashlib.sha256((ROOT / PHOTO).read_bytes()).hexdigest(),
                  'decoder_sha256': hashlib.sha256((ROOT / IMAGE).read_bytes()).hexdigest(),
                  'theme_getter_sha256': hashlib.sha256(block((ROOT / THEME).read_text(), 'open var backgroundMode: TableBackgroundMode').encode()).hexdigest(),
                  'hardware': subprocess.check_output(['sysctl', '-n', 'hw.model', 'hw.memsize', 'hw.ncpu'], text=True).splitlines(),
                  'swift': subprocess.check_output(['swift', '--version'], text=True, stderr=subprocess.STDOUT),
                  'macos': subprocess.check_output(['sw_vers'], text=True)}
    if args.current_ref:
        provenance['current'] = git('rev-parse', args.current_ref).strip()
    if tested_ref:
        provenance['tested_ref'] = tested_ref
        provenance['tested_cache_sha256'] = hashlib.sha256(tested_photo.encode()).hexdigest()
    (work / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    candidate = extract(tested_photo, table, image)
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
    (work / 'Before.swift').write_text(previous + theme_probe())
    (work / 'Candidate.swift').write_text(candidate + theme_probe())
    (work / 'main.swift').write_text((HERE / 'Bench.swift').read_text())
    variants = [('before', 'Before.swift'), ('after', 'Candidate.swift')]
    if args.current_ref:
        current = provenance['current']
        (work / 'Current.swift').write_text(extract(git('show', current + ':' + PHOTO), table, image) + theme_probe())
        variants.insert(1, ('current', 'Current.swift'))
    for name, source in variants:
        run(['swiftc', '-O', str(work / source), str(work / 'main.swift'), '-o', str(work / name)], work / ('compile-' + name + '.log'))
    run([str(work / 'after'), 'fixtures', str(work / 'fixtures')], work / 'fixtures.log')
    verified_hashes = []
    for variant, _ in variants:
        verified_hashes.append(json.loads(run([str(work / variant), 'verify', str(work / 'fixtures')], work / ('pixels-' + variant + '.json')))['render_hashes'])
    if any(hashes != verified_hashes[0] for hashes in verified_hashes):
        raise RuntimeError('Decoded pixel data changed')
    records = []
    render_hashes = {}
    scenarios = args.scenarios
    for repetition in range(args.repetitions):
        for scenario in scenarios:
            order = variants[repetition % len(variants):] + variants[:repetition % len(variants)]
            for variant, _ in order:
                log = work / ('%s-%s-%s.json' % (scenario, variant, repetition))
                record = json.loads(run([str(work / variant), scenario, str(work / 'fixtures')], log))
                expected = render_hashes.setdefault(scenario, record['render_hashes'])
                if record['render_hashes'] != expected:
                    raise RuntimeError('Rendered output changed in ' + scenario)
                record.update(variant=variant, repetition=repetition)
                records.append(record)
                print('%s %s %s: %.1f MiB, %s decodes, %.1f ms' % (repetition, scenario, variant, record['footprint_delta'] / 1048576, record['decodes'], record['decode_ms']))
    summary = []
    for scenario in scenarios:
        for variant, _ in variants:
            samples = [r for r in records if r['scenario'] == scenario and r['variant'] == variant]
            summary.append(dict(scenario=scenario, variant=variant, **{key: statistics.median(r[key] for r in samples) for key in ['footprint_delta', 'retained_bitmap_bytes', 'live_images', 'hits', 'decodes', 'decode_ms', 'cache_ms', 'request_ms', 'warm_request_p50_ms', 'warm_request_p95_ms', 'live_after_clear', 'live_after_owners_close', 'live_after_themes_close', 'bitmap_bytes_after_themes_close', 'footprint_after_themes_close_delta', 'footprint_after_clear_delta']}))
    method = {'repetitions': args.repetitions, 'rotating_order': True, 'fresh_process_each_run': True,
              'fixture': '20 deterministic JPEGs, 2080x3160 pixels, quality 0.85',
              'decode': 'production downsampledImage, maxPixelSize 3160 or 132 for thumbnails',
              'footprint': 'TASK_VM_INFO.phys_footprint after minus before workload',
              'byte_cost': 'selected CGImage.bytesPerRow * height',
              'theme_scenarios': 'extracted production backgroundMode getter, fixture resource/palette adapters',
              'warm_requests': 'after first 12 requests, first 2 for recent/same-themes, first 20 for thumbnails, first 13 for return-to-open',
              'timing': 'synchronous background retrieval only; excludes offscreen hashing and full UI work', 'cache_budget_bytes': 67108864,
              'budget_is_advisory': True, 'full_app_memory_measurement': False}
    for record in records:
        hashes = record.pop('render_hashes')
        record['render_hashes_digest'] = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
    (work / 'summary.json').write_text(json.dumps({'provenance': provenance, 'pixel_equivalence_count': len(verified_hashes[0]), 'medians': summary, 'method': method}, indent=2) + '\n')
    (work / 'runs.jsonl').write_text(''.join(json.dumps(record, sort_keys=True) + '\n' for record in records))
    (work / 'pixels.json').write_text(json.dumps({'equal': True, 'before_after_bitmap_sha256': verified_hashes[0]}, indent=2) + '\n')


if __name__ == '__main__':
    main()
