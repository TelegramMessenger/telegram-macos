import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import ApiCredentials
import InAppSettings
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import InputDataUI
import TelegramIconsTheme
import AlertsUI
import TelegramMediaUtils

public extension TelegramApplicationIcons.Icon {
    var path: String {
        return iconsFolder + "/" + self.file.fileName!
    }
    
    func resourcePath(_ context: any AccountContextProtocol) -> String? {
        if self.file.fileName == TelegramApplicationIcons.Icon.defaultIconName {
            return nil
        } else {
            return context.account.postbox.mediaBox.resourcePath(self.file.resource)
        }
    }
    
    var isPremium: Bool {
        if let fileName = file.fileName, fileName.contains("Premium") {
            return true
        }
        return false
    }
    
    static let defaultIconName = "Default.icns"
}

private var iconsFolder: String {
    return ApiEnvironment.containerURL!.appendingPathComponent("icons").path
}

public final class DockControl {
    
    private let promise: ValuePromise<TelegramApplicationIcons> = .init()
    
    public var icons: Signal<TelegramApplicationIcons, NoError> {
        return promise.get()
    }
    
    private let disposable = MetaDisposable()
    
    private let fetch = DisposableSet()
    private let data = DisposableSet()
    
    private let engine: TelegramEngine
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let update = MetaDisposable()
    private let applyResource = MetaDisposable()
    public init(_ engine: TelegramEngine, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.engine = engine
        self.accountManager = accountManager
        loadResources()
        
        observeSelection()
    }
    
    private func loadResources() {
        disposable.set((engine.resources.applicationIcons() |> deliverOnMainQueue).start(next: { [weak self] icons in
            self?.update(icons)
        }))
    }
    
    private func update(_ icons: TelegramApplicationIcons) {
        for icon in icons.icons {
            let fetchDispsable = fetchedMediaResource(mediaBox: engine.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: .media(media: AnyMediaReference.message(message: icon.reference, media: icon.file), resource: icon.file.resource)).start()
            fetch.add(fetchDispsable)
        }
        self.promise.set(icons)
    }
    
    private func observeSelection() {
        let signal = combineLatest(self.icons, dockSettings(accountManager: accountManager))
        |> distinctUntilChanged(isEqual: { previous, current in
            previous.0 == current.0 && previous.1 == current.1
        })
        |> deliverOnMainQueue
        update.set(signal.start(next: { [weak self] icons, settings in
            guard let self else {
                return
            }
            self.applyResource.set(nil)

            guard let selected = settings.iconSelected, selected != TelegramApplicationIcons.Icon.defaultIconName else {
                Dock.setCustomAppIcon(path: nil)
                return
            }
            if let icon = icons.icons.first(where: { $0.file.fileName == selected }) {
                let resource = self.engine.account.postbox.mediaBox.resourceData(icon.file.resource) |> filter { $0.complete } |> take(1) |> deliverOnMainQueue
                self.applyResource.set(resource.start(next: { resource in
                    Dock.setCustomAppIcon(path: resource.path)
                }))
            }
        }))
    }
    
    public func clear() {
        update.dispose()
        data.dispose()
        fetch.dispose()
        disposable.dispose()
        applyResource.dispose()
    }
    
    deinit {
        clear()
    }
}

//
//private func moveIconToCache(path: String, icon: TelegramApplicationIcons.Icon) {
//    try? FileManager.default.createDirectory(at: URL(fileURLWithPath: iconsFolder), withIntermediateDirectories: true, attributes: nil)
//    
//    if let fileName = icon.file.fileName {
//        try? FileManager.default.copyItem(atPath: path, toPath: iconsFolder + "/" + fileName)
//    }
//}
