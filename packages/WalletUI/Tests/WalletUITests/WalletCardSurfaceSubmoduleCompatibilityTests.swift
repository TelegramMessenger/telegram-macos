import XCTest
import Cocoa
import Metal
@testable import WalletUI

private func submoduleNoiseBytes() -> [UInt8] {
    let dimension = 256
    var seed: UInt64 = 0x2545_F491_4F6C_DD1D

    func random() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return Float(seed & 0xffff) / Float(0xffff)
    }

    let base = (0 ..< dimension * dimension).map { _ in random() }
    let radius = 9
    var pixels = [UInt8](repeating: 0, count: dimension * dimension)

    for y in 0 ..< dimension {
        for x in 0 ..< dimension {
            var accumulator: Float = 0.0
            for offset in -radius ... radius {
                accumulator += base[y * dimension + ((x + offset + dimension) % dimension)]
            }
            var value = accumulator / Float(2 * radius + 1)
            value = 0.5 + (value - 0.5) * 3.4
            let combined = 0.68 * value + 0.32 * random()
            pixels[y * dimension + x] = UInt8(max(0.0, min(255.0, combined * 255.0)))
        }
    }
    return pixels
}

private func submoduleQRBytes() -> [UInt8] {
    let side = 176
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    pixels.withUnsafeMutableBytes { buffer in
        let cg = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.translateBy(x: 0.0, y: CGFloat(side))
        cg.scaleBy(x: 8.0, y: -8.0)
        cg.translateBy(x: -282.5, y: -90.0)
        cg.setFillColor(NSColor.white.cgColor)
        for origin in [CGPoint(x: 284.25, y: 91.75), CGPoint(x: 294.5, y: 91.75), CGPoint(x: 284.25, y: 102.0)] {
            let outer = CGRect(origin: origin, size: CGSize(width: 8.25, height: 8.25))
            let inner = outer.insetBy(dx: 1.375, dy: 1.375)
            let path = CGMutablePath()
            path.addRoundedRect(in: outer, cornerWidth: 2.4, cornerHeight: 2.4)
            path.addRoundedRect(in: inner, cornerWidth: 1.1, cornerHeight: 1.1)
            cg.addPath(path)
            cg.fillPath(using: .evenOdd)
        }
        for origin in [CGPoint(x: 295.0, y: 103.0), CGPoint(x: 300.12, y: 103.0), CGPoint(x: 297.6, y: 105.3),
                       CGPoint(x: 295.0, y: 108.15), CGPoint(x: 300.12, y: 108.15)] {
            let dot = CGRect(origin: origin, size: CGSize(width: 2.12, height: 2.1))
            cg.addPath(CGPath(roundedRect: dot, cornerWidth: 0.45, cornerHeight: 0.45, transform: nil))
            cg.fillPath()
        }
    }
    return pixels
}

private func submoduleEdgeShift(pitch: Double, yaw: Double, width: CGFloat, scale: CGFloat) -> CGPoint {
    let thickness: CGFloat = 9.0
    let depth = -thickness * width / 370.0 * scale
    var rotation = CATransform3DRotate(CATransform3DIdentity, CGFloat(pitch), 1.0, 0.0, 0.0)
    rotation = CATransform3DRotate(rotation, CGFloat(yaw), 0.0, 1.0, 0.0)
    return CGPoint(x: depth * rotation.m31, y: depth * rotation.m32)
}

