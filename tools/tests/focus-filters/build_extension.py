import argparse
import copy
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--configuration", choices=["Debug", "Release"], default="Debug")
    return parser.parse_args()


def prepare_output(requested_output):
    output = requested_output.resolve() if requested_output else Path(tempfile.mkdtemp(prefix="telegram-focus-build-"))
    output.mkdir(parents=True, exist_ok=True)
    return output


def read_production_project(root):
    return json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", str(root / "Telegram.xcodeproj/project.pbxproj")
    ]))


def find_extension_target(objects):
    return next((key, value) for key, value in objects.items()
                if value.get("isa") == "PBXNativeTarget" and value.get("name") == "FocusIntents")


def validate_production_target(objects, target_id, target):
    assert target["productType"] == "com.apple.product-type.extensionkit-extension"
    host = next(value for value in objects.values()
                if value.get("isa") == "PBXNativeTarget" and value.get("name") == "Telegram")
    assert any(objects[item]["target"] == target_id for item in host["dependencies"])
    embedding = [objects[item] for item in host["buildPhases"]
                 if objects[item]["isa"] == "PBXCopyFilesBuildPhase"
                 and objects[item].get("dstPath") == "$(EXTENSIONS_FOLDER_PATH)"]
    assert any(objects[item]["fileRef"] == target["productReference"]
               for phase in embedding for item in phase["files"])


def locate_source_paths(objects, main_group, root):
    paths = {}

    def locate(key, parent):
        obj = objects[key]
        tree = obj.get("sourceTree", "<group>")
        if tree == "BUILT_PRODUCTS_DIR":
            return
        base = root if tree == "SOURCE_ROOT" else parent
        path = base / obj.get("path", "")
        paths[key] = path
        if obj["isa"] in {"PBXGroup", "PBXVariantGroup"}:
            for child in obj.get("children", []):
                locate(child, parent if obj["isa"] == "PBXVariantGroup" else path)

    locate(main_group, root)
    return paths


def extract_reachable_objects(objects, target_id):
    selected = {}

    def include(value):
        if isinstance(value, str) and value in objects and value not in selected:
            selected[value] = copy.deepcopy(objects[value])
            include(selected[value])
        elif isinstance(value, dict):
            for item in value.values():
                include(item)
        elif isinstance(value, list):
            for item in value:
                include(item)

    include(target_id)
    return selected


def resolve_build_paths(selected, paths, root):
    for key, obj in selected.items():
        if obj["isa"] == "PBXFileReference" and obj.get("sourceTree") != "BUILT_PRODUCTS_DIR":
            obj["path"] = str(paths[key])
            obj["sourceTree"] = "<absolute>"
        if obj["isa"] == "XCLocalSwiftPackageReference":
            obj["relativePath"] = str(root / obj["relativePath"])
        if obj["isa"] == "XCBuildConfiguration":
            for setting in ["INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS"]:
                if setting in obj.get("buildSettings", {}):
                    obj["buildSettings"][setting] = str(root / obj["buildSettings"][setting])


def make_fixture_project(selected, target_id):
    project_id = "F0C050FFFFFFFFFFFFFFFF01"
    group_id = "F0C050FFFFFFFFFFFFFFFF02"
    config_id = "F0C050FFFFFFFFFFFFFFFF03"
    debug_id = "F0C050FFFFFFFFFFFFFFFF04"
    release_id = "F0C050FFFFFFFFFFFFFFFF05"
    selected[group_id] = {"isa": "PBXGroup", "children": [], "sourceTree": "<group>"}
    selected[config_id] = {"isa": "XCConfigurationList", "buildConfigurations": [debug_id, release_id],
                           "defaultConfigurationIsVisible": "0", "defaultConfigurationName": "Debug"}
    for key, name in [(debug_id, "Debug"), (release_id, "Release")]:
        selected[key] = {"isa": "XCBuildConfiguration", "name": name,
                         "buildSettings": {"MACOSX_DEPLOYMENT_TARGET": "13.0", "SDKROOT": "macosx"}}
    selected[project_id] = {
        "isa": "PBXProject", "attributes": {}, "buildConfigurationList": config_id,
        "compatibilityVersion": "Xcode 14.0", "developmentRegion": "en", "hasScannedForEncodings": "0",
        "knownRegions": ["en", "ru"], "mainGroup": group_id,
        "packageReferences": [key for key, value in selected.items()
                              if value["isa"] == "XCLocalSwiftPackageReference"],
        "projectDirPath": "", "projectRoot": "", "targets": [target_id]
    }
    return {"archiveVersion": "1", "classes": {}, "objectVersion": "56",
            "objects": selected, "rootObject": project_id}


