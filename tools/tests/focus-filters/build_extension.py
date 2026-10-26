import argparse
import copy
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path)
parser.add_argument("--configuration", choices=["Debug", "Release"], default="Debug")
args = parser.parse_args()
output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="telegram-focus-build-"))
output.mkdir(parents=True, exist_ok=True)
project = json.loads(subprocess.check_output([
    "plutil", "-convert", "json", "-o", "-", str(root / "Telegram.xcodeproj/project.pbxproj")
]))
objects = project["objects"]
production_project = objects[project["rootObject"]]
target_id, target = next((key, value) for key, value in objects.items()
                         if value.get("isa") == "PBXNativeTarget" and value.get("name") == "FocusIntents")
assert target["productType"] == "com.apple.product-type.extensionkit-extension"
host = next(value for value in objects.values() if value.get("isa") == "PBXNativeTarget" and value.get("name") == "Telegram")
assert any(objects[item]["target"] == target_id for item in host["dependencies"])
embedding = [objects[item] for item in host["buildPhases"]
             if objects[item]["isa"] == "PBXCopyFilesBuildPhase" and objects[item].get("dstPath") == "$(EXTENSIONS_FOLDER_PATH)"]
assert any(objects[item]["fileRef"] == target["productReference"] for phase in embedding for item in phase["files"])

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


locate(production_project["mainGroup"], root)
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
selected[project_id] = {"isa": "PBXProject", "attributes": {}, "buildConfigurationList": config_id,
                        "compatibilityVersion": "Xcode 14.0", "developmentRegion": "en", "hasScannedForEncodings": "0",
                        "knownRegions": ["en", "ru"], "mainGroup": group_id,
                        "packageReferences": [key for key, value in selected.items() if value["isa"] == "XCLocalSwiftPackageReference"],
                        "projectDirPath": "", "projectRoot": "", "targets": [target_id]}


def openstep(value):
    if isinstance(value, dict):
        return "{\n" + "".join(json.dumps(key) + " = " + openstep(item) + ";\n" for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "(" + ",".join(openstep(item) for item in value) + ",)" if value else "()"
    return json.dumps(str(value), ensure_ascii=False)


fixture = output / "FocusFilterBuild.xcodeproj"
fixture.mkdir(exist_ok=True)
(fixture / "project.pbxproj").write_text(openstep({"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": selected, "rootObject": project_id}))
scheme = root / "Telegram.xcodeproj/xcshareddata/xcschemes/FocusIntents.xcscheme"
schemes = fixture / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / scheme.name).write_text(scheme.read_text().replace("container:Telegram.xcodeproj", "container:FocusFilterBuild.xcodeproj"))
log = output / (args.configuration.lower() + ".log")
with log.open("w") as stream:
    result = subprocess.run([
        "xcodebuild", "-project", str(fixture), "-scheme", "FocusIntents", "-configuration", args.configuration,
        "-derivedDataPath", str(output / "DerivedData"), "CODE_SIGNING_ALLOWED=NO", "build"
    ], stdout=stream, stderr=subprocess.STDOUT)
print(f"Build log: {log}")
if result.returncode:
    print("\n".join(log.read_text().splitlines()[-60:]))
    raise SystemExit(result.returncode)
product = output / "DerivedData/Build/Products" / args.configuration / "FocusIntents.appex"
with (product / "Contents/Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
assert info["EXAppExtensionAttributes"]["EXExtensionPointIdentifier"] == "com.apple.appintents-extension"
assert info["FocusAppGroup"] == "6N38VWS5BX.ru.keepcoder.Telegram"
assert info["SOURCE"] == ("DEBUG" if args.configuration == "Debug" else "STABLE")
metadata = product / "Contents/Resources/Metadata.appintents/extract.actionsdata"
assert metadata.exists(), "App Intents metadata was not extracted"
actions = json.loads(metadata.read_bytes())
action = actions["actions"]["TelegramFocusFilter"]
assert "com.apple.link.systemProtocol.FocusConfiguration" in action["systemProtocols"]
parameters = {parameter["name"]: parameter for parameter in action["parameters"]}
assert set(parameters) == {"accounts", "effect", "mode", "folders", "chats"}
for parameter in ["accounts", "folders", "chats"]:
    assert "array" in parameters[parameter]["valueType"]
for language in ["en", "ru"]:
    assert (product / "Contents/Resources" / (language + ".lproj") / "Localizable.strings").exists()
if args.configuration == "Release":
    architectures = subprocess.check_output(["lipo", "-archs", str(product / "Contents/MacOS/FocusIntents")], text=True).split()
    assert set(architectures) == {"arm64", "x86_64"}
print(f"PASS: {args.configuration} extension and App Intents metadata: {product}")
