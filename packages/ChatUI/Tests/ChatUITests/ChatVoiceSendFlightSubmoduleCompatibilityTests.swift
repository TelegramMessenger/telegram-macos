import XCTest
import Cocoa
@testable import ChatUI

final class ChatVoiceSendFlightSubmoduleCompatibilityTests: XCTestCase {
    private static let transitionPath = "submodules/telegram-ios/submodules/TelegramUI/Sources/ChatMessageTransitionNode.swift"
    private static let recordingButtonPath = "submodules/telegram-ios/submodules/TelegramUI/Components/ChatTextInputMediaRecordingButton/Sources/ChatTextInputMediaRecordingButton.swift"
    private static let bubblePath = "submodules/telegram-ios/submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift"

    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func numbers(in path: String, _ pattern: String) throws -> [Double] {
        return try numbers(inText: source(path), pattern)
    }

    private func numbers(inText text: String, _ pattern: String) throws -> [Double] {
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            XCTFail("Source does not match \(pattern)")
            return []
        }
        return (1 ..< match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).flatMap { Double(text[$0]) }
        }
    }

    private func controlPoints(of function: CAMediaTimingFunction) -> [Float] {
        var result: [Float] = []
        for index in 1 ... 2 {
            var point: [Float] = [0, 0]
            function.getControlPoint(at: index, values: &point)
            result.append(contentsOf: point)
        }
        return result
    }

    private func block(in text: String, startingAt signature: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: signature))
        let open = try XCTUnwrap(text[start.lowerBound...].firstIndex(of: "{"))
        var depth = 0
        for index in text[open...].indices {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" { depth -= 1 }
            if depth == 0 { return String(text[start.lowerBound...index]) }
        }
        XCTFail("Unbalanced source block after \(signature)")
        return ""
    }

    private func calls(in text: String, named name: String) -> [String] {
        var result: [String] = []
        var remaining = text.startIndex..<text.endIndex
        while let start = text.range(of: name + "(", range: remaining) {
            var depth = 1
            var index = start.upperBound
            while index < text.endIndex && depth > 0 {
                if text[index] == "(" { depth += 1 }
                if text[index] == ")" { depth -= 1 }
                index = text.index(after: index)
            }
            guard depth == 0 else { break }
            result.append(String(text[start.lowerBound..<index]))
            remaining = index..<text.endIndex
        }
        return result
    }

    private func argument(_ name: String, in call: String) throws -> String {
        let regex = try NSRegularExpression(pattern: "\\b" + name + ":\\s*([A-Za-z0-9_.]+)")
        let match = try XCTUnwrap(regex.firstMatch(in: call, range: NSRange(call.startIndex..., in: call)))
        return String(call[try XCTUnwrap(Range(match.range(at: 1), in: call))])
    }

    func testDurationAndCurvesMatchSubmodule() throws {
        let transition = try source(Self.transitionPath)
        let bezier = try block(in: transition, startingAt: "public static let bezier: AnimationParameters =")
        let durationFunction = try block(in: transition, startingAt: "private func chatMessageTransitionAnimationDuration(_ duration: Double)")
        XCTAssertTrue(durationFunction.contains("#else return duration #endif"))
        let duration = try numbers(inText: bezier, "let duration = chatMessageTransitionAnimationDuration\\(([0-9.]+)\\)")
        XCTAssertEqual(duration, [ChatVoiceSendFlightMotion.duration])
        let vertical = try numbers(inText: bezier, "verticalControlPoints: \\(Float, Float, Float, Float\\) = \\(([0-9.]+), ([0-9.]+), ([0-9.]+), ([0-9.]+)\\)")
        let actualVertical = ChatVoiceSendFlightMotion.verticalControlPoints
        XCTAssertEqual(vertical.map { Float($0) }, [actualVertical.0, actualVertical.1, actualVertical.2, actualVertical.3])
        let horizontal = try numbers(inText: bezier, "horizontalCurve: \\.custom\\(([0-9.]+), ([0-9.]+), ([0-9.]+), ([0-9.]+)\\)")
        let actualHorizontal = ChatVoiceSendFlightMotion.horizontalControlPoints
        XCTAssertEqual(horizontal.map { Float($0) }, [actualHorizontal.0, actualHorizontal.1, actualHorizontal.2, actualHorizontal.3])
        XCTAssertEqual(controlPoints(of: ChatVoiceSendFlightMotion.timingFunction(actualVertical)), vertical.map { Float($0) })
        XCTAssertEqual(controlPoints(of: ChatVoiceSendFlightMotion.timingFunction(actualHorizontal)), horizontal.map { Float($0) })
        XCTAssertEqual(try numbers(in: Self.transitionPath, "let horizontalDuration: Double = verticalDuration let delay: Double = ([0-9.]+)"), [0.0])
    }

    func testBothAxesUseTheirOwnCurveInSubmodule() throws {
        let transition = try source(Self.transitionPath)
        let audioStart = try XCTUnwrap(transition.range(of: "case let .audioMicInput(audioMicInput):"))
        let audioEnd = try XCTUnwrap(transition.range(of: "case let .videoMessage(videoMessage):", range: audioStart.upperBound..<transition.endIndex))
        let audio = String(transition[audioStart.upperBound..<audioEnd.lowerBound])
        let decoration = try XCTUnwrap(calls(in: audio, named: "audioMicInput.micButton.animateDecorationToSentMessage").first)
        XCTAssertEqual(try argument("horizontalCurve", in: decoration), "self.parameters.horizontalCurve")
        XCTAssertEqual(try argument("verticalCurve", in: decoration), "self.parameters.verticalCurve")
        let positions = calls(in: audio, named: "self.containerNode.layer.animatePosition")
        XCTAssertEqual(positions.count, 2)
        let vertical = try XCTUnwrap(positions.first { $0.contains("from: CGPoint(x: 0.0, y:") })
        let horizontal = try XCTUnwrap(positions.first { $0.contains("from: CGPoint(x: sourceAbsoluteRect.midX") })
        XCTAssertEqual(try argument("mediaTimingFunction", in: vertical), "self.parameters.verticalCurve.mediaTimingFunction")
        XCTAssertEqual(try argument("mediaTimingFunction", in: horizontal), "self.parameters.horizontalCurve.mediaTimingFunction")
        let button = try block(in: source(Self.recordingButtonPath), startingAt: "public func animateDecorationToSentMessage(")
        let decorationPositions = calls(in: button, named: "decoration.layer.animatePosition")
        XCTAssertEqual(decorationPositions.count, 2)
        for call in decorationPositions {
            let axis = call.contains("from: CGPoint(x: 0.0, y:") ? "verticalCurve" : "horizontalCurve"
            XCTAssertEqual(try argument("mediaTimingFunction", in: call), axis + ".mediaTimingFunction")
        }
        let scale = try XCTUnwrap(calls(in: button, named: "decoration.layer.animateScale").first)
        XCTAssertEqual(try argument("mediaTimingFunction", in: scale), "verticalCurve.mediaTimingFunction")

        let horizontalTiming = ChatVoiceSendFlightMotion.timingFunction(ChatVoiceSendFlightMotion.horizontalControlPoints)
        let verticalTiming = ChatVoiceSendFlightMotion.timingFunction(ChatVoiceSendFlightMotion.verticalControlPoints)
        let x = flightAnimation(keyPath: "position", from: NSValue(point: NSPoint(x: 75, y: 0)), to: NSValue(point: .zero), duration: ChatVoiceSendFlightMotion.duration, timingFunction: horizontalTiming, additive: true)
        let y = flightAnimation(keyPath: "position", from: NSValue(point: NSPoint(x: 0, y: 120)), to: NSValue(point: .zero), duration: ChatVoiceSendFlightMotion.duration, timingFunction: verticalTiming, additive: true)
        XCTAssertEqual((x.fromValue as? NSValue)?.pointValue, NSPoint(x: 75, y: 0))
        XCTAssertEqual((y.fromValue as? NSValue)?.pointValue, NSPoint(x: 0, y: 120))
        XCTAssertEqual(x.duration, 0.3)
        XCTAssertEqual(y.duration, 0.3)
        XCTAssertTrue(x.isAdditive && y.isAdditive)
        XCTAssertEqual(controlPoints(of: try XCTUnwrap(x.timingFunction)), controlPoints(of: horizontalTiming))
        XCTAssertEqual(controlPoints(of: try XCTUnwrap(y.timingFunction)), controlPoints(of: verticalTiming))
        XCTAssertNotEqual(controlPoints(of: horizontalTiming), controlPoints(of: verticalTiming))
    }

    func testFadesMatchSubmodule() throws {
        let button = try source(Self.recordingButtonPath)
        XCTAssertTrue(button.contains("let fadeDuration = min(0.06, duration)"))
        XCTAssertTrue(button.contains("decoration.layer.allowsGroupOpacity = true decoration.layer.animateAlpha(from: 1.0, to: 0.0, duration: fadeDuration, removeOnCompletion: false"))
        let bubble = try source(Self.bubblePath)
        XCTAssertTrue(bubble.contains("statusContainerNode.contentNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.06)"))
        XCTAssertEqual(ChatVoiceSendFlightMotion.fadeDuration, 0.06)
        XCTAssertEqual(min(ChatVoiceSendFlightMotion.fadeDuration, ChatVoiceSendFlightMotion.duration), 0.06)
    }

    func testScalesMatchSubmodule() throws {
        let button = try source(Self.recordingButtonPath)
        XCTAssertTrue(button.contains("let centreDiameter = decoration.bounds.width * CGFloat(ChatRecordingBlobAppearance.centreScale)"))
        XCTAssertTrue(button.contains("let toScale = target.width / centreDiameter"))
        XCTAssertTrue(button.contains("let diameter = decoration.bounds.width * CGFloat(ChatRecordingBlobAppearance.centreScale) return (decoration, CGSize(width: diameter, height: diameter).centered(in: decoration.bounds))"))
        let bubble = try source(Self.bubblePath)
        XCTAssertTrue(bubble.contains("transition.vertical.animateTransformScale(node: statusContainerNode.contentNode, from: sourceSize.width / statusContainerNode.contentRect.width)"))

        let submoduleToScale: (CGFloat, CGFloat) -> CGFloat = { targetWidth, centreDiameter in targetWidth / centreDiameter }
        let submoduleFromScale: (CGFloat, CGFloat) -> CGFloat = { sourceWidth, contentWidth in sourceWidth / contentWidth }
        for (centre, target) in [(CGFloat(60), CGFloat(40)), (40, 40), (99, 44)] {
            XCTAssertEqual(ChatVoiceSendFlightMotion.blobScale(targetWidth: target, centreDiameter: centre), submoduleToScale(target, centre))
            XCTAssertEqual(ChatVoiceSendFlightMotion.buttonScale(sourceWidth: centre, targetWidth: target), submoduleFromScale(centre, target))
        }
    }

    func testScaleTransformKeepsTheCentre() {
        let size = NSMakeSize(100, 40)
        for scale: CGFloat in [0.1, 0.4, 1.0, 1.5, 2.25] {
            let transform = CATransform3DGetAffineTransform(ChatVoiceSendFlightMotion.scaleTransform(scale, size: size))
            let centre = CGPoint(x: 50, y: 20).applying(transform)
            XCTAssertEqual(centre.x, 50, accuracy: 1e-9)
            XCTAssertEqual(centre.y, 20, accuracy: 1e-9)
            let corner = CGPoint(x: 100, y: 40).applying(transform)
            XCTAssertEqual(corner.x, 50 + 50 * scale, accuracy: 1e-9)
            XCTAssertEqual(corner.y, 20 + 20 * scale, accuracy: 1e-9)
        }
        XCTAssertTrue(CATransform3DIsIdentity(ChatVoiceSendFlightMotion.scaleTransform(1.0, size: size)))
    }

    func testMacFlightUsesTheSubmoduleTiming() throws {
        let flight = try source("packages/ChatUI/Sources/ChatUI/ChatVoiceSendFlight.swift")
        XCTAssertEqual(flight.components(separatedBy: "timingFunction: horizontalCurve, additive: true").count - 1, 2)
        XCTAssertEqual(flight.components(separatedBy: "timingFunction: verticalCurve, additive: true").count - 1, 2)
        XCTAssertEqual(flight.components(separatedBy: "timingFunction: verticalCurve, additive: false").count - 1, 2)
        XCTAssertTrue(flight.contains("duration: min(ChatVoiceSendFlightMotion.fadeDuration, duration)"))
        XCTAssertTrue(flight.contains("layer.allowsGroupOpacity = true layer.opacity = 0"))
        XCTAssertTrue(flight.contains("from: 0.0 as NSNumber, to: 1.0 as NSNumber, duration: ChatVoiceSendFlightMotion.fadeDuration, timingFunction: CAMediaTimingFunction(name: .easeInEaseOut)"))
        XCTAssertTrue(flight.contains("NSAnimationContext.beginGrouping() NSAnimationContext.current.duration = 0 NSAnimationContext.current.timingFunction = nil NSAnimationContext.current.allowsImplicitAnimation = false if !self.start(overlay: pending.overlay, target: target, tableView: tableView) {"))
        XCTAssertTrue(flight.contains("NSAnimationContext.endGrouping() }"))
    }
}
