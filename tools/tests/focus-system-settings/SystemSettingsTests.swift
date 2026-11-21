import AppKit
import XCTest

final class SystemSettingsTests: XCTestCase {
    private let host = XCUIApplication(bundleIdentifier: "org.telegram.FocusSettingsCI")
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.systempreferences")
    private var activeParameter = ""
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
        executionTimeAllowance = 180
        unlock()
        try openEditor()
        for parameter in ["Accounts", "Folders", "Chats"] {
            try openPicker(parameter)
            let title = try XCTUnwrap(titles[parameter])
            XCTAssertTrue(catalogItem(title).waitForExistence(timeout: 20), settings.debugDescription)
            try search("No matching Focus fixture")
            let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: catalogItem(title))
            XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 10), .completed, settings.debugDescription)
            try search(title)
            XCTAssertTrue(catalogItem(title).waitForExistence(timeout: 10), settings.debugDescription)
            catalogItem(title).click()
            closePicker()
            let selected = parameterGroup(parameter).descendants(matching: .any).matching(NSPredicate(
                format: "label BEGINSWITH %@ OR value BEGINSWITH %@", title, title
            )).firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 10), settings.debugDescription)
            XCTAssertTrue(parameterGroup(parameter).staticTexts.matching(textPredicate("1 item")).firstMatch.exists, settings.debugDescription)
        }
        record(settings, name: "Selected account folder and chat")
    }

    func testLockedCatalogAndUnlockRecovery() throws {
        try openEditor()
        try openPicker("Accounts")
        assertLockedPicker()
        let dismiss = settings.buttons["action-button-1"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10), settings.debugDescription)
        dismiss.click()
        unlock()
        settings.activate()
        try openPicker("Accounts")
        XCTAssertTrue(catalogItem("Focus CI Account").waitForExistence(timeout: 20), settings.debugDescription)
    }

    func testLockingWithPickerAlreadyOpen() throws {
        unlock()
        try openEditor()
        try openPicker("Chats")
        XCTAssertTrue(catalogItem("Focus CI Chat").waitForExistence(timeout: 20), settings.debugDescription)
        record(settings, name: "Visible chat before lock")
        let searchField = try pickerSearchField()
        XCTAssertTrue(searchField.isHittable, settings.debugDescription)
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("org.telegram.FocusSettingsCI.lock"), object: nil, userInfo: nil, deliverImmediately: true)
        assertHostState("Locked")
        XCTAssertEqual(settings.state, .runningForeground)
        XCTAssertTrue(searchField.exists && searchField.isHittable, "The existing picker closed instead of redacting its content")
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: catalogRowWithPrivateDetails)
        let result = XCTWaiter.wait(for: [hidden], timeout: 10)
        continueAfterFailure = true
        XCTAssertEqual(result, .completed, "System Settings retained a catalog name or ID after Telegram locked.\n\(settings.debugDescription)")
        continueAfterFailure = false
        XCTAssertTrue(searchField.exists && searchField.isHittable, "The picker closed before the locked search")
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
        activeParameter = parameter
        let group = parameterGroup(parameter)
        let add = group.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Add New Item")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15), settings.debugDescription)
        let editor = settings.scrollViews.containing(.group, identifier: group.identifier).firstMatch
        XCTAssertTrue(editor.exists, settings.debugDescription)
        if !editor.frame.contains(add.frame) {
            let margin = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.5))
            margin.scroll(byDeltaX: 0, deltaY: editor.frame.midY - add.frame.midY)
        }
        XCTAssertTrue(editor.frame.contains(add.frame) && add.isHittable, settings.debugDescription)
        add.click()
        record(settings, name: "\(parameter) picker")
    }

    private func search(_ text: String) throws {
        let field = try pickerSearchField()
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    private var picker: XCUIElement {
        parameterGroup(activeParameter).popovers.firstMatch
    }

    private func pickerSearchField() throws -> XCUIElement {
        let field = picker.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), settings.debugDescription)
        XCTAssertEqual(picker.searchFields.count, 1, settings.debugDescription)
        XCTAssertTrue(field.isHittable, settings.debugDescription)
        return field
    }

    private func closePicker() {
        if picker.exists {
            settings.typeKey(.escape, modifierFlags: [])
        }
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed, settings.debugDescription)
    }

    private func parameterGroup(_ parameter: String) -> XCUIElement {
        settings.groups["focusConfiguration." + parameter.lowercased()]
    }

    private func catalogItem(_ title: String) -> XCUIElement {
        picker.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func textPredicate(_ title: String) -> NSPredicate {
        NSPredicate(format: "label == %@ OR value == %@", title, title)
    }

    private var catalogRowWithPrivateDetails: XCUIElement {
        let privateDetails = Array(titles.values) + ["1042", "1043", "1044"]
        let predicates = privateDetails.map { NSPredicate(format: "label CONTAINS %@", $0) }
        return picker.buttons.matching(NSCompoundPredicate(orPredicateWithSubpredicates: predicates)).firstMatch
    }

    private func assertLockedPicker() {
        let locked = settings.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", "Open and unlock Telegram", "Open and unlock Telegram")).firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 15), settings.debugDescription)
        XCTAssertFalse(catalogRowWithPrivateDetails.exists, "Locked picker disclosed a catalog name or ID")
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
