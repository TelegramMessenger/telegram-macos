import Foundation
import os

typealias CVReturn = Int32
typealias CGDirectDisplayID = UInt32
typealias CVOptionFlags = UInt64
struct CVTimeStamp {}
let kCVReturnSuccess: CVReturn = 0
let scenario = CommandLine.arguments[1]

final class CVDisplayLink {
    var running = false
    var callback: ((UnsafeMutableRawPointer?) -> Void)?
    var starts = 0
}

func CGMainDisplayID() -> CGDirectDisplayID { 1 }
func CVDisplayLinkCreateWithCGDisplay(_ display: CGDirectDisplayID, _ result: inout CVDisplayLink?) -> CVReturn {
    if scenario == "create-failure" { return -1 }
    result = CVDisplayLink()
    return 0
}
func CVDisplayLinkSetCurrentCGDisplay(_ timer: CVDisplayLink, _ display: CGDirectDisplayID) -> CVReturn {
    scenario == "display-failure" ? -1 : 0
}
func CVDisplayLinkGetCurrentCGDisplay(_ timer: CVDisplayLink) -> CGDirectDisplayID { 1 }
func CVDisplayLinkIsRunning(_ timer: CVDisplayLink) -> Bool { timer.running }
func CVDisplayLinkGetActualOutputVideoRefreshPeriod(_ timer: CVDisplayLink) -> Double { 1.0 / 60 }
func CVDisplayLinkSetOutputCallback(_ timer: CVDisplayLink, _ callback: @escaping (CVDisplayLink, UnsafePointer<CVTimeStamp>, UnsafePointer<CVTimeStamp>, CVOptionFlags, UnsafeMutablePointer<CVOptionFlags>, UnsafeMutableRawPointer?) -> CVReturn, _ context: UnsafeMutableRawPointer?) -> CVReturn {
    if scenario == "callback-failure" { return -1 }
    timer.callback = { _ in
        var timestamp = CVTimeStamp()
        var flags: CVOptionFlags = 0
        withUnsafePointer(to: &timestamp) { pointer in
            _ = callback(timer, pointer, pointer, 0, &flags, context)
        }
    }
    return 0
}
func CVDisplayLinkStart(_ timer: CVDisplayLink) -> CVReturn {
    timer.starts += 1
    if scenario == "start-failure" { return -1 }
    timer.running = true
    return 0
}
func CVDisplayLinkStop(_ timer: CVDisplayLink) -> CVReturn { timer.running = false; return 0 }

__SOURCE__

let queue = DispatchQueue(label: "display-link-lifecycle")
func exercise() {
    let link = DisplayLink(onQueue: queue)
    if ["create-failure", "display-failure", "callback-failure"].contains(scenario) {
        precondition(link == nil)
        return
    }
    guard let link else { preconditionFailure() }
    if scenario == "never-started" { return }
    if scenario == "cancel-before-start" { link.cancel(); return }
    let signal = DispatchSemaphore(value: 0)
    var received = 0
    link.callback = { frames in received += frames; signal.signal() }
    link.start()
    if scenario == "start-failure" { precondition(!link.running); return }
    link.start()
    precondition(link.running && link.timer.starts == 1)
    link.timer.callback?(nil)
    precondition(signal.wait(timeout: .now() + 2) == .success)
    queue.sync { precondition(received == 1) }
    if scenario == "cancel" {
        link.cancel()
        link.cancel()
        precondition(!link.running)
    }
}
exercise()
queue.sync {}
print("PASS \(scenario)")
