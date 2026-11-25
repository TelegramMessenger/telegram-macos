import Foundation
import XCTest

struct Signal<Value> {
    let value: Value
    func start(next: (Value) -> Void) { next(value) }
}
infix operator |> : AdditionPrecedence
func |> <A, B>(value: A, transform: (A) -> B) -> B { transform(value) }
func mapToSignal<A, B>(_ transform: @escaping (A) -> Signal<B>) -> (Signal<A>) -> Signal<B> { { transform($0.value) } }
func deliverOnMainQueue<A>(_ signal: Signal<A>) -> Signal<A> { signal }

final class NSPasteboard {
    struct PasteboardType: Hashable { let rawValue: String }
    struct Item {
        let path: String?
        var types: [PasteboardType] = []
        func string(forType: PasteboardType) -> String? { path }
    }
    var pasteboardItems: [Item]?
    var image: NSImage?
    init(paths: [String] = [], image: NSImage? = nil) {
        pasteboardItems = paths.isEmpty ? [Item(path: nil)] : paths.map { Item(path: URL(fileURLWithPath: $0).absoluteString) }
        self.image = image
    }
    func readObjects(forClasses: [AnyClass], options: Any?) -> [Any]? { image.map { [$0] } }
}
final class NSImage { var representations: [Any] = [] }
final class NSPDFImageRep { let pdfRepresentation = Data() }
final class Window {}
let mainWindow = Window()
struct Peer {}
struct PeerId { let namespace = 0 }
enum Namespaces { enum Peer { static let SecretChat = 1 } }
enum Permission { case banSendMedia }
enum Entry { case clipboard }
enum Mode { case media }
enum Blocker: Equatable { case sizeLimit, fileUnavailable, permission }
final class PresentationLease { func end() {} }
final class Context {
    func beginPresentation() -> PresentationLease { PresentationLease() }
    func preservingPresentation<T>(_ value: T) -> T { value }
}
final class Journey {
    var blockers: [Blocker] = []
    var failure: Blocker?
    var prepared = false
    func blocked(_ reason: Blocker) { blockers.append(reason) }
    func fail(_ reason: Blocker) { failure = reason }
    func preparing() { prepared = true }
}
struct MediaSenderContainer { let path: String; let isFile: Bool }
enum Sender {
    static func generateMedia(for container: MediaSenderContainer, account: Int, isSecretRelated: Bool) -> Signal<(Int, Int)> { Signal(value: (1, 0)) }
}
struct EditState { var canEditMedia = true }
struct InterfaceState { var editState: EditState? }
struct Presentation {
    var interfaceState = InterfaceState()
    var peer: Peer? = Peer()
}
struct InteractionContext { let account = 0 }
final class ChatInteraction {
    let context = Context()
    var presentation = Presentation()
    let interactionContext = InteractionContext()
    let peerId = PeerId()
    var admitted = true
    var created: [Journey] = []
    var preview: [URL]?
    var previewJourney: Journey?
    var replacements = 0
    var replacementRejections: [Blocker] = []
    func captureAnalyticsContext() -> Context { context }
    func makeMediaAnalyticsJourney(context: Context, entry: Entry, mode: Mode) -> Journey? {
        guard admitted, presentation.interfaceState.editState == nil else { return nil }
        let task = Journey()
        created.append(task)
        return task
    }
    func rejectMediaReplacement(entry: Entry, mode: Mode, context: Context, reason: Blocker) { replacementRejections.append(reason) }
    func beginMediaReplacement(entry: Entry, mode: Mode, context: Context) -> Int { 0 }
    func applyMediaReplacement(_ media: Int, request: Int) { replacements += 1 }
    func showPreviewSender(_ files: [URL], _ media: Bool, _ caption: String?, analyticsContext: Context, journey: Journey?) {
        preview = files
        previewJourney = journey
    }
}
var fileSizes: [String: Int64] = [:]
var permissionDenied = false
var limitAlerts = 0
var permissionAlerts = 0
func fileSize(_ path: String) -> Int64? { fileSizes[path] }
func fileSizeLimitExceed(context: InteractionContext, fileSize: Int64) -> Bool { fileSize <= 100 }
func permissionText(from: Peer, for: Permission) -> String? { permissionDenied ? "denied" : nil }
func showFileLimit(context: InteractionContext, fileSize: Int64?) { limitAlerts += 1 }
func alert(for: Window, info: String) { permissionAlerts += 1 }
func putToTemp(image: NSImage, compress: Bool = true) -> Signal<String> { Signal(value: "/prepared-image") }
final class InputPasteboardParser {
__PROCESS__
}

