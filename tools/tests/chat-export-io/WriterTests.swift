import Foundation
import Darwin

final class ChatExportHtmlWriter {
    let baseURL: URL
    let chatName = "Test chat"
    let themeColors: Int? = nil
    let messagesPerPage = 1
    var currentPageIndex = 0
    var messagesInCurrentPage = 0
    var handle: FileHandle?
    var lastAuthorId: Int? = nil
    var lastTimestamp: Int32 = 0
    var lastDayKey = ""
    let dayFormatter = DateFormatter()
    let dividerFormatter = DateFormatter()
    static let scriptJs = "script"
    static func styleCss(_ colors: Int?) -> String { "style" }
    init(baseURL: URL) { self.baseURL = baseURL }
    func headerAvatarHtml() -> String { "" }
    func headerSubtitleHtml() -> String { "" }
    func esc(_ text: String) -> String { text }

__METHODS__
}

let scenario = CommandLine.arguments[1]
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let writer = ChatExportHtmlWriter(baseURL: directory)
let page = directory.appendingPathComponent("messages.html")
if scenario == "create-failure" {
    try FileManager.default.createDirectory(at: page, withIntermediateDirectories: false)
}
var caught: Error?
do {
    try writer.begin()
    if ["message-failure", "footer-failure"].contains(scenario) {
        writer.handle?.closeFile()
        writer.handle = try FileHandle(forReadingFrom: page)
    }
    if scenario == "full-file" {
        signal(SIGXFSZ, SIG_IGN)
        var limit = rlimit(rlim_cur: 4096, rlim_max: 4096)
        precondition(setrlimit(RLIMIT_FSIZE, &limit) == 0)
    }
    if scenario != "empty" && scenario != "footer-failure" {
        try writer.appendService(id: 1, html: scenario == "full-file" ? String(repeating: "x", count: 8192) : "first message", timestamp: 1)
    }
    if scenario == "rollover-failure" {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("messages2.html"), withIntermediateDirectories: false)
    }
    if scenario == "pagination" || scenario == "rollover-failure" {
        try writer.appendService(id: 2, html: "second message", timestamp: 2)
    }
    let result = try writer.finish()
    precondition(result == page)
} catch {
    caught = error
}
if ["create-failure", "message-failure", "footer-failure", "rollover-failure", "full-file"].contains(scenario) {
    precondition(caught != nil)
} else {
    precondition(caught == nil)
    let content = try String(contentsOf: page, encoding: .utf8)
    precondition(content.contains("<!DOCTYPE html>") && content.contains("</html>"))
    if scenario != "empty" { precondition(content.contains("first message")) }
    if scenario == "pagination" {
        let second = try String(contentsOf: directory.appendingPathComponent("messages2.html"), encoding: .utf8)
        precondition(content.contains("messages2.html") && second.contains("second message") && second.contains("Previous messages"))
    }
}
print("PASS \(scenario)")
