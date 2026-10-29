import Cocoa
import LocalAnimations
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI

import SwiftSignalKit
import Postbox
import TelegramCore
import InAppSettings
import TGUIKit


private final class ChatListPresetArguments {
    let environment: SidebarUIEnvironment
    let context: any AccountContextProtocol
    let openPreset:(ChatListFilter, Bool)->Void
    let removePreset: (ChatListFilter)->Void
    let addFeatured: (ChatListFeaturedFilter)->Void
    let toggleSidebar: (Bool)->Void
    let limitExceeded:()->Void
    let toggleTags:(Bool)->Void
    init(context: any AccountContextProtocol, environment: SidebarUIEnvironment, openPreset: @escaping(ChatListFilter, Bool)->Void, removePreset: @escaping(ChatListFilter)->Void, addFeatured: @escaping(ChatListFeaturedFilter)->Void, toggleSidebar: @escaping(Bool)->Void, limitExceeded:@escaping()->Void, toggleTags:@escaping(Bool)->Void) {
        self.context = context
        self.environment = environment
        self.openPreset = openPreset
        self.removePreset = removePreset
        self.addFeatured = addFeatured
        self.toggleSidebar = toggleSidebar
        self.limitExceeded = limitExceeded
        self.toggleTags = toggleTags
    }
}
private func _id_preset(_ filter: ChatListFilter) -> InputDataIdentifier {
    return InputDataIdentifier("_id_filter_\(filter.sidebarId)")
}
private func _id_recommended(_ index: Int32) -> InputDataIdentifier {
    return InputDataIdentifier("_id_recommended\(index)")
}
private let _id_add_new = InputDataIdentifier("_id_add_new")
private let _id_add_tabs = InputDataIdentifier("_id_add_tabs")
private let _id_badge_tabs = InputDataIdentifier("_id_badge_tabs")

private let _id_header = InputDataIdentifier("_id_header")

private let _id_show_tags = InputDataIdentifier("_id_show_tags")

private func chatListPresetEntries(filtersWithCounts: [(ChatListFilter, Int)], sidebar: Bool, showTags: Bool, suggested: ChatListFiltersFeaturedState?, arguments: ChatListPresetArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1


    let limit = arguments.context.isPremium ? arguments.environment.limits.dialog_filters_limit_premium : arguments.environment.limits.dialog_filters_limit_default

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: nil, comparable: nil, item: { initialSize, stableId in

        let attributedString = NSMutableAttributedString()

        _ = attributedString.append(string: strings().chatListFilterHeader, color: theme.colors.listGrayText, font: .normal(.text))

        return ChatListFiltersHeaderItem(initialSize, context: arguments.context, environment: arguments.environment, stableId: stableId, sticker: .folder, text: attributedString)
    }))

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterListHeader), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textTopItem)))
    index += 1

    let filtersWithCounts = filtersWithCounts.filter { filter, _ in
        if !arguments.context.isPremium {
            return !filter.isAllChats
        } else {
            return true
        }
    }

    let sharedImage = arguments.environment.image(.iconSharedFolder).precomposed(theme.colors.grayText.withAlphaComponent(0.8))

    for (filter, count) in filtersWithCounts {
        var viewType = bestGeneralViewType(filtersWithCounts.map { $0.0 }, for: filter)

        if filtersWithCounts.count == 1 {
            viewType = .firstItem
        } else if filter == filtersWithCounts.last?.0, filtersWithCounts.count < arguments.environment.limits.dialog_filters_limit_premium {
            viewType = .innerItem
        }

        switch filter {
        case .allChats:
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_preset(filter), data: .init(name: filter.title, color: theme.colors.text, icon: FolderIcon(emoticon: .allChats).icon(for: .preview, image: arguments.environment.folderImage), type: .none, viewType: viewType)))
            index += 1
        case let .filter(_, title, _, data):

            var image: CGImage?
            if let color = data.color, showTags {

                let colors = [theme.colors.peerColors(0).bottom,
                              theme.colors.peerColors(1).bottom,
                              theme.colors.peerColors(2).bottom,
                              theme.colors.peerColors(3).bottom,
                              theme.colors.peerColors(4).bottom,
                              theme.colors.peerColors(5).bottom,
                              theme.colors.peerColors(6).bottom]

                image = generateImage(NSMakeSize(20, 20), contextGenerator: { size, ctx in
                    ctx.clear(size.bounds)
                    ctx.setFillColor(colors[abs(Int(color.rawValue)) % colors.count].cgColor)
                    ctx.fillEllipse(in: size.bounds)
                })

                if data.isShared {
                    image = generateImage(NSMakeSize(20 + 3 + sharedImage.backingSize.width, 20), contextGenerator: { size, ctx in
                        ctx.clear(size.bounds)
                        var rect = size.bounds.focus(sharedImage.backingSize)
                        rect.origin.x = 0
                        ctx.draw(sharedImage, in: rect)

                        var rect2 = size.bounds.focus(image!.backingSize)
                        rect2.origin.x = rect.maxX + 3
                        ctx.draw(image!, in: rect2)
                    })
                }

            } else if data.isShared {
                image = sharedImage
            } else {
                image = nil
            }

            struct E : Equatable {
                let filter: ChatListFilter
                let viewType: GeneralViewType
                let count: Int
            }

            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_preset(filter), equatable: InputDataEquatable(E(filter: filter, viewType: viewType, count: count)), comparable: nil, item: { initialSize, stableId in

                let attr = NSMutableAttributedString()
                attr.append(string: title.text, color: theme.colors.text, font: .normal(.text))
                arguments.environment.applyInlineStickers(to: attr, entities: title.entities, isPremium: arguments.context.isPremium, animated: title.enableAnimations)

                return GeneralInteractedRowItem(initialSize, stableId: stableId, name: title.text, nameAttributed: attr, icon: FolderIcon(filter).icon(for: .preview, image: arguments.environment.folderImage), type: image != nil ? .nextImage(image!) : .nextContext(count > 0 ? "\(count)" : ""), viewType: viewType, action: {
                    arguments.openPreset(filter, false)
                }, menuItems: {
                    return filterContextMenuItems(filter, unreadCount: nil, context: arguments.context, environment: arguments.environment)
                }, context: arguments.context)
            }))
            index += 1

