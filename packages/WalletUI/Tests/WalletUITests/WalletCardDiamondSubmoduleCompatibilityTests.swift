import XCTest
import Cocoa
import SceneEffects
@testable import WalletUI

private func submoduleWalletCardDiamondLayout(scale: CGFloat, balanceScale: CGFloat, integralTextSize: CGSize) -> (icon: CGRect, balanceOriginX: CGFloat, diamond: CGRect, diamondWidth: CGFloat, leftInset: CGFloat) {
    let balanceOriginX = 20.0 * scale
    let balanceContentScale = scale * balanceScale
    let gramIconSize = CGSize(width: 30.0 * balanceContentScale, height: 30.0 * balanceContentScale)
    let gramIconSpacing = gramIconSize.width + 3.25 * balanceContentScale
    let integralSize = CGSize(
        width: gramIconSpacing + integralTextSize.width,
        height: max(gramIconSize.height, integralTextSize.height)
    )
    let mainCenterY = 94.0 * scale
    let integralOriginY = floor(mainCenterY - integralSize.height * 0.5)
    let integralFrame = CGRect(origin: CGPoint(x: balanceOriginX, y: integralOriginY), size: integralSize)
    let primaryBalanceBaseFrame = integralFrame
    let gramIconContentFrame = CGRect(
        origin: CGPoint(
            x: integralFrame.minX - primaryBalanceBaseFrame.minX - balanceContentScale,
            y: mainCenterY - primaryBalanceBaseFrame.minY - gramIconSize.height * 0.5 - 3.0 * balanceContentScale
        ),
        size: gramIconSize
    )
    let diamondSize = CGSize(width: 96.0 * balanceContentScale, height: 96.0 * balanceContentScale)
    let diamondFrame = CGRect(
        x: primaryBalanceBaseFrame.minX + gramIconContentFrame.midX - diamondSize.width * 0.5,
        y: primaryBalanceBaseFrame.minY + gramIconContentFrame.midY - diamondSize.height * 0.5,
        width: diamondSize.width,
        height: diamondSize.height
    )
    return (
        gramIconContentFrame.offsetBy(dx: primaryBalanceBaseFrame.minX, dy: primaryBalanceBaseFrame.minY),
        integralFrame.minX + gramIconSpacing,
        diamondFrame,
        26.0 * 1.09 * 0.8 * balanceContentScale,
        primaryBalanceBaseFrame.minX + gramIconContentFrame.midX - 14.0 * scale * balanceScale
    )
}

private struct SubmoduleWalletCardSway {
    private static let maxYaw = 0.30

    var diamondRotation: Double?
    private var previousDiamondRotation: Double?
    private(set) var diamondRate = 0.0
    private(set) var diamondRoll = 0.0

    private static func clamp(_ value: Double, _ limit: Double) -> Double {
        return max(-limit, min(limit, value))
    }

    mutating func tick(deltaTime: Double, reduceMotion: Bool) {
        if !reduceMotion, let rotation = self.diamondRotation {
            if let previousRotation = self.previousDiamondRotation {
                let delta = atan2(sin(rotation - previousRotation), cos(rotation - previousRotation))
                self.diamondRate += (delta / deltaTime - self.diamondRate) * min(1.0, deltaTime * 3.0)
            }
            self.previousDiamondRotation = rotation
        } else {
            self.previousDiamondRotation = nil
            self.diamondRate = 0.0
        }
        let baseSpin = 2.0 * Double.pi / 26.0
        let extraSpin = self.diamondRate - baseSpin * (self.diamondRate >= 0.0 ? 1.0 : -1.0)
        let rollTarget = Self.clamp(
            0.006 * (abs(self.diamondRate) > baseSpin * 1.5 ? extraSpin : 0.0), Self.maxYaw * 0.18
        )
        self.diamondRoll += (rollTarget - self.diamondRoll) * (1.0 - exp(-deltaTime * 2.5))
    }
}

private func submoduleCardScrollTransform(fraction: CGFloat, reduceMotion: Bool) -> CATransform3D {
    let cardCollapsedScale: CGFloat = 0.19
    let cardCollapsedPitch: CGFloat = .pi / 3.0
    var transform = CATransform3DIdentity
    if !reduceMotion {
        let pitchFraction = fraction * (2.0 - fraction)
        let pitch = cardCollapsedPitch * pitchFraction
        transform.m34 = -fraction / 650.0
        transform = CATransform3DRotate(transform, pitch, 1.0, 0.0, 0.0)
    }
    let scale = 1.0 + (cardCollapsedScale - 1.0) * fraction
    transform = CATransform3DScale(transform, scale, scale, 1.0)
    return transform
}

