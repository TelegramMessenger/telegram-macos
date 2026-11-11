import XCTest
import Cocoa
import TGUIKit
import SwiftSignalKit
@testable import InputDataUI

final class InputDataModalNavigationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    func testPushAndPopTransferAppearanceCallbacksToTheVisibleForm() {
        var events: [String] = []
        let root = InputDataController(dataSignal: .single(.init(entries: [])), title: "Providers", hasDone: false)
        let child = InputDataController(dataSignal: .single(.init(entries: [])), title: "API Key", hasDone: false)
        for (name, controller) in [("root", root), ("child", child)] {
            controller.willAppear = { _ in events.append("\(name).willAppear") }
            controller.didAppear = { _ in events.append("\(name).didAppear") }
            controller.willDisappear = { _ in events.append("\(name).willDisappear") }
            controller.didDisappear = { _ in events.append("\(name).didDisappear") }
        }
        let modal = InputDataModalController(root)
        _ = modal.view
        modal.viewWillAppear(false)
        modal.viewDidAppear(false)
        events.removeAll()

        let appeared = expectation(description: "Child form appeared")
        child.didAppear = { _ in
            events.append("child.didAppear")
            appeared.fulfill()
        }
        modal.push(child, animated: false)
        wait(for: [appeared], timeout: 2)
        XCTAssertEqual(events, ["root.willDisappear", "child.willAppear", "root.didDisappear", "child.didAppear"])

        events.removeAll()
        modal.pop(animated: false)
        XCTAssertTrue(modal.current === root)
        XCTAssertEqual(events, ["child.willDisappear", "root.willAppear", "child.didDisappear", "root.didAppear"])
    }
}
