import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as XML


GROUP = 'group.org.telegram.FocusSettingsCI'
HOST_IDENTIFIER = 'org.telegram.FocusSettingsCI'
HOST_NAME = 'Telegram Focus CI'
SCHEME = 'FocusSystemSettings'


def load_extension_builder(root):
    path = root / 'tools/tests/focus-filters/build_extension.py'
    spec = importlib.util.spec_from_file_location('focus_extension_builder', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_plist(path, contents):
    path.write_bytes(plistlib.dumps(contents))
    return str(path)


def add_object(objects, suffix, contents):
    key = 'F0C05100000000000000' + suffix
    if key in objects:
        raise ValueError(f'Duplicate fixture object: {key}')
    objects[key] = contents
    return key


def add_configuration(objects, suffix, settings):
    configuration = add_object(objects, suffix + '1', {
        'isa': 'XCBuildConfiguration', 'name': 'Debug', 'buildSettings': settings,
    })
    return add_object(objects, suffix + '2', {
        'isa': 'XCConfigurationList', 'buildConfigurations': [configuration],
        'defaultConfigurationIsVisible': '0', 'defaultConfigurationName': 'Debug',
    })


def add_source_phase(objects, suffix, path):
    source = add_object(objects, suffix + '1', {
        'isa': 'PBXFileReference', 'lastKnownFileType': 'sourcecode.swift',
        'path': str(path), 'sourceTree': '<absolute>',
    })
    build_file = add_object(objects, suffix + '2', {'isa': 'PBXBuildFile', 'fileRef': source})
    return add_object(objects, suffix + '3', {
        'isa': 'PBXSourcesBuildPhase', 'buildActionMask': '2147483647',
        'files': [build_file], 'runOnlyForDeploymentPostprocessing': '0',
    })


def add_dependency(objects, suffix, target):
    return add_object(objects, suffix, {'isa': 'PBXTargetDependency', 'target': target})


def signed_settings(identifier, name, info):
    return {
        'PRODUCT_BUNDLE_IDENTIFIER': identifier, 'PRODUCT_NAME': name,
        'INFOPLIST_FILE': info, 'CODE_SIGN_STYLE': 'Manual', 'CODE_SIGN_IDENTITY': '-',
        'CODE_SIGNING_ALLOWED': 'YES', 'DEVELOPMENT_TEAM': '',
        'MACOSX_DEPLOYMENT_TARGET': '13.0', 'SDKROOT': 'macosx',
        'SWIFT_VERSION': '5.0', 'ONLY_ACTIVE_ARCH': 'YES',
        'GENERATE_INFOPLIST_FILE': 'NO', 'ENABLE_HARDENED_RUNTIME': 'NO',
    }


def configure_extension(objects, target, output):
    entitlements = write_plist(output / 'Extension.entitlements', {
        'com.apple.security.app-sandbox': True,
        'com.apple.security.application-groups': [GROUP],
    })
    for key in objects[target['buildConfigurationList']]['buildConfigurations']:
        settings = objects[key]['buildSettings']
        settings.update({
            'PRODUCT_BUNDLE_IDENTIFIER': HOST_IDENTIFIER + '.FocusIntents',
            'FOCUS_APP_GROUP': GROUP, 'CODE_SIGN_ENTITLEMENTS': entitlements,
            'CODE_SIGN_STYLE': 'Manual', 'CODE_SIGN_IDENTITY': '-',
            'CODE_SIGNING_ALLOWED': 'YES', 'DEVELOPMENT_TEAM': '',
        })


def add_host(objects, extension_id, extension, fixtures, output):
    info = write_plist(output / 'Host-Info.plist', {
        'CFBundleIdentifier': HOST_IDENTIFIER, 'CFBundleExecutable': HOST_NAME,
        'CFBundleName': HOST_NAME, 'CFBundleDisplayName': HOST_NAME,
        'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
        'CFBundlePackageType': 'APPL', 'NSPrincipalClass': 'NSApplication',
        'LSMinimumSystemVersion': '13.0', 'NSHighResolutionCapable': True,
        'FocusAppGroup': GROUP, 'SOURCE': 'DEBUG',
    })
    entitlements = write_plist(output / 'Host.entitlements', {'com.apple.security.application-groups': [GROUP]})
    settings = signed_settings(HOST_IDENTIFIER, HOST_NAME, info)
    settings.update({'CODE_SIGN_ENTITLEMENTS': entitlements, 'PRODUCT_MODULE_NAME': 'FocusSettingsHost'})
    configurations = add_configuration(objects, '101', settings)
    sources = add_source_phase(objects, '102', fixtures / 'Host.swift')
    frameworks = []
    for index, dependency in enumerate(extension['packageProductDependencies']):
        frameworks.append(add_object(objects, f'103{index}', {'isa': 'PBXBuildFile', 'productRef': dependency}))
    framework_phase = add_object(objects, '1040', {
        'isa': 'PBXFrameworksBuildPhase', 'buildActionMask': '2147483647',
        'files': frameworks, 'runOnlyForDeploymentPostprocessing': '0',
    })
    embedded = add_object(objects, '1050', {
        'isa': 'PBXBuildFile', 'fileRef': extension['productReference'],
        'settings': {'ATTRIBUTES': ['CodeSignOnCopy', 'RemoveHeadersOnCopy']},
    })
    embedding = add_object(objects, '1060', {
        'isa': 'PBXCopyFilesBuildPhase', 'buildActionMask': '2147483647',
        'dstPath': '$(EXTENSIONS_FOLDER_PATH)', 'dstSubfolderSpec': '16',
        'name': 'Embed Focus Extension', 'files': [embedded], 'runOnlyForDeploymentPostprocessing': '0',
    })
    product = add_object(objects, '1070', {
        'isa': 'PBXFileReference', 'explicitFileType': 'wrapper.application',
        'path': HOST_NAME + '.app', 'sourceTree': 'BUILT_PRODUCTS_DIR',
    })
    dependency = add_dependency(objects, '1080', extension_id)
    return add_object(objects, '1090', {
        'isa': 'PBXNativeTarget', 'name': 'FocusSettingsHost', 'productName': HOST_NAME,
        'productType': 'com.apple.product-type.application', 'productReference': product,
        'buildConfigurationList': configurations, 'buildPhases': [sources, framework_phase, embedding],
        'buildRules': [], 'dependencies': [dependency],
        'packageProductDependencies': extension['packageProductDependencies'],
    })


def add_ui_tests(objects, host_id, fixtures, output):
    info = write_plist(output / 'Tests-Info.plist', {
        'CFBundleIdentifier': HOST_IDENTIFIER + '.UITests',
        'CFBundleExecutable': 'FocusSystemSettingsTests', 'CFBundleName': 'FocusSystemSettingsTests',
        'CFBundleVersion': '1', 'CFBundlePackageType': 'BNDL',
    })
    settings = signed_settings(HOST_IDENTIFIER + '.UITests', 'FocusSystemSettingsTests', info)
    settings.update({
        'TEST_TARGET_NAME': 'FocusSettingsHost', 'ENABLE_APP_SANDBOX': 'NO',
        'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/../Frameworks', '@loader_path/../Frameworks'],
    })
    configurations = add_configuration(objects, '201', settings)
    sources = add_source_phase(objects, '202', fixtures / 'SystemSettingsTests.swift')
    product = add_object(objects, '2030', {
        'isa': 'PBXFileReference', 'explicitFileType': 'wrapper.cfbundle',
        'path': 'FocusSystemSettingsTests.xctest', 'sourceTree': 'BUILT_PRODUCTS_DIR',
    })
    dependency = add_dependency(objects, '2040', host_id)
    return add_object(objects, '2050', {
        'isa': 'PBXNativeTarget', 'name': 'FocusSystemSettingsTests', 'productName': 'FocusSystemSettingsTests',
        'productType': 'com.apple.product-type.bundle.ui-testing', 'productReference': product,
        'buildConfigurationList': configurations, 'buildPhases': [sources], 'buildRules': [],
        'dependencies': [dependency],
    })