final class PasteTests: XCTestCase {
    override func setUp() {
        fileSizes = ["/small": 10, "/large": 101, "/other": 20]
        permissionDenied = false
        limitAlerts = 0
        permissionAlerts = 0
    }
    @discardableResult private func paste(_ board: NSPasteboard, into chat: ChatInteraction) -> Bool {
        InputPasteboardParser.proccess(pasteboard: board, chatInteraction: chat, window: mainWindow)
    }
    func testAllOversizedFilesFailBeforePreview() {
        let chat = ChatInteraction()
        XCTAssertFalse(paste(NSPasteboard(paths: ["/large"]), into: chat))
        XCTAssertEqual(chat.created.count, 1)
        XCTAssertEqual(chat.created.first?.failure, .sizeLimit)
        XCTAssertEqual(chat.created.first?.blockers, [])
        XCTAssertNil(chat.preview)
        XCTAssertEqual(limitAlerts, 1)
    }
    func testUnavailableMetadataDoesNotClaimMissingFile() {
        let chat = ChatInteraction()
        paste(NSPasteboard(paths: ["/unreadable"]), into: chat)
        XCTAssertEqual(chat.created.first?.failure, .fileUnavailable)
        XCTAssertNil(chat.preview)
    }
    func testPartialSelectionPreservesSameJourneyAndAcceptedFiles() {
        let chat = ChatInteraction()
        paste(NSPasteboard(paths: ["/large", "/small", "/other"]), into: chat)
        XCTAssertEqual(chat.created.count, 1)
        XCTAssertTrue(chat.previewJourney === chat.created.first)
        XCTAssertEqual(chat.preview?.map(\.path), ["/small", "/other"])
        XCTAssertEqual(chat.previewJourney?.blockers, [.sizeLimit])
        XCTAssertNil(chat.previewJourney?.failure)
        XCTAssertEqual(limitAlerts, 0)
    }
    func testPartialUnavailableMetadataAndMixedGatePriority() {
        for rejected in [["/unreadable"], ["/unreadable", "/large"]] {
            let chat = ChatInteraction()
            paste(NSPasteboard(paths: rejected + ["/small"]), into: chat)
            XCTAssertEqual(chat.previewJourney?.blockers, rejected.count == 1 ? [.fileUnavailable] : [.sizeLimit])
        }
    }
    func testPermissionRejectsFilesAndImagesWithoutPreview() {
        permissionDenied = true
        for board in [NSPasteboard(paths: ["/small"]), NSPasteboard(image: NSImage())] {
            let chat = ChatInteraction()
            paste(board, into: chat)
            XCTAssertEqual(chat.created.first?.failure, .permission)
            XCTAssertNil(chat.preview)
        }
        XCTAssertEqual(permissionAlerts, 2)
    }
    func testPermissionAfterPartialFilteringRetainsEarlierBlocker() {
        permissionDenied = true
        let chat = ChatInteraction()
        paste(NSPasteboard(paths: ["/small", "/large"]), into: chat)
        XCTAssertEqual(chat.created.first?.blockers, [.sizeLimit])
        XCTAssertEqual(chat.created.first?.failure, .permission)
    }
    func testAcceptedImageKeepsJourneyAcrossPreparation() {
        let chat = ChatInteraction()
        paste(NSPasteboard(image: NSImage()), into: chat)
        XCTAssertEqual(chat.created.count, 1)
        XCTAssertTrue(chat.previewJourney === chat.created.first)
        XCTAssertEqual(chat.previewJourney?.prepared, true)
        XCTAssertEqual(chat.preview?.map(\.path), ["/prepared-image"])
    }
    func testTextEmptyAndIgnoredApplicationPasteCreateNoJourney() {
        let empty = NSPasteboard()
        empty.pasteboardItems = []
        let ignored = NSPasteboard(paths: ["/small"])
        ignored.pasteboardItems?[0].types = [.init(rawValue: "com.microsoft.appbundleid")]
        for board in [NSPasteboard(), empty, ignored] {
            let chat = ChatInteraction()
            XCTAssertTrue(paste(board, into: chat))
            XCTAssertTrue(chat.created.isEmpty)
            XCTAssertNil(chat.preview)
        }
    }
    func testEditingDoesNotBecomeCompositionJourney() {
        for path in ["/small", "/large"] {
            let chat = ChatInteraction()
            chat.presentation.interfaceState.editState = EditState()
            paste(NSPasteboard(paths: [path]), into: chat)
            XCTAssertTrue(chat.created.isEmpty)
            XCTAssertNil(chat.preview)
            XCTAssertEqual(chat.replacements, path == "/small" ? 1 : 0)
            XCTAssertEqual(chat.replacementRejections, path == "/large" ? [.sizeLimit] : [])
        }
    }
    func testIneligibleContextLeavesFunctionalPasteUnchanged() {
        let chat = ChatInteraction()
        chat.admitted = false
        paste(NSPasteboard(paths: ["/small", "/large"]), into: chat)
        XCTAssertTrue(chat.created.isEmpty)
        XCTAssertNil(chat.previewJourney)
        XCTAssertEqual(chat.preview?.map(\.path), ["/small"])
    }
}
