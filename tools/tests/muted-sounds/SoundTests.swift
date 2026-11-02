final class NSSound {
    static func beep() { played += 1 }
    static var created = 0
    static var played = 0
    static var createdHook: (() -> Void)?
    static var currentOutput: () -> String? = { nil }
    static var lastPinnedOutput: String?
    static var lastOutput: String?
    var playbackDeviceIdentifier: String?
    var volume: Float = 1
    init?(contentsOfFile: String, byReference: Bool) { Self.created += 1; Self.createdHook?() }
    @discardableResult func play() -> Bool { Self.played += 1; Self.lastPinnedOutput = playbackDeviceIdentifier; Self.lastOutput = playbackDeviceIdentifier ?? Self.currentOutput(); return true }
}
final class Bundle {
    static let main = Bundle()
    func path(forResource: String, ofType: String) -> String? { "/test/sent.mp3" }
}
var device: AudioDeviceID? = 7
var systemDevice: AudioDeviceID? = 9
var systemMutes: [UInt32: UInt32] = [:]
var systemVolumes: [UInt32: Float32] = [:]
var uid: String? = "speakers"
var mutes: [UInt32: UInt32] = [:]
var volumes: [UInt32: Float32] = [:]
var channels: [UInt32]? = [1, 2]
func readTestProperty(_ object: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>, _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?, _ size: UnsafeMutablePointer<UInt32>, _ data: UnsafeMutableRawPointer) -> OSStatus {
    switch address.pointee.mSelector {
    case kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice:
        let selected = address.pointee.mSelector == kAudioHardwarePropertyDefaultSystemOutputDevice ? systemDevice : device
        guard let selected else { return -1 }
        data.assumingMemoryBound(to: AudioDeviceID.self).pointee = selected
    case kAudioDevicePropertyDeviceUID:
        guard let uid else { return -1 }
        data.assumingMemoryBound(to: Optional<CFString>.self).pointee = uid as CFString
    case kAudioDevicePropertyMute:
        guard let value = (object == systemDevice ? systemMutes : mutes)[address.pointee.mElement] else { return -1 }
        data.assumingMemoryBound(to: UInt32.self).pointee = value
    case kAudioDevicePropertyVolumeScalar:
        guard let value = (object == systemDevice ? systemVolumes : volumes)[address.pointee.mElement] else { return -1 }
        data.assumingMemoryBound(to: Float32.self).pointee = value
    case kAudioDevicePropertyPreferredChannelsForStereo:
        guard let channels else { return -1 }
        for (i, value) in channels.enumerated() { data.assumingMemoryBound(to: UInt32.self)[i] = value }
    default: return -1
    }
    return noErr
}
var failures = 0
var checks = 0
func reset() {
    device = 7; systemDevice = 9; systemMutes = [:]; systemVolumes = [:]; uid = "speakers"; mutes = [:]; volumes = [:]; channels = [1, 2]
    NSSound.created = 0; NSSound.played = 0; NSSound.lastOutput = nil; NSSound.lastPinnedOutput = nil; NSSound.createdHook = nil; NSSound.currentOutput = { uid }
}
func check(_ name: String, _ condition: Bool) {
    checks += 1
    if !condition { failures += 1 }
    print("\(condition ? "PASS" : "FAIL") \(name)")
}
func suppressed(_ name: String) {
    playSoundEffect(.sent)
    check(name, NSSound.created == 0 && NSSound.played == 0)
}
reset(); mutes[0] = 1; suppressed("system mute skips sound allocation and playback")
reset(); volumes[0] = 0; suppressed("zero master volume skips audio activation")
reset(); mutes = [1: 1, 2: 1]; suppressed("both output channels muted")
reset(); volumes = [1: 0, 2: 0]; suppressed("zero volume on both channels")
reset(); mutes[1] = 1; volumes[2] = 0; suppressed("mixed mute and zero volume remains silent")
reset(); device = nil; suppressed("missing default output does not fall back to another device")
reset(); device = 0; suppressed("unknown device is not activated")
reset(); uid = nil; playSoundEffect(.sent)
check("an unreadable device UID does not block an audible default output",NSSound.played == 1)
reset(); volumes = [1: 0, 2: 0.5]; playSoundEffect(.sent)
check("one audible channel still plays", NSSound.created == 1 && NSSound.played == 1)
reset(); channels = nil; playSoundEffect(.sent)
check("fixed-volume output without channel controls remains supported", NSSound.played == 1)
check("sound retains default-output routing without pinning a UID", NSSound.lastPinnedOutput == nil)
uid = "wired-headphones"; playSoundEffect(.sent)
check("manual device changes are read on the next sound", NSSound.lastOutput == "wired-headphones")
mutes[0] = 1; let prior = NSSound.created; playSoundEffect(.sent)
check("muting after playback prevents the next allocation", NSSound.created == prior)
reset(); systemMutes[0] = 1; playSoundEffectBeep()
check("incorrect-answer system beep respects mute", NSSound.played == 0)
reset(); playSoundEffectBeep()
check("audible incorrect answer retains the system beep", NSSound.played == 1)
reset(); mutes[0] = 1; playSoundEffectBeep()
check("muted ordinary output does not mute a separate audible alert device", NSSound.played == 1)
reset(); systemMutes[0] = 1; playSoundEffect(.sent); playSoundEffectBeep()
check("muted alert device blocks beep while ordinary output stays audible", NSSound.created == 1 && NSSound.played == 1)
reset(); NSSound.createdHook = { uid = "new-default" }; playSoundEffect(.sent)
check("switching output before play follows the new default", NSSound.lastOutput == "new-default" && NSSound.lastPinnedOutput == nil)
reset(); NSSound.createdHook = { device = nil; uid = nil }; playSoundEffect(.sent)
check("disconnecting the output before playback suppresses the sound", NSSound.played == 0)
reset(); NSSound.createdHook = { mutes[0] = 1 }; playSoundEffect(.sent)
check("muting the new output before playback is rechecked", NSSound.played == 0)
print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
