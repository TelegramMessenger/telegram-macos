import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox
import CoreMediaIO
import InAppSettings
import TelegramMedia
import TelegramTheme
import TelegramContext
import TelegramUtils
import AVFoundation

public struct IODevices {
    public let camera: [AVCaptureDevice]
    public let audioInput: [AVCaptureDevice]
    public let audioOutput: [AudioDeviceID]
    public let loading: Bool
    public init(camera: [AVCaptureDevice], audioInput: [AVCaptureDevice], audioOutput: [AudioDeviceID], loading: Bool) {
        self.camera = camera
        self.audioInput = audioInput
        self.audioOutput = audioOutput
        self.loading = loading
    }
}

private extension AudioListener {
    static var nominalSampler: AudioObjectPropertyListenerProc = { _, _, _, _ in
        incrementSampleIndex()
        return 0
    }
}


extension AudioDeviceID {
    public var uniqueID: String {
        return DevicesContext.Audio.getDeviceUid(deviceId: self)
    }
    public var localizedName: String {
        return DevicesContext.Audio.getDeviceName(deviceID: self)
    }
}

private func devicesList(queue: Queue) -> Signal<IODevices, NoError> {
    return Signal { subscriber in
        
        let defAudioDevice = AVCaptureDevice.default(for: .audio)
        let defVideoDevice = AVCaptureDevice.default(for: .video)
        
        var videoDevices = DALDevices()
        var audioDevices = AVCaptureDevice.devices(for: .audio)
        
        if !videoDevices.isEmpty, let device = defVideoDevice {
            videoDevices.removeAll(where: { $0.uniqueID == device.uniqueID})
            videoDevices.insert(device, at: 0)
        }
        if !audioDevices.isEmpty, let device = defAudioDevice {
            audioDevices.removeAll(where: { $0.uniqueID == device.uniqueID})
            audioDevices.insert(device, at: 0)
        }
        subscriber.putNext(.init(camera: videoDevices, audioInput: audioDevices, audioOutput: DevicesContext.Audio.getAllDevices().filter { DevicesContext.Audio.isOutputDevice(deviceID: $0) && !DevicesContext.Audio.isPrivateAggregateDevice(deviceID: $0) }, loading: false))
        subscriber.putCompletion()
        
        
        return EmptyDisposable
    } |> runOn(queue)
    
}


public func sizeof <T> (_ : T.Type) -> Int
{
    return (MemoryLayout<T>.size)
}

public func sizeof <T> (_ : T) -> Int
{
    return (MemoryLayout<T>.size)
}

public func sizeof <T> (_ value : [T]) -> Int
{
    return (MemoryLayout<T>.size * value.count)
}

public struct CaptureDeviceCandidate: Equatable {
    public let uniqueID: String
    public let isAvailable: Bool
    public init(uniqueID: String, isAvailable: Bool) {
        self.uniqueID = uniqueID
        self.isAvailable = isAvailable
    }
}

public typealias DevicesUpdate = (camera: String?, input: String?, output: String?, sampleUpdateIndex: Int?)

public struct DevicesChangeTracker {
    private var camera: String?
    private var input: String?
    private var output: String?
    private var sampleIndex: Int?
    
    public init() {
    }
    
    public mutating func update(camera: String?, input: String?, output: String?, sampleIndex: Int) -> DevicesUpdate {
        let sampleChanged = self.sampleIndex != sampleIndex
        var result: DevicesUpdate = (camera: nil, input: nil, output: nil, sampleUpdateIndex: nil)
        if self.input != input || sampleChanged {
            result.input = input
        }
        if self.camera != camera {
            result.camera = camera
        }
        if self.output != output || sampleChanged {
            result.output = output
        }
        if sampleChanged {
            result.sampleUpdateIndex = sampleIndex
        }
        self.camera = camera
        self.input = input
        self.output = output
        self.sampleIndex = sampleIndex
        return result
    }
}

private let sampleUpdater = ValuePromise(0, ignoreRepeated: false)
private var index: Int = 0
private func incrementSampleIndex() {
    index += 1
    sampleUpdater.set(index)
}

public final class DevicesContext : NSObject {
    private var _signal: Promise<IODevices> = Promise()
    public var signal: Signal<IODevices, NoError> {
        return _signal.get()
    }
    
    
    private final class UpdaterContext {
//        var status: (camera: String?, input: String?, output: String?) = (camera: nil, input: nil, output: nil)
        public let subscribers = Bag<((camera: String?, input: String?, output: String?, sampleUpdateIndex: Int?)) -> Void>()
    }
    
    private let updaterContext: UpdaterContext = UpdaterContext()
    
   
    