private func submoduleDiamondTilt(pitch: CGFloat, roll: CGFloat, scrollTransform: CATransform3D) -> (pitch: CGFloat, roll: CGFloat) {
    let followsCardTilt = CATransform3DIsIdentity(scrollTransform)
    return (followsCardTilt ? pitch : 0.0, followsCardTilt ? roll : 0.0)
}

final class WalletCardDiamondSubmoduleCompatibilityTests: XCTestCase {
    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func submoduleCard() throws -> String {
        let url = repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletCardComponent/Sources/WalletCardComponent.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testSubmoduleCardStillUsesTheCopiedRules() throws {
        let source = try submoduleCard()
        for line in [
            "let balanceOriginX = 20.0 * scale",
            "let balanceContentScale = scale * balanceScale",
            "let gramIconSize = CGSize(width: 30.0 * balanceContentScale, height: 30.0 * balanceContentScale)",
            "let gramIconSpacing = gramIconSize.width + 3.25 * balanceContentScale",
            "var mainOriginX = balanceOriginX",
            "x: integralFrame.minX - primaryBalanceBaseFrame.minX - balanceContentScale,",
            "y: mainCenterY - primaryBalanceBaseFrame.minY - gramIconSize.height * 0.5 - 3.0 * balanceContentScale",
            "let diamondSize = CGSize(width: 96.0 * balanceContentScale, height: 96.0 * balanceContentScale)",
            "diamondWidth: 26.0 * 1.09 * 0.8 * balanceContentScale,",
            "appearance: .white,",
            "expansionStyle: .wallet,",
            "tapToSpin: true",
            "x: self.primaryBalanceBaseFrame.minX + self.gramIconContentFrame.midX,",
            "leftInset: diamondCenter.x - 14.0 * scale * self.primaryBalanceScale,",
            "let followsCardTilt = CATransform3DIsIdentity(self.scrollTransform)",
            "pitch: (followsCardTilt ? CGFloat(cardPitch) : 0.0) - self.styleGemV.value * 0.22 / 2.8,",
            "roll: (followsCardTilt ? CGFloat(self.currentCardY) : 0.0) + self.styleGemH.value * 0.33 / 2.6,",
            "self.diamondRate += (delta / deltaTime - self.diamondRate) * min(1.0, deltaTime * 3.0)",
            "0.006 * (abs(self.diamondRate) > baseSpin * 1.5 ? extraSpin : 0.0), Self.maxYaw * 0.18",
            "self.diamondRoll += (rollTarget - self.diamondRoll) * (1.0 - exp(-deltaTime * 2.5))",
            "let cardTargetY = Self.clamp(self.panRoll + self.diamondRoll, Self.maxYaw)",
            "private static let maxYaw = 0.30",
            "let textViews = [self.integralBalance.view, self.fractionalBalance.view, self.currency.view].compactMap { $0 }"
        ] {
            XCTAssertTrue(source.contains(line), line)
        }
    }

    func testDiamondLayoutMatchesSubmodule() {
        for scale: CGFloat in [0.8, 336.0 / 370.0, 1.0, 1.25] {
            for balanceScale: CGFloat in [1.0, 0.83, 0.55] {
            let actual = WalletCardDiamondLayout(scale: scale, balanceScale: balanceScale)
            for textHeight: CGFloat in [26.0, 34.0] {
                let expected = submoduleWalletCardDiamondLayout(scale: scale, balanceScale: balanceScale, integralTextSize: CGSize(width: 64.0 * scale * balanceScale, height: textHeight * scale * balanceScale))
                let label = "scale \(scale) balance \(balanceScale) text \(textHeight)"
                XCTAssertEqual(actual.gramIconFrame.minX, expected.icon.minX, accuracy: 1e-9, label)
                XCTAssertEqual(actual.gramIconFrame.minY, expected.icon.minY, accuracy: 1e-9, label)
                XCTAssertEqual(actual.gramIconFrame.width, expected.icon.width, accuracy: 1e-9, label)
                XCTAssertEqual(actual.gramIconFrame.height, expected.icon.height, accuracy: 1e-9, label)
                XCTAssertEqual(actual.balanceOriginX, expected.balanceOriginX, accuracy: 1e-9, label)
                XCTAssertEqual(actual.diamondFrame.minX, expected.diamond.minX, accuracy: 1e-9, label)
                XCTAssertEqual(actual.diamondFrame.minY, expected.diamond.minY, accuracy: 1e-9, label)
                XCTAssertEqual(actual.diamondFrame.width, expected.diamond.width, accuracy: 1e-9, label)
                XCTAssertEqual(actual.diamondFrame.height, expected.diamond.height, accuracy: 1e-9, label)
                XCTAssertEqual(actual.diamondWidth, expected.diamondWidth, accuracy: 1e-9, label)
                XCTAssertEqual(actual.leftInset, expected.leftInset, accuracy: 1e-9, label)
            }
            }
        }
        XCTAssertEqual(WalletCardDiamondLayout(scale: 0.9).gramIconFrame, WalletCardDiamondLayout(scale: 0.9, balanceScale: 1.0).gramIconFrame)
    }

    private func captures(_ pattern: String, in source: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let match = try XCTUnwrap(regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)), pattern)
        return try (1 ..< match.numberOfRanges).map { index in
            try String(source[XCTUnwrap(Range(match.range(at: index), in: source), pattern)])
        }
    }

    func testCardDiamondSizeAndLookFollowSubmodule() throws {
        let submodule = try captures("InteractiveDiamondComponent\\(\\s*size: diamondSize,\\s*diamondWidth: ([0-9.* ]+?) \\* balanceContentScale,[^)]*?appearance: \\.(\\w+),\\s*expansionStyle: \\.wallet,", in: submoduleCard())
        let factors = submodule[0].split(separator: "*").map { $0.trimmingCharacters(in: .whitespaces) }
        let widthPerScale = try factors.reduce(1.0) { try $0 * XCTUnwrap(Double($1), submodule[0]) }
        XCTAssertEqual(factors.count, 3, submodule[0])
        for scale: CGFloat in [0.8, 336.0 / 370.0, 360.0 / 370.0, 1.0, 1.25] {
            for balanceScale: CGFloat in [1.0, 0.7] {
                XCTAssertEqual(WalletCardDiamondLayout(scale: scale, balanceScale: balanceScale).diamondWidth, CGFloat(widthPerScale) * scale * balanceScale, accuracy: 1e-9, "scale \(scale) balance \(balanceScale)")
            }
        }

        let card = try String(contentsOf: repositoryRoot().appendingPathComponent("packages/WalletUI/Sources/WalletUI/WalletCardView.swift"), encoding: .utf8)
        let actualWallet = try captures("gramDiamondView\\.update\\(size: diamondLayout\\.diamondFrame\\.size, diamondWidth: diamondLayout\\.diamondWidth, [^\\n]*?appearance: \\.(\\w+), expansionStyle: \\.wallet, tapToSpin: true\\)", in: card)
        XCTAssertEqual(actualWallet[0], submodule[1])

        let bubble = try String(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Chat/ChatMessageTransferBubbleContentNode/Sources/ChatMessageTransferBubbleContentNode.swift"), encoding: .utf8)
        let submoduleChat = try captures("theme: item\\.presentationData\\.theme\\.theme, appearance: \\.(\\w+),", in: bubble)
        let actualChat = try captures("gramDiamondView\\.update\\(size: NSMakeSize\\(walletChatCardDiamondCanvas, walletChatCardDiamondCanvas\\), [^\\n]*?appearance: \\.(\\w+), expansionStyle: \\.downward", in: card)
        XCTAssertEqual(actualChat[0], submoduleChat[0])
        XCTAssertNotEqual(submodule[1], submoduleChat[0])

        let component = try String(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Premium/PremiumDiamondComponent/Sources/PremiumDiamondComponent.swift"), encoding: .utf8)
        let enumBody = try captures("public enum Appearance: UInt32, CaseIterable, Sendable \\{([^}]*)\\}", in: component)[0]
        let submoduleCases = try NSRegularExpression(pattern: "case (\\w+) = (\\d+)").matches(in: enumBody, range: NSRange(enumBody.startIndex..., in: enumBody)).map { match in
            (String(enumBody[Range(match.range(at: 1), in: enumBody)!]), UInt32(enumBody[Range(match.range(at: 2), in: enumBody)!])!)
        }
        XCTAssertEqual(submoduleCases.map(\.0), InteractiveDiamondView.Appearance.allCases.map { String(describing: $0) })
        XCTAssertEqual(submoduleCases.map(\.1), InteractiveDiamondView.Appearance.allCases.map(\.rawValue))
    }

    private func flingRotation(at time: Double, flingStart: Double, velocity: Double, decay: Double) -> Double {
        let baseSpin = 2.0 * Double.pi / 26.0
        let rotation = baseSpin * time
        guard time > flingStart else {
            return rotation
        }
        let elapsed = time - flingStart
        return rotation + velocity / decay * (1.0 - exp(-decay * elapsed))
    }

    private func assertSwayMatchesSubmodule(velocity: Double, decay: Double, file: StaticString = #filePath, line: UInt = #line) -> (maxRoll: Double, finalRoll: CGFloat, wasActiveBeforeFling: Bool) {
        let frame = 1.0 / 60.0
        var actual = WalletCardDiamondSway()
        var submodule = SubmoduleWalletCardSway()
        var maxRoll = 0.0
        var wasActiveBeforeFling = false
        for index in 0 ..< 60 * 8 {
            let time = Double(index) * frame
            let rotation = flingRotation(at: time, flingStart: 1.0, velocity: velocity, decay: decay)
            submodule.diamondRotation = rotation
            submodule.tick(deltaTime: frame, reduceMotion: false)
            actual.update(rotation: CGFloat(rotation), at: time)
            actual.step(deltaTime: CGFloat(frame))
            XCTAssertEqual(Double(actual.rate), submodule.diamondRate, accuracy: 1e-9, "frame \(index)", file: file, line: line)
            XCTAssertEqual(Double(actual.roll), submodule.diamondRoll, accuracy: 1e-4, "frame \(index)", file: file, line: line)
            maxRoll = max(maxRoll, abs(submodule.diamondRoll))
            if index > 30 && time < 1.0 {
                wasActiveBeforeFling = wasActiveBeforeFling || actual.isActive
            }
        }
        return (maxRoll, actual.roll, wasActiveBeforeFling)
    }

    func testFastSpinSwaysTheCardLikeSubmodule() {
        let right = assertSwayMatchesSubmodule(velocity: 16.0, decay: 1.1)
        XCTAssertFalse(right.wasActiveBeforeFling)
        XCTAssertGreaterThan(right.maxRoll, 0.02)
        XCTAssertLessThanOrEqual(right.maxRoll, 0.30 * 0.18)
        XCTAssertEqual(right.finalRoll, 0)

        let left = assertSwayMatchesSubmodule(velocity: -16.0, decay: 1.1)
        XCTAssertFalse(left.wasActiveBeforeFling)
        XCTAssertGreaterThan(left.maxRoll, 0.02)
        XCTAssertLessThanOrEqual(left.maxRoll, 0.30 * 0.18)

        let gentle = assertSwayMatchesSubmodule(velocity: 0.1, decay: 1.1)
        XCTAssertEqual(gentle.maxRoll, 0)
        XCTAssertEqual(gentle.finalRoll, 0)
    }

    func testSwayStopsWhenTheDiamondStopsLikeSubmodule() {
        var actual = WalletCardDiamondSway()
        var submodule = SubmoduleWalletCardSway()
        for index in 0 ..< 30 {
            let time = Double(index) / 60.0
            let rotation = 12.0 * time
            submodule.diamondRotation = rotation
            submodule.tick(deltaTime: 1.0 / 60.0, reduceMotion: false)
            actual.update(rotation: CGFloat(rotation), at: time)
            actual.step(deltaTime: 1.0 / 60.0)
        }
        XCTAssertTrue(actual.isActive)
        submodule.diamondRotation = nil
        submodule.tick(deltaTime: 1.0 / 60.0, reduceMotion: false)
        actual.update(rotation: nil, at: 0.5)
        actual.step(deltaTime: 1.0 / 60.0)
        XCTAssertEqual(Double(actual.rate), submodule.diamondRate)
        XCTAssertEqual(Double(actual.roll), submodule.diamondRoll, accuracy: 1e-9)
        actual.reset()
        XCTAssertFalse(actual.isActive)
        XCTAssertEqual(actual.roll, 0)
    }

    func testSubmoduleScrollTransformStillUsesTheCopiedRules() throws {
        let source = try String(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletScreen/Sources/WalletScreen.swift"), encoding: .utf8)
        for line in [
            "private let cardCollapsedScale: CGFloat = 0.19",
            "private let cardCollapsedPitch: CGFloat = .pi / 3.0",
            "let pitchFraction = fraction * (2.0 - fraction)",
            "transform.m34 = -fraction / 650.0",
            "scale: 1.0 + (self.cardCollapsedScale - 1.0) * fraction"
        ] {
            XCTAssertTrue(source.contains(line), line)
        }
    }

    func testDiamondTiltStopsWhileTheCardScrollsLikeSubmodule() {
        for fraction: CGFloat in [0.0, 0.001, 0.3, 1.0] {
            for reduceMotion in [false, true] {
                for (pitch, roll) in [(CGFloat(0.08), CGFloat(-0.05)), (-0.12, 0.2), (0.0, 0.0)] {
                    let submodule = submoduleDiamondTilt(pitch: pitch, roll: roll, scrollTransform: submoduleCardScrollTransform(fraction: fraction, reduceMotion: reduceMotion))
                    let actual = WalletCardDiamondLayout.tilt(pitch: pitch, roll: roll, scrollCollapseFraction: fraction)
                    XCTAssertEqual(actual.pitch, submodule.pitch, "fraction \(fraction) reduceMotion \(reduceMotion)")
                    XCTAssertEqual(actual.roll, submodule.roll, "fraction \(fraction) reduceMotion \(reduceMotion)")
                }
            }
        }
    }
}