private func submodulePerspectiveTransform(cardX: Double, cardY: Double, pitch: Double, scale: Double) -> CATransform3D {
    var perspectiveTransform = CATransform3DIdentity
    perspectiveTransform.m34 = -1.0 / 650.0
    perspectiveTransform = CATransform3DTranslate(perspectiveTransform, CGFloat(-cardY * 3.0), CGFloat(cardX * 2.5), 0.0)
    perspectiveTransform = CATransform3DScale(perspectiveTransform, CGFloat(scale), CGFloat(scale), 1.0)
    perspectiveTransform = CATransform3DRotate(perspectiveTransform, CGFloat(pitch), 1.0, 0.0, 0.0)
    perspectiveTransform = CATransform3DRotate(perspectiveTransform, CGFloat(cardY), 0.0, 1.0, 0.0)
    perspectiveTransform = CATransform3DRotate(perspectiveTransform, CGFloat(cardY * 0.05), 0.0, 0.0, 1.0)
    return perspectiveTransform
}

private func submoduleProjectedPoint(_ point: CGPoint, transform: CATransform3D, size: CGSize) -> CGPoint {
    let anchor = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
    let x = point.x - anchor.x
    let y = point.y - anchor.y
    let transformedX = x * transform.m11 + y * transform.m21 + transform.m41
    let transformedY = x * transform.m12 + y * transform.m22 + transform.m42
    let transformedW = x * transform.m14 + y * transform.m24 + transform.m44
    let safeW = abs(transformedW) < 0.0001 ? 0.0001 : transformedW
    return CGPoint(x: anchor.x + transformedX / safeW, y: anchor.y + transformedY / safeW)
}

private func submoduleFit(_ transform: CATransform3D, edgeShift: CGPoint, size: CGSize) -> (face: CATransform3D, back: CATransform3D, fitScale: CGFloat) {
    var perspectiveTransform = transform
    let bounds = CGRect(origin: .zero, size: size)
    let anchorX = size.width * 0.5
    var reachX: CGFloat = 0.0
    for corner in [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                   CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)] {
        let x = submoduleProjectedPoint(corner, transform: perspectiveTransform, size: size).x - anchorX
        reachX = max(reachX, max(abs(x), abs(x + edgeShift.x)))
    }
    let fitScale = reachX > anchorX ? anchorX / reachX : 1.0
    perspectiveTransform = CATransform3DConcat(perspectiveTransform, CATransform3DMakeScale(fitScale, fitScale, 1.0))
    let backTransform = CATransform3DConcat(perspectiveTransform,
        CATransform3DMakeTranslation(edgeShift.x * fitScale, edgeShift.y * fitScale, 0.0))
    return (perspectiveTransform, backTransform, fitScale)
}

private func submoduleBevelLight(surface: CGPoint) -> CGPoint {
    let x = Float(-0.45 - 0.9 * surface.x)
    let y = Float(-0.9 + 0.7 * surface.y)
    let length = (x * x + y * y).squareRoot()
    return CGPoint(x: CGFloat(x / length), y: CGFloat(y / length))
}

private func submoduleBevelWeight(normal: CGPoint, light: CGPoint) -> CGFloat {
    return 0.03 + 0.26 * max(normal.x * light.x + normal.y * light.y, 0.0)
}

private let walletCardChipHarness = """
constant WalletCardStyle walletCardClassicStyle = {};

struct WalletCardChipTestOutput { float4 position [[position]]; };

vertex WalletCardChipTestOutput walletCardChipTestVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[] = { float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0) };
    WalletCardChipTestOutput output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    return output;
}

fragment float4 walletCardChipTestFragment(WalletCardChipTestOutput input [[stage_in]],
    constant float4 &layout [[buffer(0)]], constant float4 &state [[buffer(1)]],
    texture2d<float> noiseMap [[texture(0)]], texture2d<float> qrMap [[texture(1)]]) {
    float2 position = input.position.xy / layout.z - layout.w * layout.xy;
    float2 cp = position / layout.xy + float2(268.5, 82.0);
    return walletCardQRChip(cp, state.xy, state.z, noiseMap, qrMap, cp, walletCardClassicStyle);
}
"""

