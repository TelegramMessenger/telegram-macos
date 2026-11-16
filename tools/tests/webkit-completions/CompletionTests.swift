import Foundation

public final class WKWebView {}
public final class WKFrameInfo {}
public final class WKSecurityOrigin {}
public final class WKOpenPanelParameters {
    let allowsMultipleSelection = true
    let allowsDirectories = false
    let allowsDirectorySelection = false
}
public enum WKMediaCaptureType { case camera, microphone, cameraAndMicrophone, future }
public enum WKPermissionDecision: Equatable { case grant, deny }
final class Window {}
final class Peer {
    let id = 1
    let displayTitle = "Bot"
}
final class RequestData { let bot = Peer() }
let appName = "Telegram"
var success: (() -> Void)?
var cancel: (() -> Void)?
var dismissed: (() -> Void)?
var selectedFiles: (([String]?) -> Void)?
var permissions: [((Bool) -> Void)] = []
var allowed = false
var storedGrants = 0
func filePanel(with: Any?, allowMultiple: Bool, canChooseDirectories: Bool, for window: Window, completion: @escaping ([String]?) -> Void) { selectedFiles = completion }
func verifyAlert_button(for window: Window, header: String = "", information: String, ok: String = "", successHandler: @escaping (Bool) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void = {}) {
    success = { successHandler(true) }
    cancel = cancelHandler
    dismissed = onDeinit
}
func alert(for window: Window, header: String = "", info: String, onDeinit: @escaping () -> Void = {}) { dismissed = onDeinit }
struct Strings {
    let webAppAccessAllow = "Allow"
    let unknownError = "Unknown"
    func webAppAccessVideo(_ title: String) -> String { title }
    func webAppAccessAudio(_ title: String) -> String { title }
    func webAppAccessAudioVideo(_ title: String) -> String { title }
}
func strings() -> Strings { Strings() }
enum FastSettings {
    static func botAccessTo(_ type: WKMediaCaptureType, peerId: Int) -> Bool { allowed }
    static func allowBotAccessTo(_ type: WKMediaCaptureType, peerId: Int) { storedGrants += 1 }
}
enum MediaType { case video, audio }
struct PermissionSignal {
    func start(next: @escaping (Bool) -> Void) -> Int { permissions.append(next); return 0 }
}
struct CombinedPermissionSignal {
    func start(next: @escaping (Bool, Bool) -> Void) -> Int { permissions.append { next($0, $0) }; return 0 }
}
func requestMediaPermission(_ type: MediaType) -> PermissionSignal { PermissionSignal() }
func combineLatest(_ first: PermissionSignal, _ second: PermissionSignal) -> CombinedPermissionSignal { CombinedPermissionSignal() }
final class Controller {
    var window: Window? = Window()
    var requestData: RequestData? = RequestData()
    let context = 0
    __METHODS__
}
let test = CommandLine.arguments[1]
var owner: Controller? = Controller()
let web = WKWebView(), frame = WKFrameInfo()
var responses: [Bool] = []
var decisions: [WKPermissionDecision] = []
var files: [[URL]?] = []
if test.hasPrefix("confirm-") {
    if test == "confirm-no-window" { owner!.window = nil }
    owner!.webView(web, runJavaScriptConfirmPanelWithMessage: "Confirm", initiatedByFrame: frame) { responses.append($0) }
    switch test {
    case "confirm-accept": success?()
    case "confirm-cancel": cancel?()
    case "confirm-dismiss": dismissed?()
    case "confirm-accept-dismiss": success?(); dismissed?()
    case "confirm-cancel-dismiss": cancel?(); dismissed?()
    default: break
    }
    precondition(responses == [test == "confirm-accept" || test == "confirm-accept-dismiss"])
} else if test.hasPrefix("open-") {
    if test == "open-no-window" { owner!.window = nil }
    owner!.webView(web, runOpenPanelWith: WKOpenPanelParameters(), initiatedByFrame: frame) { files.append($0) }
    if test == "open-cancel" { selectedFiles?(nil) }
    if test == "open-files" { selectedFiles?(["/tmp/input.png"]) }
    precondition(files.count == 1)
    precondition(files[0] == (test == "open-files" ? [URL(fileURLWithPath: "/tmp/input.png")] : nil))
} else if test.hasPrefix("permission-") {
    if test == "permission-cached" { allowed = true }
    if test == "permission-no-bot" { owner!.requestData = nil }
    let type: WKMediaCaptureType = test == "permission-unknown" ? .future : test == "permission-microphone" ? .microphone : test.hasPrefix("permission-combined") ? .cameraAndMicrophone : .camera
    owner!.webView(web, requestMediaCapturePermissionFor: WKSecurityOrigin(), initiatedByFrame: frame, type: type) { decisions.append($0) }
    if test == "permission-no-window" { owner!.window = nil }
    if test == "permission-owner-gone" { owner = nil }
    for permission in permissions { permission(!test.hasSuffix("denied")) }
    if test == "permission-dismiss" { dismissed?() }
    if test == "permission-allow-dismiss" { success?(); dismissed?() }
    if test == "permission-cancel-dismiss" { cancel?(); dismissed?() }
    if test == "permission-microphone" || test == "permission-combined" { success?(); dismissed?() }
    let granted = test == "permission-cached" || test == "permission-allow-dismiss" || test == "permission-microphone" || test == "permission-combined"
    precondition(decisions == [granted ? .grant : .deny])
    precondition(storedGrants == (granted && test != "permission-cached" ? 1 : 0))
} else if test == "alert-dismiss" {
    owner!.webView(web, runJavaScriptAlertPanelWithMessage: "Alert", initiatedByFrame: frame) { responses.append(true) }
    dismissed?()
    precondition(responses == [true])
}
print("completed once with expected decision")