def extract_extension_project(project, root):
    objects = project["objects"]
    production_project = objects[project["rootObject"]]
    target_id, target = find_extension_target(objects)
    validate_production_target(objects, target_id, target)
    paths = locate_source_paths(objects, production_project["mainGroup"], root)
    selected = extract_reachable_objects(objects, target_id)
    resolve_build_paths(selected, paths, root)
    return make_fixture_project(selected, target_id)


def openstep(value):
    if isinstance(value, dict):
        return "{\n" + "".join(json.dumps(key) + " = " + openstep(item) + ";\n" for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "(" + ",".join(openstep(item) for item in value) + ",)" if value else "()"
    return json.dumps(str(value), ensure_ascii=False)


def write_fixture_project(project, root, output):
    fixture = output / "FocusFilterBuild.xcodeproj"
    fixture.mkdir(exist_ok=True)
    (fixture / "project.pbxproj").write_text(openstep(project))
    scheme = root / "Telegram.xcodeproj/xcshareddata/xcschemes/FocusIntents.xcscheme"
    schemes = fixture / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / scheme.name).write_text(scheme.read_text().replace(
        "container:Telegram.xcodeproj", "container:FocusFilterBuild.xcodeproj"
    ))
    return fixture


def build_extension(fixture, output, configuration):
    log = output / (configuration.lower() + ".log")
    with log.open("w") as stream:
        result = subprocess.run([
            "xcodebuild", "-project", str(fixture), "-scheme", "FocusIntents", "-configuration", configuration,
            "-derivedDataPath", str(output / "DerivedData"), "CODE_SIGNING_ALLOWED=NO", "build"
        ], stdout=stream, stderr=subprocess.STDOUT)
    print(f"Build log: {log}")
    if result.returncode:
        print("\n".join(log.read_text().splitlines()[-60:]))
        raise SystemExit(result.returncode)
    return output / "DerivedData/Build/Products" / configuration / "FocusIntents.appex"


def validate_extension_info(product, configuration):
    with (product / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    assert info["EXAppExtensionAttributes"]["EXExtensionPointIdentifier"] == "com.apple.appintents-extension"
    assert info["FocusAppGroup"] == "6N38VWS5BX.ru.keepcoder.Telegram"
    assert info["SOURCE"] == ("DEBUG" if configuration == "Debug" else "STABLE")


def validate_intent_metadata(product):
    metadata = product / "Contents/Resources/Metadata.appintents/extract.actionsdata"
    assert metadata.exists(), "App Intents metadata was not extracted"
    actions = json.loads(metadata.read_bytes())
    action = actions["actions"]["TelegramFocusFilter"]
    assert "com.apple.link.systemProtocol.FocusConfiguration" in action["systemProtocols"]
    parameters = {parameter["name"]: parameter for parameter in action["parameters"]}
    assert set(parameters) == {"accounts", "effect", "mode", "folders", "chats"}
    for parameter in ["accounts", "folders", "chats"]:
        collection = parameters[parameter]["valueType"]["array"]["wrapper"]
        assert collection["capabilities"] == 0, f"{parameter} must use Set semantics without duplicates or ordering"
        assert collection["memberValueType"]["entity"]["wrapper"]["typeName"] == {
            "accounts": "FocusAccountEntity", "folders": "FocusFolderEntity", "chats": "FocusChatEntity"
        }[parameter]


def validate_localizations(product):
    for language in ["en", "ru"]:
        assert (product / "Contents/Resources" / (language + ".lproj") / "Localizable.strings").exists()


def validate_release_architectures(product):
    architectures = subprocess.check_output([
        "lipo", "-archs", str(product / "Contents/MacOS/FocusIntents")
    ], text=True).split()
    assert set(architectures) == {"arm64", "x86_64"}


def validate_extension(product, configuration):
    validate_extension_info(product, configuration)
    validate_intent_metadata(product)
    validate_localizations(product)
    if configuration == "Release":
        validate_release_architectures(product)


def main():
    args = parse_arguments()
    root = Path(__file__).resolve().parents[3]
    output = prepare_output(args.output)
    project = extract_extension_project(read_production_project(root), root)
    fixture = write_fixture_project(project, root, output)
    product = build_extension(fixture, output, args.configuration)
    validate_extension(product, args.configuration)
    print(f"PASS: {args.configuration} extension and App Intents metadata: {product}")


if __name__ == "__main__":
    main()
