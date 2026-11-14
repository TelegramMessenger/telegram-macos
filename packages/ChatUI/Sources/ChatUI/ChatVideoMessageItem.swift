import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import Postbox
import ChatHistoryModel
import InputTextView
import Localization
import TelegramContext
import TelegramMediaUtils
import TelegramTheme


public class ChatVideoMessageItem: ChatMediaItem {

    fileprivate var isTranslateLoading: Bool

    public override init(_ initialSize:NSSize, _ chatInteraction:ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        self.isTranslateLoading = object.additionalData.transcribeTranslateLoading

        super.init(initialSize, chatInteraction, context, object, theme: theme)

        let isIncoming = object.message!.isIncoming(context.account, object.renderType == .bubble)

        let parameters: ChatMediaVideoMessageLayoutParameters = ChatMediaLayoutParameters.layout(for: media as! TelegramMediaFile, isWebpage: false, chatInteraction: chatInteraction, presentation: .make(for: object.message!, account: context.account, renderType: object.renderType, theme: theme), automaticDownload: downloadSettings.isDownloable(object.message!), isIncoming: isIncoming, autoplayMedia: object.autoplayMedia) as! ChatMediaVideoMessageLayoutParameters

        let message = object.message!
        parameters.transcribe = { [weak self] in
            self?.chatInteraction.transcribeAudio(message)
        }

        let canTranscribe = canTranscribeMessage(message, context: context)

        if canTranscribe {
            var pending: Bool
            if let transcribe = message.audioTranscription {
                pending = transcribe.isPending
            } else {
                pending = false
            }
            let bgColor: NSColor
            let fgColor: NSColor
            if renderType == .list {
                bgColor = theme.colors.accent.withAlphaComponent(0.1)
                fgColor = parameters.presentation.activityBackground
            } else {
                bgColor = theme.chatServiceItemColor
                fgColor = theme.chatServiceItemTextColor
            }

            var transcribtedColor = fgColor

            if let state = object.additionalData.transribeState {
                var transcribed: String?
                switch state {
                case let .revealed(success):
                    if !success {
                        transcribed = strings().chatVoiceTransribeError
                        transcribtedColor = parameters.presentation.grayText
                    } else {
                        if let translatedText = object.additionalData.transcribeTranslate, !translatedText.isEmpty {
                            transcribed = translatedText
                        } else if let result = message.audioTranscription, !result.text.isEmpty {
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
            } else if let _ = message.audioTranscription {
                parameters.transcribeData = .init(state: .state(.collapsed(true)), text: nil, isPending: false, fontColor: transcribtedColor, backgroundColor: bgColor)
            } else {
                let locked: Bool
                if let cooldown = context.audioTranscriptionTrial.cooldownUntilTime, cooldown > Int32(Date().timeIntervalSince1970) {
                    locked = true
                } else {
                    locked = false
                }
                parameters.transcribeData = .init(state: locked ? .locked : .possible, text: nil, isPending: pending, fontColor: fgColor, backgroundColor: bgColor)
            }
        }
        self.parameters = parameters
    }
    
    public var canTranscribe: Bool {
        return canTranscribeMessage(message!, context: context)
    }
    
    public override var instantlyResize: Bool {
        return true
    }
    
    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        if let parameters = parameters as? ChatMediaVideoMessageLayoutParameters {
            parameters.durationLayout.measure(width: width - 50)
            _ = parameters.transcribeData?.makeSize(width)
            if isTranslateLoading {
                parameters.transcribeData?.text?.makeImageBlock(backgroundColor: .blackTransparent)
            }
        }
        return super.makeContentSize(width)
    }
    
}
