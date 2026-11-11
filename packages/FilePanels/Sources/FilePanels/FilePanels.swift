import Cocoa
import TGUIKit
import TelegramTheme
import AppAnalytics

public let mediaExts:[String] = ["png","jpg","jpeg","tiff", "heic","mp4","mov","avi", "gif", "m4v"]
public let photoExts:[String] = ["png","jpg","jpeg","tiff", "heic"]
public let videoExts:[String] = ["mp4","mov","avi", "m4v"]
public let audioExts:[String] = ["mp3","wav", "m4a", "ogg"]

public func filePanel(with exts:[String]? = nil, allowMultiple:Bool = true, canChooseDirectories: Bool = false, for window:Window, appearance: NSAppearance? = theme.appearance, completion:@escaping ([String]?)->Void) {
    filePanel(with: exts, allowMultiple: allowMultiple, canChooseDirectories: canChooseDirectories, for: window, appearance: appearance, analyticsContext: nil, completion: completion)
}

public func filePanel(with exts:[String]? = nil, allowMultiple:Bool = true, canChooseDirectories: Bool = false, for window:Window, appearance: NSAppearance? = theme.appearance, analyticsContext: AnalyticsContext?, completion:@escaping ([String]?)->Void) {
    presentFilePanel(with: exts, allowMultiple: allowMultiple, canChooseDirectories: canChooseDirectories, for: window, appearance: appearance, analyticsContext: analyticsContext, cancelled: nil, completion: completion)
}

public func filePanel(with exts:[String]? = nil, allowMultiple:Bool = true, canChooseDirectories: Bool = false, for window:Window, appearance: NSAppearance? = theme.appearance, analyticsContext: AnalyticsContext?, cancelled: @escaping () -> Void, completion:@escaping ([String]?)->Void) {
    presentFilePanel(with: exts, allowMultiple: allowMultiple, canChooseDirectories: canChooseDirectories, for: window, appearance: appearance, analyticsContext: analyticsContext, cancelled: cancelled, completion: completion)
}

private func presentFilePanel(with exts: [String]?, allowMultiple: Bool, canChooseDirectories: Bool, for window: Window, appearance: NSAppearance?, analyticsContext: AnalyticsContext?, cancelled: (() -> Void)?, completion: @escaping ([String]?) -> Void) {
    let analyticsContext = analyticsContext ?? Analytics.shared.unresolvedContext()
    let analyticsPresentation = analyticsContext.beginPresentation()
    delay(0.01, closure: {
        var result:[String] = []
        let panel:NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = canChooseDirectories
        panel.appearance = appearance
        panel.canCreateDirectories = true
        panel.allowedFileTypes = exts
        panel.allowsMultipleSelection = allowMultiple
        Analytics.shared.screens.showStandalone(.systemFilePicker, owner: panel, context: analyticsContext)
        panel.beginSheetModal(for: window) { (response) in
            defer { analyticsPresentation.end() }
            Analytics.shared.screens.hideStandalone(owner: panel)
            if response == .OK {
                for url in panel.urls {
                    let path:String = url.path
                    if let exts = exts {
                        let ext:String = path.nsstring.pathExtension.lowercased()
                        if exts.contains(ext) || (canChooseDirectories && path.isDirectory) {
                            result.append(path)
                        }
                    } else {
                        result.append(path)
                    }
                }
                completion(result)
            } else {
                if response == .cancel { cancelled?() }
                completion(nil)
            }
        }
    })
}

public func selectFolder(for window:Window, completion:@escaping (String)->Void) {
    selectFolder(for: window, analyticsContext: nil, completion: completion)
}

public func selectFolder(for window:Window, analyticsContext: AnalyticsContext?, completion:@escaping (String)->Void) {
    let analyticsContext = analyticsContext ?? Analytics.shared.unresolvedContext()
    let analyticsPresentation = analyticsContext.beginPresentation()
    delay(0.01, closure: {
        var result:[String] = []
        let panel:NSOpenPanel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        Analytics.shared.screens.showStandalone(.systemFolderPicker, owner: panel, context: analyticsContext)
        panel.beginSheetModal(for: window) { (response) in
            defer { analyticsPresentation.end() }
            Analytics.shared.screens.hideStandalone(owner: panel)
            if response == .OK {
                for url in panel.urls {
                    let path:String = url.path
                    result.append(path)
                }
                if let first = result.first {
                    completion(first)
                }
            }
        }
    })
}

public func savePanel(file:String, ext:String, for window:Window, defaultName: String? = nil, completion:((String?)->Void)? = nil) {
    savePanel(file: file, ext: ext, for: window, defaultName: defaultName, analyticsContext: nil, completion: completion)
}

public func savePanel(file:String, ext:String, for window:Window, defaultName: String? = nil, analyticsContext: AnalyticsContext?, completion:((String?)->Void)? = nil) {
    
    let analyticsContext = analyticsContext ?? Analytics.shared.unresolvedContext()
    let analyticsPresentation = analyticsContext.beginPresentation()
    delay(0.01, closure: {
        let savePanel:NSSavePanel = NSSavePanel()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        savePanel.nameFieldStringValue = defaultName ?? "\(dateFormatter.string(from: Date())).\(ext)"
        
        let wLevel = window.level
       // if wLevel == .screenSaver {
            window.level = .normal
        //}
        
        Analytics.shared.screens.showStandalone(.systemFileSave, owner: savePanel, context: analyticsContext)
        savePanel.begin { (result) in
            defer { analyticsPresentation.end() }
            Analytics.shared.screens.hideStandalone(owner: savePanel)
            if result == NSApplication.ModalResponse.OK, let saveUrl = savePanel.url {
                try? FileManager.default.removeItem(atPath: saveUrl.path)
                try? FileManager.default.copyItem(atPath: file, toPath: saveUrl.path)
                completion?(saveUrl.path)
                delay(0.3, closure: {
                    FilePanelsHooks.shared?.showSavedPathSuccess(saveUrl.path)
                })
            } else {
                completion?(nil)
            }
            window.level = wLevel
        }
        
    })
}

public func savePanel(file:String, named:String, for window:Window, completion:((String)->Void)? = nil) {
    savePanel(file: file, named: named, for: window, analyticsContext: nil, completion: completion)
}

public func savePanel(file:String, named:String, for window:Window, analyticsContext: AnalyticsContext?, completion:((String)->Void)? = nil) {
    
    let analyticsContext = analyticsContext ?? Analytics.shared.unresolvedContext()
    let analyticsPresentation = analyticsContext.beginPresentation()
    delay(0.01, closure: {
        let savePanel:NSSavePanel = NSSavePanel()
        _ = DateFormatter()

        savePanel.nameFieldStringValue = named
        Analytics.shared.screens.showStandalone(.systemFileSave, owner: savePanel, context: analyticsContext)
        savePanel.beginSheetModal(for: window, completionHandler: {(result) in
            defer { analyticsPresentation.end() }
            Analytics.shared.screens.hideStandalone(owner: savePanel)
            
            if result == NSApplication.ModalResponse.OK, let saveUrl = savePanel.url {
                try? FileManager.default.copyItem(atPath: file, toPath: saveUrl.path)
                completion?(saveUrl.path)
            }
        })
    })
    
}
