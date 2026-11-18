import InputView
import Postbox
import TelegramCore

func pollTextInputForSending(_ state: ChatTextInputState, isPremium: Bool) -> ChatTextInputState {
    if isPremium {
        return state
    }
    let attributes = state.attributes.filter { attribute in
        if case let .animated(_, _, fileId, file, _) = attribute {
            guard let file = file, file.fileId == MediaId(namespace: Namespaces.Media.CloudFile, id: fileId), file.isCustomEmoji else {
                return false
            }
        }
        return true
    }
    return ChatTextInputState(inputText: state.inputText, selectionRange: state.selectionRange, attributes: attributes).unique(isPremium: false)
}
