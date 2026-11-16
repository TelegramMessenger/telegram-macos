from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
sources = root / "packages/AppAnalytics/Sources/AppAnalytics"
fields = {
    "AnalyticsForwardPickerJourney": {"stage": "Int?", "retryPending": "Bool", "retryCount": "Int", "submission": "Int?", "searched": "Bool"},
    "AnalyticsRecordingJourney": {"stage": "Int?", "kind": "Int?", "locked": "Bool", "reviewed": "Bool", "pendingTrimChange": "Bool", "oneTime": "Bool"},
    "AnalyticsStickerJourney": {"entry": "Int?", "stage": "Int?", "destination": "Int?", "retryPending": "Bool", "retryCount": "Int", "attempt": "Int"},
    "AnalyticsShareJourney": {"stage": "Int?", "retryPending": "Bool", "retryCount": "Int", "confirmationOpen": "Bool"},
    "AnalyticsMediaJourney": {"stage": "Int?", "submissionWasBlocked": "Bool"},
}
fixture = """
final class Policy {
    var reads = 0
    func sync<T>(_ action: () -> T) -> T { reads += 1; return action() }
}
struct Scope { let policy: Policy }
struct Flow { let storedStepCount: Int }
var checks = 0
"""
tests = ""
for name, members in fields.items():
    source = (sources / (name + ".swift")).read_text()
    start = source.index("    var retainedStateCount: Int {")
    end = source.index("\n    }", start) + len("\n    }")
    fixture += "\nstruct " + name + " {\n var scope: Scope?\n var flow: Flow?\n"
    for field, kind in members.items():
        fixture += f" var {field}: {kind}\n"
    if name == "AnalyticsMediaJourney":
        fixture += " var partResults: [Int]\n var retryCount: Int\n var expectedParts: Int\n"
    fixture += source[start:end] + "\n}\n"
    tests += f"\nfor mask in 0..<{1 << len(members)} {{\n for enabled in [false, true] {{\n  for steps: Int? in [nil, 0, 7] {{\n"
    tests += " let policy = Policy()\n let scope: Scope? = enabled ? Scope(policy: policy) : nil\n"
    arguments = ["scope: scope", "flow: steps.map { Flow(storedStepCount: $0) }"]
    for index, (field, kind) in enumerate(members.items()):
        bit = f"mask & {1 << index} != 0"
        value = bit if kind == "Bool" else f"({bit}) ? 9 : " + ("nil" if kind == "Int?" else "0")
        arguments.append(field + ": " + value)
    extras = 0
    if name == "AnalyticsMediaJourney":
        arguments += ["partResults: [1, 2, 3]", "retryCount: 4", "expectedParts: 5"]
        extras = 12
    tests += f" let journey = {name}(" + ", ".join(arguments) + ")\n"
    tests += f" let expected = enabled ? (steps ?? 0) + mask.nonzeroBitCount + {extras} : 0\n"
    tests += " precondition(journey.retainedStateCount == expected)\n precondition(policy.reads == (enabled ? 1 : 0))\n checks += 1\n }\n }\n}\n"
fixture += tests + '\nprint("Retained-state accounting: \\(checks) checks passed")\n'
with tempfile.TemporaryDirectory(prefix="analytics-retained-state-") as directory:
    directory = Path(directory)
    source = directory / "main.swift"
    source.write_text(fixture)
    common = ["xcrun", "swiftc", "-module-cache-path", str(directory / "cache"), "-O", "-whole-module-optimization", str(source)]
    subprocess.run(common + ["-target", "x86_64-apple-macosx10.13", "-emit-object", "-o", str(directory / "intel.o")], check=True)
    subprocess.run(common + ["-o", str(directory / "check")], check=True)
    subprocess.run([str(directory / "check")], check=True)