def buildable(parent, target_id, name, product):
    return XML.SubElement(parent, 'BuildableReference', {
        'BuildableIdentifier': 'primary', 'BlueprintIdentifier': target_id,
        'BuildableName': product, 'BlueprintName': name,
        'ReferencedContainer': 'container:FocusSystemSettings.xcodeproj',
    })


def write_scheme(project, host_id, tests_id):
    scheme = XML.Element('Scheme', {'LastUpgradeVersion': '1600', 'version': '1.3'})
    build = XML.SubElement(scheme, 'BuildAction', {'parallelizeBuildables': 'YES', 'buildImplicitDependencies': 'YES'})
    entries = XML.SubElement(build, 'BuildActionEntries')
    for identifier, name, product in [
        (host_id, 'FocusSettingsHost', HOST_NAME + '.app'),
        (tests_id, 'FocusSystemSettingsTests', 'FocusSystemSettingsTests.xctest'),
    ]:
        entry = XML.SubElement(entries, 'BuildActionEntry', {
            'buildForTesting': 'YES', 'buildForRunning': 'NO', 'buildForProfiling': 'NO',
            'buildForArchiving': 'NO', 'buildForAnalyzing': 'YES',
        })
        buildable(entry, identifier, name, product)
    test = XML.SubElement(scheme, 'TestAction', {
        'buildConfiguration': 'Debug', 'selectedDebuggerIdentifier': 'Xcode.DebuggerFoundation.Debugger.LLDB',
        'selectedLauncherIdentifier': 'Xcode.IDEFoundation.Launcher.LLDB', 'shouldUseLaunchSchemeArgsEnv': 'YES',
        'language': 'en', 'region': 'US',
    })
    environment = XML.SubElement(test, 'EnvironmentVariables')
    XML.SubElement(environment, 'EnvironmentVariable', {'key': 'FOCUS_SETTINGS_CI', 'value': '1', 'isEnabled': 'YES'})
    testable = XML.SubElement(XML.SubElement(test, 'Testables'), 'TestableReference', {'skipped': 'NO'})
    buildable(testable, tests_id, 'FocusSystemSettingsTests', 'FocusSystemSettingsTests.xctest')
    path = project / 'xcshareddata/xcschemes' / (SCHEME + '.xcscheme')
    path.parent.mkdir(parents=True, exist_ok=True)
    XML.indent(scheme)
    XML.ElementTree(scheme).write(path, encoding='utf-8', xml_declaration=True)


