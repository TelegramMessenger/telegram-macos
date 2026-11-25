import XCTest
import Cocoa
import Foundation
import simd
@testable import WalletUI
@testable import SceneEffects

private struct SubmoduleSendAmountIntro {
    static let duration = 1.2
    var progress: CGFloat = 1.0
    var caret: CGFloat = 1.0
    var lift: CGFloat { -48.0 * 4.0 * self.progress * (1.0 - self.progress) }
    var scale: CGFloat { 1.0 + 5.0 * pow(max(0.0, 1.0 - self.progress), 1.25) }
    var rise: CGFloat { 56.0 * (1.0 - self.progress) }

    init(time: Double?) {
        guard let time, time < Self.duration else { return }
        let t = max(time - 0.18, 0.0)
        let k = min(max((time - 0.78) / 0.2, 0.0), 1.0)
        self.caret = CGFloat(k * k * (3.0 - 2.0 * k))
        let omega = 2.0 * Double.pi / 0.9
        let a = 0.8 * omega
        let wd = omega * sqrt(1.0 - 0.8 * 0.8)
        self.progress = CGFloat(1.0 - exp(-a * t) * (cos(wd * t) + (a - 1.2) / wd * sin(wd * t)))
    }

    func finishing(_ progress: CGFloat) -> SubmoduleSendAmountIntro {
        var result = self
        result.progress += (1.0 - result.progress) * progress
        result.caret += (1.0 - result.caret) * progress
        return result
    }
}

private func submoduleOpeningText(_ opening: SubmoduleSendAmountIntro?, layoutWidth: CGFloat, gramMidX: CGFloat, left: CGFloat, right: CGFloat) -> (shift: CGFloat, alpha: CGFloat, reveal: SIMD2<Float>) {
    var shift: CGFloat = 0.0
    var alpha: CGFloat = 1.0
    var reveal = SIMD2<Float>.zero
    if let opening, opening.progress < 1.0 {
        shift = (layoutWidth / 2.0 - 64.0 - (left + right) / 2.0) * (1.0 - opening.progress)
        alpha = min(1.0, max(0.0, opening.progress) / 0.08)
        let edge = layoutWidth / 2.0 + (gramMidX - layoutWidth / 2.0) * opening.progress + 32.0
        reveal = SIMD2(Float(edge - 4.0), Float(edge + 22.0))
    }
    return (shift, alpha, reveal)
}

private func submoduleOpeningCenter(_ opening: SubmoduleSendAmountIntro?, rect: CGRect, layoutWidth: CGFloat) -> CGPoint {
    if let opening {
        return CGPoint(x: layoutWidth / 2.0 + (rect.midX - layoutWidth / 2.0) * opening.progress, y: rect.midY + opening.lift)
    } else {
        return CGPoint(x: rect.midX, y: rect.midY)
    }
}

private struct SubmoduleRise: Equatable {
    let values: [CGFloat]
    let duration: Double
}

private final class SubmoduleSendOpening {
    private static let risingViewCount = 2

    var now: Double = 0.0
    private var openingStart: CFTimeInterval?
    private(set) var openingFinished = false
    private var openingFinish: (start: CFTimeInterval, amount: SubmoduleSendAmountIntro, recipientTime: Double)?
    private var hasDisplayLink = false
    private var riseAttached = Array(repeating: false, count: risingViewCount)
    private(set) var amountCalls: [SubmoduleSendAmountIntro?] = []
    private(set) var recipientCalls: [Double?] = []
    private(set) var rises: [[SubmoduleRise]] = Array(repeating: [], count: risingViewCount)

    private func removeRiseAnimations() {
        for index in self.riseAttached.indices {
            self.riseAttached[index] = false
        }
    }

    func finishOpening(animated: Bool) {
        guard !self.openingFinished else { return }
        if animated, let start = self.openingStart, self.openingFinish == nil {
            let now = self.now
            self.openingFinish = (now, SubmoduleSendAmountIntro(time: now - start), now - start)
            self.removeRiseAnimations()
            self.updateOpening()
            return
        }
        if animated, self.openingFinish != nil { return }
        self.openingFinished = true
        self.openingFinish = nil
        self.hasDisplayLink = false
        self.amountCalls.append(nil)
        self.recipientCalls.append(nil)
        self.removeRiseAnimations()
    }

