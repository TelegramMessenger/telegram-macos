import Cocoa
import Darwin
import NativeBlur
import TGUIKit

func footprint() throws -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard status == KERN_SUCCESS else { throw NSError(domain: "task_info", code: Int(status)) }
    return info.phys_footprint
}

func usage() -> rusage {
    var result = rusage()
    precondition(getrusage(RUSAGE_SELF, &result) == 0)
    return result
}

func cpu(_ value: rusage) -> Double {
    Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
}

@main
struct BlurBenchmark {
    static func main() throws {
        func argument(_ name: String, _ fallback: String) -> String {
            guard let index = CommandLine.arguments.firstIndex(of: name) else { return fallback }
            return CommandLine.arguments[index + 1]
        }
        let width = Int(argument("--width", "500"))!
        let height = Int(argument("--height", "500"))!
        let scale = Double(argument("--scale", "2"))!
        let iterations = Int(argument("--iterations", "100"))!
        let variant = argument("--variant", "current")
        precondition(width >= 50 && height >= 50 && iterations > 0)
        System.updateScaleFactor(scale)
        let image = fixtureImage(width: width, height: height)
        let render = variant == "baseline" ? NativeBlur.renderReference : NativeBlur.renderBlur
        let coldStart = DispatchTime.now().uptimeNanoseconds
        var last: CGImage? = autoreleasepool { render(image) }
        let coldMicroseconds = Double(DispatchTime.now().uptimeNanoseconds - coldStart) / 1000
        for _ in 0..<5 {
            last = autoreleasepool { render(image) }
        }
        let before = try footprint()
        let startUsage = usage()
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            last = autoreleasepool { render(image) }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1000)
        }
        let endUsage = usage()
        let after = try footprint()
        let bytes = pixelBytes(last!)
        var checksum: UInt64 = 1469598103934665603
        for value in bytes { checksum = (checksum ^ UInt64(value)) &* 1099511628211 }
        samples.sort()
        let result: [String: Any] = [
            "variant": variant, "width": width, "height": height, "scale": scale,
            "iterations": iterations, "run": argument("--run", "0"),
            "cpuSeconds": cpu(endUsage) - cpu(startUsage),
            "p50Microseconds": samples[(iterations - 1) / 2],
            "p95Microseconds": samples[Int(Double(iterations - 1) * 0.95)],
            "coldMicroseconds": coldMicroseconds,
            "physicalFootprintBefore": before, "physicalFootprintAfter": after,
            "maximumResidentSetBytes": endUsage.ru_maxrss,
            "outputWidth": last!.width, "outputHeight": last!.height,
            "outputChecksum": String(checksum),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