    public func updater() -> Signal<(camera: String?, input: String?, output: String?, sampleUpdateIndex: Int?), NoError> {
        return Signal { subscriber in
            
            let disposable = MetaDisposable()
            let statusContext: UpdaterContext = self.updaterContext
            
            let index = statusContext.subscribers.add({ status in
                subscriber.putNext(status)
            })
            
//            subscriber.putNext(statusContext.status)
            
            disposable.set(ActionDisposable {
                DispatchQueue.main.async {
                    self.updaterContext.subscribers.remove(index)
                }
            })
            
            return disposable
        } |> runOn(.mainQueue())
    }
    
    
    private let disposable = MetaDisposable()
    private let updateSampler = MetaDisposable()
    private let devicesQueue = Queue(name: "devicesQueue")
    
    private let _currentCameraId: Atomic<String?> = Atomic(value: nil)
    private let _currentMicroId: Atomic<String?> = Atomic(value: nil)
    private let _currentOutputId: Atomic<String?> = Atomic(value: nil)
    
    public var currentCameraId: String? {
        return _currentCameraId.with { $0 }
    }
    public var currentMicroId: String? {
        return _currentMicroId.with { $0 }
    }
    public var currentOutputId: String? {
        return _currentOutputId.with { $0 }
    }
    
    public init(_ accountManager: AccountManager<TelegramAccountManagerTypes> ) {
        super.init()
        
//
//        var prop : CMIOObjectPropertyAddress = CMIOObjectPropertyAddress(
//                mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
//                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
//                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster))
//        
//        var allow: UInt32 = 1
//        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
//                                &prop, 0, nil,
//                                UInt32(sizeof(allow)), &allow );
        

    
        NotificationCenter.default.addObserver(forName: NSNotification.Name.AVCaptureDeviceWasConnected, object: nil, queue: nil, using: { [weak self] _ in
            self?.update()
        })
        NotificationCenter.default.addObserver(forName: NSNotification.Name.AVCaptureDeviceWasDisconnected, object: nil, queue: nil, using: { [weak self] _ in
            self?.update()
        })
        devicesQueue.async {
            AudioListener.retainOutputListener()
            AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &AudioAddress.inputDevice, AudioListener.input, nil)
            AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &AudioAddress.devices, AudioListener.devices, nil)
        }
        
        NotificationCenter.default.addObserver(forName: AudioNotification.audioDevicesDidChange.notificationName, object: nil, queue: nil, using: { [weak self] _ in
            self?.update()
        })

        
        NotificationCenter.default.addObserver(forName: AudioNotification.audioOutputDeviceDidChange.notificationName, object: nil, queue: nil, using: { [weak self] _ in
            self?.update()
        })
        
        NotificationCenter.default.addObserver(forName: AudioNotification.audioInputDeviceDidChange.notificationName, object: nil, queue: nil, using: { [weak self] _ in
            self?.update()
        })
        
        NotificationCenter.default.addObserver(forName: AudioNotification.mixStereo.notificationName, object: nil, queue: nil, using: { [weak self] _ in
            self?.update()
        })
        
        
        
        let currentCameraId = self._currentCameraId
        let currentMicroId = self._currentMicroId
        let currentOutputId = self._currentOutputId
        
        var tracker = DevicesChangeTracker()
        
        let updated = combineLatest(queue: devicesQueue, voiceCallSettings(accountManager), signal, sampleUpdater.get()) |> map { settings, devices, index -> DevicesUpdate in
            let inputUpdated = DevicesContext.updateMicroId(settings, devices: devices)
            let cameraUpdated = DevicesContext.updateCameraId(settings, devices: devices)
            let outputUpdated = DevicesContext.updateOutputId(settings, devices: devices)
            
            _ = currentMicroId.swap(inputUpdated)
            _ = currentCameraId.swap(cameraUpdated)
            _ = currentOutputId.swap(outputUpdated)
            
            return tracker.update(camera: cameraUpdated, input: inputUpdated, output: outputUpdated, sampleIndex: index)
        } |> deliverOnMainQueue
        
        disposable.set(updated.start(next: { [weak self] result in
            guard let `self` = self else {
                return
            }
            //self.updaterContext.status = result
            
            for subscriber in self.updaterContext.subscribers.copyItems() {
                subscriber(result)
            }

           // self.updaterContext.status = (camera: nil, input: nil, output: nil)
        }))
        
        let previous: Atomic<IODevices?> = Atomic(value: nil)
        
        let signal = self.signal |> afterDisposed {
            let devices = previous.swap(nil)
            if let list = devices?.audioOutput {
                for device in list {
                    AudioObjectRemovePropertyListener(device, &AudioAddress.nominalSampleRates, AudioListener.nominalSampler, nil)
                }
            }
        }
        
        updateSampler.set(signal.start(next: { devices in
            let previous = previous.swap(devices)
            if let list = previous?.audioOutput {
                for device in list {
                    AudioObjectRemovePropertyListener(device, &AudioAddress.nominalSampleRates, AudioListener.nominalSampler, nil)
                }
            }
            for device in devices.audioOutput {
                AudioObjectAddPropertyListener(device, &AudioAddress.nominalSampleRates, AudioListener.nominalSampler, nil)
            }
        }))
        
        update()
    }
    
    private func update() {
        _signal.set(devicesList(queue: devicesQueue) |> filter { !$0.loading })
    }
    
    @objc private func handleOutputNotification(_ notification: Notification) {
        self.update()
    }
    
    public static func resolveCaptureDeviceId(selectedId: String?, candidates: [CaptureDeviceCandidate], defaultId: String?) -> String? {
        if let selectedId, let device = candidates.first(where: { $0.uniqueID == selectedId }), device.isAvailable {
            return device.uniqueID
        }
        return defaultId
    }
    
    public static func resolveOutputDeviceId(selectedId: String?, available: [String], defaultId: String?) -> String? {
        if let selectedId, available.contains(selectedId) {
            return selectedId
        }
        return defaultId
    }
    
    private static func candidates(_ devices: [AVCaptureDevice]) -> [CaptureDeviceCandidate] {
        return devices.map { CaptureDeviceCandidate(uniqueID: $0.uniqueID, isAvailable: $0.isConnected && !$0.isSuspended) }
    }
    
    public static func updateCameraId(_ settings: VoiceCallSettings, devices: IODevices) -> String? {
        return resolveCaptureDeviceId(selectedId: settings.cameraInputDeviceId, candidates: candidates(devices.camera), defaultId: AVCaptureDevice.default(for: .video)?.uniqueID)
    }
    
    public static func updateMicroId(_ settings: VoiceCallSettings, devices: IODevices) -> String? {
        return resolveCaptureDeviceId(selectedId: settings.audioInputDeviceId, candidates: candidates(devices.audioInput), defaultId: AVCaptureDevice.default(for: .audio)?.uniqueID)
    }
    
    public static func updateOutputId(_ settings: VoiceCallSettings, devices: IODevices) -> String? {
        let available = devices.audioOutput.map { Audio.getDeviceUid(deviceId: $0) }
        return resolveOutputDeviceId(selectedId: settings.audioOutputDeviceId, available: available, defaultId: Audio.getDeviceUid(deviceId: Audio.getDefaultOutputDevice()))
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        AudioListener.releaseOutputListener()
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &AudioAddress.inputDevice, AudioListener.input, nil)
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &AudioAddress.devices, AudioListener.devices, nil)
        disposable.dispose()
        updateSampler.dispose()
    }
}