    func updateOpening() {
        guard !self.openingFinished else { return }
        let now = self.now
        if self.openingStart == nil {
            self.openingStart = now
        }
        let elapsed = self.openingStart.map { now - $0 } ?? 0.0
        var amount = SubmoduleSendAmountIntro(time: elapsed)
        var recipientTime = elapsed
        if let finish = self.openingFinish {
            let p = min(1.0, max(0.0, (now - finish.start) / 0.15))
            if p >= 1.0 { self.finishOpening(animated: false); return }
            let k = p * p * (3.0 - 2.0 * p)
            amount = finish.amount.finishing(CGFloat(k))
            recipientTime = finish.recipientTime + (2.1 - finish.recipientTime) * k
        } else if elapsed >= 2.1 {
            self.finishOpening(animated: false)
            return
        }
        self.amountCalls.append(elapsed < SubmoduleSendAmountIntro.duration || self.openingFinish != nil ? amount : nil)
        self.recipientCalls.append(recipientTime)
        if self.openingStart != nil {
            for index in self.riseAttached.indices where !self.riseAttached[index] {
                let duration = self.openingFinish.map { max(0.0, 0.15 - (now - $0.start)) }
                    ?? max(0.0, SubmoduleSendAmountIntro.duration - elapsed)
                guard duration > 0.0 else { continue }
                let samples = max(2, Int(ceil(duration * 120.0)))
                let values = (0 ... samples).map { index -> CGFloat in
                    let dt = duration * Double(index) / Double(samples)
                    if let finish = self.openingFinish {
                        let p = min(1.0, max(0.0, (now + dt - finish.start) / 0.15))
                        return finish.amount.rise * CGFloat(1.0 - p * p * (3.0 - 2.0 * p))
                    }
                    return index == samples ? 0.0 : SubmoduleSendAmountIntro(time: elapsed + dt).rise
                }
                self.rises[index].append(SubmoduleRise(values: values, duration: duration))
                self.riseAttached[index] = true
            }
            if !self.hasDisplayLink {
                self.hasDisplayLink = true
            }
        }
    }
}

private enum OpeningEvent {
    case frame(Double)
    case interrupt(Double)
    case disappear(Double)
}

