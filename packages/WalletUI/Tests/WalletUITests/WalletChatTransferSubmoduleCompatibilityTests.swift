import XCTest
import Cocoa
import Foundation
@testable import WalletUI
@testable import SceneEffects

private enum SubmoduleArrival {
    static let climax = passTime(122.0)
    static let landing = climax - 0.08
    static let duration = landing + 1.8

    static func passTime(_ x: CGFloat) -> Double {
        let e = min(1.0, max(0.0, (Double(x) + 30.0) / 320.0))
        return 0.05 + 1.1 * (0.5 - sin(asin(1.0 - 2.0 * e) / 3.0))
    }

    static func sheenX(_ time: Double) -> CGFloat? {
        let u = (time - 0.05) / 1.1
        guard u >= 0.0, u <= 1.0 else { return nil }
        return CGFloat(-30.0 + 320.0 * u * u * (3.0 - 2.0 * u))
    }

    static func crossing(_ point: CGPoint) -> CGFloat {
        return point.x + 4.0 + 0.35 * (point.y + 4.0) - 13.7
    }

    static func lift(_ time: Double, at x: CGFloat) -> CGFloat {
        let t = time - passTime(x)
        guard t > 0.0, t < 0.8 else { return 0.0 }
        return CGFloat(sin(2.0 * .pi * 1.7 * t) * exp(-t / 0.2))
    }
}

private enum SubmoduleArrivalText {
    struct Stroke: Equatable {
        let digit: Int
        let dy: CGFloat
        let alpha: CGFloat
    }

    static func strokes(value: Int, column: Int, pitch: CGFloat, landing: Double, time: Double, integralCount: Int) -> [Stroke]? {
        func progress(_ back: Double) -> Double {
            return min(1.0, max(0.0, (time - back - 0.02) / max(landing - 0.02, 0.05)))
        }
        guard progress(0) < 0.999 else { return nil }
        var result: [Stroke] = []
        let distance = Double(value + 10 * min(column, 2))
        func position(_ back: Double) -> Double { distance * (1.0 - pow(1.0 - progress(back), 1.7)) }
        let now = position(0.0)
        let was = position(1.0 / 60.0)
        let travel = CGFloat(abs(now - was)) * pitch
        let samples = travel > 1.0 ? min(2 + Int(travel), 14) : 1
        let weights = (0 ..< samples).map { index -> CGFloat in
            guard samples > 1 else { return 1.0 }
            let q = CGFloat(index) / CGFloat(samples - 1) * 2.0 - 1.0
            return 1.0 - 0.55 * q * q
        }
        let total = weights.reduce(0, +)
        let low = Int(floor(min(now, was))) - 1
        let high = Int(ceil(max(now, was))) + 1
        for n in low ... high {
            let digit = ((n % 10) + 10) % 10
            if digit == 0 && column == 0 && integralCount > 1 && value != 0 { continue }
            for sample in 0 ..< samples {
                let q = samples > 1 ? Double(sample) / Double(samples - 1) : 1.0
                let dy = CGFloat(was + (now - was) * q - Double(n)) * pitch
                let edge = abs(dy) / (pitch * 0.58)
                let alpha = (edge >= 1 ? 0 : 1 - pow(edge, 2.2)) * weights[sample] / total
                guard alpha > 0.006 else { continue }
                result.append(Stroke(digit: digit, dy: dy, alpha: alpha))
            }
        }
        return result
    }

    static func lift(kind: Int, x: CGFloat, time: Double) -> (scale: CGFloat, dy: CGFloat) {
        let lift = SubmoduleArrival.lift(time, at: x)
        return (1.0 + (kind == 0 ? 0.1 : 0.08) * lift, (kind == 0 ? 1.2 : 0.9) * lift)
    }
}

private enum SubmoduleReceiving {
    enum State: Equatable {
        case receiving(t: Float)
        case completion(time: Float, spin: Float)
        case finished
    }

    static func state(t: Float, completionDelay: Float, rotationSpeed: Float) -> State {
        let completionTime = t - completionDelay
        if completionTime >= 1.8 {
            return .finished
        }
        if completionTime >= 0 {
            return .completion(time: completionTime, spin: (rotationSpeed < 0 ? -11 : 11) * exp(-completionTime / 0.7))
        }
        return .receiving(t: t)
    }
}

