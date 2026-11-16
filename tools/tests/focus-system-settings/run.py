import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess


LAUNCH_SERVICES = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def require_hosted_runner():
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted':
        raise SystemExit('System Settings tests run only on disposable GitHub-hosted macOS runners.')
    if os.uname().sysname != 'Darwin':
        raise SystemExit('System Settings tests require macOS.')


def command(arguments, log, check=True, timeout=60):
    with log.open('a') as stream:
        stream.write('Command: ' + repr(arguments) + '\n')
        stream.flush()
        result = subprocess.run(arguments, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    if check and result.returncode:
        print('\n'.join(log.read_text().splitlines()[-70:]))
        raise subprocess.CalledProcessError(result.returncode, arguments)
    return result


def relocate_target(value, original, application):
    if isinstance(value, dict):
        for key, child in value.items():
            value[key] = relocate_target(child, original, application)
    elif isinstance(value, list):
        return [relocate_target(child, original, application) for child in value]
    elif isinstance(value, str):
        return value.replace(str(original), str(application)).replace(
            "__TESTROOT__/Debug/" + original.name, str(application)
        )
    return value


def install_fixture(manifest, output):
    original = Path(manifest['app'])
    destination = Path.home() / 'Applications' / original.name
    destination.parent.mkdir(exist_ok=True)
    if destination.exists():
        raise RuntimeError(f'Refusing to replace an existing fixture: {destination}')
    command([LAUNCH_SERVICES, '-u', str(original)], output / 'registration.log', check=False)
    shutil.move(str(original), destination)
    command([LAUNCH_SERVICES, '-f', str(destination)], output / 'registration.log')
    command(['pluginkit', '-m', '-A', '-D', '-v', '-i', manifest['bundle_id'] + '.FocusIntents'],
            output / 'registration.log', check=False)
    source = Path(manifest['xctestrun'])
    run = plistlib.loads(source.read_bytes())
    relocate_target(run, original, destination)
    target = source.with_name('FocusSystemSettings-installed.xctestrun')
    target.write_bytes(plistlib.dumps(run))
    return destination, target


def collect_diagnostics(output, manifest):
    command(['pluginkit', '-m', '-A', '-D', '-v', '-i', manifest['bundle_id'] + '.FocusIntents'],
            output / 'registration.log', check=False)
    command(['/usr/bin/log', 'show', '--last', '15m', '--style', 'compact', '--predicate',
             'process == "Telegram Focus CI" OR process == "Telegram Focus Filters"'],
            output / 'extension-system.log', check=False)


def main():
    require_hosted_runner()
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    manifest = json.loads((output / 'manifest.json').read_text())
    application, run = install_fixture(manifest, output)
    result = None
    try:
        extension = application / 'Contents/Extensions/FocusIntents.appex'
        info = plistlib.loads((extension / 'Contents/Info.plist').read_bytes())
        command(['xcrun', 'dwarfdump', '--uuid', str(application / 'Contents/MacOS/Telegram Focus CI'),
                 str(extension / 'Contents/MacOS' / info['CFBundleExecutable'])], output / 'installation.log')
        command([str(application / 'Contents/MacOS/Telegram Focus CI'), '--verify-installation'], output / 'installation.log')
        result = command([
            'xcodebuild', 'test-without-building', '-xctestrun', str(run),
            '-destination', 'platform=macOS', '-parallel-testing-enabled', 'NO',
            '-resultBundlePath', str(output / 'SystemSettings.xcresult'),
            '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '120',
            '-maximum-test-execution-time-allowance', '180',
        ], output / 'ui-tests.log', check=False, timeout=900)
    finally:
        try:
            collect_diagnostics(output, manifest)
        except subprocess.TimeoutExpired as error:
            print(f'Diagnostic collection timed out: {error.cmd[0]}')
        command([LAUNCH_SERVICES, '-u', str(application)], output / 'registration.log', check=False)
    print('\n'.join((output / 'ui-tests.log').read_text().splitlines()[-120:]))
    summary = json.loads(subprocess.check_output([
        'xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
        '--path', str(output / 'SystemSettings.xcresult'),
    ], text=True, timeout=30))
    (output / 'test-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    if result is None or result.returncode:
        raise SystemExit(result.returncode if result else 1)
    expected = {'totalTestCount': 3, 'passedTests': 3, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}
    if any(summary.get(key) != value for key, value in expected.items()):
        raise RuntimeError(f'Expected three executed passing UI tests: {summary}')
    print('PASS: all three real System Settings Focus editor integration tests completed.')


if __name__ == '__main__':
    main()
