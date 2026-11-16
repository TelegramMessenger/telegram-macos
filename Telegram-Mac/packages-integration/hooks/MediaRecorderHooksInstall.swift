import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import MediaRecorderUI
import TelegramMediaUtils

func installMediaRecorderUIHooks() {
    var hooks = MediaRecorderHooks(setPendingMedia: { chatInteraction, data in
        guard let chatInteraction = chatInteraction as? ChatInteraction else {
            return
        }
        chatInteraction.mediaPromise.set(data)
    }, clearRecordingState: { chatInteraction in
        guard let chatInteraction = chatInteraction as? ChatInteraction else {
            return
        }
        chatInteraction.update({ $0.withoutRecordingState() })
    })
    hooks.setPendingMediaWithContext = { chatInteraction, data, analyticsContext in
        guard let chatInteraction = chatInteraction as? ChatInteraction else { return }
        chatInteraction.recordingMediaPromise.set(data |> map { ($0, analyticsContext) })
    }
    hooks.setPendingRecording = { chatInteraction, data, analyticsContext, request in
        guard let chatInteraction = chatInteraction as? ChatInteraction else {
            request?.end()
            return
        }
        chatInteraction.recordingSubmissionPromise.set(data |> map { ($0, analyticsContext, request) })
    }
    installMediaRecorderHooks(hooks)
}
