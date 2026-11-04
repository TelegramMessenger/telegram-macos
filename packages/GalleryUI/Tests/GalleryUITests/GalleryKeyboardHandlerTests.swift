import AppKit
import XCTest
import TGUIKit
import KeyboardKey
import InputView
@testable import GalleryUI

final class GalleryKeyboardHandlerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GalleryKeyboardTestBootstrap.install()
    }

    func testRecipientSearchReceivesLettersSymbolsAndSpace() throws {
        let fixture = GalleryKeyboardFixture()
        defer { fixture.close() }
        let dialog = fixture.openDialog()
        dialog.search.change(state: .Focus, false)
        try fixture.focus(dialog.search.input, in: dialog)
        try assertTyping(in: dialog.search.input, fixture: fixture)
    }

    func testTokenizedRecipientSearchReceivesLettersSymbolsAndSpace() throws {
        let fixture = GalleryKeyboardFixture()
        defer { fixture.close() }
        let dialog = fixture.openDialog()
        let input = try XCTUnwrap(dialog.tokens.responder as? NSTextView)
        try fixture.focus(input, in: dialog)
        try assertTyping(in: input, fixture: fixture)
        XCTAssertEqual(dialog.tokens.query, input.string)
    }

    func testCommentReceivesLettersSymbolsAndSpace() throws {
        let fixture = GalleryKeyboardFixture()
        defer { fixture.close() }
        let dialog = fixture.openDialog()
        try fixture.focus(dialog.comment.inputView, in: dialog)
        try assertTyping(in: dialog.comment.inputView, fixture: fixture)
    }

    func testCommentArrowKeysMoveAndSelectTextInsteadOfChangingMedia() throws {
        let fixture = GalleryKeyboardFixture()
        defer { fixture.close() }
        let dialog = fixture.openDialog()
        let input = dialog.comment.inputView
        try fixture.focus(input, in: dialog)
        input.string = "first photo"
        input.setSelectedRange(NSRange(location: 5, length: 0))
        try fixture.send(.LeftArrow, "\u{f702}")
        XCTAssertEqual(input.selectedRange(), NSRange(location: 4, length: 0))
        try fixture.send(.RightArrow, "\u{f703}", flags: .shift)
        XCTAssertEqual(input.selectedRange(), NSRange(location: 4, length: 1))
        XCTAssertTrue(fixture.invocations.isEmpty)
        XCTAssertTrue(hasModals(fixture.window))
    }

    func testModalReturnEscapeAndRecipientNavigationKeepPriority() throws {
        let fixture = GalleryKeyboardFixture()
        defer { fixture.close() }
        let dialog = fixture.openDialog()
        try fixture.focus(dialog.search.input, in: dialog)
        for key: KeyboardKey in [.UpArrow, .DownArrow] {
            fixture.window.set(handler: { _ in
                dialog.navigation.append(key)
                return .invoked
            }, with: dialog, for: key, priority: .modal)
        }
        try fixture.send(.UpArrow, "\u{f700}")
        try fixture.send(.DownArrow, "\u{f701}")
        try fixture.send(.Return, "\r")
        try fixture.send(.Escape, "\u{1b}")
        XCTAssertEqual(dialog.search.state, .None)
        XCTAssertEqual(dialog.escapeCount, 0)
        try fixture.focus(dialog.comment.inputView, in: dialog)
        try fixture.send(.Escape, "\u{1b}")
        XCTAssertEqual(dialog.navigation, [.UpArrow, .DownArrow])
        XCTAssertEqual(dialog.returnCount, 1)
        XCTAssertEqual(dialog.escapeCount, 1)
        XCTAssertTrue(hasModals(fixture.window))
        XCTAssertTrue(fixture.invocations.isEmpty)
    }

    func testModalBlocksGalleryShortcutsWithoutAnEditableResponder() throws {
        let fixture = GalleryKeyboardFixture()
        defer { fixture.close() }
        let dialog = fixture.openDialog()
        dialog.activeResponder = dialog.sink
        XCTAssertTrue(fixture.window.makeFirstResponder(dialog.sink))
        for key: KeyboardKey in [.F, .Space, .Minus, .Equal, .LeftArrow, .RightArrow, .Comma, .Period] {
            try fixture.send(key, "x")
        }
        XCTAssertEqual(dialog.sink.events.count, 8)
        XCTAssertTrue(fixture.invocations.isEmpty)
    }

    func testModifiedGalleryShortcutsYieldToOtherHandlersDuringModal() throws {
        let fixture = GalleryKeyboardFixture()
        defer { fixture.close() }
        _ = fixture.openDialog()
        var forwarded: [KeyboardKey] = []
        let keys: [(KeyboardKey, NSEvent.ModifierFlags)] = [(.Minus, [.command, .option]), (.Equal, [.command, .option]), (.R, .command), (.S, .command), (.T, .command)]
        for (key, flags) in keys {
            fixture.window.set(handler: { _ in
                forwarded.append(key)
                return .invoked
            }, with: fixture.fallbackOwner, for: key, modifierFlags: flags)
            fixture.window.setGalleryKeyHandler({ _ in
                fixture.invocations.append(key)
                return .invoked
            }, with: fixture.owner, for: key, priority: .high, modifierFlags: flags)
            try fixture.send(key, "x", flags: flags)
        }
        XCTAssertEqual(forwarded, keys.map { $0.0 })
        XCTAssertTrue(fixture.invocations.isEmpty)
    }

    func testGalleryShortcutsResumeAfterRepeatedModalDismissal() throws {
        let fixture = GalleryKeyboardFixture()
        defer { fixture.close() }
        for _ in 0..<3 {
            let dialog = fixture.openDialog()
            try fixture.focus(dialog.comment.inputView, in: dialog)
            try fixture.send(.F, "f")
            XCTAssertEqual(dialog.comment.inputView.string, "f")
            let count = fixture.invocations.count
            fixture.dismissDialogs()
            XCTAssertFalse(hasModals(fixture.window))
            try fixture.send(.F, "f")
            try fixture.send(.Space, " ")
            try fixture.send(.Minus, "-")
            try fixture.send(.Equal, "+", flags: .shift)
            try fixture.send(.Escape, "\u{1b}")
            XCTAssertEqual(Array(fixture.invocations.dropFirst(count)), [.F, .Space, .Minus, .Equal, .Escape])
        }
    }

    func testModalInAnotherWindowDoesNotDisableGalleryShortcuts() throws {
        let gallery = GalleryKeyboardFixture()
        let other = GalleryKeyboardFixture()
        defer {
            other.close()
            gallery.close()
        }
        _ = other.openDialog()
        XCTAssertTrue(hasModals(other.window))
        XCTAssertFalse(hasModals(gallery.window))
        try gallery.send(.F, "f")
        XCTAssertEqual(gallery.invocations, [.F])
    }

    func testRemovingGalleryOwnerRemovesItsHandlers() throws {
        let fixture = GalleryKeyboardFixture()
        defer { fixture.close() }
        fixture.window.removeAllHandlers(for: fixture.owner)
        let search = SearchTextField()
        search.frame = NSRect(x: 0, y: 0, width: 300, height: 30)
        XCTAssertNotNil(search.textStorage)
        fixture.window.contentView?.addSubview(search)
        XCTAssertTrue(fixture.window.makeFirstResponder(search))
        try fixture.send(.F, "f")
        XCTAssertEqual(search.string, "f")
        XCTAssertTrue(fixture.invocations.isEmpty)
    }

    func testUnscopedHandlerReproducesOriginalInputLoss() throws {
        let fixture = GalleryKeyboardFixture(installHandlers: false)
        defer { fixture.close() }
        let dialog = fixture.openDialog()
        try fixture.focus(dialog.search.input, in: dialog)
        fixture.window.set(handler: { _ in
            fixture.invocations.append(.F)
            return .invoked
        }, with: fixture.owner, for: .F)
        try fixture.send(.F, "а")
        XCTAssertEqual(fixture.invocations, [.F])
        XCTAssertTrue(dialog.search.input.string.isEmpty)
        XCTAssertTrue(hasModals(fixture.window))
    }

    private func assertTyping(in input: NSTextView, fixture: GalleryKeyboardFixture) throws {
        let keys: [(KeyboardKey, String, NSEvent.ModifierFlags)] = [
            (.F, "f", []), (.F, "F", .shift), (.F, "а", []), (.F, "А", .shift),
            (.Minus, "-", []), (.Minus, "_", .shift), (.Equal, "=", []), (.Equal, "+", .shift),
            (.Space, " ", []), (.Comma, ",", []), (.Comma, "<", .shift),
            (.Period, ".", []), (.Period, ">", .shift), (.Comma, "б", []), (.Period, "ю", [])
        ]
        var expected = ""
        for (key, text, flags) in keys {
            try fixture.send(key, text, flags: flags)
            expected += text
            XCTAssertEqual(input.string, expected)
            XCTAssertTrue(fixture.invocations.isEmpty)
            XCTAssertTrue(hasModals(fixture.window))
            XCTAssertTrue(fixture.window.firstResponder === input)
        }
    }
}

