import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InAppSettings
import ColorPalette
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import DiceCache
import AppAnalytics

private final class Arguments {
    let context: any AccountContextProtocol
    let openStickerPack: (StickerPackCollectionInfo) -> Void
    let removePack: (ItemCollectionId) -> Void
    let openStickerBot:()->Void
    let toggleSuggest:()->Void
    init(context: any AccountContextProtocol, openStickerPack: @escaping (StickerPackCollectionInfo) -> Void, removePack: @escaping (ItemCollectionId) -> Void, openStickerBot:@escaping()->Void, toggleSuggest:@escaping()->Void) {
        self.context = context
        self.openStickerPack = openStickerPack
        self.removePack = removePack
        self.openStickerBot = openStickerBot
        self.toggleSuggest = toggleSuggest
    }
}

private struct State : Equatable {
    struct Section : Equatable {
        var info: StickerPackCollectionInfo
        var topItem: StickerPackItem?
        var count: Int32
        var installed: Bool
        var editing: ItemListStickerPackItemEditing
    }
    var editing: ItemListStickerPackItemEditing = .init(editable: true, editing: false)
    var sections:[Section]
    var suggest: Bool = false
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("suggest"), data: .init(name: strings().customEmojiSuggest, color: theme.colors.text, type: .switchable(state.suggest), viewType: .singleItem, enabled: true, action: arguments.toggleSuggest)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    for (i, section) in state.sections.enumerated() {
        
        struct Tuple : Equatable {
            let section: State.Section
            let viewType: GeneralViewType
        }
        
        let tuple = Tuple(section: section, viewType: bestGeneralViewType(state.sections, for: i))
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("_id_\(section.info.id.id)"), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
            return StickerSetTableRowItem(initialSize, context: arguments.context, stableId: stableId, info: tuple.section.info, topItem: tuple.section.topItem, itemCount: tuple.section.count, unread: false, editing: section.editing, enabled: true, control: .none, viewType: tuple.viewType, action: {
                arguments.openStickerPack(tuple.section.info)
            }, removePack: {
                arguments.removePack(tuple.section.info.id)
            })
        }))
        index += 1
    }
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().customEmojiInfo, linkHandler: { _ in
        arguments.openStickerBot()
    }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    
  
    // entries
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func CustomEmojiController(context: any AccountContextProtocol) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State(sections: [], suggest: FastSettings.suggestSwapEmoji)
    
    let statePromise: ValuePromise<State> = ValuePromise(ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let arguments = Arguments(context: context, openStickerPack: { info in
        showModal(with: StickerSettingsHooks.shared.makeStickerPackPreview(context, nil, [.emoji(.name(info.shortName))]), for: context.window)
    }, removePack: { id in
        
        verifyAlert_button(for: context.window, information: strings().installedStickersRemoveDescription, ok: strings().installedStickersRemoveDelete, successHandler: { result in
            switch result {
            case .basic:
                _ = context.engine.stickers.removeStickerPackInteractively(id: id, option: .delete).start()
            case .thrid:
                break
            }
        })
    }, openStickerBot: {
        StickerSettingsHooks.shared.openStickersBot(context)
    }, toggleSuggest: {
        updateState { current in
            var current = current
            current.suggest = !current.suggest
            return current
        }
        FastSettings.toggleSwapEmoji(stateValue.with { $0.suggest})
    })
    
    let emojiPacksKey: PostboxViewKey = .itemCollectionInfos(namespaces: [Namespaces.ItemCollection.CloudEmojiPacks])

    
    actionsDisposable.add(context.account.postbox.combinedView(keys: [emojiPacksKey]).start(next: { view in
        updateState { current in
            var current = current
            var sections: [State.Section] = []
            let packs = (view.views[emojiPacksKey] as? ItemCollectionInfosView)?.entriesByNamespace[Namespaces.ItemCollection.CloudEmojiPacks] ?? []
            for pack in packs {
                if let info = pack.info as? StickerPackCollectionInfo, pack.count > 0 {
                    sections.append(.init(info: info, topItem: pack.firstItem as? StickerPackItem, count: pack.count, installed: true, editing: current.editing))
                }
            }
            current.sections = sections
            return current
        }
    }))
    
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().installedStickersCustomEmoji, hasDone: false)
    controller.analyticsScreen = .settingsStickersEmojiCustomEmoji
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.afterTransaction = { controller in
        let resortRange = NSMakeRange(3, controller.tableView.count - 5)
        if resortRange.length > 0 {
            
            let sections = stateValue.with { $0.sections }
            
            controller.tableView.resortController = .init(resortRange: resortRange, start: {_ in }, resort: { _ in }, complete: { fromIndex, toIndex in
                if fromIndex == toIndex {
                    return
                }
                
                let fromSection = sections[fromIndex - resortRange.location]
                let toSection = sections[toIndex - resortRange.location]

                let referenceId: ItemCollectionId = toSection.info.id
                
                let _ = (context.account.postbox.transaction { transaction -> Void in
                    var infos = transaction.getItemCollectionsInfos(namespace: Namespaces.ItemCollection.CloudEmojiPacks)
                    var reorderInfo: ItemCollectionInfo?
                    for i in 0 ..< infos.count {
                        if infos[i].0 == fromSection.info.id {
                            reorderInfo = infos[i].1
                            infos.remove(at: i)
                            break
                        }
                    }
                    if let reorderInfo = reorderInfo {
                        var inserted = false
                        for i in 0 ..< infos.count {
                            if infos[i].0 == referenceId {
                                if fromIndex < toIndex {
                                    infos.insert((fromSection.info.id, reorderInfo), at: i + 1)
                                } else {
                                    infos.insert((fromSection.info.id, reorderInfo), at: i)
                                }
                                inserted = true
                                break
                            }
                        }
                        if !inserted {
                            infos.append((fromSection.info.id, reorderInfo))
                        }
                        addSynchronizeInstalledStickerPacksOperation(transaction: transaction, namespace: Namespaces.ItemCollection.CloudEmojiPacks, content: .sync, noDelay: false)
                        transaction.replaceItemCollectionInfos(namespace: Namespaces.ItemCollection.CloudEmojiPacks, itemCollectionInfos: infos)
                    }
                 } |> deliverOnMainQueue).start(completed: { })
                
            })
        } else {
            controller.tableView.resortController = nil
            controller.navigationController?.back()
        }
        
    }

    return controller
    
}