final class WalletCardSurfaceSubmoduleCompatibilityTests: XCTestCase {
    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func collapsed(_ text: String) -> String {
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private let cardComponentPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletCardComponent/Sources/WalletCardComponent.swift"
    private let cardBackgroundPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletCardComponent/Sources/WalletCardBackgroundView.swift"
    private let cardTexturesPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletCardComponent/Sources/WalletCardTextures.swift"
    private let transferCardPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletCardComponent/Sources/WalletTransferCardComponent.swift"
    private let shaderPath = "submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletCardComponent/Resources/WalletCardBackground.metal"
    private let cardViewPath = "packages/WalletUI/Sources/WalletUI/WalletCardView.swift"

    func testSubmoduleStillUsesTheCopiedCardRules() throws {
        let card = collapsed(try source(cardComponentPath))
        for line in [
            "private static let maxPitch = 0.20",
            "private static let maxYaw = 0.30",
            "private static let thickness: CGFloat = 9.0",
            "let depth = -Self.thickness * self.currentSize.width / 370.0 * self.currentScale",
            "var rotation = CATransform3DRotate(CATransform3DIdentity, CGFloat(pitch), 1.0, 0.0, 0.0)",
            "rotation = CATransform3DRotate(rotation, CGFloat(yaw), 0.0, 1.0, 0.0)",
            "return CGPoint(x: depth * rotation.m31, y: depth * rotation.m32)",
            "let edgeShift = self.edgeShift(pitch: cardPitch, yaw: self.stickerYaw)",
            "let x = self.projectedPoint(corner, transform: perspectiveTransform).point.x - anchorX",
            "reachX = max(reachX, max(abs(x), abs(x + edgeShift.x)))",
            "let fitScale = reachX > anchorX ? anchorX / reachX : 1.0",
            "perspectiveTransform = CATransform3DConcat(perspectiveTransform, CATransform3DMakeScale(fitScale, fitScale, 1.0))",
            "var backTransform = CATransform3DConcat(perspectiveTransform, CATransform3DMakeTranslation(edgeShift.x * fitScale, edgeShift.y * fitScale, 0.0))",
            "perspectiveTransform = scrolled(perspectiveTransform) backTransform = scrolled(backTransform)",
            "perspectiveTransform.m34 = -1.0 / 650.0",
            "CGFloat(-self.stickerYaw * 3.0), CGFloat(self.currentCardX * 2.5),",
            "let detailsFraction = max(0.0, min(1.0, (self.balanceTransitionFraction - 0.3) / 0.3))",
            "let easedDetailsFraction = detailsFraction * detailsFraction * (3.0 - 2.0 * detailsFraction)",
            "self.qrAlpha = detailsAlpha self.qrBlurRadius = easedDetailsFraction * 8.0",
            "let deltaTime = min(max(Double(frameDuration), 0.0), 1.0 / 30.0)",
            "if !UIAccessibility.isReduceMotionEnabled { self.elapsedTime += deltaTime }",
            "surfaceTiltX: Self.clamp(self.currentDepthX + self.overscrollPitch, maxPitch + 0.03), surfaceTiltY: self.currentDepthY,",
            "0.006 * (abs(self.diamondRate) > baseSpin * 1.5 ? extraSpin : 0.0), Self.maxYaw * 0.18",
            "qrChip: WalletCardQRChip(frame: self.qrFrame, alpha: self.qrAlpha, blurRadius: self.qrBlurRadius)"
        ] {
            XCTAssertTrue(card.contains(collapsed(line)), line)
        }

        let shader = collapsed(try source(shaderPath))
        for line in [
            "float2 surface = clamp(float2(uniforms.surfaceTilt.y / 0.30, uniforms.surfaceTilt.x / 0.20), float2(-1.0), float2(1.0));",
            "float band = smoothstep(-1.1, -0.35, d);",
            "float2 light = normalize(float2(-0.45 - 0.9 * surface.x, -0.9 + 0.7 * surface.y));",
            "gradient += float3(0.10, 0.36, 0.85) * band * (0.03 + 0.26 * max(dot(n, light), 0.0));",
            "float2 chipScale = uniforms.qrRect.zw / float2(50.0, 38.0);",
            "float2 cp = (position - uniforms.qrRect.xy) / chipScale + float2(268.5, 82.0);",
            "outputColor = outputColor * (1.0 - chip.a) + chip.rgb;"
        ] {
            XCTAssertTrue(shader.contains(collapsed(line)), line)
        }

        let background = collapsed(try source(cardBackgroundPath))
        XCTAssertTrue(background.contains(collapsed("self.fragmentUniforms.qrEffects.z = backQuad == nil ? 0.0 : 1.0")))
        XCTAssertTrue(background.contains(collapsed(".SRGB: false, .origin: MTKTextureLoader.Origin.topLeft")))

        let transfer = collapsed(try source(transferCardPath))
        XCTAssertTrue(transfer.contains("self.backgroundView.renderStaticFrame(reflectionRotation: self.reflectionRotation.value)"))
        XCTAssertFalse(transfer.contains("backQuad"))
        XCTAssertFalse(transfer.contains("qrChip"))

        let textures = collapsed(try source(cardTexturesPath))
        for line in [
            "var seed: UInt64 = 0x2545_F491_4F6C_DD1D",
            "accumulator += base[y * dimension + ((x + offset + dimension) % dimension)]",
            "value = 0.5 + (value - 0.5) * 3.4",
            "let combined = 0.68 * value + 0.32 * random()",
            "format.scale = 8.0",
            "return UIGraphicsImageRenderer(size: CGSize(width: 22.0, height: 22.0), format: format).image { context in",
            "cg.translateBy(x: -282.5, y: -90.0)",
            "for origin in [CGPoint(x: 284.25, y: 91.75), CGPoint(x: 294.5, y: 91.75), CGPoint(x: 284.25, y: 102.0)] {",
            "let outer = CGRect(origin: origin, size: CGSize(width: 8.25, height: 8.25))",
            "let inner = outer.insetBy(dx: 1.375, dy: 1.375)",
            "path.addRoundedRect(in: outer, cornerWidth: 2.4, cornerHeight: 2.4)",
            "path.addRoundedRect(in: inner, cornerWidth: 1.1, cornerHeight: 1.1)",
            "for origin in [CGPoint(x: 295.0, y: 103.0), CGPoint(x: 300.12, y: 103.0), CGPoint(x: 297.6, y: 105.3), CGPoint(x: 295.0, y: 108.15), CGPoint(x: 300.12, y: 108.15)] {",
            "let dot = CGRect(origin: origin, size: CGSize(width: 2.12, height: 2.1))",
            "cg.addPath(CGPath(roundedRect: dot, cornerWidth: 0.45, cornerHeight: 0.45, transform: nil))"
        ] {
            XCTAssertTrue(textures.contains(collapsed(line)), line)
        }
    }

    func testCardFollowsTheCopiedRules() throws {
        let view = collapsed(try source(cardViewPath))
        for line in [
            "let detailsFraction = walletCardSmoothStep((scrollCollapseFraction - 0.3) / 0.3)",
            "blurFilter.setValue(detailsFraction * 8.0 as NSNumber, forKey: \"inputRadius\")",
            "edgeView.isHidden = isTransfer",
            "bevelLayer.isHidden = isTransfer",
            "(transform, edgeTransform) = walletCardFitTransforms(face: transform, edgeShift: edgeShift, size: NSMakeSize(width, height))",
            "surfaceTilt = walletCardSurfaceTilt(pitch: angleX, yaw: angleY, roll: diamondSway.roll)",
            "surfaceTime += min(max(duration, 0.0), 1.0 / 30.0)",
            "guard window != nil, !isTransfer, !reduceMotion, scrollCollapseFraction < 1.0, qrChipRenderer != nil else {",
            "private let walletCardMaxDiamondRoll: CGFloat = 0.30 * 0.18"
        ] {
            XCTAssertTrue(view.contains(collapsed(line)), line)
        }
        let tiltRange = view.components(separatedBy: "if !reduceMotion, scrollCollapseFraction > 0.0 {")
        XCTAssertEqual(tiltRange.count, 2)
        XCTAssertTrue(tiltRange[0].contains("walletCardFitTransforms"))
    }

    func testChipTexturesMatchSubmodule() {
        let noise = submoduleNoiseBytes()
        XCTAssertEqual(walletCardChipNoise.width, 256)
        XCTAssertEqual(walletCardChipNoise.height, 256)
        var noiseDifference: Float = 0.0
        var noiseMismatches = 0
        for index in 0 ..< noise.count {
            let difference = abs(Float(noise[index]) / 255.0 - walletCardChipNoise.values[index])
            noiseDifference = max(noiseDifference, difference)
            if difference > 0.0001 {
                noiseMismatches += 1
            }
        }
        XCTAssertLessThanOrEqual(noiseDifference, 1.0 / 255.0 + 1e-6)
        XCTAssertLessThan(noiseMismatches, noise.count / 100)

        let qr = submoduleQRBytes()
        XCTAssertEqual(walletCardChipGlyph.width, 176)
        XCTAssertEqual(walletCardChipGlyph.height, 176)
        var glyphDifference: Float = 0.0
        var inked = 0
        for index in 0 ..< 176 * 176 {
            glyphDifference = max(glyphDifference, abs(Float(qr[index * 4 + 3]) / 255.0 - walletCardChipGlyph.values[index]))
            if qr[index * 4 + 3] > 127 {
                inked += 1
            }
        }
        XCTAssertLessThanOrEqual(glyphDifference, 1.0 / 255.0 + 1e-6)
        XCTAssertGreaterThan(inked, 3000)
        XCTAssertGreaterThan(walletCardChipGlyph.values[47 * 176 + 19], 0.9)
        XCTAssertLessThan(walletCardChipGlyph.values[47 * 176 + 47], 0.1)
    }

    private func gpuChip(device: MTLDevice, width: Int, height: Int, chipScale: CGSize, backingScale: CGFloat, surface: CGPoint, time: Float) throws -> [Float] {
        let library = try device.makeLibrary(source: try source(shaderPath) + walletCardChipHarness, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "walletCardChipTestVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "walletCardChipTestFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let noise = submoduleNoiseBytes()
        let noiseTexture = try XCTUnwrap(device.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 256, height: 256, mipmapped: false)))
        noiseTexture.replace(region: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0, withBytes: noise, bytesPerRow: 256)
        let qr = submoduleQRBytes()
        let qrTexture = try XCTUnwrap(device.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 176, height: 176, mipmapped: false)))
        qrTexture.replace(region: MTLRegionMake2D(0, 0, 176, 176), mipmapLevel: 0, withBytes: qr, bytesPerRow: 176 * 4)

        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        outputDescriptor.usage = [.renderTarget, .shaderRead]
        outputDescriptor.storageMode = .shared
        let output = try XCTUnwrap(device.makeTexture(descriptor: outputDescriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store

        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline)
        var layout = SIMD4<Float>(Float(chipScale.width), Float(chipScale.height), Float(backingScale), Float(walletCardQRChipMargin))
        var state = SIMD4<Float>(Float(surface.x), Float(surface.y), time, 0.0)
        encoder.setFragmentBytes(&layout, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.setFragmentBytes(&state, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
        encoder.setFragmentTexture(noiseTexture, index: 0)
        encoder.setFragmentTexture(qrTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixels = [Float](repeating: 0.0, count: width * height * 4)
        output.getBytes(&pixels, bytesPerRow: width * 16, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        XCTAssertEqual(image.bytesPerRow, image.width * 4)
        XCTAssertEqual(image.alphaInfo, .premultipliedLast)
        return [UInt8](data)
    }

    func testChipMatchesSubmoduleShader() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }
        let chipSizes: [(NSSize, CGFloat)] = [
            (NSSize(width: floor(50.0 * 336.0 / 370.0), height: floor(38.0 * 336.0 / 370.0)), 2.0),
            (NSSize(width: 50.0, height: 38.0), 1.0),
            (NSSize(width: 50.0, height: 38.0), 2.0)
        ]
        let states: [(CGPoint, CGFloat)] = [
            (.zero, 0.0),
            (CGPoint(x: 1.0, y: 1.0), 0.0),
            (CGPoint(x: -1.0, y: -1.0), 0.0),
            (CGPoint(x: 1.0, y: -1.0), 3.49),
            (CGPoint(x: -1.0, y: 1.0), 7.0),
            (CGPoint(x: -0.4, y: 0.7), 10.0),
            (CGPoint(x: 0.25, y: -0.6), 20.0)
        ]
        for (chipSize, backingScale) in chipSizes {
            let renderer = try XCTUnwrap(WalletCardQRChipRenderer(chipSize: chipSize, backingScale: backingScale))
            let chipScale = CGSize(width: chipSize.width / walletCardQRChipReferenceSize.width, height: chipSize.height / walletCardQRChipReferenceSize.height)
            for (surface, time) in states {
                let expected = try gpuChip(device: device, width: renderer.width, height: renderer.height, chipScale: chipScale, backingScale: backingScale, surface: surface, time: Float(time))
                let actual = try bytes(XCTUnwrap(renderer.image(surface: surface, time: time)))
                XCTAssertEqual(actual.count, expected.count)
                var maxDifference: Float = 0.0
                var sum: Float = 0.0
                var covered = 0
                for index in 0 ..< min(actual.count, expected.count) {
                    let difference = abs(expected[index] * 255.0 - Float(actual[index]))
                    maxDifference = max(maxDifference, difference)
                    sum += difference
                    if index % 4 == 3, actual[index] == 255 {
                        covered += 1
                    }
                }
                let label = "chip \(chipSize) @\(backingScale) surface \(surface) time \(time)"
                XCTAssertLessThanOrEqual(maxDifference, 4.0, label)
                XCTAssertLessThanOrEqual(sum / Float(actual.count), 0.3, label)
                XCTAssertGreaterThan(covered, renderer.width * renderer.height / 2, label)
            }
        }
    }

    func testChipChangesWithTiltAndTimeLikeSubmodule() throws {
        let renderer = try XCTUnwrap(WalletCardQRChipRenderer(chipSize: NSSize(width: 45.0, height: 34.0), backingScale: 2.0))
        let rest = try bytes(XCTUnwrap(renderer.image(surface: .zero, time: 0.0)))
        let tilted = try bytes(XCTUnwrap(renderer.image(surface: CGPoint(x: 1.0, y: 0.0), time: 0.0)))
        let later = try bytes(XCTUnwrap(renderer.image(surface: .zero, time: 3.49)))
        let period = try bytes(XCTUnwrap(renderer.image(surface: .zero, time: 2.0 * .pi / 0.45)))
        let clamped = try bytes(XCTUnwrap(renderer.image(surface: CGPoint(x: 3.0, y: 0.0), time: 0.0)))
        func difference(_ a: [UInt8], _ b: [UInt8]) -> Int {
            return zip(a, b).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
        }
        XCTAssertGreaterThan(difference(rest, tilted), 40)
        XCTAssertGreaterThan(difference(rest, later), 10)
        XCTAssertLessThanOrEqual(difference(rest, period), 1)
        XCTAssertEqual(difference(tilted, clamped), 0)
    }

    func testEdgeShiftMatchesSubmodule() {
        for width: CGFloat in [300.0, 336.0, 370.0] {
            for pitch in stride(from: -0.3, through: 0.3, by: 0.05) {
                for yaw in stride(from: -0.35, through: 0.35, by: 0.05) {
                    let expected = submoduleEdgeShift(pitch: pitch, yaw: yaw, width: width, scale: 1.0)
                    let actual = walletCardEdgeShift(pitch: CGFloat(pitch), yaw: CGFloat(yaw), width: width)
                    XCTAssertEqual(actual.x, expected.x, accuracy: 1e-12, "width \(width) pitch \(pitch) yaw \(yaw)")
                    XCTAssertEqual(actual.y, expected.y, accuracy: 1e-12, "width \(width) pitch \(pitch) yaw \(yaw)")
                }
            }
        }
        let shift = walletCardEdgeShift(pitch: 0.0, yaw: walletCardMaxHoverTilt, width: 370.0)
        XCTAssertEqual(shift.x, -9.0 * sin(walletCardMaxHoverTilt), accuracy: 1e-9)
        XCTAssertEqual(shift.y, 0.0, accuracy: 1e-12)
    }

    func testFitScaleMatchesSubmodule() {
        let size = CGSize(width: 336.0, height: 336.0 * 220.0 / 370.0)
        let center = CATransform3DMakeTranslation(size.width * 0.5, size.height * 0.5, 0.0)
        let back = CATransform3DMakeTranslation(-size.width * 0.5, -size.height * 0.5, 0.0)
        var shrunk = 0
        for cardX in stride(from: -0.2, through: 0.2, by: 0.1) {
            for cardY in stride(from: -0.3, through: 0.3, by: 0.075) {
                for scale in [1.0, 1.01] {
                    let submoduleTransform = submodulePerspectiveTransform(cardX: cardX, cardY: cardY, pitch: cardX, scale: scale)
                    let edgeShift = submoduleEdgeShift(pitch: cardX, yaw: cardY, width: size.width, scale: CGFloat(scale))
                    let expected = submoduleFit(submoduleTransform, edgeShift: edgeShift, size: size)
                    let macTransform = CATransform3DConcat(CATransform3DConcat(back, submoduleTransform), center)
                    let actual = walletCardFitTransforms(face: macTransform, edgeShift: edgeShift, size: size)
                    if expected.fitScale < 1.0 {
                        shrunk += 1
                    }
                    for corner in [CGPoint.zero, CGPoint(x: size.width, y: 0.0), CGPoint(x: 0.0, y: size.height), CGPoint(x: size.width, y: size.height), CGPoint(x: size.width * 0.3, y: size.height * 0.8)] {
                        let label = "x \(cardX) y \(cardY) scale \(scale) corner \(corner)"
                        let expectedFace = submoduleProjectedPoint(corner, transform: expected.face, size: size)
                        let actualFace = project(corner, actual.face)
                        XCTAssertEqual(actualFace.x, expectedFace.x, accuracy: 1e-9, label)
                        XCTAssertEqual(actualFace.y, expectedFace.y, accuracy: 1e-9, label)
                        let expectedBack = submoduleProjectedPoint(corner, transform: expected.back, size: size)
                        let actualBack = project(corner, actual.edge)
                        XCTAssertEqual(actualBack.x, expectedBack.x, accuracy: 1e-9, label)
                        XCTAssertEqual(actualBack.y, expectedBack.y, accuracy: 1e-9, label)
                    }
                }
            }
        }
        XCTAssertGreaterThan(shrunk, 10)

        let flat = walletCardFitTransforms(face: CATransform3DIdentity, edgeShift: .zero, size: size)
        XCTAssertTrue(CATransform3DEqualToTransform(flat.face, CATransform3DIdentity))
        XCTAssertTrue(CATransform3DEqualToTransform(flat.edge, CATransform3DIdentity))
    }

    private func project(_ point: CGPoint, _ transform: CATransform3D) -> CGPoint {
        let x = point.x * transform.m11 + point.y * transform.m21 + transform.m41
        let y = point.x * transform.m12 + point.y * transform.m22 + transform.m42
        let w = point.x * transform.m14 + point.y * transform.m24 + transform.m44
        return CGPoint(x: x / w, y: y / w)
    }

    func testBevelLightMatchesSubmodule() {
        let normals: [CGPoint] = [CGPoint(x: 0.0, y: -1.0), CGPoint(x: 0.0, y: 1.0), CGPoint(x: -1.0, y: 0.0), CGPoint(x: 1.0, y: 0.0), CGPoint(x: -0.6, y: -0.8), CGPoint(x: 0.8, y: 0.6)]
        for x in stride(from: -1.0, through: 1.0, by: 0.25) {
            for y in stride(from: -1.0, through: 1.0, by: 0.25) {
                let surface = CGPoint(x: x, y: y)
                let expected = submoduleBevelLight(surface: surface)
                let actual = walletCardBevelLight(surface: surface)
                XCTAssertEqual(actual.x, expected.x, accuracy: 1e-6, "\(surface)")
                XCTAssertEqual(actual.y, expected.y, accuracy: 1e-6, "\(surface)")
                for normal in normals {
                    XCTAssertEqual(walletCardBevelWeight(lightDot: normal.x * actual.x + normal.y * actual.y), submoduleBevelWeight(normal: normal, light: expected), accuracy: 1e-6, "\(surface) \(normal)")
                }
            }
        }
        let rest = walletCardBevelLight(surface: .zero)
        XCTAssertLessThan(rest.x, 0.0)
        XCTAssertLessThan(rest.y, 0.0)
    }

    func testSurfaceTiltNormalizesTheMacTiltLikeSubmodule() {
        let maxRoll = 0.30 * 0.18
        XCTAssertEqual(walletCardSurfaceTilt(pitch: 0.0, yaw: walletCardMaxHoverTilt, roll: 0.0).x, 1.0, accuracy: 1e-12)
        XCTAssertEqual(walletCardSurfaceTilt(pitch: -walletCardMaxHoverTilt, yaw: 0.0, roll: 0.0).y, -1.0, accuracy: 1e-12)
        XCTAssertEqual(walletCardSurfaceTilt(pitch: 0.0, yaw: maxRoll, roll: maxRoll).x, maxRoll / 0.30, accuracy: 1e-12)
        XCTAssertEqual(walletCardSurfaceTilt(pitch: 0.0, yaw: walletCardMaxHoverTilt * 0.5 + 0.02, roll: 0.02).x, 0.5 + 0.02 / 0.30, accuracy: 1e-12)
        XCTAssertEqual(walletCardSurfaceTilt(pitch: walletCardMaxHoverTilt * 3.0, yaw: -walletCardMaxHoverTilt * 3.0, roll: 0.0), CGPoint(x: -1.0, y: 1.0))
        XCTAssertEqual(walletCardSurfaceTilt(pitch: 0.0, yaw: 0.0, roll: 0.0), .zero)
    }

    func testChipStaysOnTheCardSurfaceLikeSubmodule() throws {
        let component = collapsed(try source(cardComponentPath))
        XCTAssertTrue(component.contains(collapsed("qrChip: WalletCardQRChip(frame: self.qrFrame, alpha: self.qrAlpha, blurRadius: self.qrBlurRadius)")))
        XCTAssertTrue(component.contains(collapsed("(self.qrButton.view as? PlainButtonComponent.View)?.contentView?.isHidden = self.backgroundView.displaysQRChip")))
        let view = try source(cardViewPath)
        XCTAssertFalse(view.contains("qrButton.layer?.transform"))
        XCTAssertTrue(collapsed(view).contains(collapsed("infoButton.layer?.transform = CATransform3DMakeTranslation(parallaxX * 6, parallaxY * 6, 0)")))
    }
}