private extension DevicesContext {
    class Audio {
        public static func isOutputDevice(deviceID: AudioDeviceID) -> Bool {
            var propertySize: UInt32 = 256
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreams),
                mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMaster))
            
            _ = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
            
            return propertySize > 0
        }
        
        public static func isPrivateAggregateDevice(deviceID: AudioDeviceID) -> Bool {
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMaster)
            var transportType: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &size, &transportType) == noErr, transportType == kAudioDeviceTransportTypeAggregate else {
                return false
            }
            var compositionAddress = AudioObjectPropertyAddress(
                mSelector: kAudioAggregateDevicePropertyComposition,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMaster)
            var composition: Unmanaged<CFDictionary>?
            size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
            guard AudioObjectGetPropertyData(deviceID, &compositionAddress, 0, nil, &size, &composition) == noErr, let dictionary = composition?.takeRetainedValue() as? [String: Any] else {
                return false
            }
            return (dictionary[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue ?? false
        }
        
        public static func getDefaultOutputDevice() -> AudioDeviceID {
            var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
            var deviceID = kAudioDeviceUnknown
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMaster))
            
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
            
            return deviceID
        }
        
        private static func getNumberOfDevices() -> UInt32 {
            var propertySize: UInt32 = 0
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMaster))
            
            _ = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
            
            return propertySize / UInt32(MemoryLayout<AudioDeviceID>.size)
        }
        
        public static func getDeviceName(deviceID: AudioDeviceID) -> String {
            var propertySize = UInt32(MemoryLayout<CFString>.size)
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceNameCFString),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMaster))
            
            var result: CFString = "" as CFString
            
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &result)
            
            return result as String
        }
        
        public static func getDeviceUid(deviceId: AudioDeviceID) -> String {
            var propertySize = UInt32(MemoryLayout<CFString>.size)
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMaster)
            
            var deviceUid: CFString = "" as CFString
            AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, nil, &propertySize, &deviceUid)
            
            return deviceUid as String
        }
        
        public static func getAllDevices() -> [AudioDeviceID] {
            let devicesCount = getNumberOfDevices()
            var devices = [AudioDeviceID](repeating: 0, count: Int(devicesCount))
            
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMaster))
            
            var devicesSize = devicesCount * UInt32(MemoryLayout<UInt32>.size)
            
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &devicesSize, &devices)
            
            return devices
        }
        
    }
}
