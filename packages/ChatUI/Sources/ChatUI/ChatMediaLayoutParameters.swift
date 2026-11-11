import Cocoa
import TelegramCore
import InAppSettings
import Postbox
import TGUIKit
import SwiftSignalKit
import TGModernGrowingTextView
import InputView
import TelegramMedia
import TelegramMediaResources
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatModeTypes
import AudioPlayerCore

public class ChatMediaLayoutParameters : Equatable {
    
    public var showMedia:(Message)->Void = {_ in }
    public var showMessage:(Message)->Void = {_ in }
    
    public let isRevealed: Bool
    public var forceSpoiler: Bool = false
    public var payAmount: Int64? = nil
    public var isProtected: Bool = false
    public var canReveal: Bool = true
    
    public var colors: [LottieColor]


    public var revealMedia:(Message)->Void = { _ in }
    
    public var chatLocationInput:(Message)->ChatLocationInput = { _ in fatalError() }
    public var chatMode:ChatMode = .history
    
    public var getUpdatingMediaProgress:(MessageId)->Signal<Float?, NoError> = { _ in return .single(nil) }
    public var cancelOperation:(Message, Media)->Void = { _, _ in }
    
    public let presentation: ChatMediaPresentation
    public let media: Media
    
    
    public var runEmojiScreenEffect:(String)->Void = { _ in }
    
    public var runPremiumScreenEffect:(Message)->Void = { _ in }
    
    public var markDiceAsPlayed:(Message)->Void = { _ in }
    public var dicePlayed:(Message)->Bool = { _ in return true }
    
    public var mirror: Bool = false
    
    private var _timeCodeInitializer: Double? = nil

    public var timeCodeInitializer:Double? {
        let current = self._timeCodeInitializer
        self._timeCodeInitializer = nil
        return current
    }
    
    public func remove_timeCodeInitializer() {
        self._timeCodeInitializer = nil
    }
    
    public func set_timeCodeInitializer(_ timecode: Double?) {
        self._timeCodeInitializer = timecode
    }
    
    private var _automaticDownload: Bool
    
    public var automaticDownload: Bool {
        get {
            let value = _automaticDownload
//            _automaticDownload = false
            return value
        }
    }
    
    public let autoplayMedia: AutoplayMediaPreferences
    
    public var autoplay: Bool
    public var soundOnHover: Bool {
        return autoplayMedia.soundOnHover
    }
    public var preload: Bool {
        return autoplayMedia.preloadVideos
    }
    
//    var autoplay: Bool {
//        get {
//            let value = _automaticDownload
//            return value
//        }
//    }
//
    
    public var automaticDownloadFunc:(Message)->Bool
    
    public var fillContent: Bool? = nil
    public var bubbleCorners: () -> ImageCorners? = { nil }
    public var flatSides: LayoutPositionFlags = []