private final class GalleryKeyboardFixture {
    let window = GalleryTestWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
    let owner = NSObject()
    let fallbackOwner = NSObject()
    var invocations: [KeyboardKey] = []
    private var dialogs: [GalleryInputDialog] = []

    init(installHandlers: Bool = true) {
        window.isReleasedWhenClosed = false
        if installHandlers {
            for key: KeyboardKey in [.Space, .F, .Escape, .LeftArrow, .RightArrow, .Minus, .Equal, .Comma, .Period] {
                window.setGalleryKeyHandler({ [weak self] _ in
                    self?.invocations.append(key)
                    return .invoked
                }, with: owner, for: key, priority: [.Comma, .Period].contains(key) ? .modal : .low)
            }
        }
    }

    func openDialog() -> GalleryInputDialog {
        let dialog = GalleryInputDialog(frame: NSRect(x: 0, y: 0, width: 360, height: 320))
        dialog.loadViewIfNeeded()
        dialog.activeResponder = dialog.search.input
        let modal = Modal(controller: dialog, for: window, animated: false, isOverlay: false, animationType: .none)
        dialogs.append(dialog)
        modal.show()
        dialog.search.change(state: .Focus, false)
        XCTAssertTrue(hasModals(window))
        return dialog
    }

    func focus(_ input: NSTextView, in dialog: GalleryInputDialog) throws {
        input.isHidden = false
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        dialog.activeResponder = input
        XCTAssertTrue(window.makeFirstResponder(input))
        XCTAssertTrue(window.firstResponder === input)
    }

