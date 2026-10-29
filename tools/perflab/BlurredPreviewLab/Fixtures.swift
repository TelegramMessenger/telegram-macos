import Cocoa

func fixtureImage(width: Int, height: Int, seed: UInt32 = 1, colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()) -> CGImage {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    var value = seed
    for index in stride(from: 0, to: pixels.count, by: 4) {
        value = value &* 1664525 &+ 1013904223
        pixels[index] = UInt8(truncatingIfNeeded: value)
        pixels[index + 1] = UInt8(truncatingIfNeeded: value >> 8)
        pixels[index + 2] = UInt8(truncatingIfNeeded: value >> 16)
    }
    let data = Data(pixels)
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue), provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

func pixelBytes(_ image: CGImage) -> Data {
    let bytes = image.dataProvider!.data!
    let pointer = CFDataGetBytePtr(bytes)!
    let width = image.width * image.bitsPerPixel / 8
    var data = Data()
    for row in 0..<image.height {
        data.append(pointer + row * image.bytesPerRow, count: width)
    }
    return data
}
