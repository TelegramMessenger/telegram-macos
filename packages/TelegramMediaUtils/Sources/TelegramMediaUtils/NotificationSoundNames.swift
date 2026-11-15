import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import Localization
import TGUIKit

private var modernSoundsNamePaths: [String] {
    return [
        strings().notificationsSoundNote,
        strings().notificationsSoundAurora,
        strings().notificationsSoundBamboo,
        strings().notificationsSoundChord,
        strings().notificationsSoundCircles,
        strings().notificationsSoundComplete,
        strings().notificationsSoundHello,
        strings().notificationsSoundInput,
        strings().notificationsSoundKeys,
        strings().notificationsSoundPopcorn,
        strings().notificationsSoundPulse,
        strings().notificationsSoundSynth
    ]
}

private var classicSoundNamePaths: [String] {
    return [
        strings().notificationsSoundTritone,
        strings().notificationsSoundTremolo,
        strings().notificationsSoundAlert,
        strings().notificationsSoundBell,
        strings().notificationsSoundCalypso,
        strings().notificationsSoundChime,
        strings().notificationsSoundGlass,
        strings().notificationsSoundTelegraph
    ]
}

private func soundName(sound: PeerMessageSound) -> String {
    switch sound {
        case .none:
            return strings().notificationsSoundNone
        case .default:
            return ""
        case let .bundledModern(id):
            let names = modernSoundsNamePaths
            if id >= 0 && Int(id) < names.count {
                return names[Int(id)]
            }
            return "Sound \(id)"
        case let .bundledClassic(id):
            let names = classicSoundNamePaths
            if id >= 0 && Int(id) < names.count {
                return names[Int(id)]
            }
            return "Sound \(id)"
    case let .cloud(fileId):
        return "Sound \(fileId)"
    }
}

public func localizedPeerNotificationSoundString(sound: PeerMessageSound, default: PeerMessageSound? = nil, list: [NotificationSoundList.NotificationSound]? = nil) -> String {
    switch sound {
    case .`default`:
        if let defaultSound = `default` {
            let name = soundName(sound: defaultSound)
            let actualName: String
            if name.isEmpty {
                actualName = soundName(sound: .bundledModern(id: 0))
            } else {
                actualName = name
            }
            return strings().peerInfoNotificationsDefaultSound(actualName)
        } else {
            return strings().peerInfoNotificationsDefault
        }
    case let .cloud(fileId):
        if let list = list, let sound = list.first(where: { $0.file.fileId.id == fileId }) {
            if sound.file.fileName == nil || sound.file.fileName!.isEmpty, sound.file.isVoice {
                return strings().notificationSoundToneVoice
            }
            return (sound.file.fileName ?? "#").nsstring.deletingPathExtension
        } else {
            return strings().peerInfoNotificationsDefault
        }
    default:
        return soundName(sound: sound)
    }
}

public func fileNameForNotificationSound(postbox: Postbox, sound: PeerMessageSound, defaultSound: PeerMessageSound?, list: [NotificationSoundList.NotificationSound]? = nil) -> Signal<TelegramMediaResource?, NoError> {
    switch sound {
    case .none:
        return .single(nil)
    case .`default`:
        if let defaultSound = defaultSound {
            if case .default = defaultSound {
                return .single(SoundEffectPlay.resource(name: "100", type: "m4a"))
            } else {
                return fileNameForNotificationSound(postbox: postbox, sound: defaultSound, defaultSound: nil, list: list)
            }
        } else {
            return .single(LocalFileReferenceMediaResource(localFilePath: "default", randomId: arc4random64()))
        }
    case let .bundledModern(id):
        return .single(SoundEffectPlay.resource(name: "\(id + 100)", type: "m4a"))
    case let .bundledClassic(id):
        return .single(SoundEffectPlay.resource(name: "\(id + 2)", type: "m4a"))
    case let .cloud(fileId):
        if let list = list {
            if let file = list.first(where: { $0.file.fileId.id == fileId})?.file {
                _ = fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: .other, userContentType: .other, reference: .standalone(resource: file.resource), ranges: nil, statsCategory: .audio, reportResultStatus: true).start()
                return postbox.mediaBox.resourceData(id: file.resource.id) |> filter { $0.complete } |> take(1) |> map { _ in
                    return file.resource
                }
            }
        }
        return .single(nil)
    }
}