    func send(_ key: KeyboardKey, _ text: String, flags: NSEvent.ModifierFlags = []) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: key.rawValue))
        window.sendEvent(event)
    }

    func dismissDialogs() {
        for dialog in dialogs {
            dialog.close(animationType: .noneDelayed(duration: 0))
            window.removeAllHandlers(for: dialog)
        }
        _ = window.makeFirstResponder(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        dialogs.removeAll()
    }

    func close() {
        dismissDialogs()
        window.removeAllHandlers(for: owner)
        window.removeAllHandlers(for: fallbackOwner)
        window.close()
    }
}

private final class GalleryTestWindow: Window {
    override var isKeyWindow: Bool {
        return true
    }
}

private final class GalleryInputDialog: ModalViewController {
    let search = SearchView(frame: NSRect(x: 10, y: 10, width: 340, height: 30))
    let tokens = TokenizedView(frame: NSRect(x: 10, y: 60, width: 340, height: 30), localizationFunc: { $0 }, placeholderKey: "Share to...")
    let comment = ChatInputTextView(frame: NSRect(x: 10, y: 110, width: 340, height: 120))
    let sink = GalleryKeySink(frame: NSRect(x: 10, y: 250, width: 100, height: 30))
    var activeResponder: NSResponder?
    var returnCount = 0
    var escapeCount = 0
    var navigation: [KeyboardKey] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        for child in [search, tokens, comment, sink] as [NSView] {
            view.addSubview(child)
        }
        tokens.setString("")
        readyOnce()
    }

    override func firstResponder() -> NSResponder? {
        return activeResponder
    }

    override func returnKeyAction() -> KeyHandlerResult {
        returnCount += 1
        return .invoked
    }

    override func escapeKeyAction() -> KeyHandlerResult {
        escapeCount += 1
        return .invoked
    }
}

private final class GalleryKeySink: NSView {
    var events: [NSEvent] = []

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        events.append(event)
    }
}

private enum GalleryKeyboardTestBootstrap {
    private static var images: [NSImage] = []
    private static var installed = false

    static func install() {
        guard !installed else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        System.liquidGlass = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode", "Icon_Menu_More"] {
            let directory = root.appendingPathComponent("Telegram-Mac/Assets.xcassets/\(name).imageset")
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("Contents.json")), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let entries = json["images"] as? [[String: Any]] else {
                XCTFail("Missing image metadata: \(name)")
                return
            }
            let image = NSImage()
            for entry in entries {
                guard let file = entry["filename"] as? String, let representation = NSImageRep(contentsOf: directory.appendingPathComponent(file)) else { continue }
                let scale = CGFloat(Double((entry["scale"] as? String ?? "1x").dropLast()) ?? 1)
                if !(representation is NSPDFImageRep) {
                    representation.size = NSSize(width: CGFloat(representation.pixelsWide) / scale, height: CGFloat(representation.pixelsHigh) / scale)
                }
                image.addRepresentation(representation)
                image.size = representation.size
            }
            guard !image.representations.isEmpty else {
                XCTFail("Missing image: \(name)")
                return
            }
            image.setName(name)
            images.append(image)
        }
        installed = true
    }
}