//            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_preset(filter), data: .init(name: title.text, color: theme.colors.text, icon: FolderIcon(filter).icon(for: .preview, image: arguments.environment.folderImage), type: image != nil ? .nextImage(image!) : .nextContext(count > 0 ? "\(count)" : ""), viewType: viewType, enabled: true, description: nil, action: {
//                arguments.openPreset(filter, false)
//            }, menuItems: {
//                return filterContextMenuItems(filter, unreadCount: nil, context: arguments.context, environment: arguments.environment)
//            })))
//            index += 1

        }
    }
    if filtersWithCounts.count < arguments.environment.limits.dialog_filters_limit_premium {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_add_new, data: InputDataGeneralData(name: strings().chatListFilterListAddNew, color: theme.colors.accent, type: .next, viewType: filtersWithCounts.isEmpty ? .singleItem : .lastItem, action: {

            if filtersWithCounts.count < limit {
                arguments.openPreset(ChatListFilter.new(excludeIds: filtersWithCounts.map { $0.0.sidebarId }), true)
            } else {
                arguments.limitExceeded()
            }

        })))
        index += 1
    }


    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterListDesc), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textBottomItem)))
    index += 1


    if let suggested = suggested, filtersWithCounts.count < 10 {

        let filtered = suggested.filters.filter { value -> Bool in
            return filtersWithCounts.first(where: { $0.0.data == value.data }) == nil
        }
        if !filtered.isEmpty {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1

            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterRecommendedHeader), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textTopItem)))
            index += 1

            var suggeted_index:Int32 = 0
            for filter in filtered {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_recommended(suggeted_index), equatable: InputDataEquatable(filter), comparable: nil, item: { initialSize, stableId in
                    return ChatListFilterRecommendedItem(initialSize, stableId: stableId, title: filter.title.text, description: filter.description, viewType: bestGeneralViewType(filtered, for: filter), add: {
                        arguments.addFeatured(filter)
                    })
                }))
                suggeted_index += 1
                index += 1
            }
        }
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_show_tags, data: .init(name: strings().chatListFolderTags, color: theme.colors.text, type: .switchable(showTags), viewType: .singleItem, action: {
        arguments.toggleTags(!showTags)
    }, autoswitch: false)))
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFolderTagsInfo), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textBottomItem)))
    index += 1





    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1


    if !filtersWithCounts.isEmpty {

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterTabBarHeader), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textTopItem)))
        index += 1

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("sidebar"), equatable: InputDataEquatable(sidebar), comparable: nil, item: { initialSize, stableId in
            return ChatListFilterVisibilityItem(initialSize, images: arguments.environment.image, stableId: stableId, sidebar: sidebar, viewType: .singleItem, toggle: { sidebar in
                arguments.toggleSidebar(sidebar)
            })
        }))
        index += 1

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterTabBarDesc), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textBottomItem)))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }


    return entries
}