    public init(presentation: ChatMediaPresentation, media: Media, automaticDownload: Bool = true, autoplayMedia: AutoplayMediaPreferences = .defaultSettings, isRevealed: Bool? = nil, colors: [LottieColor] = []) {
        self.automaticDownloadFunc = { _ in
            return automaticDownload
        }
        self.presentation = presentation
        self.media = media
        self.colors = colors
        self.isRevealed = isRevealed ?? false
        self.autoplayMedia = autoplayMedia
        self._automaticDownload = automaticDownload
        if let media = media as? TelegramMediaFile {
            if media.isVideo && media.isAnimated {
                self.autoplay = autoplayMedia.gifs
            } else {
                self.autoplay = autoplayMedia.videos
            }
        } else {
            self.autoplay = false
        }
    }
    
    
    public static func layout(for media:TelegramMediaFile, isWebpage: Bool, chatInteraction:ChatInteraction, presentation: ChatMediaPresentation, automaticDownload: Bool, isIncoming: Bool, isFile: Bool = false, autoplayMedia: AutoplayMediaPreferences, isChatRelated: Bool = false, isCopyProtected: Bool = false, isRevealed: Bool? = nil) -> ChatMediaLayoutParameters {
        if media.isInstantVideo && !isFile {
            var duration:Double = 0
            for attr in media.attributes {
                switch attr {
                case let .Video(_duration, _, _, _, _, _):
                    duration = _duration
                default:
                    break
                }
            }
            
            return ChatMediaVideoMessageLayoutParameters(showPlayer:chatInteraction.inlineAudioPlayer, duration: duration, isMarked: true, isWebpage: isWebpage || chatInteraction.isLogInteraction, resource: media.resource, presentation: presentation, media: media, automaticDownload: automaticDownload, autoplayMedia: autoplayMedia, isRevealed: isRevealed)
        } else if media.isVoice && !isFile {
            var waveform:AudioWaveform? = nil
            var duration:Double = 0
            for attr in media.attributes {
                switch attr {
                case let .Audio(_, _duration, _, _, _data):
                    if let data = _data {
                        waveform = AudioWaveform(bitstream: data, bitsPerSample: 5)
                    }
                    duration = Double(_duration)
                default:
                    break
                }
            }
            
            return ChatMediaVoiceLayoutParameters(showPlayer:chatInteraction.inlineAudioPlayer, waveform:waveform, duration: duration, isMarked: true, isWebpage: isWebpage || chatInteraction.isLogInteraction, resource: media.resource, presentation: presentation, media: media, automaticDownload: automaticDownload)
        } else if media.isMusic && !isFile {
            var audioTitle:String?
            var audioPerformer:String?
            
            var duration:Int = 0
            for attribute in media.attributes {
                if case let .Audio(_, d, title, performer, _) = attribute {
                    duration = d
                    audioTitle = title
                    audioPerformer = performer
                    break
                }
            }
            
            let attr = NSMutableAttributedString()
            
            
            if let _audioTitle = audioTitle, let audioPerformer = audioPerformer {
                if _audioTitle.isEmpty && audioPerformer.isEmpty {
                    _ = attr.append(string: media.fileName, color: presentation.text, font: NSFont.medium(.title))
                    audioTitle = media.fileName
                } else {
                    _ = attr.append(string: _audioTitle + " - " + audioPerformer, color: presentation.text, font: NSFont.medium(.title))
                }
            } else {
                _ = attr.append(string: media.fileName, color: presentation.text, font: NSFont.medium(.title))
                audioTitle = media.fileName
            }
            
            return ChatMediaMusicLayoutParameters(nameLayout: TextViewLayout(attr, maximumNumberOfLines: 1, truncationType: .end), durationLayout: TextViewLayout(.initialize(string: String.durationTransformed(elapsed: duration), color: presentation.grayText, font: .normal(.title)), maximumNumberOfLines: 1, truncationType: .end), sizeLayout: TextViewLayout(.initialize(string: (media.size ?? 0).prettyNumber, color: presentation.grayText, font: .normal(.title)), maximumNumberOfLines: 1, truncationType: .middle), resource: media.resource, isWebpage: isWebpage, title: audioTitle, performer: audioPerformer, showPlayer:chatInteraction.inlineAudioPlayer, presentation: presentation, media: media, automaticDownload: automaticDownload)
        } else {
            var fileName:String = "Unknown.file"
            if let name = media.fileName {
                fileName = name
            }
            return ChatFileLayoutParameters(fileName: fileName, hasThumb: !media.previewRepresentations.isEmpty, presentation: presentation, media: media, automaticDownload: automaticDownload, isIncoming: isIncoming, autoplayMedia: autoplayMedia, isChatRelated: isChatRelated, isCopyProtected: isCopyProtected)
        }
    }
    
    @discardableResult public func makeLabelsForWidth(_ width: CGFloat) -> CGFloat {
        return 0
    }
    
}

public class ChatMediaGalleryParameters : ChatMediaLayoutParameters {
    public let isWebpage: Bool

    public init(showMedia:@escaping(Message)->Void = { _ in }, showMessage:@escaping(Message)->Void = { _ in }, isWebpage: Bool, presentation: ChatMediaPresentation = .Empty, media: Media, automaticDownload: Bool, autoplayMedia: AutoplayMediaPreferences = AutoplayMediaPreferences.defaultSettings, isRevealed: Bool? = nil) {
        self.isWebpage = isWebpage
        super.init(presentation: presentation, media: media, automaticDownload: automaticDownload, autoplayMedia: autoplayMedia, isRevealed: isRevealed)
        self.showMedia = showMedia
        self.showMessage = showMessage
    }
}

public func ==(lhs:ChatMediaLayoutParameters, rhs:ChatMediaLayoutParameters) -> Bool {
    return false
}

public extension ImageCorners {
    static func chatMedia(_ positionFlags: LayoutPositionFlags?, bubble: ImageCorners?, inner: CGFloat = .cornerRadius, flat: LayoutPositionFlags = []) -> ImageCorners {
        func corner(_ vertical: LayoutPositionFlags, _ horizontal: LayoutPositionFlags, _ edge: ImageCorner?) -> ImageCorner {
            if let positionFlags, positionFlags.contains(vertical), positionFlags.contains(horizontal) {
                return edge ?? .Corner(inner * 3 + 2)
            }
            return flat.contains(vertical) ? .Corner(0) : .Corner(inner)
        }
        return ImageCorners(
            topLeft: corner(.top, .left, bubble?.topLeft),
            topRight: corner(.top, .right, bubble?.topRight),
            bottomLeft: corner(.bottom, .left, bubble?.bottomLeft),
            bottomRight: corner(.bottom, .right, bubble?.bottomRight),
            smoothing: bubble?.smoothing ?? 0.0
        )
    }
}