def create_project(root, output):
    builder = load_extension_builder(root)
    project = builder.extract_extension_project(builder.read_production_project(root), root)
    objects = project['objects']
    project_object = objects[project['rootObject']]
    extension_id, extension = builder.find_extension_target(objects)
    configure_extension(objects, extension, output)
    fixtures = root / 'tools/tests/focus-system-settings'
    host_id = add_host(objects, extension_id, extension, fixtures, output)
    tests_id = add_ui_tests(objects, host_id, fixtures, output)
    project_object['targets'].extend([host_id, tests_id])
    project_object['attributes']['TargetAttributes'] = {tests_id: {'TestTargetID': host_id}}
    path = output / 'FocusSystemSettings.xcodeproj'
    path.mkdir(exist_ok=True)
    (path / 'project.pbxproj').write_text(builder.openstep(project))
    write_scheme(path, host_id, tests_id)
    return path


def build(project, output):
    log = output / 'build.log'
    with log.open('w') as stream:
        result = subprocess.run([
            'xcodebuild', '-project', str(project), '-scheme', SCHEME, '-configuration', 'Debug',
            '-destination', 'platform=macOS', '-derivedDataPath', str(output / 'DerivedData'),
            '-packageCachePath', str(output / 'PackageCache'),
            'build-for-testing',
        ], stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        print('\n'.join(log.read_text().splitlines()[-100:]))
        raise SystemExit(result.returncode)
    products = output / 'DerivedData/Build/Products'
    runs = list(products.glob('*.xctestrun'))
    if len(runs) != 1:
        raise RuntimeError(f'Expected one test run description, found {runs}')
    app = products / 'Debug' / (HOST_NAME + '.app')
    extension = app / 'Contents/Extensions/FocusIntents.appex'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    load_extension_builder(Path(__file__).resolve().parents[3]).validate_intent_metadata(extension)
    manifest = {'project': str(project), 'scheme': SCHEME, 'app': str(app), 'extension': str(extension),
                'xctestrun': str(runs[0]), 'bundle_id': HOST_IDENTIFIER, 'app_group': GROUP}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[3]
    build(create_project(root, output), output)


if __name__ == '__main__':
    main()