private func reflected<T>(_ subject: Any, _ label: String) -> T? {
    var mirror: Mirror? = Mirror(reflecting: subject)
    while let current = mirror {
        if let child = current.children.first(where: { $0.label == label }) {
            return child.value as? T
        }
        mirror = current.superclassMirror
    }
    return nil
}

private func reflectedIsNil(_ subject: Any, _ label: String) -> Bool {
    var mirror: Mirror? = Mirror(reflecting: subject)
    while let current = mirror {
        if let child = current.children.first(where: { $0.label == label }) {
            let value = Mirror(reflecting: child.value)
            return value.displayStyle == .optional && value.children.isEmpty
        }
        mirror = current.superclassMirror
    }
    return false
}

final class WalletChatTransferSubmoduleCompatibilityTests: XCTestCase {
    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func submoduleSource(_ path: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules").appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func assertSubmodule(_ path: String, contains snippets: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let source = try submoduleSource(path)
        for snippet in snippets {
            let normalized = snippet.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            XCTAssertTrue(source.contains(normalized), "\(path) no longer contains: \(snippet)", file: file, line: line)
        }
    }

    private static let bubblePath = "TelegramUI/Components/Chat/ChatMessageTransferBubbleContentNode/Sources/ChatMessageTransferBubbleContentNode.swift"
    private static let layerPath = "TelegramUI/Components/Premium/PremiumDiamondComponent/Sources/InteractiveDiamond/InteractiveDiamondLayer.swift"
    private static let componentPath = "TelegramUI/Components/Premium/PremiumDiamondComponent/Sources/PremiumDiamondComponent.swift"