private func repositoryRoot() -> URL {
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func source(_ path: String) throws -> String {
    return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
}

private func walletSubmoduleSource(_ path: String) throws -> String {
    return try source("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/" + path)
}

private func normalized(_ text: String) -> String {
    var lines: [String] = []
    for rawLine in text.components(separatedBy: "\n") {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("//") {
            continue
        }
        if let range = line.range(of: "//") {
            line = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        line = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if !line.isEmpty {
            lines.append(line)
        }
    }
    return lines.joined(separator: "\n")
}

private func stripped(_ text: String) -> String {
    return normalized(text).replacingOccurrences(of: "\\s+|;", with: "", options: .regularExpression)
}

private func block(_ signature: String, in text: String) throws -> String {
    let start = try XCTUnwrap(text.range(of: signature), "missing \(signature)")
    let open = try XCTUnwrap(text.range(of: "{", range: start.upperBound ..< text.endIndex), "no body for \(signature)")
    var depth = 0
    var index = open.lowerBound
    while index < text.endIndex {
        let character = text[index]
        if character == "{" {
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0 {
                return String(text[start.lowerBound ... index])
            }
        }
        index = text.index(after: index)
    }
    XCTFail("unbalanced \(signature)")
    return ""
}

final class WalletSendOpeningSubmoduleCompatibilityTests: XCTestCase {
    private let sendScreenPath = "WalletSendScreen/Sources/WalletSendScreen.swift"
    private let amountFieldPath = "WalletSendScreen/Sources/WalletSendAnimatedAmountField.swift"
    private let recipientPath = "WalletSendScreen/Sources/WalletSendRecipientComponent.swift"
    private let fieldScale: CGFloat = 34.0 / 48.0

    private var sampleTimes: [Double?] {
        return [nil, -0.2, 0.0] + stride(from: 0.005, through: 1.4, by: 0.0125).map { Optional($0) } + [1.19999, 1.2, 1.21, 3.0]
    }

    func testAmountIntroSourceMatchesSubmodule() throws {
        let submodule = try block("struct WalletSendAmountIntro {", in: walletSubmoduleSource(amountFieldPath))
        let actual = try block("struct WalletSendAmountIntro {", in: source("packages/WalletUI/Sources/WalletUI/WalletSendOpening.swift"))
        XCTAssertEqual(normalized(actual), normalized(submodule))
    }

    func testAmountIntroValuesMatchSubmodule() {
        XCTAssertEqual(WalletSendAmountIntro.duration, SubmoduleSendAmountIntro.duration)
        for time in sampleTimes {
            let actual = WalletSendAmountIntro(time: time)
            let submodule = SubmoduleSendAmountIntro(time: time)
            let label = "time \(String(describing: time))"
            XCTAssertEqual(actual.progress, submodule.progress, accuracy: 1e-12, label)
            XCTAssertEqual(actual.caret, submodule.caret, accuracy: 1e-12, label)
            XCTAssertEqual(actual.lift, submodule.lift, accuracy: 1e-12, label)
            XCTAssertEqual(actual.scale, submodule.scale, accuracy: 1e-12, label)
            XCTAssertEqual(actual.rise, submodule.rise, accuracy: 1e-12, label)
            for k in stride(from: 0.0, through: 1.0, by: 0.125) {
                XCTAssertEqual(actual.finishing(k).progress, submodule.finishing(k).progress, accuracy: 1e-12, label)
                XCTAssertEqual(actual.finishing(k).caret, submodule.finishing(k).caret, accuracy: 1e-12, label)
            }
        }
        XCTAssertEqual(WalletSendAmountIntro(time: 0.0).scale, 6.0, accuracy: 1e-12)
        XCTAssertEqual(WalletSendAmountIntro(time: 0.0).caret, 0.0)
        XCTAssertEqual(WalletSendAmountIntro(time: 0.5).caret, 0.0)
        XCTAssertEqual(WalletSendAmountIntro(time: 0.98).caret, 1.0, accuracy: 1e-12)
    }

    func testAmountTextOpeningMatchesSubmodule() throws {
        let field = try walletSubmoduleSource(amountFieldPath)
        for line in [
            "shift = (layout.width / 2.0 - 64.0 - (left + right) / 2.0) * (1.0 - opening.progress)",
            "alpha = min(1.0, max(0.0, opening.progress) / 0.08)",
            "let edge = layout.width / 2.0 + (layout.gram.midX - layout.width / 2.0) * opening.progress + 32.0",
            "reveal = SIMD2(Float(edge - 4.0), Float(edge + 22.0))",
            "sprite.glyph.position.x += 32.0 + shift",
            "sprite.alpha *= alpha",
            "self.updateDiamondRefraction(textOffset: shift)"
        ] {
            XCTAssertTrue(field.contains(line), line)
        }
        let layouts: [(width: CGFloat, gram: CGFloat, left: CGFloat, right: CGFloat)] = [
            (180.0, 17.0, 40.0, 150.0),
            (240.0, 17.0, 40.0, 230.0),
            (320.0, 30.0, 52.0, 300.0)
        ]
        for time in sampleTimes {
            let actualIntro = WalletSendAmountIntro(time: time)
            let submoduleIntro = SubmoduleSendAmountIntro(time: time)
            for layout in layouts {
                let label = "time \(String(describing: time)) width \(layout.width)"
                let submodule = submoduleOpeningText(submoduleIntro, layoutWidth: layout.width, gramMidX: layout.gram, left: layout.left, right: layout.right)
                let unscaled = walletSendAmountOpeningText(actualIntro, width: layout.width, gramMidX: layout.gram, textMinX: layout.left, textMaxX: layout.right, scale: 1.0)
                XCTAssertEqual(unscaled.shift, submodule.shift, accuracy: 1e-9, label)
                XCTAssertEqual(unscaled.alpha, submodule.alpha, accuracy: 1e-9, label)
                XCTAssertEqual(unscaled.reveal.x, submodule.reveal.x, accuracy: 1e-3, label)
                XCTAssertEqual(unscaled.reveal.y, submodule.reveal.y, accuracy: 1e-3, label)

                let s = fieldScale
                let scaled = walletSendAmountOpeningText(actualIntro, width: layout.width * s, gramMidX: layout.gram * s, textMinX: layout.left * s, textMaxX: layout.right * s, scale: s)
                XCTAssertEqual(scaled.shift, submodule.shift * s, accuracy: 1e-9, label)
                XCTAssertEqual(scaled.alpha, submodule.alpha, accuracy: 1e-9, label)
                if submodule.reveal != .zero {
                    XCTAssertEqual(scaled.reveal.x, (submodule.reveal.x - 32.0) * Float(s) + 32.0, accuracy: 1e-3, label)
                    XCTAssertEqual(scaled.reveal.y, (submodule.reveal.y - 32.0) * Float(s) + 32.0, accuracy: 1e-3, label)
                } else {
                    XCTAssertEqual(scaled.reveal, .zero, label)
                }
            }
        }
        XCTAssertEqual(walletSendAmountOpeningText(nil, width: 200, gramMidX: 17, textMinX: 40, textMaxX: 150, scale: fieldScale), WalletSendAmountOpeningText())
    }

    func testAmountIconOpeningMatchesSubmodule() throws {
        let field = try walletSubmoduleSource(amountFieldPath)
        let compactField = field.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        XCTAssertTrue(compactField.contains("view.center = CGPoint(x: layout.width / 2.0 + (rect.midX - layout.width / 2.0) * opening.progress, y: rect.midY + opening.lift)"))
        XCTAssertTrue(field.contains("(self.gramIcon.view as? InteractiveDiamondComponent.View)?.updateOpeningScale(self.canvas.isAvailable ? self.opening?.scale : nil)"))
        let rects = [CGRect(x: 0, y: 26, width: 96, height: 96), CGRect(x: -8, y: 20, width: 40, height: 50)]
        for time in sampleTimes {
            for rect in rects {
                let label = "time \(String(describing: time)) rect \(rect)"
                let submodule = submoduleOpeningCenter(SubmoduleSendAmountIntro(time: time), rect: rect, layoutWidth: 240.0)
                let unscaled = walletSendAmountOpeningCenter(WalletSendAmountIntro(time: time), rect: rect, width: 240.0, scale: 1.0)
                XCTAssertEqual(unscaled.x, submodule.x, accuracy: 1e-9, label)
                XCTAssertEqual(unscaled.y, submodule.y, accuracy: 1e-9, label)
                let s = fieldScale
                let scaledRect = CGRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s)
                let scaled = walletSendAmountOpeningCenter(WalletSendAmountIntro(time: time), rect: scaledRect, width: 240.0 * s, scale: s)
                XCTAssertEqual(scaled.x, submodule.x * s, accuracy: 1e-9, label)
                XCTAssertEqual(scaled.y, submodule.y * s, accuracy: 1e-9, label)
            }
        }
        let resting = walletSendAmountOpeningCenter(nil, rect: rects[0], width: 240.0, scale: fieldScale)
        XCTAssertEqual(resting, CGPoint(x: rects[0].midX, y: rects[0].midY))
    }

    private func runOpening(_ events: [OpeningEvent]) -> (actual: (amounts: [WalletSendAmountIntro?], recipients: [Double?], rises: [[SubmoduleRise]], finished: Bool), submodule: SubmoduleSendOpening) {
        var time = 0.0
        let opening = WalletSendOpening(now: { time })
        var amounts: [WalletSendAmountIntro?] = []
        var recipients: [Double?] = []
        let views = [NSView(frame: NSMakeRect(0, 0, 10, 10)), NSView(frame: NSMakeRect(0, 0, 10, 10))]
        for view in views {
            view.wantsLayer = true
        }
        opening.isReady = { true }
        opening.updateAmount = { amounts.append($0) }
        opening.updateRecipient = { recipients.append($0) }
        opening.risingViews = { views }
        var rises: [[SubmoduleRise]] = Array(repeating: [], count: views.count)
        var attached: [CAKeyframeAnimation?] = Array(repeating: nil, count: views.count)
        func collectRises() {
            for (index, view) in views.enumerated() {
                let animation = view.layer?.animation(forKey: "walletSendOpening") as? CAKeyframeAnimation
                if let animation, animation !== attached[index] {
                    XCTAssertTrue(animation.isAdditive)
                    XCTAssertEqual(animation.keyPath, "transform.translation.y")
                    XCTAssertEqual(animation.calculationMode, .linear)
                    XCTAssertNil(animation.timingFunction)
                    rises[index].append(SubmoduleRise(values: (animation.values as? [CGFloat]) ?? [], duration: animation.duration))
                }
                attached[index] = animation
            }
        }

        let submodule = SubmoduleSendOpening()
        for event in events {
            switch event {
            case let .frame(t):
                time = t
                submodule.now = t
                opening.update()
                submodule.updateOpening()
            case let .interrupt(t):
                time = t
                submodule.now = t
                opening.finish(animated: true)
                submodule.finishOpening(animated: true)
            case let .disappear(t):
                time = t
                submodule.now = t
                opening.finish(animated: false)
                submodule.finishOpening(animated: false)
            }
            collectRises()
        }
        return ((amounts, recipients, rises, opening.isFinished), submodule)
    }

    private func compareOpening(_ events: [OpeningEvent], _ name: String) {
        let result = runOpening(events)
        let actual = result.actual
        let submodule = result.submodule
        XCTAssertEqual(actual.finished, submodule.openingFinished, name)
        XCTAssertEqual(actual.amounts.count, submodule.amountCalls.count, name)
        for (index, pair) in zip(actual.amounts, submodule.amountCalls).enumerated() {
            let label = "\(name) amount call \(index)"
            XCTAssertEqual(pair.0 == nil, pair.1 == nil, label)
            if let lhs = pair.0, let rhs = pair.1 {
                XCTAssertEqual(lhs.progress, rhs.progress, accuracy: 1e-12, label)
                XCTAssertEqual(lhs.caret, rhs.caret, accuracy: 1e-12, label)
            }
        }
        XCTAssertEqual(actual.recipients.count, submodule.recipientCalls.count, name)
        for (index, pair) in zip(actual.recipients, submodule.recipientCalls).enumerated() {
            let label = "\(name) recipient call \(index)"
            XCTAssertEqual(pair.0 == nil, pair.1 == nil, label)
            if let lhs = pair.0, let rhs = pair.1 {
                XCTAssertEqual(lhs, rhs, accuracy: 1e-12, label)
            }
        }
        XCTAssertEqual(actual.rises.map(\.count), submodule.rises.map(\.count), name)
        for (viewIndex, pair) in zip(actual.rises, submodule.rises).enumerated() {
            for (riseIndex, rise) in zip(pair.0, pair.1).enumerated() {
                let label = "\(name) view \(viewIndex) rise \(riseIndex)"
                XCTAssertEqual(rise.0.duration, rise.1.duration, accuracy: 1e-12, label)
                XCTAssertEqual(rise.0.values.count, rise.1.values.count, label)
                for (lhs, rhs) in zip(rise.0.values, rise.1.values) {
                    XCTAssertEqual(lhs, rhs, accuracy: 1e-9, label)
                }
            }
        }
    }

    private func frames(from start: Double, to end: Double, step: Double = 1.0 / 120.0) -> [OpeningEvent] {
        return stride(from: start, through: end, by: step).map { .frame($0) }
    }

    func testOpeningTimelineMatchesSubmodule() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion skips the opening")
        compareOpening(frames(from: 10.0, to: 12.3), "uninterrupted")
        compareOpening(frames(from: 10.0, to: 10.45) + [.interrupt(10.452)] + frames(from: 10.46, to: 11.0), "interrupted early")
        compareOpening(frames(from: 10.0, to: 11.5) + [.interrupt(11.503)] + frames(from: 11.51, to: 12.0), "interrupted after the amount")
        compareOpening(frames(from: 10.0, to: 10.3) + [.interrupt(10.301), .interrupt(10.35)] + frames(from: 10.31, to: 10.8), "interrupted twice")
        compareOpening(frames(from: 10.0, to: 10.6) + [.disappear(10.6)] + frames(from: 10.61, to: 10.9), "left the screen")
        compareOpening([.interrupt(5.0)] + frames(from: 5.0, to: 5.2), "interrupted before the start")
        compareOpening(frames(from: 10.0, to: 10.1, step: 0.05) + frames(from: 10.9, to: 11.3, step: 0.07) + frames(from: 12.0, to: 12.2, step: 0.1), "slow frames")
    }

    func testOpeningRiseIsTheSubmoduleSpring() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "reduce motion skips the opening")
        let result = runOpening([.frame(3.0)])
        let rise = try XCTUnwrap(result.actual.rises.first?.first)
        XCTAssertEqual(rise.duration, 1.2, accuracy: 1e-12)
        XCTAssertEqual(rise.values.first ?? -1, 56.0, accuracy: 1e-9)
        XCTAssertEqual(rise.values.last ?? -1, 0.0)
        XCTAssertEqual(rise.values.count, 145)
        XCTAssertEqual(result.actual.recipients.first ?? nil, 0.0)
    }

    func testOpeningWiringMatchesSubmodule() throws {
        let screen = try walletSubmoduleSource(sendScreenPath)
        let field = try walletSubmoduleSource(amountFieldPath)
        for line in [
            "if self.openingStart == nil, self.window != nil {",
            "} else if elapsed >= 2.1 {",
            "let p = min(1.0, max(0.0, (now - finish.start) / 0.15))",
            "recipientTime = finish.recipientTime + (2.1 - finish.recipientTime) * k",
            "(self.amountField as? WalletSendAnimatedAmountField)?.updateOpening(elapsed < WalletSendAmountIntro.duration || self.openingFinish != nil ? amount : nil)",
            "let animation = CAKeyframeAnimation(keyPath: \"transform.translation.y\")",
            "let samples = max(2, Int(ceil(duration * 120.0)))",
            "return index == samples ? 0.0 : WalletSendAmountIntro(time: elapsed + dt).rise",
            "for view in [self.balanceText.view, self.sendButton.view].compactMap({ $0 })",
            "self.finishOpening(animated: true)\n            guard let feeRequest = self.currentFeeRequest else { return }"
        ] {
            XCTAssertTrue(screen.contains(line), line)
        }
        XCTAssertEqual(screen.components(separatedBy: "self.finishOpening(animated: false)").count - 1, 6)
        XCTAssertTrue(field.contains("self.textField.interactionBegan = { [weak self] in\n            self?.openingInterrupted?()"))
        XCTAssertTrue(field.contains("if expanded {\n                    self.openingInterrupted?()"))
        XCTAssertTrue(field.contains("if event?.type == .touches, self.point(inside: point, with: event) {\n            self.openingInterrupted?()"))

        let controller = try source("packages/WalletUI/Sources/WalletUI/WalletSendController.swift")
        let row = try source("packages/WalletUI/Sources/WalletUI/WalletAmountRowItem.swift")
        XCTAssertTrue(controller.contains("guard walletCanSend(state) else {\n            return\n        }\n        arguments.opening.finish(animated: true)"))
        XCTAssertTrue(controller.contains("controller.willDisappear = { _ in\n        arguments.opening.finish(animated: false)"))
        XCTAssertTrue(row.contains("inputView.interactionBegan = { [weak self] in\n            self?.currentItem?.opening.finish(animated: true)"))
        XCTAssertTrue(row.contains("if expanded {\n                self.currentItem?.opening.finish(animated: true)"))
        XCTAssertTrue(row.contains("public override func mouseDown(with event: NSEvent) {\n        currentItem?.opening.finish(animated: true)"))
        XCTAssertTrue(row.contains("needsLayout = true\n            currentItem?.opening.update()"))
    }

    func testDiamondOpeningScaleMatchesSubmodule() throws {
        let component = try source("submodules/telegram-ios/submodules/TelegramUI/Components/Premium/PremiumDiamondComponent/Sources/PremiumDiamondComponent.swift")
        let diamond = try source("packages/SceneEffects/Sources/InteractiveDiamond/InteractiveDiamondView.swift")
        XCTAssertEqual(normalized(try block("public func updateOpeningScale(", in: diamond)), normalized(try block("public func updateOpeningScale(", in: component)))
        XCTAssertTrue(component.contains("self.diamondLayer.usesHighFrameRate = expanded || self.openingScale != nil || self.diamondLayer.hasTransferAnimation"))
        XCTAssertTrue(diamond.contains("self.diamondLayer.usesHighFrameRate = expanded || self.openingScale != nil || self.diamondLayer.hasTransferAnimation"))
        XCTAssertTrue(component.contains("self.diamondLayer.interactionScale = (self.expansionStyle != .centered ? 1.0 : Float(1.0 + 2.75 * self.grip)) * Float(self.openingScale ?? 1.0)"))
        XCTAssertTrue(diamond.contains("self.diamondLayer.interactionScale = (self.expansionStyle != .centered ? 1.0 : Float(1.0 + 2.75 * self.grip)) * Float(self.openingScale ?? 1.0)"))
        XCTAssertTrue(component.contains("if self.openingScale != nil {\n                self.diamondLayer.renderSize = CGSize(width: 320.0, height: 320.0)\n            } else if self.diamondLayer.isCompletingTransfer"))

        let s = fieldScale
        let size = CGSize(width: 96 * s, height: 96 * s)
        let view = InteractiveDiamondView(frame: CGRect(origin: .zero, size: size))
        view.update(size: size, diamondWidth: 34 * s, isVisible: true, lightBackground: true, metricsScale: s)
        let resting = view.diamondLayer.renderSize
        XCTAssertFalse(view.diamondLayer.usesHighFrameRate)
        view.updateOpeningScale(WalletSendAmountIntro(time: 0.0).scale)
        XCTAssertEqual(view.diamondLayer.interactionScale, 6.0, accuracy: 1e-6)
        XCTAssertEqual(view.diamondLayer.renderSize, CGSize(width: 320 * s, height: 320 * s))
        XCTAssertTrue(view.diamondLayer.usesHighFrameRate)
        XCTAssertFalse(view.isExpanded)
        view.updateOpeningScale(WalletSendAmountIntro(time: 0.5).scale)
        XCTAssertEqual(view.diamondLayer.interactionScale, Float(SubmoduleSendAmountIntro(time: 0.5).scale), accuracy: 1e-6)
        view.updateOpeningScale(nil)
        XCTAssertEqual(view.diamondLayer.interactionScale, 1.0)
        XCTAssertEqual(view.diamondLayer.renderSize, resting)
        XCTAssertFalse(view.diamondLayer.usesHighFrameRate)

        view.updateOpeningScale(3.0)
        view.prepareForWalletTransfer()
        XCTAssertEqual(view.diamondLayer.interactionScale, 1.0)
        view.update(size: size, diamondWidth: 34 * s, isVisible: true, lightBackground: true, metricsScale: s)
        XCTAssertEqual(view.diamondLayer.interactionScale, 1.0)
        XCTAssertEqual(view.diamondLayer.renderSize, resting)
    }

    func testAmountShaderMatchesSubmodule() throws {
        let submodule = try walletSubmoduleSource("WalletSendScreen/Resources/WalletSendAmount.metal")
        let actual = try source("packages/WalletUI/Sources/WalletUI/WalletSendAmount.metal")
        XCTAssertEqual(normalized(actual), normalized(submodule))
        XCTAssertTrue(submodule.contains("alpha *= saturate((in.localX - in.reveal.x) / (in.reveal.y - in.reveal.x));"))
    }

    func testAmountCanvasRevealMatchesSubmodule() throws {
        let submodule = try walletSubmoduleSource("WalletSendScreen/Sources/WalletSendAmountCanvas.swift")
        let actual = try source("packages/WalletUI/Sources/WalletUI/WalletSendAmountCanvas.swift")
        XCTAssertEqual(normalized(try block("struct Quad {", in: actual)), normalized(try block("struct Quad {", in: submodule)))
        XCTAssertEqual(normalized(try block("func quad(", in: actual)), normalized(try block("func quad(", in: submodule)))
        let line = "let quad = renderer.quad(rect: draw.rect, uv: draw.uv, color: draw.color, viewport: viewport, threshold: draw.threshold, reveal: reveal)"
        XCTAssertTrue(submodule.contains(line))
        XCTAssertTrue(actual.contains(line))
        XCTAssertTrue(submodule.contains("func update(sprites: [WalletSendAmountSprite], isAnimating: Bool, reveal: SIMD2<Float> = .zero) {\n        self.metalLayer.reveal = reveal"))
        XCTAssertTrue(actual.contains("func update(sprites: [WalletSendAmountSprite], isAnimating: Bool, reveal: SIMD2<Float> = .zero) {\n        metalLayer.reveal = reveal"))
    }

    func testRecipientIntroMatchesSubmodule() throws {
        let submodule = try walletSubmoduleSource(recipientPath)
        let actual = try source("packages/WalletUI/Sources/WalletUI/WalletSendRecipientIntroView.swift")
        let blocks: [(String, [(String, String)])] = [
            ("private static func noise(", []),
            ("private static func start(", []),
            ("private static func path(", []),
            ("private static func passTime(", [("varlo=0.0,hi=1.0", "varlo=0.0varhi=1.0")]),
            ("private static func smooth(", []),
            ("private func random(", [
                (".utf16.first!", ".utf16.first??48"),
                ("font=Font.regular(CTFontGetSize(font))asCTFontCTFontGetGlyphsForCharacters", "font=NSFont.systemFont(ofSize:CTFontGetSize(font))asCTFont_=CTFontGetGlyphsForCharacters")
            ]),
            ("private func smear(", [("color:UIColor", "color:NSColor")]),
            ("override func draw(", [("overridefuncdraw(_rect:CGRect){guardletcontext=UIGraphicsGetCurrentContext()else{return}", "overridefuncdraw(_dirtyRect:NSRect){guardletcontext=NSGraphicsContext.current?.cgContextelse{return}")]),
            ("private func addressTiming(", []),
            ("private func drawAddress(", [("letline=self.address.count>1?self.address[1][0].origin.y-firstBaseline:CTFontGetAscent(self.font)+CTFontGetDescent(self.font)+2.0", "letline:CGFloatifself.address.count>1,letsecond=self.address[1].first{line=second.origin.y-firstBaseline}else{line=CTFontGetAscent(self.font)+CTFontGetDescent(self.font)+2.0}")]),
            ("private func putAddress(", [
                ("varfrom=column,to=column", "varfrom=columnvarto=column"),
                ("varar:CGFloat=0.0,ag:CGFloat=0.0,ab:CGFloat=0.0,aa:CGFloat=0.0varbr:CGFloat=0.0,bg:CGFloat=0.0,bb:CGFloat=0.0,ba:CGFloat=0.0self.secondary.getRed(&ar,green:&ag,blue:&ab,alpha:&aa)piece.color.getRed(&br,green:&bg,blue:&bb,alpha:&ba)letcolor=UIColor(red:ar+(br-ar)*k,green:ag+(bg-ag)*k,blue:ab+(bb-ab)*k,alpha:aa+(ba-aa)*k)", "letcolor:NSColorifk>=1.0{color=piece.color}elseifk<=0.0{color=self.secondary}else{color=self.secondary.interpolateTo(piece.color,fraction:k)??piece.color}")
            ]),
            ("private var avatarGrid:", [("varzero:UniChar=48,glyph:CGGlyph=0CTFontGetGlyphsForCharacters", "varzero:UniChar=48varglyph:CGGlyph=0_=CTFontGetGlyphsForCharacters")]),
            ("private func drawAvatar(", [("letsample=k<1.0/3.0?self.coarseAvatar:(k<2.0/3.0?self.fineAvatar:image)sample?.draw(in:self.avatarFrame)", "ifletsample=k<1.0/3.0?self.coarseAvatar:(k<2.0/3.0?self.fineAvatar:image){self.drawImage(sample,in:self.avatarFrame,context:context)}")]),
            ("private func fill(", [
                ("color:UIColor", "color:NSColor"),
                ("image.draw(in:CGRect(x:origin.x+bounds.minX,y:origin.y-bounds.maxY,width:bounds.width,height:bounds.height))", "self.drawImage(image,in:CGRect(x:origin.x+bounds.minX,y:origin.y-bounds.maxY,width:bounds.width,height:bounds.height),context:context)")
            ])
        ]
        for (signature, adaptations) in blocks {
            var expected = stripped(try block(signature, in: submodule))
            for (from, to) in adaptations {
                XCTAssertTrue(expected.contains(from), "\(signature) \(from)")
                expected = expected.replacingOccurrences(of: from, with: to)
            }
            XCTAssertEqual(stripped(try block(signature, in: actual)), expected, signature)
        }
        XCTAssertTrue(submodule.contains("private static let alphabet = Array(\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\")"))
        XCTAssertTrue(actual.contains("private static let alphabet = Array(\"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\")"))
    }

    func testRecipientSpringMatchesSubmodule() throws {
        let submodule = try walletSubmoduleSource(recipientPath)
        let row = try source("packages/WalletUI/Sources/WalletUI/WalletLinkedRecipientRowItem.swift")
        for line in [
            "let omega = 2.0 * Double.pi / 0.52",
            "let wd = omega * sqrt(1.0 - 0.36 * 0.36)",
            "let k = exp(-0.36 * omega * t) * (cos(wd * t) + 0.36 * omega / wd * sin(wd * t))",
            "self.contentView.transform = CGAffineTransform(translationX: 0.0, y: CGFloat(26.0 * k))\n                    .scaledBy(x: CGFloat(1.0 - 0.07 * k), y: CGFloat(1.0 - 0.07 * k))",
            "private var openingTime: Double? = UIAccessibility.isReduceMotionEnabled ? nil : 0.0",
            "if self.addressPhase == .revealing && self.openingTime == nil {",
            "} else if hasPeer && continuesLoading && self.openingTime == nil && !component.address.isEmpty {"
        ] {
            XCTAssertTrue(submodule.contains(line), line)
        }
        for line in [
            "let omega = 2.0 * Double.pi / 0.52",
            "let wd = omega * sqrt(1.0 - 0.36 * 0.36)",
            "let k = CGFloat(exp(-0.36 * omega * time) * (cos(wd * time) + 0.36 * omega / wd * sin(wd * time)))",
            "layer.transform = walletAmountCenteredTransform(CATransform3DScale(CATransform3DMakeTranslation(0, 26 * k, 0), 1 - 0.07 * k, 1 - 0.07 * k, 1), layer: layer)"
        ] {
            XCTAssertTrue(row.contains(line), line)
        }
        for k in stride(from: -0.4, through: 1.0, by: 0.1) {
            let submoduleTransform = CGAffineTransform(translationX: 0.0, y: CGFloat(26.0 * k)).scaledBy(x: CGFloat(1.0 - 0.07 * k), y: CGFloat(1.0 - 0.07 * k))
            let actualTransform = CATransform3DGetAffineTransform(CATransform3DScale(CATransform3DMakeTranslation(0, 26 * k, 0), 1 - 0.07 * k, 1 - 0.07 * k, 1))
            XCTAssertEqual(actualTransform.a, submoduleTransform.a, accuracy: 1e-12)
            XCTAssertEqual(actualTransform.d, submoduleTransform.d, accuracy: 1e-12)
            XCTAssertEqual(actualTransform.tx, submoduleTransform.tx, accuracy: 1e-12)
            XCTAssertEqual(actualTransform.ty, submoduleTransform.ty, accuracy: 1e-12)
        }
        let layer = CALayer()
        layer.anchorPoint = .zero
        layer.bounds = CGRect(x: 0, y: 0, width: 320, height: 60)
        let k: CGFloat = 0.6
        let centered = walletAmountCenteredTransform(CATransform3DScale(CATransform3DMakeTranslation(0, 26 * k, 0), 1 - 0.07 * k, 1 - 0.07 * k, 1), layer: layer)
        let corner = CGPoint(x: 0, y: 0).applying(CATransform3DGetAffineTransform(centered))
        let center = CGPoint(x: 160, y: 30)
        let submoduleCorner = CGPoint(x: center.x + (0 - center.x) * (1 - 0.07 * k), y: center.y + (0 - center.y) * (1 - 0.07 * k) + 26 * k)
        XCTAssertEqual(corner.x, submoduleCorner.x, accuracy: 1e-9)
        XCTAssertEqual(corner.y, submoduleCorner.y, accuracy: 1e-9)
    }

    func testTransactionInfoOpensTheWalletPageLikeSubmodule() throws {
        let submodule = try walletSubmoduleSource("WalletTransactionScreen/Sources/WalletTransactionScreen.swift")
        XCTAssertEqual(submodule.components(separatedBy: "makeWalletInfoScreen(").count - 1, 3)
        XCTAssertEqual(submodule.components(separatedBy: "mode: .wallet,\n").count - 1, 2)
        XCTAssertEqual(submodule.components(separatedBy: "mode: .firstGrams,\n").count - 1, 1)
        XCTAssertFalse(submodule.contains("mode: .gram,"))
        let actual = try source("packages/WalletUI/Sources/WalletUI/WalletTransactionController.swift")
        let showWhatsGram = try block("let showWhatsGram: ((() -> NSView?)?) -> Void = {", in: actual)
        XCTAssertTrue(showWhatsGram.contains("mode: .wallet)"))
        XCTAssertTrue(actual.contains("action: arguments.showWhatsGram)"))
        XCTAssertTrue(actual.contains("ContextMenuItem(strings().walletTransactionControllerWhatIsGram, handler: { showWhatsGram(nil) }"))
        XCTAssertEqual(macEnglishStrings()["Wallet.TransactionController.WhatIsGram"], "What is Gram?")
    }
}
