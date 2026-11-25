import XCTest
import Cocoa
@testable import ChatUI

private enum SubmoduleFlight {
    static func frame(now: CFTimeInterval, startedAt: CFTimeInterval, sourceCenter: CGPoint, sourceWidth: CGFloat, slotCenter: CGPoint, slotWidth: CGFloat) -> (center: CGPoint, width: CGFloat, speed: Float, cool: Bool, t: Double) {
        let t = min(1.0, max(0.0, now - startedAt) / 0.62)
        let deltaY = slotCenter.y - sourceCenter.y
        let rise = 56.0 + max(0.0, -deltaY)
        let b = -2.0 * rise - 2.0 * sqrt(max(0.0, rise * rise + rise * deltaY))
        let center = CGPoint(
            x: sourceCenter.x + (slotCenter.x - sourceCenter.x) * t,
            y: sourceCenter.y + b * t + (deltaY - b) * t * t
        )
        let width = (sourceWidth + (slotWidth - sourceWidth) * t)
            * (1.0 + 0.28 * sin(.pi * min(1.0, t / 0.75)))
        let speed = Float(2.0 * .pi / 26.0 + (5.0 - 2.0 * .pi / 26.0) * min(1.0, t / 0.6))
        return (center, width, speed, t > 0.5, t)
    }

    static func landing() -> [(scale: Double, offset: Double)] {
        let duration = 1.2
        let count = Int(duration * 120.0)
        let impact = (0 ... count).map { index -> Double in
            let time = duration * Double(index) / Double(count)
            return index == count ? 0.0 : sin(2.0 * .pi * 2.2 * time) * exp(-time / 0.2)
        }
        return impact.map { (1.0 - 0.025 * $0, 4.0 * $0) }
    }
}

private enum SubmoduleArrivalCard {
    static func presentation(t: Double, finish: Double, rise: Bool, height: CGFloat) -> (scale: CGFloat, y: CGFloat, alpha: CGFloat) {
        let bounce = finish > 0 && finish < 1.2 ? -sin(2 * .pi * 2 * finish) * exp(-finish / 0.25) : 0
        let scale: CGFloat
        let y: CGFloat
        let alpha: CGFloat
        if rise {
            let spring = t < 0.8 ? 1 - exp(-9 * t) * (cos(13 * t) + 9.0 / 13.0 * sin(13 * t)) : 1
            scale = CGFloat(0.86 + 0.14 * spring) * CGFloat(1 + 0.045 * bounce)
            y = CGFloat(70 * (1 - spring)) + (1 - scale) * height * 0.5
            alpha = CGFloat(min(1, t / 0.12))
        } else {
            let pop = t < 1.2 ? 0.05 * sin(2 * .pi * 1.8 * t) * exp(-t / 0.22) : 0
            scale = CGFloat((1 + pop) * (1 + 0.045 * bounce))
            y = 0
            alpha = 1
        }
        return (scale, y, alpha)
    }

    static func ribbon(finish: Double, pivot: CGPoint, center: CGPoint) -> (transform: CGAffineTransform, alpha: CGFloat, textAlpha: CGFloat) {
        let tau = 0.08, w = 2 * Double.pi * 1.6
        let length = 1 - exp(-finish / tau) * (cos(w * finish) + sin(w * finish) / (tau * w))
        let width = 1 - pow(1 - min(1, finish / 0.3), 2.2)
        let transform = CGAffineTransform(translationX: pivot.x - center.x, y: pivot.y - center.y)
            .rotated(by: .pi / 4).scaledBy(x: CGFloat(max(0.001, length)), y: CGFloat(0.2 + 0.8 * width))
            .rotated(by: -.pi / 4).translatedBy(x: center.x - pivot.x, y: center.y - pivot.y)
        let alpha = CGFloat(min(1, max(0, length * 4)))
        return (transform, alpha, alpha * CGFloat(min(1, max(0, (length - 0.6) / 0.35))))
    }
}

final class ChatWalletTransferSubmoduleCompatibilityTests: XCTestCase {
    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func assertSource(_ path: String, contains snippets: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let text = try source(path)
        for snippet in snippets {
            let normalized = snippet.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            XCTAssertTrue(text.contains(normalized), "\(path) does not contain: \(snippet)", file: file, line: line)
        }
    }