    private func actualSource(_ path: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    func testChatHearsAboutTheFlightBeforeTheSpinLikeSubmodule() throws {
        try assertSubmodule("TelegramUI/Components/Wallet/WalletSendScreen/Sources/WalletSendScreen.swift", contains: [
            "guard let transferId, let transferAnimation = component.transferAnimation else { close() return } let revision = self.sendRevision let presentationId = \"pending:\\(transferId)\"",
            "guard self.commentSessionAvailable, UIApplication.shared.applicationState != .background, !UIAccessibility.isReduceMotionEnabled else { launch() return } controller.transferAnimationWillStart?(presentationId) let switchedFromFiat = self.inputMode == .fiat"
        ])
        try assertSubmodule("TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift", contains: [
            "allowOpenRecipientChat: false,",
            "acceptedTransferAnimation = self.walletTransferAnimationCoordinator().receive(id: id, source: source) return acceptedTransferAnimation",
            "if !acceptedTransferAnimation { self?.scrollToEndOfHistory() }",
            "controller.transferAnimationWillStart = { [weak self] id in self?.walletTransferAnimationCoordinator().prepare(id: id) }"
        ])
        try assertSubmodule("TelegramUI/Components/Wallet/WalletSendScreen/Sources/WalletSendScreen.swift", contains: [
            "guard let self, self.isVisible, self.sendRevision == revision, self.component?.walletContext === component.walletContext, controller?.peerTransferSubmission != nil else { self?.isClosingAfterRegistration = false return }",
            "guard let self, self.isVisible, self.sendRevision == revision else { self?.isClosingAfterRegistration = false return } guard self.commentSessionAvailable, UIApplication.shared.applicationState != .background, !UIAccessibility.isReduceMotionEnabled else { launch() return } spinStartedAt = CACurrentMediaTime() (self.amountField as? WalletSendAnimatedAmountField)?.spinForTransfer()"
        ])
        let send = try actualSource("packages/WalletUI/Sources/WalletUI/WalletSendController.swift")
        XCTAssertTrue(send.contains("guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { launch() return } #if arch(arm64) transferAnimationWillStart?(\"pending:\\(transferId)\") #endif let switchedFromFiat"), "the chat must hear about the flight before the spin, only when it will fly, and only where a diamond can fly")
        XCTAssertTrue(send.contains("guard let transferAnimation else { finish() return } let isFormVisible"), "a flight that will not play must not be announced")
        XCTAssertEqual(send.components(separatedBy: "transferAnimationWillStart?(").count, 2, "the flight is announced from one place only")
        XCTAssertTrue(send.contains("let launch: () -> Void = { guard isFormVisible() else { return }"), "a closed form must not launch the flight")
        XCTAssertTrue(send.contains("closure: { guard isFormVisible() else { return } guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { launch() return } #if arch(arm64) amountRowView()?.spinForTransfer()"), "a closed form must not spin, and reduced motion turned on during the switch launches without the spin")
        let chat = try actualSource("packages/ChatUI/Sources/ChatUI/ChatInputAttachView.swift")
        XCTAssertTrue(chat.contains("chatInteraction?.walletTransferAnimation?.prepare(id: id)"))
        XCTAssertTrue(chat.contains("acceptedTransferAnimation = chatInteraction?.walletTransferAnimation?.receive(id: id, source: source) ?? false return acceptedTransferAnimation"))
        XCTAssertTrue(chat.contains("if !acceptedTransferAnimation { chatInteraction?.scrollToLatest(true) }"))
        XCTAssertTrue(chat.contains("showWalletSendMoney(chatInteraction: chatInteraction, user: user, flyIntoChat: true, morphSource: { [weak self] in self?.button })"), "the attachment menu flies like the submodule's")
    }

    func testSendingFromAMessageMenuDoesNotFlyLikeSubmodule() throws {
        try assertSubmodule("TelegramUI/Sources/ChatInterfaceStateContextMenus.swift", contains: [
            "openResolved(result: .sendGrams(transfer: WalletSendRequest(recipient: recipient, amountNanograms: nil)), sourceMessageId: message.id)"
        ])
        try assertSubmodule("TelegramUI/Sources/OpenResolvedUrl.swift", contains: [
            "controller = WalletSendScreen( context: context, peer: peer, walletContext: walletContext, resolvedAddress: resolvedAddress, initialAmountNanograms: transfer.amountNanograms, completed: {",
            "chatController.scrollToEndOfHistory()"
        ])
        let menu = try actualSource("packages/ChatUI/Sources/ChatUI/ChatMessageMenuItems.swift")
        XCTAssertTrue(menu.contains("showWalletSendMoney(chatInteraction: data.chatInteraction, recipient: recipient, flyIntoChat: false)"))
        let chat = try actualSource("packages/ChatUI/Sources/ChatUI/ChatInputAttachView.swift")
        XCTAssertTrue(chat.contains("transferAnimationWillStart: !flyIntoChat ? nil :"))
        XCTAssertTrue(chat.contains("transferAnimation: !flyIntoChat ? nil :"))
    }

    func testSendDiamondSpinsOnlyWhileInTheFormLikeSubmodule() throws {
        let amount = try actualSource("packages/WalletUI/Sources/WalletUI/WalletAmountRowItem.swift")
        XCTAssertTrue(amount.contains("func spinForTransfer() { guard !hasTransferredDiamond, diamondView.window != nil else { return } diamondView.spin(walletSendTransferSpin.velocity, decay: walletSendTransferSpin.decay) }"))
    }

    private func chatCardDiamond() -> InteractiveDiamondView {
        let view = InteractiveDiamondView(frame: NSRect(x: 0.0, y: 0.0, width: 64.0, height: 64.0))
        view.update(size: NSSize(width: 64.0, height: 64.0), diamondWidth: 38.0, isVisible: true, lightBackground: false, appearance: .cool, expansionStyle: .downward, tapToSpin: true)
        view.diamondLayer.isInHierarchy = true
        return view
    }

    func testSubmoduleArrivalTimingIsStillTheCopiedOne() throws {
        try assertSubmodule(Self.bubblePath, contains: [
            "public static let climax = passTime(122.0)",
            "static let landing = climax - 0.08",
            "public static let duration = landing + 1.8",
            "let e = min(1.0, max(0.0, (Double(x) + 30.0) / 320.0)) return 0.05 + 1.1 * (0.5 - sin(asin(1.0 - 2.0 * e) / 3.0))",
            "let u = (time - 0.05) / 1.1 guard u >= 0.0, u <= 1.0 else { return nil } return CGFloat(-30.0 + 320.0 * u * u * (3.0 - 2.0 * u))",
            "return point.x + 4.0 + 0.35 * (point.y + 4.0) - 13.7",
            "guard t > 0.0, t < 0.8 else { return 0.0 } return CGFloat(sin(2.0 * .pi * 1.7 * t) * exp(-t / 0.2))"
        ])
    }

    func testArrivalTimingMatchesSubmodule() {
        XCTAssertEqual(WalletTransferArrivalAnimation.climax, SubmoduleArrival.climax, accuracy: 1e-12)
        XCTAssertEqual(WalletTransferArrivalAnimation.landing, SubmoduleArrival.landing, accuracy: 1e-12)
        XCTAssertEqual(WalletTransferArrivalAnimation.duration, SubmoduleArrival.duration, accuracy: 1e-12)
        for step in -40 ... 400 {
            let x = CGFloat(step)
            XCTAssertEqual(WalletTransferArrivalAnimation.passTime(x), SubmoduleArrival.passTime(x), accuracy: 1e-12, "pass at \(x)")
        }
        for step in 0 ... 360 {
            let time = Double(step) / 120.0
            let actual = WalletTransferArrivalAnimation.sheenX(time)
            let submodule = SubmoduleArrival.sheenX(time)
            XCTAssertEqual(actual == nil, submodule == nil, "sheen presence at \(time)")
            if let actual, let submodule {
                XCTAssertEqual(actual, submodule, accuracy: 1e-9, "sheen at \(time)")
            }
            for x in stride(from: CGFloat(-30.0), through: 300.0, by: 15.0) {
                XCTAssertEqual(WalletTransferArrivalAnimation.lift(time, at: x), SubmoduleArrival.lift(time, at: x), accuracy: 1e-12, "lift at \(time), \(x)")
            }
        }
        for point in [CGPoint(x: 0.0, y: 0.0), CGPoint(x: 108.0, y: 70.0), CGPoint(x: 216.0, y: 148.0), CGPoint(x: 37.5, y: 120.25)] {
            XCTAssertEqual(WalletTransferArrivalAnimation.crossing(point), SubmoduleArrival.crossing(point), accuracy: 1e-12)
        }
    }

    func testSubmoduleArrivalTextIsStillTheCopiedOne() throws {
        try assertSubmodule(Self.bubblePath, contains: [
            "return min(1.0, max(0.0, (self.time - back - 0.02) / max(landing - 0.02, 0.05)))",
            "if let value = glyph.value, progress(0) < 0.999 {",
            "let distance = Double(value + 10 * min(glyph.column, 2))",
            "func position(_ back: Double) -> Double { distance * (1.0 - pow(1.0 - progress(back), 1.7)) }",
            "let samples = travel > 1.0 ? min(2 + Int(travel), 14) : 1",
            "return 1.0 - 0.55 * q * q",
            "if digit == 0 && glyph.column == 0 && self.integralCount > 1 && value != 0 { continue }",
            "let alpha = (edge >= 1 ? 0 : 1 - pow(edge, 2.2)) * weights[sample] / total guard alpha > 0.006 else { continue }",
            "let edge = abs(dy) / (glyph.pitch * 0.58)",
            "pitch: isIntegral ? 17.0 : 13.2",
            "let isIntegral = CTFontGetSize(font) >= 17.0",
            "let scale = 1.0 + (glyph.kind == 0 ? 0.1 : 0.08) * lift",
            "y: bounds.midY - (glyph.kind == 0 ? 1.2 : 0.9) * lift",
            "context.drawLinearGradient(gradient, start: CGPoint(x: x - 112 - 4, y: -4), end: CGPoint(x: x + 112 - 4, y: 112 * 0.7 - 4), options: [])",
            "self.addressGradient = gradient(color: UIColor(red: 0.36, green: 0.86, blue: 1.0, alpha: 1.0), peak: 0.9) self.nameGradient = gradient(color: .white, peak: 0.25)",
            "if path === namePath { context.setBlendMode(.plusLighter) }",
            "context.setFillColor(UIColor.white.withAlphaComponent(0.06).cgColor)",
            "layer.startPoint = CGPoint(x: (x - width - 4) / self.bounds.width, y: -4 / self.bounds.height) layer.endPoint = CGPoint(x: (x + width - 4) / self.bounds.width, y: (width * 0.7 - 4) / self.bounds.height)"
        ])
    }

    func testRollingDigitsMatchSubmodule() {
        for (value, column, pitch, integralCount) in [(0, 0, CGFloat(17.0), 1), (7, 0, 17.0, 1), (4, 0, 17.0, 2), (0, 1, 17.0, 2), (9, 2, 13.2, 3), (3, 4, 13.2, 3), (1, 0, 17.0, 3)] {
            for x in [CGFloat(-20.0), 40.0, 122.0, 230.0] {
                let landing = WalletTransferArrivalAnimation.passTime(x)
                XCTAssertEqual(landing, SubmoduleArrival.passTime(x), accuracy: 1e-12)
                for step in 0 ... 260 {
                    let time = Double(step) / 120.0
                    let actual = WalletTransferArrivalAnimation.rolledDigit(value: value, column: column, pitch: pitch, landing: landing, time: time, integralCount: integralCount)
                    let expected = SubmoduleArrivalText.strokes(value: value, column: column, pitch: pitch, landing: landing, time: time, integralCount: integralCount)
                    XCTAssertEqual(actual == nil, expected == nil, "settled state for \(value) col \(column) at \(time)")
                    guard let actual, let expected else {
                        continue
                    }
                    XCTAssertEqual(actual.count, expected.count, "strokes for \(value) col \(column) at \(time)")
                    for (a, e) in zip(actual, expected) {
                        XCTAssertEqual(a.digit, e.digit)
                        XCTAssertEqual(a.offset, e.dy, accuracy: 1e-12)
                        XCTAssertEqual(a.alpha, e.alpha, accuracy: 1e-12)
                    }
                }
            }
        }
    }

    func testRollingDigitsEndOnTheirValue() {
        let landing = WalletTransferArrivalAnimation.passTime(60.0)
        let near = WalletTransferArrivalAnimation.rolledDigit(value: 7, column: 1, pitch: 17.0, landing: landing, time: landing * 0.995, integralCount: 2)!
        let strongest = near.max(by: { $0.alpha < $1.alpha })!
        XCTAssertEqual(strongest.digit, 7)
        XCTAssertNil(WalletTransferArrivalAnimation.rolledDigit(value: 7, column: 1, pitch: 17.0, landing: landing, time: landing + 0.01, integralCount: 2))
    }

    func testGlyphLiftAndSheenMatchSubmodule() {
        for step in 0 ... 300 {
            let time = Double(step) / 120.0
            for x in stride(from: CGFloat(-20.0), through: 260.0, by: 20.0) {
                for kind in [0, 1, 2] {
                    let actual = WalletTransferArrivalAnimation.glyphLift(isAmount: kind == 0, at: x, time: time)
                    let expected = SubmoduleArrivalText.lift(kind: kind, x: x, time: time)
                    XCTAssertEqual(actual.scale, expected.scale, accuracy: 1e-12)
                    XCTAssertEqual(actual.offset, expected.dy, accuracy: 1e-12)
                }
            }
            guard let x = SubmoduleArrival.sheenX(time) else {
                continue
            }
            let sheen = WalletTransferArrivalAnimation.textSheen(x: x)
            XCTAssertEqual(sheen.start, CGPoint(x: x - 112 - 4, y: -4))
            XCTAssertEqual(sheen.end, CGPoint(x: x + 112 - 4, y: 112 * 0.7 - 4))
            let size = CGSize(width: 216.0, height: 148.0)
            for width in [CGFloat(160.0), 128.0, 112.0] {
                let band = WalletTransferArrivalAnimation.cardSheenBand(x: x, width: width, size: size)
                XCTAssertEqual(band.start.x, (x - width - 4) / size.width, accuracy: 1e-12)
                XCTAssertEqual(band.start.y, -4 / size.height, accuracy: 1e-12)
                XCTAssertEqual(band.end.x, (x + width - 4) / size.width, accuracy: 1e-12)
                XCTAssertEqual(band.end.y, (width * 0.7 - 4) / size.height, accuracy: 1e-12)
            }
        }
    }

    func testFlownDiamondTakesTheAppearanceLikeSubmodule() throws {
        try assertSubmodule(Self.componentPath, contains: [
            "public func updateWalletTransfer(width: CGFloat, rotationSpeed: Float, completion: Bool, isDark: Bool, appearance: Appearance = .blue) {",
            "style.appearance = appearance"
        ])
        let view = chatCardDiamond()
        defer { view.diamondLayer.isInHierarchy = false }
        view.prepareForWalletTransfer()
        view.updateWalletTransfer(width: 40.0, rotationSpeed: 2.0, completion: false, isDark: false)
        XCTAssertEqual(view.diamondLayer.diamondStyle.appearance, .blue)
        view.updateWalletTransfer(width: 40.0, rotationSpeed: 2.0, completion: false, isDark: false, appearance: .cool)
        XCTAssertEqual(view.diamondLayer.diamondStyle.appearance, .cool)
    }

    func testLandedDiamondCalmsDownLikeSubmodule() throws {
        try assertSubmodule(Self.componentPath, contains: [
            "let returningFromFlight = self.isWalletTransfer self.isWalletTransfer = false",
            "if returningFromFlight { style.rotationSpeed = 2.0 * .pi / 26.0 let defaults = DiamondStyle() style.backgroundStars = false style.steadyStars = defaults.steadyStars style.starZoom = defaults.starZoom style.starEmission = defaults.starEmission style.burstSize = defaults.burstSize style.burstFadeInDuration = defaults.burstFadeInDuration }"
        ])
        let card = chatCardDiamond()
        defer { card.diamondLayer.isInHierarchy = false }
        let flown = InteractiveDiamondView(frame: NSRect(x: 0.0, y: 0.0, width: 96.0, height: 96.0))
        flown.update(size: NSSize(width: 96.0, height: 96.0), diamondWidth: 34.0, isVisible: true, lightBackground: true, metricsScale: 34.0 / 48.0)
        flown.diamondLayer.isInHierarchy = true
        defer { flown.diamondLayer.isInHierarchy = false }
        flown.prepareForWalletTransfer()
        flown.updateWalletTransfer(width: 52.0, rotationSpeed: 5.0, completion: false, isDark: true, appearance: .cool)
        XCTAssertEqual(flown.diamondLayer.renderSize, CGSize(width: 150.0, height: 150.0))

        flown.frame = NSRect(x: 0.0, y: 0.0, width: 64.0, height: 64.0)
        flown.update(size: NSSize(width: 64.0, height: 64.0), diamondWidth: 38.0, isVisible: true, lightBackground: false, appearance: .cool, expansionStyle: .downward, tapToSpin: true)

        let defaults = DiamondStyle()
        var expected = card.diamondLayer.diamondStyle
        expected.rotationSpeed = 2.0 * .pi / 26.0
        expected.backgroundStars = false
        expected.steadyStars = defaults.steadyStars
        expected.starZoom = defaults.starZoom
        expected.starEmission = defaults.starEmission
        expected.burstSize = defaults.burstSize
        expected.burstFadeInDuration = defaults.burstFadeInDuration
        XCTAssertEqual(flown.diamondLayer.diamondStyle, expected)
        XCTAssertEqual(flown.diamondLayer.renderSize, card.diamondLayer.renderSize)
        XCTAssertEqual(flown.diamondLayer.position, card.diamondLayer.position)

        flown.update(size: NSSize(width: 64.0, height: 64.0), diamondWidth: 38.0, isVisible: true, lightBackground: false, appearance: .cool, expansionStyle: .downward, tapToSpin: true)
        XCTAssertEqual(flown.diamondLayer.diamondStyle, expected, "a second update keeps the calm style")
    }

    func testSubmoduleReceivingIsStillTheCopiedOne() throws {
        try assertSubmodule(Self.layerPath, contains: [
            "let completionTime = t - receiving.completionDelay if completionTime >= DiamondTransferAnimation.completionDuration { self.receivingTransfer = nil self.transferAnimation = nil self.starBursts.removeAll(where: { !$0.isFromTap }) }",
            "let phase: DiamondTransferAnimation.Phase = completionTime >= 0 ? .completion : .receiving",
            "self.motion.spin((self.diamondStyle.rotationSpeed < 0 ? -11 : 11) * exp(-completionTime / 0.7), decay: 0.7) self.addStarBurst(at: self.elapsed - completionTime)",
            "if CACurrentMediaTime() - receiving.startTime >= Double(receiving.completionDelay + DiamondTransferAnimation.completionDuration) {"
        ])
        try assertSubmodule(Self.bubblePath, contains: [
            "self.cardIcon?.beginReceivingTransfer(at: startTime, completionDelay: WalletTransferArrivalAnimation.landing)"
        ])
    }

    func testReceivingDiamondMatchesSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion stops the transfer motion")
        let delay = Float(WalletTransferArrivalAnimation.landing)
        for t in [Float(0.05), 0.4, delay - 0.05, delay + 0.05, delay + 0.5, delay + 1.7, delay + 1.85, delay + 3.0] {
            let view = chatCardDiamond()
            defer { view.diamondLayer.isInHierarchy = false }
            let rotationSpeed = view.diamondLayer.diamondStyle.rotationSpeed
            view.beginReceivingTransfer(at: CACurrentMediaTime() - Double(t), completionDelay: Double(delay))
            let layer = view.diamondLayer
            let elapsed: Float = reflected(layer, "elapsed")!
            let animation: DiamondTransferAnimation? = reflected(layer, "transferAnimation")
            let motion: DiamondMotion = reflected(layer, "motion")!
            let spin: Float = reflected(motion, "spinVelocity")!
            let bursts: [DiamondStarBurst] = reflected(layer, "starBursts") ?? []
            switch SubmoduleReceiving.state(t: t, completionDelay: delay, rotationSpeed: rotationSpeed) {
            case let .receiving(expectedTime):
                let animation = try XCTUnwrap(animation, "receiving at \(t)")
                XCTAssertEqual(animation.phase, .receiving, "phase at \(t)")
                XCTAssertEqual(elapsed - animation.startTime, expectedTime, accuracy: 0.02, "receiving time at \(t)")
                XCTAssertEqual(spin, 0, "no spin before the landing at \(t)")
                XCTAssertTrue(bursts.isEmpty, "no stars before the landing at \(t)")
                XCTAssertTrue(layer.hasTransferAnimation)
            case let .completion(expectedTime, expectedSpin):
                let animation = try XCTUnwrap(animation, "completion at \(t)")
                XCTAssertEqual(animation.phase, .completion, "phase at \(t)")
                XCTAssertEqual(elapsed - animation.startTime, expectedTime, accuracy: 0.02, "completion time at \(t)")
                XCTAssertEqual(spin, expectedSpin, accuracy: abs(expectedSpin) * 0.03, "landing spin at \(t)")
                XCTAssertEqual(bursts.count, 1, "one landing burst at \(t)")
                XCTAssertEqual(bursts.first.map { elapsed - $0.startTime } ?? -1, expectedTime, accuracy: 0.02, "burst start at \(t)")
                XCTAssertTrue(layer.isCompletingTransfer)
            case .finished:
                XCTAssertNil(animation, "finished at \(t)")
                XCTAssertTrue(reflectedIsNil(layer, "receivingTransfer"), "receiving cleared at \(t)")
                XCTAssertTrue(bursts.isEmpty)
            }
        }
    }

    func testEndingAReceivedTransferMatchesSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion stops the transfer motion")
        let delay = WalletTransferArrivalAnimation.landing

        let early = chatCardDiamond()
        defer { early.diamondLayer.isInHierarchy = false }
        early.beginReceivingTransfer(at: CACurrentMediaTime() - delay - 0.3, completionDelay: delay)
        XCTAssertNotNil(reflected(early.diamondLayer, "transferAnimation") as DiamondTransferAnimation?)
        early.endReceivingTransfer()
        XCTAssertNil(reflected(early.diamondLayer, "transferAnimation") as DiamondTransferAnimation?)
        XCTAssertTrue(reflectedIsNil(early.diamondLayer, "receivingTransfer"))
        XCTAssertTrue((reflected(early.diamondLayer, "starBursts") as [DiamondStarBurst]? ?? []).isEmpty)
        let earlyMotion: DiamondMotion = reflected(early.diamondLayer, "motion")!
        XCTAssertEqual(reflected(earlyMotion, "spinVelocity") as Float?, 0, "an early end stops the landing spin")

        let late = chatCardDiamond()
        defer { late.diamondLayer.isInHierarchy = false }
        late.beginReceivingTransfer(at: CACurrentMediaTime() - 0.2, completionDelay: delay)
        XCTAssertEqual((reflected(late.diamondLayer, "transferAnimation") as DiamondTransferAnimation?)?.phase, .receiving)
        late.endReceivingTransfer()
        XCTAssertNil(reflected(late.diamondLayer, "transferAnimation") as DiamondTransferAnimation?, "ending before the landing drops the receiving phase")
        XCTAssertTrue(reflectedIsNil(late.diamondLayer, "receivingTransfer"))
    }
}