public func ChatListFiltersListController(context: any AccountContextProtocol, environment: SidebarUIEnvironment) -> InputDataController {

    let arguments = ChatListPresetArguments(context: context, environment: environment, openPreset: { filter, isNew in
        context.bindings.rootNavigation().push(ChatListFilterController(context: context, environment: environment, filter: filter, isNew: isNew))
    }, removePreset: { filter in
        environment.confirmFolderAction(header: strings().chatListFilterConfirmRemoveHeader, information: strings().chatListFilterConfirmRemoveText, ok: strings().chatListFilterConfirmRemoveOK, successHandler: {
            _ = context.engine.peers.updateChatListFiltersInteractively({ filters in
                var filters = filters
                filters.removeAll(where: { $0.sidebarId == filter.sidebarId })
                return filters
            }).start()
        })

    }, addFeatured: { featured in
        _ = context.engine.peers.updateChatListFiltersInteractively({ filters in
            var filters = filters
            var new = ChatListFilter.new(excludeIds: filters.map { $0.sidebarId })
            new = new.withUpdatedData(featured.data)
                .withUpdatedTitle(featured.title)

            filters.append(new)
            return filters
        }).start()
    }, toggleSidebar: { sidebar in
        _ = updateChatListFolderSettings(context.account.postbox, {
            $0.withUpdatedSidebar(sidebar).withUpdatedSidebarInteracted(true)
        }).start()
    }, limitExceeded: {
        environment.showPremiumLimit(.folders)
    }, toggleTags: { value in
        if !context.isPremium {
            showModalText(for: context.window, text: strings().chatListFolderPremiumAlert, button: strings().alertLearnMore, callback: { _ in
                environment.showFolderTagsPremium()
            })
        } else {
            context.engine.peers.updateChatListFiltersDisplayTags(isEnabled: value)
        }

    })


    let filtersWithCounts = combineLatest(
        chatListFilterPreferences(engine: context.engine) |> distinctUntilChanged,
        environment.filterPredicates
    ) |> mapToSignal { filters, predicateForFilter -> Signal<([(ChatListFilter, Int)], Bool), NoError> in
        return context.account.postbox.transaction { transaction -> ([(ChatListFilter, Int)], Bool) in
            return (filters.list.map { filter -> (ChatListFilter, Int) in
                if let predicate = predicateForFilter(filter) {
                    return (filter, transaction.getChatCountMatchingPredicate(predicate))
                } else {
                    return (filter, 0)
                }
            }, filters.sidebar)
        }
    }

    let suggested: Signal<ChatListFiltersFeaturedState?, NoError> = context.account.postbox.preferencesView(keys: [PreferencesKeys.chatListFiltersFeaturedState]) |> map { view in
        return view.values[PreferencesKeys.chatListFiltersFeaturedState]?.get(ChatListFiltersFeaturedState.self)
    }

    let showTags = context.engine.data.subscribe(TelegramEngine.EngineData.Item.ChatList.FiltersDisplayTags())

    let dataSignal = combineLatest(queue: prepareQueue, appearanceSignal, filtersWithCounts, suggested, showTags) |> map { _, filtersWithCounts, suggested, showTags in
        return chatListPresetEntries(filtersWithCounts: filtersWithCounts.0, sidebar: filtersWithCounts.1, showTags: showTags, suggested: suggested, arguments: arguments)
    } |> map { entries in
        return InputDataSignalValue(entries: entries)
    }


    let controller = InputDataController(dataSignal: dataSignal, title: strings().chatListFilterListTitle, removeAfterDisappear: false, hasDone: false, identifier: "filters")


    controller.updateDatas = { data in
        return .none
    }


    controller.validateData = { data in
        return .success(.custom {

        })
    }


    controller.afterTransaction = { controller in
        var range: NSRange = NSMakeRange(NSNotFound, 0)

         controller.tableView.enumerateItems(with: { item in
            if let stableId = item.stableId.base as? InputDataEntryId {
                switch stableId {
                case let .general(identifier), let .custom(identifier):

                    if identifier.identifier.hasPrefix("_id_filter") {
                        if range.location == NSNotFound {
                            range.location = item.index
                        }
                        range.length += 1
                    }
                default:
                    if range.location != NSNotFound {
                        return false
                    }
                }
            }
            return true
         })

        if range.location != NSNotFound {


            let resortController = TableResortController(resortRange: range, start: { row in

            }, resort: { row in

            }, complete: { from, to in
                _ = context.engine.peers.updateChatListFiltersInteractively({ filters in
                    var filters = filters

                    var offset: Int = 0
                    if !context.isPremium {
                        offset = 1
                    }
                    filters = sidebarReorderedFilters(filters, from: from, to: to, rangeLocation: range.location, offset: offset)
                    return filters
                }).start()

            })
            resortController.completeDelay = 0
            controller.tableView.resortController = resortController
        } else {
            controller.tableView.resortController = nil
        }


    }

    return controller

}
