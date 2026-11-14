import Cocoa

import TGUIKit
import TelegramCore
import InAppSettings
import SwiftSignalKit
import Postbox
import TelegramMedia
import ChatHistoryModel
import InputTextView
import Localization
import TelegramContext
import TelegramMediaUtils
import TelegramTheme


public class ChatVoiceRowItem: ChatMediaItem {
    
    fileprivate var isTranslateLoading: Bool

    
    public override init(_ initialSize:NSSize, _ chatInteraction:ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        self.isTranslateLoading = object.additionalData.transcribeTranslateLoading

        super.init(initialSize, chatInteraction, context, object, theme: theme)
        
        let isIncoming = object.message!.isIncoming(context.account, object.renderType == .bubble)
        
        let file = media as! TelegramMediaFile

        var waveform:AudioWaveform? = nil
        var duration:Double = 0
        for attr in file.attributes {
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
        if waveform == nil, file.isInstantVideo {
            let waveformBase64 = "DAAOAAkACQAGAAwADwAMABAADQAPABsAGAALAA0AGAAfABoAHgATABgAGQAYABQADAAVABEAHwANAA0ACQAWABkACQAOAAwACQAfAAAAGQAVAAAAEwATAAAACAAfAAAAHAAAABwAHwAAABcAGQAAABQADgAAABQAHwAAAB8AHwAAAAwADwAAAB8AEwAAABoAFwAAAB8AFAAAAAAAHwAAAAAAHgAAAAAAHwAAAAAAHwAAAAAAHwAAAAAAHwAAAAAAHwAAAAAAAAA="
            waveform = AudioWaveform(bitstream: Data(base64Encoded: waveformBase64)!, bitsPerSample: 5)
        }
        let parameters = ChatMediaVoiceLayoutParameters(showPlayer:chatInteraction.inlineAudioPlayer, waveform: waveform, duration:duration, isMarked: true, isWebpage: chatInteraction.isLogInteraction, resource: file.resource, presentation: .make(for: object.message!, account: context.account, renderType: object.renderType, theme: theme), media: media, automaticDownload: downloadSettings.isDownloable(object.message!))

        
        self.parameters = parameters
        
        
        let canTranscribe = canTranscribeMessage(object.message!, context: context)

        if canTranscribe, let message = object.message {
            var pending: Bool
            if let transcribe = message.audioTranscription {
                pending = transcribe.isPending
            } else {
                pending = false
            }
            let bgColor: NSColor
            if renderType == .list {
                bgColor = theme.colors.accent.withAlphaComponent(0.1)
            } else {
                if isIncoming {
                    bgColor = theme.colors.accent.withAlphaComponent(0.1)
                } else {
                    bgColor = theme.chat.grayText(false, true).withAlphaComponent(0.1)
                }
            }

            
            var transcribtedColor = theme.chat.textColor(isIncoming, object.renderType == .bubble)
            
            if let state = entry.additionalData.transribeState {


                var transcribed: String?
                switch state {
                case let .revealed(success):
                    if !success {
                        transcribed = strings().chatVoiceTransribeError
                        transcribtedColor = parameters.presentation.grayText
                    } else {
                        if let translatedText = entry.additionalData.transcribeTranslate, !translatedText.isEmpty {
                            transcribed = translatedText
                        } else if let result = entry.message?.audioTranscription, !result.text.isEmpty {
                            transcribed = result.text
                        }
                    }
                case .loading:
                    pending = true
                default:
                    break
                }

                let textLayout: FoldingTextLayout?
                if let transcribed = transcribed {
                    let caption: NSAttributedString = .initialize(string: transcribed, color: transcribtedColor, font: .normal(theme.fontSize))

                    textLayout = FoldingTextLayout.make(caption, context: context, revealed: Set(), takeLayout: { attr in
                        let layout = TextViewLayout(attr, alignment: .left, selectText: theme.chat.selectText(isIncoming, object.renderType == .bubble), strokeLinks: object.renderType == .bubble, alwaysStaticItems: true, disableTooltips: false, mayItems: !message.isCopyProtected(cachedData: chatInteraction.presentation.cachedData))
                        restrictCopying(layout.interactions, message: message, layout: layout, chatInteraction: chatInteraction)
                        return layout
                    })
   
                } else {
                    textLayout = nil
                }

                parameters.transcribeData = .init(state: .state(state), text: textLayout, isPending: pending, isTranslateLoading: isTranslateLoading, fontColor: transcribtedColor, backgroundColor: bgColor)
            } else if message.audioTranscription != nil {
                parameters.transcribeData = .init(state: .state(.collapsed(true)), text: nil, isPending: false, fontColor: transcribtedColor, backgroundColor: bgColor)
            } else {
                let locked: Bool
                if let cooldown = context.audioTranscriptionTrial.cooldownUntilTime, cooldown > Int32(Date().timeIntervalSince1970) {
                    locked = true
                } else {
                    locked = false
                }
                parameters.transcribeData = .init(state: locked ? .locked : .possible, text: nil, isPending: pending, fontColor: transcribtedColor, backgroundColor: bgColor)
            }
            parameters.transcribe = { [weak self] in
                self?.chatInteraction.transcribeAudio(message)
            }
        }
    }
    
    public override func contentNode() -> ChatMediaContentView.Type {
        return ChatVoiceContentView.self
    }
    
    public override var isBubbleFullFilled: Bool {
        return false
    }
    
    public override func canMultiselectTextIn(_ location: NSPoint) -> Bool {
        return super.canMultiselectTextIn(location)
    }
    
    public override var isForceRightLine: Bool {
        if let parameters = parameters as? ChatMediaVoiceLayoutParameters {
            if parameters.durationLayout.layoutSize.width + 50 + rightSize.width + insetBetweenContentAndDate > contentSize.width {
                return true
            }
        }
        return super.isForceRightLine
    }
    
    public override var blockWidth: CGFloat {
        if isBubbled {
            return min(super.blockWidth, 200)
        } else {
            return super.blockWidth
        }
    }

    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        if let parameters = parameters as? ChatMediaVoiceLayoutParameters {
            parameters.durationLayout.measure(width: width - 50)
            
            let canTranscribe = canTranscribeMessage(message!, context: context)

            
            let maxVoiceWidth:CGFloat = min(min(250, blockWidth), width - 50 - (canTranscribe ? 35 : 0))

            parameters.waveformWidth = maxVoiceWidth
            
            let width = parameters.waveformWidth + 50 + (canTranscribe ? 35 : 0)
            
            var addition: CGFloat = 0
            if let height = parameters.transcribeData?.makeSize(width)?.height {
                
                addition += height + 5
                if captionLayouts.isEmpty, renderType == .bubble, reactionsLayout == nil {
                    addition += rightSize.height
                }
            }
            
            if isTranslateLoading {
                parameters.transcribeData?.text?.makeImageBlock(backgroundColor: .blackTransparent)
            }

            return NSMakeSize(parameters.waveformWidth + 50 + (canTranscribe ? 35 : 0), 40 + addition)
        }
        return NSZeroSize
    }
    
    public override var instantlyResize: Bool {
        return true
    }
}
