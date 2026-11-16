import AppKit
import XCTest

final class SystemSettingsTests: XCTestCase {
    private let host = XCUIApplication(bundleIdentifier: "org.telegram.FocusSettingsCI")
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.systempreferences")
    private let titles = ["Accounts": "Focus CI Account", "Folders": "Focus CI Folder", "Chats": "Focus CI Chat"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Fixture App Group consent") { alert in
            let text = alert.debugDescription
            guard (text.contains("Telegram Focus CI") || text.contains("Telegram Focus Filters")),
                  text.localizedCaseInsensitiveContains("access data from other apps") else { return false }
            let allow = alert.buttons["Allow"]
            guard allow.exists else { return false }
            allow.click()
            return true
        }
        host.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        host.launch()
        XCTAssertTrue(host.buttons["unlock"].waitForExistence(timeout: 30), host.debugDescription)
        assertHostState("Locked")
        settings.terminate()
    }

    override func tearDownWithError() throws {
        record(settings, name: "System Settings final state")
        record(host, name: "Fixture final state")
        settings.terminate()
        host.terminate()
    }

    func testUnlockedCatalogQueries() throws {
        unlock()
        try openEditor()
        for parameter in ["Accounts", "Folders", "Chats"] {
            try openPicker(parameter)
            let title = try XCTUnwrap(titles[parameter])
            XCTAssertTrue(element(title, in: settings).waitForExistence(timeout: 20), settings.debugDescription)
            try search(title)
            XCTAssertTrue(element(title, in: settings).waitForExistence(timeout: 10), settings.debugDescription)
            click(title, in: settings)
            closePicker()
        }
        record(settings, name: "Selected account folder and chat")
    }

    func testLockedCatalogAndUnlockRecovery() throws {
        try openEditor()
        try openPicker("Accounts")
        assertLockedPicker()
        unlock()
        settings.activate()
        closePicker()
        try openPicker("Accounts")
        XCTAssertTrue(element("Focus CI Account", in: settings).waitForExistence(timeout: 20), settings.debugDescription)
    }

    func testLockingWithPickerAlreadyOpen() throws {
        unlock()
        try openEditor()
        try openPicker("Chats")
        XCTAssertTrue(element("Focus CI Chat", in: settings).waitForExistence(timeout: 20), settings.debugDescription)
        record(settings, name: "Visible chat before lock")
        let picker = try pickerSearchField()
        XCTAssertTrue(picker.isHittable, settings.debugDescription)
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("org.telegram.FocusSettingsCI.lock"), object: nil, userInfo: nil, deliverImmediately: true)
        assertHostState("Locked")
        XCTAssertEqual(settings.state, .runningForeground)
        XCTAssertTrue(picker.exists && picker.isHittable, "The existing picker closed instead of redacting its content")
        let hidden = NSPredicate { [weak self] _, _ in
            guard let self else { return false }
            return !self.element("Focus CI Chat", in: self.settings).exists
        }
        let vanished = XCTNSPredicateExpectation(predicate: hidden, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [vanished], timeout: 10), .completed,
                       "System Settings retained a chat name after Telegram locked.\n\(settings.debugDescription)")
        try search("Focus CI")
        assertLockedPicker()
    }

    private func unlock() {
        host.activate()
        host.buttons["unlock"].click()
        assertHostState("Unlocked")
    }

    private func assertHostState(_ value: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: host.staticTexts["status"])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed, host.debugDescription)
    }

    private func openEditor() throws {
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        settings.launch()
        let url = try XCTUnwrap(URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension"))
        XCTAssertTrue(NSWorkspace.shared.open(url))
        settings.activate()
        click("Do Not Disturb", in: settings, timeout: 30)
        clickContaining("Add Filter", in: settings)
        clickContaining("Telegram Focus CI", in: settings)
        XCTAssertTrue(element("Accounts", in: settings).waitForExistence(timeout: 20), settings.debugDescription)
        record(settings, name: "Focus filter editor")
    }

    private func openPicker(_ parameter: String) throws {
        let row = settings.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR identifier == %@ OR value == %@", parameter, parameter, parameter
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), settings.debugDescription)
        row.click()
        record(settings, name: "\(parameter) picker")
    }

    private func search(_ text: String) throws {
        let field = try pickerSearchField()
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    private func pickerSearchField() throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(15)
        repeat {
            for container in settings.popovers.allElementsBoundByIndex + settings.sheets.allElementsBoundByIndex {
                let fields = container.descendants(matching: .searchField).allElementsBoundByIndex.filter { $0.isHittable }
                if fields.count == 1 { return fields[0] }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        XCTFail("No unambiguous search field inside the Focus picker.\n\(settings.debugDescription)")
        throw NSError(domain: "FocusSettingsCI", code: 1)
    }

    private func closePicker() {
        if settings.buttons["Done"].exists {
            settings.buttons["Done"].click()
        } else {
            settings.typeKey(.escape, modifierFlags: [])
        }
    }

    private func assertLockedPicker() {
        let locked = settings.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open and unlock Telegram")).firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 15), settings.debugDescription)
        for title in titles.values {
            XCTAssertFalse(element(title, in: settings).exists, "Locked picker disclosed \(title)")
        }
        record(settings, name: "Locked picker")
    }

    private func element(_ title: String, in application: XCUIApplication) -> XCUIElement {
        application.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR identifier == %@ OR value == %@", title, title, title
        )).firstMatch
    }

    private func click(_ title: String, in application: XCUIApplication, timeout: TimeInterval = 20) {
        let target = element(title, in: application)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), application.debugDescription)
        target.click()
    }

    private func clickContaining(_ title: String, in application: XCUIApplication) {
        let target = application.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 20), application.debugDescription)
        target.click()
    }

    private func record(_ application: XCUIApplication, name: String) {
        let tree = XCTAttachment(string: application.debugDescription)
        tree.name = name + " accessibility tree"
        tree.lifetime = .keepAlways
        add(tree)
        guard application.state != .notRunning else { return }
        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print("FOCUS_UI_STATE \(name)\n\(application.debugDescription)")
    }
}
