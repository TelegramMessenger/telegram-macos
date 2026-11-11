import Cocoa
import SettingsUI

func installDeveloperUIHooks() {
    DeveloperHooks.install(DeveloperHooks(updateGraphicContext: {
        appDelegate?.updateGraphicContext()
    }))
}
