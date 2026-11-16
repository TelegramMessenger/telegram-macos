__UNIQUE__

enum AdditionStep: Equatable {
    case addPaste, addDrop, addPicker, addPasteUnchanged, addDropUnchanged
}
enum AdditionMode: Equatable { case media, file }
struct AdditionState { var analyticsMode = AdditionMode.media }
final class AdditionView { var state = AdditionState() }
final class AdditionJourney {
    var steps: [AdditionStep] = []
    var counts: [Int] = []
    var modes: [AdditionMode] = []
    func step(_ step: AdditionStep) { steps.append(step) }
    func selected(count: Int, mode: AdditionMode) { counts.append(count); modes.append(mode) }
}
enum NSSound {
    static var beeps = 0
    static func beep() { beeps += 1 }
}
final class AdditionController {
    let pendingActions = PreviewSenderPendingActions()
    var sent = false
    var _urls = [URL(fileURLWithPath: "/existing")]
    var urls: [URL] {
        get { _urls }
        set {
__NORMALIZE__
        }
    }
    let genericView = AdditionView()
    var analyticsMediaJourney: AdditionJourney? = AdditionJourney()
    var insertAdditionUrls: (([URL], AdditionStep) -> Void)?
    let scrollAfterTransition = Atomic(value: false)
    init() {
        let scrollAfterTransition = self.scrollAfterTransition
__INSERT__
    }
}

final class AdditionTests: XCTestCase {
    override func setUp() { NSSound.beeps = 0 }
    func testNonemptyDuplicatePasteAndDropRecordOnlyUnchangedRoute() {
        for (route, expected) in [(AdditionStep.addPaste, AdditionStep.addPasteUnchanged), (.addDrop, .addDropUnchanged)] {
            let controller = AdditionController()
            let action = controller.pendingActions.capture()
            controller.insertAdditionUrls?(controller.urls + controller.urls, route)
            XCTAssertEqual(controller.analyticsMediaJourney?.steps, [expected])
            XCTAssertEqual(controller.analyticsMediaJourney?.counts, [])
            XCTAssertEqual(controller.urls.count, 1)
            XCTAssertFalse(controller.scrollAfterTransition.with { $0 })
            XCTAssertTrue(action())
        }
        XCTAssertEqual(NSSound.beeps, 2)
    }
    func testMixedNewAndDuplicateSelectionRemainsAcceptedAddition() {
        for route in [AdditionStep.addPaste, .addDrop] {
            let controller = AdditionController()
            controller.genericView.state.analyticsMode = .file
            let action = controller.pendingActions.capture()
            let new = URL(fileURLWithPath: "/new")
            controller.insertAdditionUrls?(controller.urls + [new, new], route)
            XCTAssertEqual(controller.urls.map(\.path), ["/existing", "/new"])
            XCTAssertEqual(controller.analyticsMediaJourney?.steps, [route])
            XCTAssertEqual(controller.analyticsMediaJourney?.counts, [2])
            XCTAssertEqual(controller.analyticsMediaJourney?.modes, [.file])
            XCTAssertTrue(controller.scrollAfterTransition.with { $0 })
            XCTAssertFalse(action())
        }
        XCTAssertEqual(NSSound.beeps, 0)
    }
    func testEmptyAndUnmeasuredRouteDoNotInventUnchangedStep() {
        let controller = AdditionController()
        controller.insertAdditionUrls?([], .addPaste)
        controller.insertAdditionUrls?([], .addDrop)
        controller.insertAdditionUrls?(controller.urls, .addPicker)
        XCTAssertEqual(controller.analyticsMediaJourney?.steps, [])
        XCTAssertEqual(controller.analyticsMediaJourney?.counts, [])
    }
    func testClosedCommittedAndReleasedPreviewDoNotObserveOrMutate() {
        for committed in [false, true] {
            let controller = AdditionController()
            if committed { controller.sent = true } else { controller.pendingActions.close() }
            controller.insertAdditionUrls?(controller.urls, .addPaste)
            controller.insertAdditionUrls?([URL(fileURLWithPath: "/new")], .addDrop)
            XCTAssertEqual(controller.analyticsMediaJourney?.steps, [])
            XCTAssertEqual(controller.urls.count, 1)
        }
        var controller: AdditionController? = AdditionController()
        weak var weakController = controller
        let action = controller?.insertAdditionUrls
        let journey = controller?.analyticsMediaJourney
        controller = nil
        XCTAssertNil(weakController)
        action?([URL(fileURLWithPath: "/new")], .addPaste)
        XCTAssertEqual(journey?.steps, [])
        XCTAssertEqual(NSSound.beeps, 0)
    }
    func testMissingRecorderDoesNotPreventAdditionOrDuplicateFeedback() {
        let controller = AdditionController()
        controller.analyticsMediaJourney = nil
        controller.insertAdditionUrls?(controller.urls, .addPaste)
        controller.insertAdditionUrls?([URL(fileURLWithPath: "/new")], .addDrop)
        XCTAssertEqual(NSSound.beeps, 1)
        XCTAssertEqual(controller.urls.count, 2)
    }
}
