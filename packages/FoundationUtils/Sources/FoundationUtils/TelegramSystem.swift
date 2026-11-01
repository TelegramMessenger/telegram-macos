import Foundation
import IOKit

func appleSiliconChipName() -> String {
    var length = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &length, nil, 0)
    guard length > 0 else {
        return ""
    }
    var bytes = [CChar](repeating: 0, count: length)
    sysctlbyname("machdep.cpu.brand_string", &bytes, &length, nil, 0)
    return String(cString: bytes)
}

func deviceFromIORegistry() -> String? {
    let entry = IORegistryEntryFromPath(mach_port_t(MACH_PORT_NULL), "IODeviceTree:/product")
    guard entry != 0 else {
        return nil
    }
    defer {
        IOObjectRelease(entry)
    }
    guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data else {
        return nil
    }
    let fullName = String(decoding: data.prefix(while: { $0 != 0 }), as: UTF8.self)
    let name = fullName.components(separatedBy: " (").first ?? fullName
    guard !name.isEmpty else {
        return nil
    }
    let chip = appleSiliconChipName()
    return chip.hasPrefix("Apple ") ? (name + chip.dropFirst(5)) : name
}

func deviceFromSystemProfiler() -> String? {
    // Starting with MacBook M2 the hw.model returns simply Mac[digits],[digits].
    // So we try reading "system_profiler" output.
    let process = Process()
    if #available(macOS 10.13, *) {
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    } else {
        process.launchPath = "/usr/sbin/system_profiler"
    }
    process.arguments = ["-json", "SPHardwareDataType", "-detailLevel", "mini"]
    let pipe = Pipe()
    process.standardOutput = pipe
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
        finished.signal()
    }
    do {
        if #available(macOS 10.13, *) {
            try process.run()
        } else {
            process.launch()
        }
    } catch {
        return nil
    }
    if finished.wait(timeout: .now() + 2) == .timedOut {
        process.terminate()
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let document = try? JSONSerialization.jsonObject(with: data, options: [])
    guard let fields = (document as? [String: Any])?["SPHardwareDataType"] as? [[String: Any]], !fields.isEmpty else {
        return nil
    }
    let result = fields[0]["machine_name"] as? String ?? ""
    guard !result.isEmpty else {
        return nil
    }
    let chip = fields[0]["chip_type"] as? String ?? ""
    return chip.hasPrefix("Apple ") ? (result + chip.dropFirst(5)) : result
}

public func deviceModelPretty() -> String {
    if let fromIORegistry = deviceFromIORegistry() {
        return fromIORegistry
    }
    if let fromSystemProfiler = deviceFromSystemProfiler(), !fromSystemProfiler.isEmpty {
        return fromSystemProfiler
    }
    var length = 0
    sysctlbyname("hw.model", nil, &length, nil, 0)
    if length > 0 {
        var bytes = [CChar](repeating: 0, count: length)
        sysctlbyname("hw.model", &bytes, &length, nil, 0)
        if let parsed = fromIdentifier(model: String(cString: bytes)), !parsed.isEmpty {
            return parsed
        }
    }
    return ""
}


func fromIdentifier(model: String) -> String? {
    guard !model.isEmpty, model.lowercased().contains("mac") else {
        return nil
    }
    
    var words = [String]()
    var word = ""
    for ch in model {
        if !ch.isLetter {
            continue
        }
        if ch.isUppercase {
            if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        word.append(ch)
    }
    if !word.isEmpty {
        words.append(word)
    }
    
    var result = ""
    for word in words {
        if !result.isEmpty && word != "Mac" && word != "Book" {
            result.append(" ")
        }
        result.append(word)
    }
    
    return result
}
