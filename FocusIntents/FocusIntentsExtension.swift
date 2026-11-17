import AppIntents
import ExtensionFoundation

@main
struct FocusIntentsExtension: AppIntentsExtension {
    init() {
        _ = FocusIntentStorage.lifecycle
    }
}
