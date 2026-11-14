import Cocoa
import XCTest

final class Window { var appearance: NSAppearance? }
struct Theme { let appearance: NSAppearance? = nil }
let theme = Theme()
final class App {
    func window(withWindowNumber: Int) -> Window? { nil }
}
let NSApp = App()
let IKPictureTakerShowEffectsKey = "effects"
let IKPictureTakerOutputImageMaxSizeKey = "size"
fileprivate final class IKPictureTaker: NSObject {
    static let shared = IKPictureTaker()
    var delegates: [PickerObserver] = []
    var image: NSImage?
    let windowNumber = 0
    static func pictureTaker() -> IKPictureTaker { shared }
    override func setValue(_ value: Any?, forKey key: String) {}
    func outputImage() -> NSImage? { image }
    func beginSheet(for window: Window, withDelegate delegate: PickerObserver, didEnd: Selector, contextInfo: Any?) {
        delegates.append(delegate)
    }
}
extension NSSize {
    func aspectFilled(_ target: NSSize) -> NSSize { target }
}
extension NSImage {
    func precomposed() -> CGImage {
        generateImage(NSMakeSize(1, 1), contextGenerator: { _, _ in })!
    }
}
func generateImage(_ size: NSSize, contextGenerator: (NSSize, CGContext) -> Void) -> CGImage? {
    let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    contextGenerator(size, context)
    return context.makeImage()
}
final class Lease {
    private var finish: (() -> Void)?
    init(_ finish: @escaping () -> Void) { self.finish = finish }
    func end() { let callback = finish; finish = nil; callback?() }
    deinit { end() }
}
final class AnalyticsContext {
    var depth = 0
    let privateOrigin: Bool
    init(privateOrigin: Bool = false) { self.privateOrigin = privateOrigin }
    func beginPresentation() -> Lease { depth += 1; return Lease { self.depth -= 1 } }
}
enum Screen { case systemPhotoPicker }
final class Screens {
    var shown: [AnalyticsContext] = []
    var hides = 0
    func showStandalone(_ screen: Screen, owner: AnyObject, context: AnalyticsContext) { shown.append(context) }
    func hideStandalone(owner: AnyObject) { hides += 1 }
}
final class Analytics {
    static let shared = Analytics()
    var screens = Screens()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(privateOrigin: true) }
}

__PICKER__

final class PickerTests: XCTestCase {
    override func setUp() {
        activePicturePicker = nil
        IKPictureTaker.shared.delegates = []
        IKPictureTaker.shared.image = nil
        Analytics.shared.screens = Screens()
    }
    override func tearDown() { activePicturePicker = nil }
    private func complete(_ index: Int = 0, code: NSApplication.ModalResponse = .OK) {
        let taker = IKPictureTaker.shared
        taker.delegates[index].validated(taker, code.rawValue, nil)
    }
    func testOverlappingRequestCannotReplaceOriginalOwnerOrContext() {
        for privateOrigin in [false, true] {
            let origin = AnalyticsContext(privateOrigin: privateOrigin)
            let competing = AnalyticsContext(privateOrigin: !privateOrigin)
            var originals = 0
            var denied = 0
            let index = IKPictureTaker.shared.delegates.count
            pickImage(for: Window(), analyticsContext: origin) { _ in
                originals += 1
                XCTAssertEqual(origin.depth, 1)
            }
            pickImage(for: Window(), analyticsContext: competing) { image in
                denied += 1
                XCTAssertNil(image)
                XCTAssertEqual(competing.depth, 1)
            }
            XCTAssertEqual(denied, 1)
            XCTAssertEqual(originals, 0)
            XCTAssertEqual(competing.depth, 0)
            XCTAssertEqual(origin.depth, 1)
            XCTAssertEqual(IKPictureTaker.shared.delegates.count, index + 1)
            XCTAssertTrue(Analytics.shared.screens.shown.last === origin)
            complete(index)
            XCTAssertEqual(originals, 1)
            XCTAssertEqual(origin.depth, 0)
            XCTAssertNil(activePicturePicker)
        }
    }
    func testDuplicateResultDoesNotCallOrHideAgain() {
        var callbacks = 0
        pickImage(for: Window(), analyticsContext: AnalyticsContext()) { _ in callbacks += 1 }
        complete()
        complete(code: .cancel)
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(Analytics.shared.screens.hides, 1)
    }
    func testCompletionCanOpenNextPickerAndOldCallbackCannotResolveIt() {
        let first = AnalyticsContext(privateOrigin: true)
        let second = AnalyticsContext()
        var deliveredSecond = 0
        pickImage(for: Window(), analyticsContext: first) { _ in
            XCTAssertEqual(first.depth, 1)
            pickImage(for: Window(), analyticsContext: second) { _ in deliveredSecond += 1 }
        }
        complete()
        XCTAssertEqual(IKPictureTaker.shared.delegates.count, 2)
        XCTAssertEqual(first.depth, 0)
        XCTAssertEqual(second.depth, 1)
        complete()
        XCTAssertEqual(deliveredSecond, 0)
        XCTAssertEqual(Analytics.shared.screens.hides, 1)
        complete(1)
        XCTAssertEqual(deliveredSecond, 1)
        XCTAssertEqual(second.depth, 0)
    }
    func testCancelledUnknownAndMissingOutputRemainNil() {
        for code in [NSApplication.ModalResponse.cancel, .abort, .OK] {
            let context = AnalyticsContext()
            var calls = 0
            let index = IKPictureTaker.shared.delegates.count
            pickImage(for: Window(), analyticsContext: context) { image in calls += 1; XCTAssertNil(image) }
            complete(index, code: code)
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(context.depth, 0)
        }
    }
    func testAcceptedImageIsDeliveredOnlyToOriginalRequest() {
        IKPictureTaker.shared.image = NSImage(size: NSMakeSize(1, 1))
        let context = AnalyticsContext(privateOrigin: true)
        var delivered: NSImage?
        pickImage(for: Window(), analyticsContext: context) { delivered = $0; XCTAssertEqual(context.depth, 1) }
        complete()
        XCTAssertNotNil(delivered)
        XCTAssertEqual(context.depth, 0)
    }
    func testLegacyPickerUsesUnresolvedContext() {
        pickImage(for: Window()) { _ in }
        XCTAssertEqual(Analytics.shared.screens.shown.last?.privateOrigin, true)
        complete()
    }
}