    private func block(_ path: String, startingAt signature: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let text = try source(path)
        let normalized = signature.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard let start = text.range(of: normalized), let open = text[start.lowerBound...].firstIndex(of: "{") else {
            XCTFail("\(path) does not contain: \(signature)", file: file, line: line)
            return ""
        }
        var depth = 0
        var index = open
        while index < text.endIndex {
            if text[index] == "{" {
                depth += 1
            } else if text[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start.lowerBound ... index])
                }
            }
            index = text.index(after: index)
        }
        XCTFail("\(path) has an unbalanced block after: \(signature)", file: file, line: line)
        return ""
    }

    private func occurrences(of snippet: String, in text: String) -> Int {
        let normalized = snippet.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.components(separatedBy: normalized).count - 1
    }

    private static let coordinatorPath = "submodules/telegram-ios/submodules/TelegramUI/Sources/ChatWalletTransferAnimation.swift"
    private static let bubblePath = "submodules/telegram-ios/submodules/TelegramUI/Components/Chat/ChatMessageTransferBubbleContentNode/Sources/ChatMessageTransferBubbleContentNode.swift"
    private static let bubbleItemPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift"
    private static let historyListPath = "submodules/telegram-ios/submodules/TelegramUI/Sources/ChatHistoryListNode.swift"
    private static let chatControllerPath = "packages/ChatUI/Sources/ChatUI/ChatController.swift"
    private static let serviceItemPath = "packages/ChatUI/Sources/ChatUI/ChatServiceItem.swift"
    private static let transferAnimationPath = "packages/ChatUI/Sources/ChatUI/ChatWalletTransferAnimation.swift"

    private func assertTransform(_ actual: CGAffineTransform, _ expected: CGAffineTransform, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (a, b) in [(actual.a, expected.a), (actual.b, expected.b), (actual.c, expected.c), (actual.d, expected.d), (actual.tx, expected.tx), (actual.ty, expected.ty)] {
            XCTAssertEqual(a, b, accuracy: 1e-9, message, file: file, line: line)
        }
    }

    func testSubmoduleFlightIsStillTheCopiedOne() throws {
        try assertSource(Self.coordinatorPath, contains: [
            "let t = min(1.0, max(0.0, now - (flight.startedAt ?? now)) / 0.62)",
            "let deltaY = slot.center.y - source.center.y let rise = 56.0 + max(0.0, -deltaY) let b = -2.0 * rise - 2.0 * sqrt(max(0.0, rise * rise + rise * deltaY))",
            "y: source.center.y + b * t + (deltaY - b) * t * t",
            "let width = (source.width + (slot.width - source.width) * t) * (1.0 + 0.28 * sin(.pi * min(1.0, t / 0.75)))",
            "let speed = Float(2.0 * .pi / 26.0 + (5.0 - 2.0 * .pi / 26.0) * min(1.0, t / 0.6))",
            "appearance: t > 0.5 ? .cool : .blue",
            "if now - flight.createdAt >= 1.5 { self.cancel(id: id, animated: true) }",
            "if flight.startedAt != nil || now - flight.createdAt >= 0.5 { self.cancel(id: id, animated: true)",
            "target.acceptTransferDiamond(diamond)"
        ])
        try assertSource(Self.bubblePath, contains: [
            "diamond.updateTransferState(isSending: true, animateCompletion: false) diamond.spin(4.5, decay: 0.7)",
            "let duration = 1.2 let count = Int(duration * 120.0)",
            "return index == count ? 0.0 : sin(2.0 * .pi * 2.2 * time) * exp(-time / 0.2)",
            "scale.values = impact.map { 1.0 - 0.025 * $0 }",
            "offset.values = impact.map { 4.0 * $0 }"
        ])
    }

    func testFlightMatchesSubmodule() {
        XCTAssertEqual(ChatWalletTransferFlightMotion.duration, 0.62)
        XCTAssertEqual(ChatWalletTransferFlightMotion.cardTimeout, 0.5)
        XCTAssertEqual(ChatWalletTransferFlightMotion.handOverTimeout, 1.5)
        let routes: [(CGPoint, CGFloat, CGPoint, CGFloat)] = [
            (CGPoint(x: 640.0, y: 420.0), 24.0, CGPoint(x: 480.0, y: 610.0), 38.0),
            (CGPoint(x: 300.0, y: 700.0), 34.0, CGPoint(x: 520.0, y: 180.0), 38.0),
            (CGPoint(x: 500.0, y: 300.0), 78.0, CGPoint(x: 500.0, y: 300.0), 38.0)
        ]
        let start: CFTimeInterval = 1000.0
        for (origin, sourceWidth, target, targetWidth) in routes {
            for step in -2 ... 90 {
                let now = start + Double(step) / 120.0
                let expected = SubmoduleFlight.frame(now: now, startedAt: start, sourceCenter: origin, sourceWidth: sourceWidth, slotCenter: target, slotWidth: targetWidth)
                let t = ChatWalletTransferFlightMotion.progress(now: now, start: start)
                XCTAssertEqual(Double(t), expected.t, accuracy: 1e-9, "progress at \(step)")
                let center = ChatWalletTransferFlightMotion.center(origin: origin, target: target, t: t)
                XCTAssertEqual(center.x, expected.center.x, accuracy: 1e-9, "x at \(step)")
                XCTAssertEqual(center.y, expected.center.y, accuracy: 1e-9, "y at \(step)")
                XCTAssertEqual(ChatWalletTransferFlightMotion.width(sourceWidth: sourceWidth, targetWidth: targetWidth, t: t), expected.width, accuracy: 1e-9, "width at \(step)")
                XCTAssertEqual(ChatWalletTransferFlightMotion.rotationSpeed(t: t), expected.speed, accuracy: 1e-6, "speed at \(step)")
                XCTAssertEqual(ChatWalletTransferFlightMotion.usesCardAppearance(t: t), expected.cool, "appearance at \(step)")
            }
        }
    }

    func testFlightRisesAboveTheSourceFirst() {
        let origin = CGPoint(x: 640.0, y: 420.0)
        let target = CGPoint(x: 480.0, y: 610.0)
        let peak = (0 ... 100).map { ChatWalletTransferFlightMotion.center(origin: origin, target: target, t: CGFloat($0) / 100.0).y }.min()!
        XCTAssertEqual(peak, origin.y - 56.0, accuracy: 0.5, "the arc tops out 56pt above the start when the card is lower")
    }

    func testLandingBounceMatchesSubmodule() {
        let expected = SubmoduleFlight.landing()
        XCTAssertEqual(ChatWalletTransferFlightMotion.landingDuration, 1.2)
        let count = Int(ChatWalletTransferFlightMotion.landingDuration * 120)
        XCTAssertEqual(count + 1, expected.count)
        for index in 0 ... count {
            let actual = ChatWalletTransferFlightMotion.landing(at: ChatWalletTransferFlightMotion.landingDuration * Double(index) / Double(count), isLast: index == count)
            XCTAssertEqual(Double(actual.scale), expected[index].scale, accuracy: 1e-9, "scale at \(index)")
            XCTAssertEqual(Double(actual.offset), expected[index].offset, accuracy: 1e-9, "offset at \(index)")
        }
    }

    func testSubmoduleArrivalIsStillTheCopiedOne() throws {
        try assertSource(Self.bubblePath, contains: [
            "let bounce = finish > 0 && finish < 1.2 ? -sin(2 * .pi * 2 * finish) * exp(-finish / 0.25) : 0",
            "let spring = t < 0.8 ? 1 - exp(-9 * t) * (cos(13 * t) + 9.0 / 13.0 * sin(13 * t)) : 1",
            "scale = CGFloat(0.86 + 0.14 * spring) * CGFloat(1 + 0.045 * bounce)",
            "y = CGFloat(70 * (1 - spring)) + (1 - scale) * self.mediaContainerNode.bounds.height * 0.5",
            "self.mediaContainerNode.alpha = CGFloat(min(1, t / 0.12))",
            "let pop = t < 1.2 ? 0.05 * sin(2 * .pi * 1.8 * t) * exp(-t / 0.22) : 0",
            "scale = CGFloat((1 + pop) * (1 + 0.045 * bounce))",
            "let tau = 0.08, w = 2 * Double.pi * 1.6",
            "let length = 1 - exp(-finish / tau) * (cos(w * finish) + sin(w * finish) / (tau * w))",
            "let width = 1 - pow(1 - min(1, finish / 0.3), 2.2)",
            "let pivot = CGPoint(x: 200, y: 24)",
            "self.ribbonBackgroundNode.alpha = CGFloat(min(1, max(0, length * 4)))",
            "self.ribbonTextContainerNode.alpha = self.ribbonBackgroundNode.alpha * CGFloat(min(1, max(0, (length - 0.6) / 0.35)))",
            "if finish >= 0.6 && !self.arrivalDidGlint {",
            "self.cardBackgroundRotationAnimation = BackgroundRotationAnimation(duration: 1.8, turns: 2)"
        ])
        try assertSource(Self.coordinatorPath, contains: [
            "if let previousStart = self.lastArrivalStartTime, now - previousStart < 0.9 { continue }",
            "for arrival in self.arrivals.values.sorted(by: { $0.message.index < $1.message.index }) {",
            "if now - startTime >= WalletTransferArrivalAnimation.duration { self.cancelArrival(id) }"
        ])
        try assertSource(Self.bubblePath, contains: [
            "public static let duration = landing + 1.8"
        ])
    }

    func testArrivalCardMotionMatchesSubmodule() {
        let landing = 0.05 + 1.1 * (0.5 - sin(asin(1.0 - 2.0 * min(1.0, max(0.0, (122.0 + 30.0) / 320.0))) / 3.0)) - 0.08
        for rise in [true, false] {
            for height in [CGFloat(156.0), 190.0] {
                for step in 0 ... 480 {
                    let t = Double(step) / 120.0
                    let finish = t - landing
                    let expected = SubmoduleArrivalCard.presentation(t: t, finish: finish, rise: rise, height: height)
                    let actual = ChatWalletTransferArrivalMotion.card(time: t, finish: finish, rise: rise, height: height)
                    XCTAssertEqual(actual.scale, expected.scale, accuracy: 1e-12, "scale at \(t), rise \(rise)")
                    XCTAssertEqual(actual.offset, expected.y, accuracy: 1e-12, "y at \(t), rise \(rise)")
                    XCTAssertEqual(actual.opacity, expected.alpha, accuracy: 1e-12, "alpha at \(t), rise \(rise)")
                }
            }
        }
    }

    func testRibbonUnfurlMatchesSubmodule() {
        let ribbonOrigin = CGPoint(x: 4.0 + 216.0 - 54.8 + 2.0, y: 4.0 - 2.0)
        let ribbonCenter = CGPoint(x: ribbonOrigin.x + 54.8 / 2.0, y: ribbonOrigin.y + 54.8 / 2.0)
        let submodulePivot = CGPoint(x: 200.0, y: 24.0)
        let actualPivot = CGPoint(x: 200.0 - ribbonOrigin.x, y: 24.0 - ribbonOrigin.y)
        let actualCenter = CGPoint(x: 54.8 / 2.0, y: 54.8 / 2.0)
        for step in 0 ... 240 {
            let finish = Double(step) / 120.0
            let expected = SubmoduleArrivalCard.ribbon(finish: finish, pivot: submodulePivot, center: ribbonCenter)
            let ribbon = ChatWalletTransferArrivalMotion.ribbon(finish: finish)
            let transform = ChatWalletTransferArrivalMotion.ribbonTransform(length: ribbon.length, width: ribbon.width, pivot: actualPivot, center: actualCenter)
            assertTransform(transform, expected.transform, "ribbon at \(finish)")
            let alpha = ChatWalletTransferArrivalMotion.ribbonAlpha(length: ribbon.length)
            XCTAssertEqual(alpha, expected.alpha, accuracy: 1e-12, "ribbon alpha at \(finish)")
            XCTAssertEqual(alpha * ChatWalletTransferArrivalMotion.ribbonTextAlpha(length: ribbon.length), expected.textAlpha, accuracy: 1e-12, "text alpha at \(finish)")
        }
    }

    func testArrivalQueueMatchesSubmodule() {
        XCTAssertEqual(ChatWalletTransferArrivalMotion.spacing, 0.9)
        XCTAssertEqual(ChatWalletTransferArrivalMotion.afterLanding, 1.8)
        XCTAssertEqual(ChatWalletTransferArrivalMotion.glintDelay, 0.6)
    }

    func testCardGeometryMatchesSubmodule() throws {
        XCTAssertEqual(ChatServiceItem.WalletTransferData.cardSize, NSSize(width: 216.0, height: 148.0))
        XCTAssertEqual(ChatServiceItem.WalletTransferData.outerInset, 4.0)
        try assertSource(Self.bubblePath, contains: [
            "let cardSize = CGSize(width: 216.0, height: 148.0)",
            "private static let imageSize = CGSize(width: 54.800781, height: 54.800766)",
            "origin: CGPoint(x: cardFrame.maxX - ribbonSize.width + 2.0, y: cardFrame.minY - 2.0),"
        ])
    }

    private func rawBlock(_ path: String, startingAt signature: String) throws -> String {
        let text = try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
        let start = try XCTUnwrap(text.range(of: signature))
        let open = try XCTUnwrap(text[start.lowerBound...].firstIndex(of: "{"))
        var depth = 0
        for index in text[open...].indices {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" { depth -= 1 }
            if depth == 0 { return String(text[start.lowerBound...index]) }
        }
        throw NSError(domain: "UnbalancedSubmoduleFixture", code: 1)
    }

    private func executeSubmoduleFixture(_ source: String) throws -> [String: Bool] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChatWalletCompatibility-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("main.swift")
        let binary = directory.appendingPathComponent("fixture")
        try source.write(to: input, atomically: true, encoding: .utf8)
        func run(_ executable: URL, _ arguments: [String]) throws -> Data {
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                XCTFail(String(data: data, encoding: .utf8) ?? "Fixture failed")
                throw NSError(domain: "SubmoduleFixtureFailed", code: Int(process.terminationStatus))
            }
            return data
        }
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("ChatWalletCompatibilityModuleCache")
        _ = try run(URL(fileURLWithPath: "/usr/bin/xcrun"), ["swiftc", "-module-cache-path", cache.path, input.path, "-o", binary.path])
        return try XCTUnwrap(JSONSerialization.jsonObject(with: run(binary, [])) as? [String: Bool])
    }

    func testSubmoduleTransferCardAcceptsSwipeToReply() throws {
        let shouldBegin = try rawBlock(Self.bubbleItemPath, startingAt: "replyRecognizer.shouldBegin =")
        let fixture = """
        import Foundation
        enum Action { case phoneCall, conferenceCall, gramTransfer, other }
        class TelegramMediaAction { let action: Action; init(_ action: Action) { self.action = action } }
        class TelegramMediaExpiredContent {}
        enum ReplyAction { case none, reply }
        class View { func convert(_ point: CGPoint, to view: View) -> CGPoint { point } }
        class ContentNode { let view = View(); var claimed = false; func claimsHorizontalDrag(at point: CGPoint) -> Bool { claimed } }
        struct MessageId { let peerId: Int }
        class Message { var media: [Any] = []; let id = MessageId(peerId: 1) }
        struct Content { let firstMessage: Message }
        struct Thread { let isChannelPost: Bool; let peerId: Int }
        enum Location { case peer, replyThread(Thread) }
        class Interaction { var canReply = true; func canSetupReply(_ message: Message) -> ReplyAction { canReply ? .reply : .none } }
        class Item {
            let message = Message(); var content: Content { Content(firstMessage: message) }
            let controllerInteraction = Interaction(); var chatLocation = Location.peer
        }
        class Recognizer { var shouldBegin: (() -> Bool)?; func location(in view: View) -> CGPoint { CGPoint(x: 0, y: 0) } }
        class Node {
            var item: Item? = Item(); var selectionNode: Int?; let view = View(); let contentNodes = [ContentNode()]
            var currentSwipeAction = ReplyAction.none; let recognizer = Recognizer()
            func configure() { let replyRecognizer = self.recognizer; \(shouldBegin) }
        }
        func permitted(_ media: [Any], canReply: Bool = true, selected: Bool = false, claimed: Bool = false, foreignPost: Bool = false) -> Bool {
            let node = Node(); node.item?.message.media = media; node.item?.controllerInteraction.canReply = canReply
            node.selectionNode = selected ? 1 : nil; node.contentNodes[0].claimed = claimed
            if foreignPost { node.item?.chatLocation = .replyThread(Thread(isChannelPost: true, peerId: 2)) }
            node.configure(); return node.recognizer.shouldBegin?() ?? false
        }
        let values: [String: Bool] = [
            "transfer": permitted([TelegramMediaAction(.gramTransfer)]),
            "phone": permitted([TelegramMediaAction(.phoneCall)]),
            "conference": permitted([TelegramMediaAction(.conferenceCall)]),
            "otherService": permitted([TelegramMediaAction(.other)]),
            "expired": permitted([TelegramMediaExpiredContent()]),
            "replyDenied": permitted([TelegramMediaAction(.gramTransfer)], canReply: false),
            "selection": permitted([TelegramMediaAction(.gramTransfer)], selected: true),
            "claimedDrag": permitted([TelegramMediaAction(.gramTransfer)], claimed: true),
            "foreignChannelPost": permitted([TelegramMediaAction(.gramTransfer)], foreignPost: true)
        ]
        print(String(data: try! JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]), encoding: .utf8)!)
        """
        XCTAssertEqual(try executeSubmoduleFixture(fixture), ["transfer": true, "phone": true, "conference": true, "otherService": false, "expired": false, "replyDenied": false, "selection": false, "claimedDrag": false, "foreignChannelPost": false])
        let gesture = try block(Self.bubbleItemPath, startingAt: "@objc private func swipeToReplyGesture(_ recognizer: ChatSwipeToReplyRecognizer) {")
        XCTAssertEqual(occurrences(of: "gestureRecognized = translation.x < -swipeOffset", in: gesture), 1)
        XCTAssertEqual(occurrences(of: "case .reply: item.controllerInteraction.setupReply(item.message.id)", in: gesture), 1)
    }

    func testOnlyTransferCardsAmongServiceRowsStartSwipeToReply() throws {
        let swipe = try block(Self.chatControllerPath, startingAt: "self.context.window.add(swipe: { [weak self] direction, _ -> SwipeHandlerResult in")
        let gate = "if let item = item as? ChatServiceItem, item.walletTransferData == nil { return .failed }"
        XCTAssertEqual(occurrences(of: gate, in: swipe), 1)
        let gateIndex = try XCTUnwrap(swipe.range(of: gate)).lowerBound
        let replyCheckIndex = try XCTUnwrap(swipe.range(of: "if !item.isSharable {")).lowerBound
        let revealIndex = try XCTUnwrap(swipe.range(of: "(item.view as? RevealTableView)?.initRevealState()")).lowerBound
        XCTAssertLessThan(gateIndex, replyCheckIndex)
        XCTAssertLessThan(replyCheckIndex, revealIndex)
    }

    func testTransferCardRowRevealsTheMessageRowReplyAction() throws {
        try assertSource(Self.serviceItemPath, contains: [
            "public class ChatServiceRowView: TableRowView, RevealTableView {"
        ])
        let initReveal = try block(Self.serviceItemPath, startingAt: "public func initRevealState() {")
        XCTAssertEqual(occurrences(of: "control.update(item: item)", in: initReveal), 1)
        XCTAssertEqual(occurrences(of: "control.centerY(x: ChatRowView.revealActionInset)", in: initReveal), 1)
        let move = try block(Self.serviceItemPath, startingAt: "public func moveReveal(delta: CGFloat) {")
        XCTAssertEqual(occurrences(of: "let progress = min(1, max(0, -delta / ChatRowView.replyRevealThreshold))", in: move), 1)
        let complete = try block(Self.serviceItemPath, startingAt: "public func completeReveal(direction: SwipeDirection) {")
        XCTAssertEqual(occurrences(of: "if case .right = direction, -delta >= ChatRowView.replyRevealThreshold { _ = (item as? ChatRowItem)?.replyAction() }", in: complete), 1)
        let layout = try block(Self.serviceItemPath, startingAt: "public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) { super.updateLayout(size: size, transition: transition) guard let item = item as? ChatServiceItem else {")
        XCTAssertEqual(occurrences(of: "let offset: CGFloat = (item.entry.additionalData.monoforumState == .vertical ? 40 : 0) + swipeOffset", in: layout), 1)
        XCTAssertEqual(occurrences(of: "transition.updateFrame(view: reactionsView, frame: reactionsRect(item).offsetBy(dx: swipeOffset, dy: 0))", in: layout), 1)
        XCTAssertEqual(occurrences(of: "if #available(macOS 10.15, *), let view = walletTransferView { transition.updateFrame(view: view, frame: view.centerFrameX(y: textView.frame.maxY + item.walletTransferSpacing).offsetBy(dx: offset, dy: 0))", in: layout), 1)
    }

    private func assertOrder(_ snippets: [String], in text: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        var previous: String.Index?
        for snippet in snippets {
            let normalized = snippet.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard let range = text.range(of: normalized) else {
                XCTFail("\(message): missing \(snippet)", file: file, line: line)
                return
            }
            if let previous {
                XCTAssertLessThan(previous, range.lowerBound, "\(message): \(snippet) is out of order", file: file, line: line)
            }
            previous = range.lowerBound
        }
    }

    func testSubmoduleIncomingVisibilityIsStillTheCopiedOne() throws {
        let visibility = try block(Self.bubblePath, startingAt: "private func updateIncomingTransferVisibility() {")
        assertOrder([
            "guard let item = self.item, self.isIncomingTransfer, self.cardNode.bounds.width > 0 else { return }",
            "if state == nil, isUnread, self.canPlayIncomingTransferAnimation { item.controllerInteraction.requestWalletTransferArrival?(item.message) state = item.controllerInteraction.walletTransferArrivalState?(item.message.id) }",
            "if UIAccessibility.isReduceMotionEnabled { self.finishIncomingTransferAnimation() return }",
            "case let .queued(rise): self.prepareIncomingTransferAnimation(rise: rise)",
            "case let .playing(startTime, rise): self.prepareIncomingTransferAnimation(rise: rise) self.updateIncomingTransferAnimation(startTime: startTime, rise: rise, at: CACurrentMediaTime())",
            "case .finished: self.finishIncomingTransferAnimation()",
            "if isUnread, item.controllerInteraction.requestWalletTransferArrival != nil, self.cardIcon?.isExpanded != true { self.prepareIncomingTransferAnimation(rise: item.controllerInteraction.freshWalletTransferMessageIds.contains(item.message.id)) } else { self.finishIncomingTransferAnimation() }"
        ], in: visibility, "submodule incoming visibility")
        try assertSource(Self.bubblePath, contains: [
            "override public func unreadMessageRangeUpdated() { self.updateIncomingTransferVisibility() }"
        ])
        try assertSource(Self.historyListPath, contains: [
            "if self.canReadHistoryValue { self.forEachVisibleMessageItemNode { itemNode in itemNode.unreadMessageRangeUpdated() } }"
        ])
        let eligibility = try rawBlock(Self.coordinatorPath, startingAt: "private var canPlayArrivals: Bool")
        let request = try rawBlock(Self.coordinatorPath, startingAt: "func requestArrival(_ message: EngineRawMessage)")
        let fixture = """
        import Foundation
        struct MessageId: Hashable { let peerId: Int; let namespace: Int; let id: Int }
        struct UnreadMessageRangeKey: Hashable { let peerId: Int; let namespace: Int }
        struct Flags: OptionSet { let rawValue: Int; static let Incoming = Flags(rawValue: 1) }
        struct EngineRawMessage { let id: MessageId; var flags: Flags = [.Incoming] }
        enum Subject { case regular, previewing }
        enum Mode { case standard(Subject) }
        class Interaction {
            var unreadMessageRange = [UnreadMessageRangeKey(peerId: 1, namespace: 0): 1...99]
            var freshWalletTransferMessageIds = Set<MessageId>()
        }
        class Controller { var walletTransferAnimationsVisible = true; var canReadHistoryValue = true; var mode = Mode.standard(.regular); let controllerInteraction = Interaction() }
        enum UIAccessibility { static var isReduceMotionEnabled = false }
        struct Arrival { let message: EngineRawMessage; let rise: Bool }
        class Coordinator {
            var controller: Controller? = Controller(); var isApplicationActive = true
            var seenArrivals = Set<MessageId>(); var arrivals: [MessageId: Arrival] = [:]; var displayLinkRequests = 0
            func ensureDisplayLink() { displayLinkRequests += 1 }
            \(eligibility)
            \(request)
        }
        let message = EngineRawMessage(id: MessageId(peerId: 1, namespace: 0, id: 42))
        func queued(_ configure: (Coordinator) -> Void) -> Bool { let value = Coordinator(); configure(value); value.requestArrival(message); return value.arrivals[message.id] != nil }
        var values: [String: Bool] = [
            "readableVisible": queued { _ in },
            "inactive": queued { $0.isApplicationActive = false },
            "hidden": queued { $0.controller?.walletTransferAnimationsVisible = false },
            "unreadable": queued { $0.controller?.canReadHistoryValue = false },
            "preview": queued { $0.controller?.mode = .standard(.previewing) },
            "readMessage": queued { $0.controller?.controllerInteraction.unreadMessageRange = [:] },
            "alreadySeen": queued { $0.seenArrivals.insert(message.id) },
            "missingController": queued { $0.controller = nil }
        ]
        let becomingReadable = Coordinator(); becomingReadable.controller?.canReadHistoryValue = false
        becomingReadable.requestArrival(message)
        values["unreadableDoesNotConsume"] = becomingReadable.seenArrivals.isEmpty
        becomingReadable.controller?.canReadHistoryValue = true; becomingReadable.requestArrival(message)
        values["queuesAfterReadable"] = becomingReadable.arrivals[message.id] != nil
        UIAccessibility.isReduceMotionEnabled = true
        let reduced = Coordinator(); reduced.requestArrival(message)
        values["reducedMotionSeen"] = reduced.seenArrivals.contains(message.id)
        values["reducedMotionNoAnimation"] = reduced.arrivals.isEmpty && reduced.displayLinkRequests == 0
        print(String(data: try! JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]), encoding: .utf8)!)
        """
        XCTAssertEqual(try executeSubmoduleFixture(fixture), ["readableVisible": true, "inactive": false, "hidden": false, "unreadable": false, "preview": false, "readMessage": false, "alreadySeen": false, "missingController": false, "unreadableDoesNotConsume": true, "queuesAfterReadable": true, "reducedMotionSeen": true, "reducedMotionNoAnimation": true])
    }

    func testSubmoduleUnreadRangesArePublishedBeforeLayout() throws {
        let history = try source(Self.historyListPath)
        XCTAssertEqual(occurrences(of: "var unreadMessageRangeUpdated = false", in: history), 1)
        assertOrder([
            "var unreadMessageRangeUpdated = false",
            "let completion: (Bool, ListViewDisplayedItemRange) -> Void = { [weak self] wasTransformed, visibleRange in",
            "if unreadMessageRangeUpdated {"
        ], in: history, "submodule unread ranges")
    }

    func testIncomingVisibilityPreparesBeforeItCanPlay() throws {
        let visibility = try block(Self.serviceItemPath, startingAt: "func updateIncomingTransferVisibility() {")
        assertOrder([
            "guard let item, let message = item.message, isIncomingTransfer, frame.width > 0, let animation = item.chatInteraction.walletTransferAnimation else { return }",
            "if state == nil, canPlayIncomingTransferAnimation { animation.requestArrival(message) state = animation.arrivalState(message.id) }",
            "if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { finishIncomingTransferAnimation() return }",
            "case let .queued(rise): prepareIncomingTransferAnimation(rise: rise)",
            "case let .playing(startTime, rise): prepareIncomingTransferAnimation(rise: rise) updateIncomingTransferAnimation(startTime: startTime, rise: rise, at: CACurrentMediaTime())",
            "case .finished: finishIncomingTransferAnimation()",
            "case nil: if let rise = animation.arrivalRise(message), !cardView.isDiamondExpanded { prepareIncomingTransferAnimation(rise: rise) } else { finishIncomingTransferAnimation() }"
        ], in: visibility, "incoming visibility")
        XCTAssertEqual(occurrences(of: "animation.requestArrival(message)", in: visibility), 1)
        let canPlay = try block(Self.serviceItemPath, startingAt: "var canPlayIncomingTransferAnimation: Bool {")
        XCTAssertEqual(occurrences(of: "guard isIncomingTransfer, let window, window.isKeyWindow, NSApp.isActive, frame.width > 0, let item, let table = item.table else { return false }", in: canPlay), 1)
        XCTAssertEqual(occurrences(of: "return NSLocationInRange(item.index, table.visibleRows()) && !cardView.isDiamondExpanded", in: canPlay), 1)
    }

    func testArrivalRequestAndPreparationShareOneRule() throws {
        let rise = try block(Self.transferAnimationPath, startingAt: "func arrivalRise(_ message: Message) -> Bool? {")
        XCTAssertEqual(occurrences(of: "let rise = message.timestamp >= self.openTimestamp", in: rise), 1)
        XCTAssertEqual(occurrences(of: "guard !self.seenArrivals.contains(message.id), message.flags.contains(.Incoming), isUnread || rise else { return nil }", in: rise), 1)
        XCTAssertEqual(occurrences(of: "insert", in: rise), 0, "the shared rule must not mark the arrival as seen")
        let request = try block(Self.transferAnimationPath, startingAt: "func requestArrival(_ message: Message) {")
        assertOrder([
            "guard let rise = self.arrivalRise(message) else { return }",
            "self.seenArrivals.insert(message.id)",
            "guard !self.reduceMotion else { return }",
            "self.arrivals[message.id] = Arrival(id: message.id, index: message.index, rise: rise)"
        ], in: request, "arrival request")
    }

    func testIncomingCardsAreCheckedAgainWhenTheChatBecomesReadable() throws {
        let animation = try source(Self.transferAnimationPath)
        let initializer = try block(Self.transferAnimationPath, startingAt: "init(chatInteraction: ChatInteraction, tableView: TableView) {")
        XCTAssertEqual(occurrences(of: "self?.updateVisibleIncomingTransfers()", in: initializer), 2, "scroll and app activation")
        XCTAssertEqual(occurrences(of: "self.updateVisibleIncomingTransfers()", in: initializer), 1, "window activation")
        assertOrder([
            "center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil, using: { [weak self] notification in guard let self, let window = self.tableView?.window, notification.object as? NSWindow === window else { return } self.updateVisibleIncomingTransfers() })",
            "center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil, using: { [weak self] _ in self?.updateVisibleIncomingTransfers() })"
        ], in: initializer, "activation observers")
        XCTAssertEqual(occurrences(of: "private func updateVisibleIncomingTransfers() { for view in self.transferViews(visibleOnly: true) { view.updateIncomingTransferVisibility() } }", in: animation), 1)
        let teardown = try block(Self.transferAnimationPath, startingAt: "deinit {")
        XCTAssertEqual(occurrences(of: "for observer in self.activityObservers { NotificationCenter.default.removeObserver(observer) }", in: teardown), 1)
    }

    func testReadStatesArePublishedBeforeTheTableMerge() throws {
        let apply = try block(Self.chatControllerPath, startingAt: "func applyTransition(_ transition:TableUpdateTransition, initialData:ChatHistoryCombinedInitialData, isLoading: Bool, processedView: ChatHistoryView) {")
        assertOrder([
            "chatInteraction.walletTransferAnimation?.updateOpenReadStates(processedView.originalView?.fixedReadStates)",
            "genericView.tableView.merge(with: transition, appearAnimated: appearAnimated)"
        ], in: apply, "read states before rows")
    }

    func testSubmoduleRibbonLabelFitIsStillTheCopiedOne() throws {
        try assertSource(Self.bubblePath, contains: [
            "font: Font.semibold(11.0), textColor: .white, paragraphAlignment: .center ), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),",
            "let ribbonTextMaxWidth: CGFloat = 52.0 if ribbonTextLayout.size.width > ribbonTextMaxWidth {",
            "font: Font.semibold(11.0 * ribbonTextMaxWidth / ribbonTextLayout.size.width),"
        ])
    }

    func testRibbonLabelFitMatchesSubmodule() throws {
        let ribbon = try block(Self.serviceItemPath, startingAt: "private func chatWalletTransferRibbonText(_ text: String) -> CGImage? {")
        assertOrder([
            "let maxWidth: CGFloat = 52",
            "NSFont.semibold(11)",
            "let width = ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))",
            "if width > maxWidth {",
            "NSFont.semibold(11 * maxWidth / width)",
            "let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)"
        ], in: ribbon, "ribbon label fit")
        for text in ["sent", "received"] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]))
            XCTAssertLessThanOrEqual(ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))), 52, "\(text) keeps its 11pt size")
        }
    }
}
