import AppKit
import Foundation
import Reference
import TGUIKit

struct Scenario {
    let name: String
    let input: NSAttributedString
    let trim: Bool
    let iterations: Int
}

func styled(_ text: String) -> NSAttributedString {
    let result = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.blue])
    let middle = result.length / 2
    result.addAttribute(NSAttributedString.Key("entity"), value: "preview", range: NSRange(location: middle, length: result.length - middle))
    return result
}

let scenarios = [
    Scenario(name: "preview-short-plain", input: NSAttributedString(string: "Hello from Telegram"), trim: false, iterations: 4000),
    Scenario(name: "preview-short-styled", input: styled("Привет 🙂\nhello\nworld"), trim: false, iterations: 4000),
    Scenario(name: "preview-no-newlines-styled", input: styled("Привет 🙂 hello world"), trim: false, iterations: 4000),
    Scenario(name: "preview-long-styled", input: styled(String(repeating: "hello 🙂\nworld\n", count: 128)), trim: false, iterations: 100),
    Scenario(name: "trim-short-styled", input: styled("  Привет 🙂\u{2028}hello\u{fffc}world\n"), trim: true, iterations: 4000),
    Scenario(name: "trim-no-separators", input: styled("Привет 🙂 hello world"), trim: true, iterations: 4000),
    Scenario(name: "trim-separators-64", input: styled("A" + String(repeating: "a\u{2028}b\u{fffc}", count: 32) + "Z"), trim: true, iterations: 400),
    Scenario(name: "trim-separators-512", input: styled("A" + String(repeating: "a\u{2028}b\u{fffc}", count: 256) + "Z"), trim: true, iterations: 60),
    Scenario(name: "trim-separators-2048", input: styled("A" + String(repeating: "a\u{2028}b\u{fffc}", count: 1024) + "Z"), trim: true, iterations: 15)
]

@inline(never)
func measure(_ scenario: Scenario, reference: Bool) -> (Double, Int) {
    var checksum = 0
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<scenario.iterations {
        autoreleasepool {
            let result: NSAttributedString
            if reference {
                result = scenario.trim ? scenario.input.referenceTrimmed : scenario.input.referenceTrimNewLinesToSpace
            } else {
                result = scenario.trim ? scenario.input.trimmed : scenario.input.trimNewLinesToSpace
            }
            checksum &+= result.length
        }
    }
    return (Double(DispatchTime.now().uptimeNanoseconds - start) / Double(scenario.iterations) / 1000, checksum)
}

var output: [[String: Any]] = []
var checksum = 0
let reverse = CommandLine.arguments.contains("--reverse")
for scenario in scenarios {
    let baseline = scenario.trim ? scenario.input.referenceTrimmed : scenario.input.referenceTrimNewLinesToSpace
    let candidate = scenario.trim ? scenario.input.trimmed : scenario.input.trimNewLinesToSpace
    precondition(baseline.isEqual(to: candidate))
    checksum &+= measure(scenario, reference: true).1
    checksum &+= measure(scenario, reference: false).1
    var before: [Double] = []
    var after: [Double] = []
    for batch in 0..<9 {
        for reference in (batch % 2 == 0) != reverse ? [true, false] : [false, true] {
            let result = measure(scenario, reference: reference)
            checksum &+= result.1
            if reference { before.append(result.0) } else { after.append(result.0) }
        }
    }
    let old = before.sorted()[before.count / 2]
    let new = after.sorted()[after.count / 2]
    print("\(scenario.name): before=\(String(format: "%.3f", old))us after=\(String(format: "%.3f", new))us speedup=\(String(format: "%.2f", old / new))x")
    output.append(["scenario": scenario.name, "iterations": scenario.iterations, "before_us": before, "after_us": after, "median_before_us": old, "median_after_us": new])
}
let json = try JSONSerialization.data(withJSONObject: ["reverse": reverse, "checksum": checksum, "results": output], options: [.sortedKeys])
print(String(data: json, encoding: .utf8)!)
