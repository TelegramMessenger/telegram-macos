import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Postbox
import ColorPalette
import TelegramMedia
import TelegramMediaResources
import Localization
import Strings
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import InlineStickers
import LocalAnimations
import GeneralRows
import InputDataUI
import ChatModeTypes
import Cocoa
import InlineStickerLayer
import ObjcUtils


// https://getemoji.com/ to get the latest list

private extension EmojiSearchCategories.Group {
    var icon: CGImage? {
        switch self.title.lowercased() {
        case "love":
            return theme.icons.msg_emoji_heart
        case "approval":
            return theme.icons.msg_emoji_like
        case "disapproval":
            return theme.icons.msg_emoji_dislike
        case "cheers":
            return theme.icons.msg_emoji_party
        case "laughter":
            return theme.icons.msg_emoji_haha
        case "astonishment":
            return theme.icons.msg_emoji_omg
        case "sadness":
            return theme.icons.msg_emoji_sad
        case "anger":
            return theme.icons.msg_emoji_angry
        case "neutral":
            return theme.icons.msg_emoji_neutral
        case "doubt":
            return theme.icons.msg_emoji_what
        case "silly":
            return theme.icons.msg_emoji_tongue
        case "hi":
            return theme.icons.msg_emoji_hi2
        case "dnd":
            return theme.icons.msg_emoji_busy
        case "work / on call":
            return theme.icons.msg_emoji_work
        case "eat":
            return theme.icons.msg_emoji_food
        case "away / bath":
            return theme.icons.msg_emoji_bath
        case "sleep":
            return theme.icons.msg_emoji_sleep
        case "travel & vacation":
            return theme.icons.msg_emoji_vacation
        case "activities":
            return theme.icons.msg_emoji_activities
        case "home":
            return theme.icons.msg_emoji_home
        case "premium":
            return theme.icons.msg_emoji_premium
        default:
            return nil
        }
    }
}

private extension RecentReactionItem.Content {
    var reaction: MessageReaction.Reaction {
        switch self {
        case let .custom(file):
            return .custom(file.fileId.id)
        case let .builtin(emoji):
            return .builtin(emoji)
        case .stars:
            return .stars
        }
    }
}

public enum EmojiSegment : Int64, Comparable  {
    case RecentAnimated = 100
    case Recent = 0
    case People = 1
    case AnimalsAndNature = 2
    case FoodAndDrink = 3
    case ActivityAndSport = 4
    case TravelAndPlaces = 5
    case Objects = 6
    case Symbols = 7
    case Flags = 8
    
    public var localizedString: String {
        switch self {
        case .RecentAnimated: return strings().emojiRecent
        case .Recent: return strings().emojiRecentNew
        case .People: return strings().emojiSmilesAndPeople
        case .AnimalsAndNature: return strings().emojiAnimalsAndNature
        case .FoodAndDrink: return strings().emojiFoodAndDrink
        case .ActivityAndSport: return strings().emojiActivityAndSport
        case .TravelAndPlaces: return strings().emojiTravelAndPlaces
        case .Objects: return strings().emojiObjects
        case .Symbols: return strings().emojiSymbols
        case .Flags: return strings().emojiFlags
        }
    }
    
    public static var all: [EmojiSegment] {
        return [.People, .AnimalsAndNature, .FoodAndDrink, .ActivityAndSport, .TravelAndPlaces, .Objects, .Symbols, .Flags]
    }
    
    public var hashValue:Int {
        return Int(self.rawValue)
    }
}

public func ==(lhs:EmojiSegment, rhs:EmojiSegment) -> Bool {
    return lhs.rawValue == rhs.rawValue
}

public func <(lhs:EmojiSegment, rhs:EmojiSegment) -> Bool {
    return lhs.rawValue < rhs.rawValue
}

public let emojiesInstance:[EmojiSegment:[String]] = {
    assertNotOnMainThread()
    var local:[EmojiSegment:[String]] = [EmojiSegment:[String]]()
    
    let resource:URL?
    if #available(OSX 26.4, *) {
        resource = Bundle.main.url(forResource:"emoji264", withExtension:"txt")
    } else if #available(OSX 14.4, *) {
        resource = Bundle.main.url(forResource:"emoji144", withExtension:"txt")
    } else if #available(OSX 14.0, *) {
        resource = Bundle.main.url(forResource:"emoji14", withExtension:"txt")
    } else if #available(OSX 11.1, *) {
        resource = Bundle.main.url(forResource:"emoji1016", withExtension:"txt")
    } else if #available(OSX 10.14.1, *) {
        resource = Bundle.main.url(forResource:"emoji1014", withExtension:"txt")
    } else {
        resource = Bundle.main.url(forResource:"emoji", withExtension:"txt")
    }
    if let resource = resource {
        
        var file:String = ""
        
        do {
            file = try String(contentsOf: resource)
            
        } catch {
            print("emoji file not loaded")
        }
        
        let segments = file.components(separatedBy: "\n\n")
        
        for (segment, content) in zip(EmojiSegment.all, segments) {
            local[segment] = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        }
        
    }
    
    return local
    
}()

private func segments(_ emoji: [EmojiSegment : [String]], skinModifiers: [EmojiSkinModifier]) -> [EmojiSegment:[[NSAttributedString]]] {
    var segments:[EmojiSegment:[[NSAttributedString]]] = [:]
    for (key,list) in emoji {
        let items = list.map { emoji -> NSAttributedString in
            let unmodified = emoji.emojiUnmodified
            let value = skinModifiers.first(where: { $0.emoji == unmodified }).map { unmodified.emojiWithSkinModifier($0.modifier) } ?? emoji
            let attributed = NSMutableAttributedString(attributedString: .initialize(string: value.normalizedEmoji, font: .normal(26.0)))
            if key == .Recent {
                attributed.addAttribute(recentEmojiSourceKey, value: emoji, range: NSRange(location: 0, length: attributed.length))
            }
            return attributed
        }
        let lines = stride(from: 0, to: items.count, by: 8).map {
            Array(items[$0 ..< min($0 + 8, items.count)])
        }
        if !lines.isEmpty {
            segments[key] = lines
        }
    }
    return segments
}



private final class Arguments {
    let context: any AccountContextProtocol
    let mode: EmojiesController.Mode
    let ignorePremium: Bool
    let send:(StickerPackItem, StickerPackCollectionInfo?, Int32?, NSRect?)->Void
    let sendEmoji:(String, NSRect)->Void
    let selectEmojiSegment:(EmojiSegment)->Void
    let viewSet:(StickerPackCollectionInfo)->Void
    let showAllItems:(Int64)->Void
    let openPremium:()->Void
    let installPack:(StickerPackCollectionInfo, [StickerPackItem])->Void
    let clearRecent:()->Void
    let selectEmojiCategory:(EmojiSearchCategories.Group?)->Void
    var staticEmojiFilter: ((String) -> Bool)?
    var sendLarge: (() -> ((StickerPackItem, NSRect?) -> Void)?)?
    var drag: ((StickerPackItem, EntertainmentStickerDrag) -> Bool)?
    var dragEmoji: ((String, EntertainmentStickerDrag) -> Bool)?
    init(context: any AccountContextProtocol, mode: EmojiesController.Mode, ignorePremium: Bool, send:@escaping(StickerPackItem, StickerPackCollectionInfo?, Int32?, NSRect?)->Void, sendEmoji:@escaping(String, NSRect)->Void, selectEmojiSegment:@escaping(EmojiSegment)->Void, viewSet:@escaping(StickerPackCollectionInfo)->Void, showAllItems:@escaping(Int64)->Void, openPremium:@escaping()->Void, installPack:@escaping(StickerPackCollectionInfo,  [StickerPackItem])->Void, clearRecent:@escaping()->Void, selectEmojiCategory:@escaping(EmojiSearchCategories.Group?)->Void) {
        self.context = context
        self.send = send
        self.sendEmoji = sendEmoji
        self.selectEmojiSegment = selectEmojiSegment
        self.viewSet = viewSet
        self.showAllItems = showAllItems
        self.openPremium = openPremium
        self.installPack = installPack
        self.mode = mode
        self.ignorePremium = ignorePremium
        self.clearRecent = clearRecent
        self.selectEmojiCategory = selectEmojiCategory
    }
}

private struct State : Equatable {

    struct EmojiState : Equatable {
        var selected: EmojiSegment?
    }
    
    struct Section : Equatable {
        var info: StickerPackCollectionInfo
        var items:[StickerPackItem]
        var dict:[MediaId: StickerPackItem]
        var installed: Bool
        var groupEmojiPack: Bool = false
        var isBig: Bool = false
        static func ==(lhs: Section, rhs: Section) -> Bool {
            if lhs.info != rhs.info {
                return false
            }
            if lhs.installed != rhs.installed {
                return false
            }
            if lhs.items != rhs.items {
                return false
            }
            if lhs.dict.count != rhs.dict.count {
                return false
            }
            if lhs.groupEmojiPack != rhs.groupEmojiPack {
                return false
            }
            if lhs.isBig != rhs.isBig {
                return false
            }
            return true
        }
    }
    var sections:[Section]
    var itemsDict: [MediaId: StickerPackItem]
    var peer: PeerEquatable?
    var emojiState: EmojiState = .init(selected: nil)
    var revealed:[Int64: Bool] = [:]
    var search: [String]? = nil
    var searchLoading = false
    var searchFiles: [TelegramMediaFile] = []
    var searchSections: [Section] = []
    var searchContext: EmojiSearchContext?
    var reactions: AvailableReactions? = nil
    var recentStatusItems: [RecentMediaItem] = []
    var forumTopicItems: [StickerPackItem] = []
    var featuredStatusItems: [RecentMediaItem] = []
    
    var recentReactionsItems: [RecentReactionItem] = []
    var topReactionsItems: [RecentReactionItem] = []
    var featuredBackgroundIconEmojiItems: [RecentMediaItem] = []
    var featuredChannelStatusEmojiItems: [RecentMediaItem] = []
    var uniqueStarGiftsItems:[RecentStarGiftItem] = []
    var recent: RecentUsedEmoji = .defaultSettings
    var reactionSettings: ReactionSettings = .default
    
    var messageEffects: [AvailableMessageEffects.MessageEffect] = []
    
    var iconStatusEmoji: [TelegramMediaFile] = []
    var selectedItems: [EmojiesSectionRowItem.SelectedItem]
    var searchCategories: EmojiSearchCategories?
    var selectedEmojiCategory: EmojiSearchCategories.Group?
    
    var availableReactions: AvailableReactions?
    
    var color: NSColor? = nil
    
    static func ==(lhs: State, rhs: State) -> Bool {
        
        if lhs.sections != rhs.sections {
            return false
        }
        if lhs.peer != rhs.peer {
            return false
        }
        if lhs.emojiState != rhs.emojiState {
            return false
        }
        if lhs.revealed != rhs.revealed {
            return false
        }
        if lhs.search != rhs.search || lhs.searchLoading != rhs.searchLoading || lhs.searchFiles != rhs.searchFiles || lhs.searchSections != rhs.searchSections {
            return false
        }
        if lhs.reactions != rhs.reactions {
            return false
        }
        if lhs.recentStatusItems.count != rhs.recentStatusItems.count {
            return false
        }
        if lhs.forumTopicItems.count != rhs.forumTopicItems.count {
            return false
        }
        if lhs.featuredStatusItems.count != rhs.featuredStatusItems.count {
            return false
        }
        if lhs.recentReactionsItems.count != rhs.recentReactionsItems.count {
            return false
        }
        if lhs.topReactionsItems.count != rhs.topReactionsItems.count {
            return false
        }
        if lhs.uniqueStarGiftsItems.count != rhs.uniqueStarGiftsItems.count {
            return false
        }
        if lhs.recent != rhs.recent {
            return false
        }
        if lhs.reactionSettings != rhs.reactionSettings {
            return false
        }
        if lhs.iconStatusEmoji.count != rhs.iconStatusEmoji.count {
            return false
        }
        if lhs.selectedItems != rhs.selectedItems {
            return false
        }
        if lhs.searchCategories != rhs.searchCategories {
            return false
        }
        if lhs.selectedEmojiCategory != rhs.selectedEmojiCategory {
            return false
        }
        if lhs.featuredBackgroundIconEmojiItems != rhs.featuredBackgroundIconEmojiItems {
            return false
        }
        if lhs.featuredChannelStatusEmojiItems != rhs.featuredChannelStatusEmojiItems {
            return false
        }
        if lhs.color != rhs.color {
            return false
        }
        if lhs.availableReactions != rhs.availableReactions {
            return false
        }
        
        return true
    }
    
    struct ExternalTopic: Equatable {
        let title: String
        let iconColor: Int32
    }
    
    var externalTopic: ExternalTopic = .init(title: "", iconColor: 0)
}

private func _id_section(_ id:Int64, _ index: String = "") -> InputDataIdentifier {
    return .init("_id_section_\(id)_\(index)")
}
private func _id_pack(_ id: Int64) -> InputDataIdentifier {
    return .init("_id_pack_\(id)")
}
private func _id_emoji_segment(_ segment:Int64) -> InputDataIdentifier {
    return .init("_id_emoji_segment_\(segment)")
}
private func _id_aemoji_block(_ segment:Int64) -> InputDataIdentifier {
    return .init("_id_aemoji_block_\(segment)")
}
private func _id_emoji_block(_ segment: Int64) -> InputDataIdentifier {
    return .init("_id_emoji_block_\(segment)")
}
private let _id_segments_pack = InputDataIdentifier("_id_segments_pack")
private let _id_recent_pack = InputDataIdentifier("_id_recent_pack")

private func emojiesRowSelection(_ selected: [EmojiesSectionRowItem.SelectedItem], in items: [StickerPackItem]) -> [EmojiesSectionRowItem.SelectedItem] {
    if selected.isEmpty {
        return []
    }
    var fileIds = Set<Int64>()
    var keys = Set<String>()
    for item in items {
        fileIds.insert(item.file.fileId.id)
        for key in item.getStringRepresentationsOfIndexKeys() {
            keys.insert(key)
        }
    }
    return selected.filter { value in
        switch value.source {
        case let .custom(fileId):
            return fileIds.contains(fileId)
        case let .builtin(emoji):
            return keys.contains(emoji)
        }
    }
}

private func packEntries(_ state: State, arguments: Arguments, presentation: TelegramPresentationTheme?) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var index: Int32 = 0
    let sectionId:Int32 = 0
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("left"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 6, stableId: stableId, backgroundColor: .clear)
    }))
    index += 1
    
    let hasRecent: Bool
    switch arguments.mode {
    case .status:
        hasRecent = !state.recentStatusItems.isEmpty || !state.featuredStatusItems.isEmpty
    case .emoji, .stories:
        hasRecent = true
    case .reactions, .quickReaction, .defaultTags:
        hasRecent = !state.recentReactionsItems.isEmpty || !state.topReactionsItems.isEmpty
    case .selectAvatar:
        hasRecent = true
    case .forumTopic:
        hasRecent = true
    case .backgroundIcon:
        hasRecent = true
    case .channelReactions, .channelStatus:
        hasRecent = true
    case .messageEffects:
        hasRecent = false
    }
    if hasRecent {
        let recentImage = TelegramThemeHooks.shared.image(.iconEmojiTabRecent)
        let color = state.color ?? theme.colors.grayIcon
        let icon = recentImage.precomposed(color.withAlphaComponent(0.8))
        let activeIcon = recentImage.precomposed((state.color ?? theme.colors.grayIcon.darker()))
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_recent_pack, equatable: .init(color), comparable: nil, item: { initialSize, stableId in
            return ETabRowItem(initialSize, stableId: stableId, icon: icon, iconSelected: activeIcon)
        }))
        index += 1
    }
   

    if arguments.mode == .emoji || arguments.mode == .stories {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_segments_pack, equatable: InputDataEquatable(state.emojiState), comparable: nil, item: { initialSize, stableId in
            return EmojiTabsItem(initialSize, stableId: stableId, segments: EmojiSegment.all, selected: state.emojiState.selected, select: arguments.selectEmojiSegment, presentation: presentation)
        }))
        index += 1
    }
    
    var color: NSColor? = state.color
    if color == nil {
        switch arguments.mode {
        case .emoji:
            color = theme.colors.text
        default:
            color = nil
        }
    }
    
    for (_, section) in state.sections.enumerated() {
        let isPremium = section.items.contains(where: { $0.file.isPremiumEmoji }) && arguments.mode != .channelReactions && !arguments.ignorePremium
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_pack(section.info.id.id), equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
            return StickerPackRowItem(initialSize, stableId: stableId, packIndex: 0, isPremium: isPremium, installed: section.installed, color: color, context: arguments.context, info: section.info, topItem: section.items.first, allItems: section.items, isTopic: arguments.mode == .forumTopic || arguments.mode == .backgroundIcon)
        }))
        index += 1
    }
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("right"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 6, stableId: stableId, backgroundColor: .clear)
    }))
    index += 1
    
    return entries
}



private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    let sectionId:Int32 = 0
    
    var index: Int32 = 0
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("search"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 46, stableId: stableId, backgroundColor: .clear)
    }))
    index += 1
    
    var e = emojiesInstance
    e[EmojiSegment.Recent] = state.recent.emojies
    if let filter = arguments.staticEmojiFilter {
        for (key, list) in e {
            let filtered = list.filter(filter)
            if filtered.isEmpty {
                e.removeValue(forKey: key)
            } else {
                e[key] = filtered
            }
        }
    }
    let seg = segments(e, skinModifiers: state.recent.skinModifiers)
    var seglist = seg.map { (key,_) -> EmojiSegment in
        return key
    }.sorted(by: <)
    if !seglist.contains(.Recent) {
        seglist.insert(.Recent, at: 0)
    }
    
    
    let isPremium = state.peer?.peer.isPremium == true || arguments.ignorePremium
        
    var recentAnimated:[StickerPackItem] = state.recent.animated.compactMap { mediaId in
        if let item = state.itemsDict[mediaId] {
            if !item.file.isPremiumEmoji || isPremium {
                return item
            }
        }
        return nil
    }
    
    if arguments.mode == .channelReactions, let availableReactions = state.availableReactions {
        recentAnimated.removeAll()
        for reaction in availableReactions.reactions {
            recentAnimated.append(.init(index: .init(index: 0, id: 0), file: reaction.activateAnimation._parse(), indexKeys: []))
        }
    }
    
    
    if arguments.mode == .forumTopic {
        let file = EntertainmentUIHooks.shared.makeTopicIconFile(state.externalTopic.title, state.externalTopic.iconColor, false)
        recentAnimated.insert(.init(index: .init(index: 0, id: 0), file: file, indexKeys: []), at: 0)
        recentAnimated.append(contentsOf: state.forumTopicItems)
    }
    
    struct Tuple : Equatable {
        let items: [StickerPackItem]
        let selected: [EmojiesSectionRowItem.SelectedItem]
        let color: NSColor?
    }
    
    if let search = state.search {
        
        if !search.isEmpty || !state.searchFiles.isEmpty {
            
            let lines: [[NSAttributedString]] = search.chunks(8).map {
                return $0.map { .initialize(string: $0, font: .normal(26.0)) }
            }

            
            if !search.isEmpty, arguments.mode == .emoji || arguments.mode == .stories {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("search_e_stick"), equatable: InputDataEquatable(search), comparable: nil, item: { initialSize, stableId in
                    return EStickItem(initialSize, stableId: stableId, segmentName: strings().emojiSearchEmoji)
                }))
                index += 1
                
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("search_e"), equatable: InputDataEquatable(search), comparable: nil, item: { initialSize, stableId in
                    return EBlockItem(initialSize, stableId: stableId, attrLines: lines, segment: .Recent, account: arguments.context.account, selectHandler: arguments.sendEmoji, dragHandler: arguments.dragEmoji)
                }))
                index += 1
                
            }
            
            let searchIndex = PanelEmojiSearchIndex(search)
            var animatedEmoji: [StickerPackItem] = []
            var animatedIds = Set<MediaId>()
            for file in state.searchFiles where animatedIds.insert(file.fileId).inserted {
                animatedEmoji.append(.init(index: .init(index: 0, id: file.fileId.id), file: file, indexKeys: []))
            }
            for section in state.sections {
                for item in section.items where item.getStringRepresentationsOfIndexKeys().contains(where: searchIndex.contains) {
                    if animatedIds.insert(item.file.fileId).inserted {
                        animatedEmoji.append(item)
                    }
                }
            }
            
            let statuses = state.iconStatusEmoji + state.recentStatusItems.map { $0.media._parse() } + state.featuredStatusItems.map { $0.media._parse() } + state.featuredBackgroundIconEmojiItems.map { $0.media._parse() } + state.featuredChannelStatusEmojiItems.map { $0.media._parse() }
            
            
            var contains:Set<MediaId> = Set()
            let normalized:[StickerPackItem] = statuses.filter { item in
                let text = item.customEmojiText ?? item.stickerText ?? ""
                if !contains.contains(item.fileId), searchIndex.contains(text) {
                    contains.insert(item.fileId)
                    return true
                }
                return false
            }.map { value in
                return StickerPackItem(index: .init(index: 0, id: 0), file: value, indexKeys: [])
            }
            for item in normalized {
                if animatedIds.insert(item.file.fileId).inserted {
                    animatedEmoji.append(item)
                }
            }
            
            if !animatedEmoji.isEmpty {
                if arguments.mode == .emoji || arguments.mode == .stories {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("search_ae_stick"), equatable: InputDataEquatable(search), comparable: nil, item: { initialSize, stableId in
                        return EStickItem(initialSize, stableId: stableId, segmentName: strings().emojiSearchAnimatedEmoji)
                    }))
                    index += 1
                }
                
                let chunks = animatedEmoji.chunks(24)
                var string: String = "a"
                for chunk in chunks {
                    let tuple = Tuple(items: chunk, selected: emojiesRowSelection(state.selectedItems, in: chunk), color: state.color)
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("search_ae_\(string)"), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
                        return EmojiesSectionRowItem(initialSize, stableId: stableId, context: arguments.context, revealed: true, installed: false, info: nil, items: tuple.items, mode: arguments.mode.itemMode, selectedItems: tuple.selected, color: tuple.color, callback: arguments.send, largeCallback: arguments.sendLarge, drag: arguments.drag, ignorePremium: arguments.ignorePremium)
                    }))
                    index += 1
                    string += "a"
                }
                                
                
                
            }
        }
        
    } else {
        for key in seglist {
            
            if key == .Recent, arguments.mode == .reactions || arguments.mode == .quickReaction || arguments.mode == .defaultTags {
                
                
                var reactionsRecent:[StickerPackItem] = []
                var reactionsPopular:[StickerPackItem] = []
                
                
                var recent:[RecentReactionItem] = []
                var popular:[RecentReactionItem] = []
                let perline: Int = 8
//                if arguments.context.isPremium {
                
                let top = state.topReactionsItems.filter { value in
                    if arguments.context.isPremium || arguments.ignorePremium {
                        return true
                    } else {
                        if arguments.mode == .defaultTags {
                            return true
                        } else {
                            return !value.content.reaction.emojiString.isEmpty
                        }
                    }
                }
                popular = Array(top.prefix(perline * 2))
                recent = state.recentReactionsItems
                
                
                for item in state.topReactionsItems {
                    let recentContains = recent.contains(where: { $0.id.id == item.id.id })
                    let popularContains = popular.contains(where: { $0.id.id == item.id.id })
                    
                    if !recentContains && !popularContains {
                        if state.recentReactionsItems.isEmpty {
                            switch item.content {
                            case .builtin:
                                recent.append(item)
                            default:
                                break
                            }
                        } else {
                            recent.append(item)
                        }
                    }
                }
                
                if let reactions = state.reactions?.enabled {
                    for reaction in reactions {
                        let recentContains = recent.contains(where: { $0.content.reaction == reaction.value })
                        let popularContains = popular.contains(where: { $0.content.reaction == reaction.value })
                        if !recentContains && !popularContains {
                            switch reaction.value {
                            case let .builtin(emoji):
                                recent.append(.init(.builtin(emoji)))
                            default:
                                break
                            }
                        }
                    }
                }
                
                recent = Array(recent.prefix(perline * 10))

                let transform:(RecentReactionItem)->StickerPackItem? = { item in
                    switch item.content {
                    case let .builtin(emoji):
                        let builtin = state.reactions?.enabled.first(where: {
                            $0.value.emojiString == emoji
                        })
                        if let builtin = builtin {
                            return .init(index: .init(index: 0, id: 0), file: builtin.selectAnimation._parse(), indexKeys: [])
                        }
                    case let .custom(file):
                        return .init(index: .init(index: -1, id: 0), file: file._parse(), indexKeys: [])
                    case .stars:
                        return nil
                    }
                    return nil
                }
                
                reactionsPopular.append(contentsOf: popular.compactMap(transform))
                reactionsRecent.append(contentsOf: recent.compactMap(transform))
                
                reactionsRecent = reactionsRecent.filter { item in
                    return !reactionsPopular.contains(where: { $0.file.fileId == item.file.fileId })
                }
                let tuple = Tuple(items: reactionsPopular, selected: emojiesRowSelection(state.selectedItems, in: reactionsPopular), color: state.color)
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_emoji_block(EmojiSegment.RecentAnimated.rawValue), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
                    return EmojiesSectionRowItem(initialSize, stableId: stableId, context: arguments.context, revealed: true, installed: true, info: nil, items: reactionsPopular, mode: arguments.mode.itemMode, selectedItems: tuple.selected, color: tuple.color, callback: arguments.send, largeCallback: arguments.sendLarge, drag: arguments.drag, ignorePremium: arguments.ignorePremium)
                }))
                index += 1
                
                if !reactionsRecent.isEmpty {
                    
                    let containsCustom = reactionsRecent.contains(where: { $0.index.index == -1 })
                    if containsCustom {
                        let text = strings().reactionsRecentlyUsed
                        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_emoji_segment(-1), equatable: InputDataEquatable(text), comparable: nil, item: { initialSize, stableId in
                            return EStickItem(initialSize, stableId: stableId, segmentName: text, clearCallback: arguments.clearRecent)
                        }))
                        index += 1
                    } else {
                        let text = strings().reactionsPopular
                        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_emoji_segment(-1), equatable: InputDataEquatable(text), comparable: nil, item: { initialSize, stableId in
                            return EStickItem(initialSize, stableId: stableId, segmentName: text )
                        }))
                        index += 1
                    }
                    
                    let tuple = Tuple(items: reactionsRecent, selected: emojiesRowSelection(state.selectedItems, in: reactionsRecent), color: state.color)
                    
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_emoji_block(-1), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
                        return EmojiesSectionRowItem(initialSize, stableId: stableId, context: arguments.context, revealed: true, installed: true, info: nil, items: reactionsRecent, mode: arguments.mode.itemMode, selectedItems: tuple.selected, color: tuple.color, callback: arguments.send, largeCallback: arguments.sendLarge, drag: arguments.drag, ignorePremium: arguments.ignorePremium)
                    }))
                    index += 1
                }
                
            }
            
            let statuses = state.recentStatusItems.filter { !isDefaultStatusesPackId($0.media._parse().emojiReference) } + state.featuredStatusItems
            var contains:Set<MediaId> = Set()
            var normalized:[StickerPackItem] = statuses.filter { item in
                if !contains.contains(item.media.fileId) {
                    contains.insert(item.media.fileId)
                    return true
                }
                return false
            }.map { value in
                return StickerPackItem(index: .init(index: 0, id: 0), file: value.media._parse(), indexKeys: [])
            }
            
            
            if key == .Recent, arguments.mode == .status || arguments.mode == .backgroundIcon || arguments.mode == .channelStatus {
                
                if arguments.mode == .status {
                    let string: String
                    if let expiryDate = state.peer?.peer.emojiStatus?.expirationDate, expiryDate > arguments.context.timestamp {
                        string = strings().customStatusExpires(timeIntervalString(Int(expiryDate - arguments.context.timestamp)))
                    } else {
                        string = strings().customStatusExpiresPromo
                    }
                    
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("_id_status_status"), equatable: .init(string), comparable: nil, item: { initialSize, stableId in
                        return EmojiStatusStatusRowItem(initialSize, stableId: stableId, status: string.uppercased(), viewType: .textTopItem)
                    }))
                    index += 1
                }
               
                let iconName: String = arguments.mode == .status ? "Icon_Premium_StickerPack" : "Icon_NoPeerIcon"
                let color = state.color ?? theme.colors.accent
                let def = TelegramMediaFile(fileId: .init(namespace: 0, id: 0), partialReference: nil, resource: LocalBundleResource(name: iconName, ext: "", color: color), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "bundle/jpeg", size: nil, attributes: [], alternativeRepresentations: [])
                
                normalized.insert(.init(index: .init(index: 0, id: 0), file: def, indexKeys: []), at: 0)
                
                normalized.insert(contentsOf: state.iconStatusEmoji.prefix(7).map {
                    .init(index: .init(index: 0, id: 0), file: $0, indexKeys: [])
                }, at: 1)
                
                struct Tuple : Equatable {
                    let items: [StickerPackItem]
                    let revealed: Bool
                    let selected:[EmojiesSectionRowItem.SelectedItem]
                    let color: NSColor?
                }
                let shownItems = Array(normalized.prefix(13 * 8))
                let tuple = Tuple(items: shownItems, revealed: state.revealed[-1] ?? false, selected: emojiesRowSelection(state.selectedItems, in: shownItems), color: state.color)
                
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_emoji_block(EmojiSegment.RecentAnimated.rawValue), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
                    return EmojiesSectionRowItem(initialSize, stableId: stableId, context: arguments.context, revealed: tuple.revealed, installed: true, info: nil, items: tuple.items, mode: arguments.mode.itemMode, selectedItems: tuple.selected, color: tuple.color, callback: arguments.send, largeCallback: arguments.sendLarge, drag: arguments.drag, showAllItems: {
                        arguments.showAllItems(-1)
                    }, ignorePremium: arguments.ignorePremium)
                }))
                index += 1
            }
            
            
            let hasAnimatedRecent = arguments.mode == .emoji || arguments.mode == .stories || arguments.mode == .forumTopic || arguments.mode == .selectAvatar || arguments.mode == .channelReactions
            
            if key == .Recent, !recentAnimated.isEmpty, hasAnimatedRecent {
                let removeRecent: ((MediaId) -> Void)?
                if arguments.mode == .emoji || arguments.mode == .stories {
                    removeRecent = { id in
                        _ = removeAnimatedUsedEmoji(id, postbox: arguments.context.account.postbox).startStandalone()
                    }
                } else {
                    removeRecent = nil
                }
                let tuple = Tuple(items: recentAnimated, selected: emojiesRowSelection(state.selectedItems, in: recentAnimated), color: state.color)
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_emoji_block(EmojiSegment.RecentAnimated.rawValue), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
                    return EmojiesSectionRowItem(initialSize, stableId: stableId, context: arguments.context, revealed: true, installed: true, info: nil, items: recentAnimated, mode: arguments.mode.itemMode, selectedItems: tuple.selected, color: tuple.color, callback: arguments.send, largeCallback: arguments.sendLarge, drag: arguments.drag, ignorePremium: arguments.ignorePremium, removeRecent: removeRecent)
                }))
                index += 1
            }
            
            guard let lines = seg[key], !lines.isEmpty else {
                continue
            }

            if key != .Recent || !recentAnimated.isEmpty, arguments.mode == .emoji || arguments.mode == .stories {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_emoji_segment(key.rawValue), equatable: InputDataEquatable(key), comparable: nil, item: { initialSize, stableId in
                    return EStickItem(initialSize, stableId: stableId, segmentName:key.localizedString)
                }))
                index += 1
            }
            
           
            if arguments.mode == .emoji || arguments.mode == .stories {
                struct Tuple : Equatable {
                    let key: EmojiSegment
                    let lines: [[NSAttributedString]]
                    let selectedOrders: [String: Int]
                    let selectionColor: NSColor?
                }
                var selectedOrders: [String: Int] = [:]
                if state.selectedItems.contains(where: { $0.index != nil }) {
                    let segmentKeys = Set(lines.flatMap { $0.map { emojiSelectionKey($0.string) } })
                    for selected in state.selectedItems {
                        if case let .builtin(emoji) = selected.source, let order = selected.index {
                            let key = emojiSelectionKey(emoji)
                            if segmentKeys.contains(key) {
                                selectedOrders[key] = order
                            }
                        }
                    }
                }
                let removeRecent: ((String) -> Void)?
                if key == .Recent {
                    removeRecent = { emoji in
                        _ = removeUsedEmoji(emoji, postbox: arguments.context.account.postbox).startStandalone()
                    }
                } else {
                    removeRecent = nil
                }
                let tuple = Tuple(key: key, lines: lines, selectedOrders: selectedOrders, selectionColor: state.color ?? theme.colors.text)
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_emoji_block(key.rawValue), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
                    return EBlockItem(initialSize, stableId: stableId, attrLines: tuple.lines, segment: tuple.key, account: arguments.context.account, selectHandler: arguments.sendEmoji, dragHandler: arguments.dragEmoji, selectedOrders: tuple.selectedOrders, selectionColor: tuple.selectionColor, removeRecent: removeRecent)
                }))
                index += 1
            }
            
        }
        
    }
    
    if state.search == nil, !state.uniqueStarGiftsItems.isEmpty {
        
        var items:[StickerPackItem] = []
        for gift in state.uniqueStarGiftsItems {
            items.append(.init(index: .init(index: 0, id: 0), file: gift.starGift.file!, indexKeys: []))
        }
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_aemoji_block(0), equatable: InputDataEquatable(items), comparable: nil, item: { initialSize, stableId in
            return GeneralRowItem(initialSize, height: 10, stableId: stableId, backgroundColor: .clear)
        }))
        index += 1
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("collectibles"), equatable: InputDataEquatable(state.uniqueStarGiftsItems), comparable: nil, item: { initialSize, stableId in
            return EmojiesSectionRowItem(initialSize, stableId: stableId, context: arguments.context, revealed: true, installed: true, info: nil, items: items, mode: arguments.mode.itemMode, selectedItems: [], color: theme.colors.text, callback: arguments.send, largeCallback: arguments.sendLarge, drag: arguments.drag, openPremium: arguments.openPremium, installPack: arguments.installPack, ignorePremium: arguments.ignorePremium, uniqueGifts: state.uniqueStarGiftsItems.map(\.starGift))
        }))
        
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_aemoji_block(1), equatable: InputDataEquatable(items), comparable: nil, item: { initialSize, stableId in
            return GeneralRowItem(initialSize, height: 10, stableId: stableId, backgroundColor: .clear)
        }))
        index += 1
        
    }
    
    let displayedSections = panelEmojiDisplayedSections(isSearching: state.search != nil, isMessageEffects: arguments.mode == .messageEffects, browsing: state.sections, matching: state.searchSections)
    for (i, section) in displayedSections.enumerated() {
        
        
        if !section.info.title.isEmpty, i > 0  {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_aemoji_block(section.info.id.id), equatable: InputDataEquatable(section.info), comparable: nil, item: { initialSize, stableId in
                return GeneralRowItem(initialSize, height: 10, stableId: stableId, backgroundColor: .clear)
            }))
            index += 1
        }
        
        struct Tuple : Equatable {
            let section: State.Section
            let isPremium: Bool
            let revealed: Bool
            let selectedItems:[EmojiesSectionRowItem.SelectedItem]
            let items: [StickerPackItem]
            let index: String
            let color: NSColor?
        }
        
        var tuples:[Tuple] = []

        let chunks = section.items.chunks(1000)
        var string: String = "a"
        
        for items in chunks {
            tuples.append(Tuple(section: section, isPremium: state.peer?.peer.isPremium ?? false || arguments.ignorePremium, revealed: state.revealed[section.info.id.id] != nil, selectedItems: emojiesRowSelection(state.selectedItems, in: items), items: items, index: string, color: state.color))
            string += "a"
        }
                
        for tuple in tuples {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_section(section.info.id.id, tuple.index), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
                return EmojiesSectionRowItem(initialSize, stableId: stableId, context: arguments.context, revealed: tuple.revealed, installed: tuple.section.installed, info: tuple.index == "a" ? section.info : nil, items: tuple.items, isBig: tuple.section.isBig, groupEmojiPack: tuple.section.groupEmojiPack, mode: arguments.mode.itemMode, selectedItems: tuple.selectedItems, color: tuple.color, callback: arguments.send, largeCallback: arguments.sendLarge, drag: arguments.drag, viewSet: { info in
                    arguments.viewSet(info)
                }, showAllItems: {
                    arguments.showAllItems(section.info.id.id)
                }, openPremium: arguments.openPremium, installPack: arguments.installPack, ignorePremium: arguments.ignorePremium)
            }))
            index += 1
        }
        
    }
    
  
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("bottom_section"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 10, stableId: stableId, backgroundColor: .clear)
    }))
    index += 1
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("bottom"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 46, stableId: stableId, backgroundColor: .clear)
    }))
    index += 1
    
    // entries
    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
    
    return entries
}

extension EmojiSearchCategories.Group : @retroactive Identifiable, @retroactive Comparable {
    public static func < (lhs: EmojiSearchCategories.Group, rhs: EmojiSearchCategories.Group) -> Bool {
        return false
    }
    
    public var stableId: AnyHashable {
        return self.id
    }
    
}


public final class BackCategoryControl : Control {
    private var sticker: InlineStickerItemLayer
    private let context: any AccountContextProtocol
    private let presentation: TelegramPresentationTheme
    public init(frame frameRect: NSRect, context: any AccountContextProtocol, presentation: TelegramPresentationTheme) {
        self.context = context
        self.presentation = presentation
        let theme = presentation
        self.sticker = .init(account: context.account, file: LocalAnimatedSticker.emoji_category_search_to_arrow.file, size: NSMakeSize(18, 18), playPolicy: .onceEnd, getColors: { _ in
            return [.init(keyPath: "", color: theme.colors.grayIcon.withMultipliedAlpha(0.8))]
        }, ignorePreview: true)
        super.init(frame: frameRect)
        
        self.sticker.isPlayable = true
        self.sticker.superview = self
        self.layer?.addSublayer(self.sticker)
        
        self.scaleOnClick = true
        
        updateLocalizationAndTheme(theme: theme)
        
        needsLayout = true
    }
    
    public func close() {
        self.sticker.removeFromSuperlayer()
        let theme = self.presentation
        
        self.sticker = .init(account: context.account, file: LocalAnimatedSticker.emoji_category_arrow_to_search.file, size: NSMakeSize(18, 18), playPolicy: .onceEnd, getColors: { _ in
            return [.init(keyPath: "", color: theme.colors.grayIcon.withMultipliedAlpha(0.8))]
        }, ignorePreview: true)

        self.sticker.isPlayable = true
        self.sticker.superview = self
        self.layer?.addSublayer(self.sticker)
        
        needsLayout = true

    }
    
    public override func layout() {
        super.layout()
        var rect = focus(NSMakeSize(18, 18))
        rect.origin.x += 5
        self.sticker.frame = rect
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
    }
    
    public func update(context: any AccountContextProtocol, isVisible: Bool, animated: Bool, callback:@escaping()->Void) {
                            
        self.isHidden = !isVisible
        
        needsLayout = true

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}


public final class AnimatedEmojiesCategories : Control {
    
    private final class CategoryView : Control {
                
        private var player: InlineStickerItemLayer?
        private var imageView: ImageView?
        let category: EmojiSearchCategories.Group
        let context: any AccountContextProtocol
        private var currentKey: String?
        
        
        private var selectionView : SimpleLayer?
        private var presenation: TelegramPresentationTheme? = nil
        
        required init(frame frameRect: NSRect, context: any AccountContextProtocol, category: EmojiSearchCategories.Group, isSelected: Bool, presenation: TelegramPresentationTheme? = nil) {
            
            self.presenation = presenation
            self.category = category
            self.context = context
           
            super.init(frame: frameRect)
                        
            self.toolTip = category.title

            scaleOnClick = true
            
            let lite = self.isLite
            if let image = category.icon {
                let imageView = ImageView()
                imageView.image = image
                imageView.sizeToFit()
                imageView.isAccessibilityDecorative = true
                addSubview(imageView)
                self.imageView = imageView
            } else {
                self.apply(key: "select", policy: .toEnd(from: lite ? .max : 0))
            }
            

            
            self.isSelected = isSelected
            
        }
        
        private func apply(key: String, policy: LottiePlayPolicy, animated: Bool = false) {
            
            let presentation = self.presenation ?? theme
            if self.currentKey != key {
                if let player = self.player {
                    performSublayerRemoval(player, animated: animated)
                }
                let color = presentation.colors.grayIcon.withAlphaComponent(0.8)
                let inline = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: category.id, file: self.player?.file, emoji: ""), size: NSMakeSize(23, 23), playPolicy: policy, getColors: { _ in
                    return [.init(keyPath: "", color: color)]
                }, ignorePreview: true)
                self.player = inline
                inline.superview = self
                inline.frame = focus(NSMakeSize(23, 23))
                inline.isPlayable = visibleRect != .zero
                self.layer?.addSublayer(inline)
                
                if animated {
                    inline.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            self.currentKey = key
        }
        
        deinit {
        }
        
        override func layout() {
            super.layout()
            updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            if let player = player {
                transition.updateFrame(layer: player, frame: self.focus(player.frame.size))
            }
            if let imageView = self.imageView {
                transition.updateFrame(view: imageView, frame: self.focus(imageView.frame.size))
            }
            if let selectionView = self.selectionView {
                transition.updateFrame(layer: selectionView, frame: self.focus(selectionView.frame.size))
            }
        }
        
        var isLite: Bool {
            return self.context.isLite(.emoji)
        }
        
        func playAppearAnimation() {
            
            guard self.visibleRect != .zero || isLite else {
                return
            }
            //self.apply(key: "appear", policy: .toEnd(from: 1))
        }
        
        func update(isSelected: Bool, animated: Bool) {
            if self.isSelected != isSelected {
                self.isSelected = isSelected
                let presentation = self.presenation ?? theme

                if isSelected {
                    let current: SimpleLayer
                    if let view = self.selectionView {
                        current = view
                    } else {
                        current = SimpleLayer()
                        current.frame = focus(NSMakeSize(25, 25))
                        current.cornerRadius = current.frame.height / 2
                        current.backgroundColor = presentation.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1).cgColor
                        self.layer?.insertSublayer(current, at: 0)
                        self.selectionView = current
                        
                        if animated {
                            current.animateAlpha(from: 0, to: 1, duration: 0.2)
                            current.animateScale(from: 0.1, to: 1, duration: 0.2)
                        }
                    }
                } else if let view = self.selectionView {
                    performSublayerRemoval(view, animated: animated)
                    self.selectionView = nil
                }
                
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        required init(frame frameRect: NSRect) {
            fatalError("init(frame:) has not been implemented")
        }
    }

    public let scrollView = HorizontalScrollView()
    private let documentView = View()
    
    private let topGradient = ShadowView()
    private let bottomGradient = ShadowView()
    
    
    private let backgroundView = View()
    
    private var categories: [EmojiSearchCategories.Group] = []
    public var select:((EmojiSearchCategories.Group?)->Void)? = nil
    public required init(frame frameRect: NSRect, presentation: TelegramPresentationTheme? = nil) {
        self.presentation = presentation
        super.init(frame: frameRect)
        
       // addSubview(backgroundView)
        addSubview(scrollView)
        
        
        
        scrollView.background = .clear
        scrollView.documentView = documentView
        
        
        self.boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.clipView, queue: OperationQueue.main, using: { [weak self] notification  in
            self?.updateScroll()
        })
        
        self.addSubview(topGradient)
        self.addSubview(bottomGradient)

        updateLocalizationAndTheme(theme: presentation ?? theme)

        self.layer?.cornerRadius = frame.height / 2
        updateScroll()
    }
    public var presentation: TelegramPresentationTheme? = nil
    
    public var searchTheme: SearchTheme? {
        didSet {
            updateLocalizationAndTheme(theme: presentation ?? theme)
        }
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundView.backgroundColor = searchTheme?.backgroundColor ?? theme.search.backgroundColor
        bottomGradient.shadowBackground = searchTheme?.backgroundColor ?? theme.search.backgroundColor
        bottomGradient.direction = .horizontal(true)
        topGradient.shadowBackground = searchTheme?.backgroundColor ?? theme.search.backgroundColor
        topGradient.direction = .horizontal(false)

    }
    
    
    private var previousRange: [Int] = []
    public func updateScroll() {
        
        self.topGradient.isHidden = self.scrollView.documentOffset.x == 0
        self.bottomGradient.isHidden = self.scrollView.documentOffset.x == self.scrollView.documentSize.width - self.scrollView.frame.width

        
        let range = visibleRange(self.scrollView.documentOffset)
        if previousRange != range, !previousRange.isEmpty {
            let new = range.filter({
                !previousRange.contains($0)
            })
            for i in new {
                let view = self.documentView.subviews[i] as? CategoryView
                view?.playAppearAnimation()
            }
        }
        self.previousRange = range
    }
    
    private func visibleRange(_ documentOffset: NSPoint) -> [Int] {
        var range: [Int] = []
        for (i, view) in documentView.subviews.enumerated() {
            if view.visibleRect != .zero {
                range.append(i)
            }
        }
        return range
    }
    
    private var boundsObserver: NSObjectProtocol?
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }
    
    public private(set) var selected: EmojiSearchCategories.Group?
    
    public func update(categories: [EmojiSearchCategories.Group], context: any AccountContextProtocol, selected: EmojiSearchCategories.Group?, animated: Bool) {
        
        
       
        let selectedUpdated = self.selected != selected
        self.selected = selected
        
        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: self.categories, rightList: categories)
        
        
                
        for rdx in deleteIndices.reversed() {
            self.documentView.subviews.remove(at: rdx)
            self.categories.remove(at: rdx)
        }
        
        
        for (idx, item, _) in indicesAndItems {
            let subview = CategoryView(frame: NSMakeRect(CGFloat(idx) * 30, 0, 30, 30), context: context, category: item, isSelected: selected == item, presenation: presentation)
            subview.set(handler: { [weak self] _ in
                self?.select?(item)
            }, for: .Click)
            self.documentView.subviews.insert(subview, at: idx)
            self.categories.insert(item, at: idx)
        }
        for (idx, item, _) in updateIndices {
            let subview = documentView.subviews[idx] as! CategoryView
            
            subview.update(isSelected: selected == item, animated: animated)
            self.categories[idx] = item
        }
        let itemViews = self.documentView.subviews.compactMap { $0 as? CategoryView }
        for view in itemViews {
            view.update(isSelected: selected == view.category, animated: animated)
        }
        
        if selectedUpdated {
            if let selected = selected {
                self.focus(to: selected, animated: animated)
            } else {
                scrollView.clipView.scroll(to: .zero, animated: animated)
            }
        }
        
    }
    
    public func focus(to category: EmojiSearchCategories.Group, animated: Bool) {
        let selectedView = documentView.subviews.first(where: { subview in
            if let subview = subview as? CategoryView, subview.category == category {
                return true
            } else {
                return false
            }
        })
        if let selectedView = selectedView {
            scrollView.clipView.scroll(to: NSMakePoint(min(max(selectedView.frame.midX - frame.width / 2, 0), max(documentView.frame.width - frame.width, 0)), 0), animated: animated)
        }
    }
    
    private var validLayout: NSSize? = nil
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        guard validLayout != size else {
            return
        }
        var rect = NSMakeRect(0, 0, 30, 30)
        var documentSize: NSSize = NSMakeSize(0, 30)
        for subview in documentView.subviews {
            transition.updateFrame(view: subview, frame: rect)
            rect = rect.offsetBy(dx: rect.width, dy: 0)
            documentSize = NSMakeSize(rect.width + documentSize.width, rect.height)
        }
        
//        transition.updateFrame(view: back, frame: back.centerFrameY(x: 0))
        
        let scrollRect = NSMakeRect(0, 0, size.width, size.height)
        transition.updateFrame(view: scrollView.contentView, frame: scrollRect)
        transition.updateFrame(view: scrollView, frame: scrollRect)
        transition.updateFrame(view: documentView, frame: documentSize.bounds)
        
        transition.updateFrame(view: backgroundView, frame: NSMakeRect(0, 0, size.width, rect.height))
        
        transition.updateFrame(view: self.topGradient, frame: NSMakeRect(0, 0, 10, size.height))
        transition.updateFrame(view: self.bottomGradient, frame: NSMakeRect(size.width - 10, 0, 10, size.height))

        
        validLayout = size
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}

public final class AnimatedEmojiesView : Control {
    public let tableView = TableView(frame: NSMakeRect(0, 0, 350, 350))
    public let packsView = HorizontalTableView(frame: NSMakeRect(0, 0, 350, 46))
    private let borderView = View()
    private let tabs = View()
    private let selectionView: View = View(frame: NSMakeRect(0, 0, 36, 36))
    
    public let searchView = SearchView(frame: .zero)
    fileprivate let searchContainer = View()
    private let visualEffect = NSVisualEffectView()
    private let searchInside = View()
    private let searchBackdrop = View()
    
    private let searchBorder = View()
    private let searchStatusView = PanelSearchStatusView(frame: .zero)
    private var searchStatus: PanelSearchPresentation = .hidden
    
    
    
    fileprivate var categories: AnimatedEmojiesCategories?
    fileprivate var closeCategories: BackCategoryControl?
    
    private var mode: EmojiesController.Mode = .emoji
    public var isGlass: Bool = false {
        didSet {
            if oldValue != isGlass {
                updateLocalizationAndTheme(theme: presentation ?? theme)
                needsLayout = true
            }
        }
    }
    public var showsGlassSurface: Bool = false {
        didSet {
            if oldValue != showsGlassSurface {
                updateGlassSurface()
            }
        }
    }
    private var glassSurface: LiquidGlassView?
    private var isClearBackground: Bool {
        return mode.isTransparent || isGlass
    }

    private func updateGlassSurface() {
        if showsGlassSurface {
            if glassSurface == nil {
                let view = LiquidGlassView(frame: bounds, cornerRadius: 18, hasShadow: false, hasBorder: true, tintAlpha: 0, forceBlur: true)
                addSubview(view, positioned: .below, relativeTo: nil)
                glassSurface = view
            }
            isGlass = true
        } else {
            glassSurface?.removeFromSuperview()
            glassSurface = nil
        }
        updateLocalizationAndTheme(theme: presentation ?? theme)
        needsLayout = true
    }
    fileprivate var state: State?
    private var context: (any AccountContextProtocol)?
    fileprivate var arguments: Arguments?
    
    public var presentation: TelegramPresentationTheme? {
        didSet {
            categories?.presentation = presentation
        }
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        self.packsView.getBackgroundColor = {
            .clear
        }
        self.tableView.getBackgroundColor = {
            .clear
        }
        addSubview(self.tableView)
        
        searchView.isLeftOrientated = true
        searchView.layer?.cornerRadius = 15

        searchInside.addSubview(searchView)
        
        visualEffect.wantsLayer = true
        
        if !TelegramUtilsHooks.shared.isLite(.blur) {
            visualEffect.state = .active
            visualEffect.blendingMode = .behindWindow
            visualEffect.autoresizingMask = []
        }
        
        
        if #available(macOS 11.0, *), !TelegramUtilsHooks.shared.isLite(.blur) {
            searchContainer.addSubview(visualEffect)
        }
        
        searchContainer.addSubview(searchBackdrop)
        searchContainer.addSubview(searchBorder)
        searchContainer.addSubview(searchInside)
        addSubview(searchContainer)
                
        tabs.addSubview(selectionView)
        tabs.addSubview(self.packsView)
        addSubview(self.borderView)
        addSubview(tabs)
        addSubview(searchStatusView)
        
        self.packsView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateSelectionState(animated: false)
        }))
        
        self.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateScrollerSearch()
        }))
        
       
        self.updateLayout(frame.size, transition: .immediate)
    }
 
    public override func layout() {
        super.layout()
        self.updateLayout(self.frame.size, transition: .immediate)
    }
    
    private func updateScrollerSearch() {
        self.updateLayout(self.frame.size, transition: .immediate)
    }
    
    public func updateLayout(_ size: NSSize, transition: ContainedViewLayoutTransition) {
        
        if let glassSurface {
            glassSurface.frame = size.bounds
            glassSurface.updateLayout(size: size, transition: .immediate)
        }

        let inSearch = searchState?.state == .Focus || state?.selectedEmojiCategory != nil
        
        let initial: CGFloat = inSearch || arguments?.mode == .messageEffects ? -46 : 0
        
        transition.updateFrame(view: tabs, frame: NSMakeRect(0, initial, size.width, 46))
        transition.updateFrame(view: packsView, frame: tabs.focus(NSMakeSize(size.width, 36)))
        transition.updateFrame(view: borderView, frame: NSMakeRect(0, tabs.frame.maxY, size.width, .borderSize))
        transition.updateFrame(view: tableView, frame: NSMakeRect(0, tabs.frame.maxY, size.width, size.height - initial))
        
        transition.updateAlpha(view: borderView, alpha: inSearch ? 0 : 1)

        
        let dest = max(0, min(tableView.rectOf(index: 0).minY + (tableView.clipView.destination?.y ?? tableView.documentOffset.y), 46))

        let searchDest = inSearch ? 0 : dest
        transition.updateFrame(view: searchContainer, frame: NSMakeRect(0, tabs.frame.maxY, size.width, 46 - min(searchDest, 46)))

        
        let searchInsideRect: CGRect = CGRect(origin: CGPoint(x: 0, y: searchContainer.frame.height - 46), size: NSMakeSize(size.width, 46))
        transition.updateFrame(view: searchInside, frame: searchInsideRect)
        transition.updateFrame(view: visualEffect, frame: searchInsideRect)
        transition.updateFrame(view: searchStatusView, frame: NSMakeRect(0, searchContainer.frame.maxY, size.width, max(0, size.height - searchContainer.frame.maxY - 56)))

        
        
        transition.updateFrame(view: searchView, frame: searchInside.focus(NSMakeSize(size.width - 16, 30)))
        transition.updateFrame(view: searchBorder, frame: NSMakeRect(0, searchContainer.frame.height - .borderSize, size.width, .borderSize))
        let alpha: CGFloat = inSearch && tableView.documentOffset.y > 0 ? 1 : 0
        transition.updateAlpha(view: searchBorder, alpha: alpha)
        if isGlass {
            transition.updateAlpha(view: searchBackdrop, alpha: alpha)
        }
        transition.updateFrame(view: searchBackdrop, frame: searchInsideRect)
        
        if let categories = categories {
            transition.updateFrame(view: categories, frame: categories.centerFrameY(x: searchInside.frame.width - categories.frame.width - searchView.frame.minX))
            categories.updateLayout(size: categories.frame.size, transition: transition)
        }
        

       
        
        self.updateSelectionState(animated: transition.isAnimated)
        
    }
    
    public override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        tableView.viewDidEndLiveResize()
        packsView.viewDidEndLiveResize()
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        
        self.borderView.backgroundColor = mode == .reactions || isGlass ? theme.colors.grayIcon.withAlphaComponent(0.1) : theme.colors.border
        self.tabs.backgroundColor = isClearBackground ? .clear : theme.colors.background
        self.backgroundColor = isClearBackground ? .clear : theme.colors.background
        self.searchContainer.background = isClearBackground ? .clear : theme.colors.background
        self.searchBorder.backgroundColor = mode.isTransparent ? .clear : isGlass ? theme.colors.grayIcon.withAlphaComponent(0.1) : theme.colors.border
        visualEffect.material = theme.colors.isDark ? .dark : .light
        visualEffect.isHidden = isGlass
        if let glassSurface {
            glassSurface.customTint = theme.colors.background.withAlphaComponent(EntertainmentView.glassTintAlpha)
            glassSurface.updateLocalizationAndTheme(theme: theme)
        }
        searchBackdrop.backgroundColor = theme.colors.background.withAlphaComponent(0.85)
        searchBackdrop.isHidden = !isGlass
        if isGlass {
            searchInside.backgroundColor = .clear
        } else {
            searchInside.backgroundColor = mode.isTransparent ? theme.colors.background.withAlphaComponent(0.7) : theme.colors.background
        }
        if isClearBackground {
            let background = theme.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1)
            let searchTheme = SearchTheme(background, theme.search.searchImage, theme.search.clearImage, theme.search.placeholder, theme.search.textColor, theme.search.placeholderColor)
            self.searchView.searchTheme = searchTheme
            self.categories?.searchTheme = searchTheme
        } else {
            self.searchView.searchTheme = theme.search
            self.categories?.searchTheme = theme.search
        }
        
        self.searchView.updateLocalizationAndTheme(theme: theme)
        searchStatusView.updateSearchStatus(searchStatus, kind: .emoji, query: searchView.query, theme: presentation ?? (theme as! TelegramPresentationTheme))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private var searchState: SearchState? = nil

    public func updateSearchState(_ searchState: SearchState, animated: Bool) {
        
        if let window = _window, self.mode.isFocusSearch {
            switch searchState.state {
            case .Focus:
                window._canBecomeKey = true
                window.makeKey()
            case .None:
                window._canBecomeKey = false
                context?.window.makeKey()
            }
        }
        
        let previous = self.searchState
        self.searchState = searchState

        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        updateSelectionState(animated: animated)
        self.updateLayout(self.frame.size, transition: transition)
        
        if previous?.state != searchState.state {
            self.tableView.scroll(to: .up(animated))
            self.moveCategories(nil)
        }
    }
    
    fileprivate func update(sections: TableUpdateTransition, packs: TableUpdateTransition, state: State, context: any AccountContextProtocol, arguments: Arguments, mode: EmojiesController.Mode) {
        self.mode = mode
        
        let previous = self.state
        self.state = state
        
        let transition: ContainedViewLayoutTransition
        if packs.animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        self.updateLayout(frame.size, transition: transition)
        
        self.arguments = arguments
        self.context = context
        self.tableView.merge(with: sections)
        self.packsView.merge(with: packs)
        var hasSearchResults = false
        if state.search != nil {
            tableView.enumerateItems { item in
                if item is EBlockItem || item is EmojiesSectionRowItem {
                    hasSearchResults = true
                    return false
                }
                return true
            }
        }
        searchStatus = .resolve(isSearching: state.search != nil, isLoading: state.searchLoading, hasResults: hasSearchResults)
        searchStatusView.updateSearchStatus(searchStatus, kind: .emoji, query: searchView.query, theme: presentation ?? theme)
        
//        searchContainer.isHidden = mode == .reactions
//        tableView.scrollerInsets = mode == .reactions ? .init() : .init(left: 0, right: 0, top: 46, bottom: 50)

//        searchContainer.isHidden = mode == .reactions
        tableView.scrollerInsets = .init(left: 0, right: 0, top: 46, bottom: 50)
        
        updateSelectionState(animated: packs.animated)
        updateLocalizationAndTheme(theme: presentation ?? theme)
        
        if state.selectedEmojiCategory != previous?.selectedEmojiCategory {
            self.tableView.scroll(to: .up(transition.isAnimated))
        }
    }
    
    
    @discardableResult public func moveCategories(_ event: NSEvent?) -> Bool {
        let transition: ContainedViewLayoutTransition = event == nil ? .animated(duration: 0.2, curve: .easeInOut) : .immediate
        if let view = self.categories {
            if let event = event, state?.selectedEmojiCategory == nil {
                let previous = view.scrollView.contentView.bounds.origin
                let point = view.scrollView.makeScrollPoint(event)
                let difference = previous.x - point.x
                var rect = view.frame.insetBy(dx: difference, dy: 0)
                
                var accept: Bool = previous.x == 0

                if accept {
                    
                    let minX = searchView.frame.minX + searchView.searchSize.width
                    
                    if rect.origin.x < minX {
                        accept = false
                    } else if rect.origin.x > searchContainer.frame.width - categoryRect.width - searchView.frame.minX {
                        accept = false
                    }
                    rect.size.width = min(searchView.frame.width - searchView.searchSize.width, max(categoryRect.width, rect.width))
                    rect.origin.x = max(minX, searchContainer.frame.width - rect.width - searchView.frame.minX)
                    transition.updateFrame(view: view, frame: rect)
                    
                    let maxX = (searchView.frame.minX + searchView.holderSize.width)
                    
                    let sInset = maxX - rect.origin.x
                    let sOpacity: CGFloat = 1 - sInset / minX
                    if minCategoryWidth != categoryRect.width {
                        searchView.movePlaceholder(-sInset, opacity: sOpacity, transition: transition)
                    } else {
                        searchView.movePlaceholder(nil, opacity: 1, transition: transition)
                    }
                }
                view.updateScroll()
                
                return accept
            } else {
                if let _ = state?.selectedEmojiCategory {
                    transition.updateFrame(view: view, frame: revealedCategoryRect)
                    if minCategoryWidth != categoryRect.width {
                        searchView.movePlaceholder(-((searchView.frame.minX + searchView.holderSize.width) - revealedCategoryRect.minX), opacity: 0, transition: transition)
                    } else {
                        searchView.movePlaceholder(nil, opacity: 1, transition: transition)
                    }
                } else {
                    transition.updateFrame(view: view, frame: categoryRect)
                    searchView.movePlaceholder(nil, opacity: 1, transition: transition)
                    view.scrollView.clipView.scroll(to: .zero, animated: transition.isAnimated)
                }
                view.updateLayout(size: view.frame.size, transition: transition)
            }
        } else {
            searchView.movePlaceholder(nil, opacity: 1, transition: transition)
        }
        return false
    }
    public var minCategoryWidth: CGFloat {
        return CGFloat(state?.searchCategories?.groups.count ?? 0) * 30
    }
    public var categoryRect: NSRect {
        let width = min(searchView.frame.width - searchView.holderSize.width, minCategoryWidth)
        return NSMakeRect(searchContainer.frame.width - (width + searchView.frame.minX), searchView.frame.minY, width, 30)
    }
    public var revealedCategoryRect: NSRect {
        let width = min(searchView.frame.width - searchView.searchSize.width, minCategoryWidth)
        return NSMakeRect(searchContainer.frame.width - (width + searchView.frame.minX), searchView.frame.minY, width, 30)
    }
    
    public func updateSelectionState(animated: Bool) {
        
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        let currentClose: BackCategoryControl

        if state?.selectedEmojiCategory != nil, let context = context {
            if let view = self.closeCategories {
                currentClose = view
            } else {
                currentClose = .init(frame: NSMakeRect(searchView.frame.minX, searchView.frame.minY, 30, 30), context: context, presentation: presentation ?? theme)
                self.closeCategories = currentClose
                searchInside.addSubview(currentClose)
                
                
                currentClose.set(handler: { [weak self] _ in
                    self?.arguments?.selectEmojiCategory(nil)
                }, for: .Click)
            }
            self.searchView.updateSearchHolderVisibility(visible: false, transition: .immediate)
        } else {
            if let view = self.closeCategories {
                view.close()
                delay(0.4, closure: { [weak self, weak view] in
                    view?.removeFromSuperview()
                    if self?.closeCategories == nil {
                        self?.searchView.updateSearchHolderVisibility(visible: true, transition: .immediate)
                    }
                })
                self.closeCategories = nil
            }
        }
        
        if searchState == nil || searchState?.state == .None, let groups = self.state?.searchCategories?.groups, let context = context {
            let current: AnimatedEmojiesCategories
            
            
            
            if let view = self.categories {
                current = view
            } else {
                current = AnimatedEmojiesCategories(frame: categoryRect, presentation: presentation)
                self.categories = current
                searchInside.addSubview(current)
                
                current.select = { [weak self] category in
                    self?.arguments?.selectEmojiCategory(category)
                }
            }
            
            current.userInteractionEnabled = current.selected != nil
            
            if current.selected != state?.selectedEmojiCategory, current.selected == nil || state?.selectedEmojiCategory == nil {
                self.moveCategories(nil)
            }
            
            current.update(categories: groups, context: context, selected: self.state?.selectedEmojiCategory, animated: animated)
            current.scrollView.applyExternalScroll = { [weak self] event in
                return self?.moveCategories(event) ?? false
            }
            current.updateScroll()
            
            
            self.searchView.externalScroll = { [weak current] event in
                if current?.mouseInside() == false {
                    current?.scrollView.scrollWheel(with: event)
                }
            }
            
        } else if let view = self.categories {
            performSubviewRemoval(view, animated: animated)
            if animated {
                view.layer?.animatePosition(from: view.frame.origin, to: categoryRect.origin, duration: 0.2, removeOnCompletion: false)
                view.layer?.animateBounds(from: view.frame.size.bounds, to: categoryRect.size.bounds, duration: 0.2, removeOnCompletion: false)
            }
            self.categories = nil
            self.searchView.externalScroll = nil
            
        }
        
//        self.moveCategories(nil)
        
        var animated = transition.isAnimated
        var item = packsView.selectedItem()
        if item == nil, packsView.count > 1 {
            item = packsView.item(at: 1)
            animated = false
        }

        let theme = presentation ?? theme
        
        guard let item = item else {
            return
        }
        let viewPoint = packsView.rectOf(item: item).origin
        
        let point = packsView.clipView.destination ?? packsView.contentOffset
        let rect = NSMakeRect(viewPoint.y - point.y, 5, item.height, packsView.frame.height)
        
        selectionView.layer?.cornerRadius = item.height == item.width && item.index != 1 ? .cornerRadius : item.width / 2
        if mode == .reactions || isGlass {
            selectionView.background = theme.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1)
        } else {
            selectionView.background = theme.colors.grayBackground.withAlphaComponent(item.height == item.width ? 1 : 0.9)
        }
        if animated {
            selectionView.layer?.animateCornerRadius()
        }
        transition.updateFrame(view: selectionView, frame: rect)
        updateLocalizationAndTheme(theme: presentation ?? theme)
    }
    
    
    public func scroll(to segment: EmojiSegment, animated: Bool) {
//        if let item = packsView.item(stableId: InputDataEntryId.custom(_id_segments_pack)) {
//            _ = self.packsView.select(item: item)
//        }
        let stableId = InputDataEntryId.custom(_id_emoji_segment(segment.rawValue))
        tableView.scroll(to: .top(id: stableId, innerId: nil, animated: animated, focus: .init(focus: false), inset: 0))
        updateSelectionState(animated: animated)
    }
    
    public func findSegmentAndScroll(selected: TableRowItem, animated: Bool) -> EmojiSegment? {
        let stableId = selected.stableId as? InputDataEntryId
        var segment: EmojiSegment?
        if let identifier = stableId?.identifier {
            if identifier == _id_recent_pack {
                tableView.scroll(to: .up(animated))
            } else if identifier == _id_segments_pack {
                segment = EmojiSegment.People
                let stableId = InputDataEntryId.custom(_id_emoji_segment(EmojiSegment.People.rawValue))
                tableView.scroll(to: .top(id: stableId, innerId: nil, animated: animated, focus: .init(focus: false), inset: 0))
            } else if identifier.identifier.hasPrefix("_id_pack_") {
                let collectionId = identifier.identifier.trimmingCharacters(in: CharacterSet(charactersIn: "1234567890").inverted)
                if let collectionId = Int64(collectionId) {
                    var stableId = InputDataEntryId.custom(_id_aemoji_block(collectionId))
                    
                    if tableView.item(stableId: stableId) == nil {
                        stableId = InputDataEntryId.custom(_id_section(collectionId, "a"))
                    }
                    
                    tableView.scroll(to: .top(id: stableId, innerId: nil, animated: animated, focus: .init(focus: false), inset: 0))
                    
                    let packStableId = InputDataEntryId.custom(_id_pack(collectionId))
                    packsView.scroll(to: .center(id: packStableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0))

                }
            }
        }
        updateSelectionState(animated: true)
        return segment
    }
    
    public func selectBestPack() -> EmojiSegment? {
        
        guard tableView.count > 1, tableView.visibleRows().location != NSNotFound else {
            return nil
        }
        
        let stableId = tableView.item(at: max(1, tableView.visibleRows().location)).stableId
        var _stableId: AnyHashable?
        var _segment: EmojiSegment?

        if let stableId = stableId as? InputDataEntryId, let identifier = stableId.identifier {
            let identifier = identifier.identifier
            
            if identifier.hasPrefix("_id_emoji_segment_") || identifier.hasPrefix("_id_emoji_block_") {
                if let segmentId = Int64(identifier.suffix(1)), let segment = EmojiSegment(rawValue: segmentId) {
                    switch segment {
                    case .Recent, .RecentAnimated:
                        _stableId = InputDataEntryId.custom(_id_recent_pack)
                    default:
                        _stableId = InputDataEntryId.custom(_id_segments_pack)
                    }
                    _segment = segment
                }
            } else if identifier.hasPrefix("_id_section_") {
                let collectionId = identifier.trimmingCharacters(in: CharacterSet(charactersIn: "1234567890").inverted)
                if let collectionId = Int64(collectionId) {
                    _stableId = InputDataEntryId.custom(_id_pack(collectionId))
                }
            }
        }
        if let stableId = _stableId, let item = packsView.item(stableId: stableId) {
            _ = self.packsView.select(item: item)
            self.packsView.scroll(to: .center(id: stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0))
        }
        updateSelectionState(animated: true)
        return _segment
    }
    
    public func scroll(to info: StickerPackCollectionInfo, animated: Bool) {
        let item = self.packsView.item(stableId: InputDataEntryId.custom(_id_pack(info.id.id)))
        if let item = item {
            _ = self.packsView.select(item: item)
            self.packsView.scroll(to: .center(id: item.stableId, innerId: nil, animated: animated, focus: .init(focus: false), inset: 0))
            self.tableView.scroll(to: .top(id: InputDataEntryId.custom(_id_aemoji_block(info.id.id)), innerId: nil, animated: animated, focus: .init(focus: false), inset: 0))
            
            updateSelectionState(animated: animated)

        }
    }
}

public enum EmojiesControllerMode {
    case emoji
    case status
    case reactions
    case quickReaction
    case selectAvatar
    case forumTopic
    case backgroundIcon
    case stories
    case channelReactions
    case channelStatus
    case defaultTags
    case messageEffects
    public var itemMode: EmojiesSectionRowItem.Mode {
        switch self {
        case .reactions:
            return .reactions
        case .quickReaction:
            return .reactions
        case .status:
            return .statuses
        case .forumTopic:
            return .topic
        case .backgroundIcon:
            return .backgroundIcon
        case .channelReactions:
            return .channelReactions
        case .channelStatus:
            return .channelStatus
        case .defaultTags:
            return .defaultTags
        case .messageEffects:
            return .messageEffects
        default:
            return .panel
        }
    }
    public var isTransparent: Bool {
        switch self {
        case .reactions:
            return true
        case .messageEffects:
            return true
        default:
            return false
        }
    }
    public var isFocusSearch: Bool {
        switch self {
        case .reactions, .messageEffects, .defaultTags:
            return true
        default:
            return false
        }
    }
}

public final class EmojiesController<Context: AccountContextProtocol> : TelegramGenericViewController<AnimatedEmojiesView, Context>, TableViewDelegate {
    public override var defaultBarTitle: String {
        return localizedString("Telegram.EmojiesController")
    }
    private let disposable = MetaDisposable()
    
    private var interactions: EntertainmentInteractions?
    private weak var chatInteraction: (any ChatInteractionProtocol)?
    
    private let onStage = ValuePromise<Bool>(ignoreRepeated: true)
    
    private var groupEmojiPack: Signal<(StickerPackCollectionInfo, [StickerPackItem])?, NoError> = .single(nil)

    
    private var updateState: (((State) -> State) -> Void)? = nil
    private var scrollOnAppear:(()->Void)? = nil
    
    public var makeSearchCommand:((ESearchCommand)->Void)?

    public var isGlass: Bool = false {
        didSet {
            if isLoaded() {
                genericView.isGlass = isGlass
            }
        }
    }

    public var showsGlassSurface: Bool = false {
        didSet {
            if isLoaded() {
                genericView.showsGlassSurface = showsGlassSurface
            }
        }
    }

    public override var popoverBackgroundColor: NSColor {
        return showsGlassSurface ? .clear : super.popoverBackgroundColor
    }
    private let searchValue = ValuePromise<SearchState>(.init(state: .None, request: nil))
    private var searchState: SearchState = .init(state: .None, request: nil) {
        didSet {
            self.searchValue.set(searchState)
        }
    }
    
    
    private func updateSearchState(_ state: SearchState) {
        let changed = self.searchState.request.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased() != state.request.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        self.searchState = state
        if changed && !state.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.makeSearchCommand?(.loading)
        }
        if self.isLoaded() == true {
            self.genericView.updateSearchState(state, animated: true)
        }
    }
    
    public typealias Mode = EmojiesControllerMode
    private let mode: Mode
    
    public var closeCurrent:(()->Void)? = nil
    public var animateAppearance:(([TableRowItem])->Void)? = nil
    private var presentation: TelegramPresentationTheme?
    private let selectedItems: [EmojiesSectionRowItem.SelectedItem]
    private let ignorePremium: Bool
    private let orderedTags: [RecentReactionItem]?
    
    public var staticEmojiFilter: ((String) -> Bool)?

    public var color: NSColor? = nil {
        didSet {
            self.updateState?({ current in
                var current = current
                current.color = color
                return current
            })
        }
    }

    private var externalSelection: [EmojiesSectionRowItem.SelectedItem]?

    public func updateSelectedItems(_ items: [EmojiesSectionRowItem.SelectedItem]) {
        self.externalSelection = items
        self.updateVisibleSelection(items)
        self.updateState?({ current in
            var current = current
            current.selectedItems = items
            return current
        })
    }
    
    private func updateVisibleSelection(_ selected: [EmojiesSectionRowItem.SelectedItem]) {
        var orders: [String: Int] = [:]
        for item in selected {
            if case let .builtin(emoji) = item.source, let index = item.index {
                orders[emojiSelectionKey(emoji)] = index
            }
        }
        self.genericView.tableView.enumerateVisibleItems(with: { item in
            if let item = item as? EBlockItem, item.selectedOrders != orders {
                item.selectedOrders = orders
                (item.view as? EBlockRowView)?.updateLines(item: item, animated: true)
            } else if let item = item as? EmojiesSectionRowItem {
                let rowSelection = emojiesRowSelection(selected, in: item.stickerItems)
                if item.selectedItems != rowSelection {
                    item.selectedItems = rowSelection
                    _ = item.makeSize(item.width)
                    item.view?.set(item: item, animated: true)
                }
            }
            return true
        })
    }

    public init(_ context: Context, mode: Mode = .emoji, selectedItems: [EmojiesSectionRowItem.SelectedItem] = [], presentation: TelegramPresentationTheme? = nil, color: NSColor? = nil, ignorePremium: Bool = false, orderedTags: [RecentReactionItem]? = nil) {
        self.orderedTags = orderedTags
        self.mode = mode
        self.presentation = presentation
        self.selectedItems = selectedItems
        self.color = color
        self.ignorePremium = ignorePremium
        super.init(context)
        _frameRect = NSMakeRect(0, 0, 350, 300)
        self.bar = .init(height: 0)

    }
    
    deinit {
        disposable.dispose()
    }
    
    private func updatePackReorder(_ sections: [State.Section]) {
        let resortRange: NSRange = NSMakeRange(3, genericView.packsView.count - 4 - sections.filter { !$0.installed }.count)
        
        let context = self.context
        
        if resortRange.length > 0 {
            self.genericView.packsView.resortController = TableResortController(resortRange: resortRange, start: { _ in }, resort: { _ in }, complete: { fromIndex, toIndex in
                
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
            self.genericView.packsView.resortController = nil
        }
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: presentation ?? theme)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        
        onStage.set(true)
        
        genericView.presentation = self.presentation
        genericView.isGlass = isGlass || showsGlassSurface
        genericView.showsGlassSurface = showsGlassSurface
        genericView.packsView.delegate = self
        
       
        
        let scrollToOnNextTransaction: Atomic<StickerPackCollectionInfo?> = Atomic(value: nil)
        let scrollToOnNextAppear: Atomic<StickerPackCollectionInfo?> = Atomic(value: nil)

        let context = self.context
        let mode = self.mode
        let actionsDisposable = DisposableSet()
        
        let initialState = State(sections: [], itemsDict: [:], selectedItems: self.selectedItems, color: self.color)
        
        let statePromise = ValuePromise<State>(ignoreRepeated: true)
        let stateValue = Atomic(value: initialState)
        let updateState: ((State) -> State) -> Void = { f in
            statePromise.set(stateValue.modify (f))
        }

        self.updateState = { f in
            updateState(f)
        }
        
        let searchInteractions = SearchInteractions({ [weak self] state, _ in
            self?.updateSearchState(state)
            updateState { current in
                var current = current
                current.selectedEmojiCategory = nil
                return current
            }
        }, { [weak self] state in
            self?.updateSearchState(state)
            updateState { current in
                var current = current
                current.selectedEmojiCategory = nil
                return current
            }
        })
        
        genericView.searchView.searchInteractions = searchInteractions
        
        
        self.scrollOnAppear = { [weak self] in
            if let info = scrollToOnNextAppear.swap(nil) {
                self?.genericView.scroll(to: info, animated: false)
            }
        }
        
        let ignorePremium = self.ignorePremium
        
        let arguments = Arguments(context: context, mode: self.mode, ignorePremium: ignorePremium, send: { [weak self] item, info, timeout, rect in
            switch mode {
            case .emoji, .stories:
                if !ignorePremium, !context.isPremium && item.file.isPremiumEmoji, context.peerId != self?.chatInteraction?.peerId {
                    showModalText(for: context.window, text: strings().emojiPackPremiumAlert, callback: { _ in
                        FeatureNavigationHooks.shared.showPremiumBoarding(context, context.window, .premiumStickers, false, nil)
                    })
                } else {
                    self?.interactions?.sendAnimatedEmoji(item, nil, info, nil, rect)
                }
                _ = scrollToOnNextAppear.swap(info)
            case .status:
                let starGift = stateValue.with { $0.uniqueStarGiftsItems.first(where: { $0.starGift.file?.fileId == item.file.fileId })}?.starGift
                self?.interactions?.sendAnimatedEmoji(item, starGift, nil, timeout, rect)
            default:
                self?.interactions?.sendAnimatedEmoji(item, nil, nil, nil, rect)
            }
            
        }, sendEmoji: { [weak self] emoji, fromRect in
            self?.interactions?.sendEmoji(emoji, fromRect)
        }, selectEmojiSegment: { [weak self] segment in
            updateState { current in
                var current = current
                current.emojiState.selected = segment
                return current
            }
            self?.genericView.scroll(to: segment, animated: true)
        }, viewSet: { info in
            showModal(with: EntertainmentUIHooks.shared.makeStickerPackPreview(context, nil, [.emoji(.name(info.shortName))]), for: context.window)
        }, showAllItems: { id in
            updateState { current in
                var current = current
                current.revealed[id] = true
                return current
            }
        }, openPremium: { [weak self] in
            FeatureNavigationHooks.shared.showPremiumBoarding(context, context.window, .premiumEmoji, false, nil)
            self?.closeCurrent?()
        }, installPack: { info, items in
            _ = scrollToOnNextTransaction.swap(info)
            let signal = context.engine.stickers.addStickerPackInteractively(info: info, items: items) |> deliverOnMainQueue
            _ = signal.start()
        }, clearRecent: {
            _ = context.engine.stickers.clearRecentlyUsedReactions().start()
        }, selectEmojiCategory: { [weak self] category in
            updateState { current in
                var current = current
                current.selectedEmojiCategory = category
                return current
            }
            let searchState: SearchState
            if let category = category {
                searchState = .init(state: .None, request: category.identifiers.joined(separator: ""))
            } else {
                searchState = .init(state: .None, request: nil)
            }
            self?.genericView.state = stateValue.with { $0 }
            self?.updateSearchState(searchState)
        })
        arguments.staticEmojiFilter = self.staticEmojiFilter
        arguments.sendLarge = { [weak self] in
            return self?.interactions?.sendLargeReaction
        }
        arguments.drag = { [weak self] item, drag in
            guard let dragItem = self?.interactions?.dragItem, context.isPremium || !item.file.isPremiumEmoji else {
                return false
            }
            dragItem(.file(item.file._parse()), nil, drag)
            return true
        }
        arguments.dragEmoji = { [weak self] emoji, drag in
            guard let dragItem = self?.interactions?.dragItem else {
                return false
            }
            dragItem(.emoji(emoji), nil, drag)
            return true
        }
        
        genericView.arguments = arguments
        
        let selectUpdater = { [weak self] in
            if self?.genericView.tableView.clipView.isAnimateScrolling == true {
                return
            }
            
            let innerSegment = self?.genericView.selectBestPack()
            
            updateState { current in
                var current = current
                current.emojiState.selected = innerSegment
                return current
            }
        }
        
        genericView.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: true, { position in
            selectUpdater()
            if position.direction == .bottom, position.rect.minY >= position.rect.height - 200 {
                stateValue.with { $0.searchContext }?.loadMore()
            }
        }))
        
        
        let searchQueries = self.searchValue.get() |> map { $0.request.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased() } |> distinctUntilChanged
        let selectedCategories = Signal<EmojiSearchCategories.Group?, NoError>.single(initialState.selectedEmojiCategory) |> then(statePromise.get() |> map { $0.selectedEmojiCategory }) |> distinctUntilChanged
        let search = combineLatest(searchQueries, selectedCategories) |> deliverOnMainQueue |> mapToSignal { query, category -> Signal<EmojiPanelSearchData, NoError> in
            let includeCustomEmoji = mode == .emoji || mode == .stories
            if let category = category {
                if includeCustomEmoji {
                    return panelCustomEmojiSearch(engine: context.engine, query: nil, values: category.identifiers, languageCode: "")
                }
                return .single(.init(values: category.identifiers, isLoading: false))
            }
            if query.isEmpty {
                return .single(.init(values: nil, isLoading: false))
            }
            let results = EntertainmentUIHooks.shared.inputSource(context).searchEmoji(postbox: context.account.postbox, engine: context.engine, sharedContext: context.sharedContext, query: query, completeMatch: false, checkPrediction: false)
            |> distinctUntilChanged
            |> deliverOnMainQueue
            |> mapToSignal { values -> Signal<EmojiPanelSearchData, NoError> in
                if includeCustomEmoji {
                    return panelCustomEmojiSearch(engine: context.engine, query: query, values: values, languageCode: currentKeyboardLanguage())
                }
                return .single(.init(values: values, isLoading: false))
            }
            |> delay(0.15, queue: .mainQueue())
            return .single(.init(values: [], isLoading: true)) |> then(results)
        }

        let combined = statePromise.get()
        
        let presentation = self.presentation
        
        let takePresentation:()->TelegramPresentationTheme = {
            return presentation ?? theme
        }
        
        let signal:Signal<(sections: InputDataSignalValue, packs: InputDataSignalValue, state: State), NoError> = combined |> deliverOnPrepareQueue |> map { state in
            let sections = InputDataSignalValue(entries: entries(state, arguments: arguments))
            let packs = InputDataSignalValue(entries: packEntries(state, arguments: arguments, presentation: takePresentation()))
            return (sections: sections, packs: packs, state: state)
        }
        
        
        let previousSections: Atomic<[AppearanceWrapperEntry<InputDataEntry>]> = Atomic(value: [])
        let previousPacks: Atomic<[AppearanceWrapperEntry<InputDataEntry>]> = Atomic(value: [])

        let initialSize = self.atomicSize
        
        let onMainQueue: Atomic<Bool> = Atomic(value: true)
        
        let inputArguments = InputDataArguments(select: { _, _ in
            
        }, dataUpdated: {
            
        })
        
        let transition: Signal<(sections: TableUpdateTransition, packs: TableUpdateTransition, state: State), NoError> = combineLatest(queue: .mainQueue(), appearanceSignal, signal) |> mapToQueue { appearance, state in
            let sectionEntries = state.sections.entries.map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
            let packEntries = state.packs.entries.map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }

            let onMain = onMainQueue.swap(false)
            
            
            let initialSize = initialSize.modify { $0 }
            
            let sectionsTransition = prepareInputDataTransition(left: previousSections.swap(sectionEntries), right: sectionEntries, animated: !onMain, searchState: state.sections.searchState, initialSize: initialSize, arguments: inputArguments, onMainQueue: onMain, animateEverything: false, grouping: true, makeFirstFast: true)
            
            
            let packsTransition = prepareInputDataTransition(left: previousPacks.swap(packEntries), right: packEntries, animated: !onMain, searchState: state.packs.searchState, initialSize: initialSize, arguments: inputArguments, onMainQueue: onMain, animateEverything: false, grouping: true, makeFirstFast: true)

            return combineLatest(sectionsTransition, packsTransition) |> map { values in
                return (sections: values.0, packs: values.1, state: state.state)
            }
            
        } |> deliverOnMainQueue
                        
        disposable.set(transition.start(next: { [weak self] values in
            self?.genericView.update(sections: values.sections, packs: values.packs, state: values.state, context: context, arguments: arguments, mode: mode)
            if let selected = self?.externalSelection {
                self?.updateVisibleSelection(selected)
            }
            
            selectUpdater()

            if let info = scrollToOnNextTransaction.swap(nil) {
                self?.genericView.scroll(to: info, animated: false)
            }
            
            self?.updatePackReorder(values.state.sections)
            var visibleItems:[TableRowItem] = []
            if self?.didSetReady == false {
                self?.genericView.packsView.enumerateVisibleItems(with: { item in
                    visibleItems.append(item)
                    return true
                })
                self?.genericView.tableView.enumerateVisibleItems(with: { item in
                    visibleItems.append(item)
                    return true
                })
            }
            self?.readyOnce()
            if !visibleItems.isEmpty {
                self?.animateAppearance?(visibleItems)
            }
        }))
        
        let updateSearchCommand:()->Void = { [weak self] in
            self?.makeSearchCommand?(.normal)

        }
        
        var iconStatusEmoji: Signal<[TelegramMediaFile], NoError> = .single([])

        if mode == .status {
            
            iconStatusEmoji = context.engine.stickers.loadedStickerPack(reference: .iconStatusEmoji, forceActualized: false)
            |> map { result -> [TelegramMediaFile] in
                switch result {
                case let .result(_, items, _):
                    return items.map(\.file).map { $0._parse() }
                default:
                    return []
                }
            }
            |> take(1)
        } else if mode == .channelStatus {
            iconStatusEmoji = context.engine.stickers.loadedStickerPack(reference: .iconChannelStatusEmoji, forceActualized: false)
            |> map { result -> [TelegramMediaFile] in
                switch result {
                case let .result(_, items, _):
                    return items.map(\.file).map { $0._parse() }
                default:
                    return []
                }
            }
            |> take(1)
        }
        
 
        let emojies: Signal<ItemCollectionsView, NoError>
        switch mode {
        case .reactions, .quickReaction, .defaultTags:
            emojies = context.diceCache.emojies_reactions_small(500) |> take(1)
            |> then(.complete() |> delay(1.0, queue: prepareQueue))
            |> then(context.diceCache.emojies_reactions(8000))
        case .status:
            emojies = context.diceCache.emojies_status_small |> take(1)
            |> then(.complete() |> delay(1.0, queue: prepareQueue))
            |> then(context.diceCache.emojies_status)
        case .backgroundIcon:
            emojies = context.diceCache.background_icons_small |> take(1)
            |> then(.complete() |> delay(1.0, queue: prepareQueue))
            |> then(context.diceCache.background_icons)
        case .channelStatus:
            emojies = context.diceCache.channel_statuses_small |> take(1)
            |> then(.complete() |> delay(1.0, queue: prepareQueue))
            |> then(context.diceCache.channel_statuses)
        default:
            emojies = context.diceCache.emojies_small |> take(1)
            |> then(.complete() |> delay(1.0, queue: prepareQueue))
            |> then(context.diceCache.emojies)
        }
        
        
        
        
        let forumTopic: Signal<[StickerPackItem], NoError>
        if mode == .forumTopic {
            forumTopic = context.engine.stickers.loadedStickerPack(reference: .iconTopicEmoji, forceActualized: false) |> map { result in
                switch result {
                case let .result(_, items, _):
                    return items
                default:
                    return []
                }
            }
        } else {
            forumTopic = .single([])
        }
        
        let searchCategories: Signal<EmojiSearchCategories?, NoError>
        if mode == .emoji || mode == .reactions || mode == .quickReaction || mode == .stories || mode == .messageEffects {
            searchCategories = context.engine.stickers.emojiSearchCategories(kind: .emoji)
        } else if mode == .status {
            searchCategories = context.engine.stickers.emojiSearchCategories(kind: .status)
        } else if mode == .selectAvatar {
            searchCategories = context.engine.stickers.emojiSearchCategories(kind: .avatar)
        } else {
            searchCategories = .single(nil)
        }
        
        let reactions = context.reactions.stateValue
        let reactionSettings = context.account.postbox.preferencesView(keys: [PreferencesKeys.reactionSettings])
           |> map { preferencesView -> ReactionSettings in
               let reactionSettings: ReactionSettings
               if let entry = preferencesView.values[PreferencesKeys.reactionSettings], let value = entry.get(ReactionSettings.self) {
                   reactionSettings = value
               } else {
                   reactionSettings = .default
               }
               return reactionSettings
           }
        
        let peer = getPeerView(peerId: context.peerId, postbox: context.account.postbox)
        
        let featured: Signal<[FeaturedStickerPackItem], NoError> = context.account.viewTracker.featuredEmojiPacks() |> map {
            Array($0.prefix(5))
        } |> take(1) |> then(context.account.viewTracker.featuredEmojiPacks() |> delay(1.0, queue: prepareQueue))
        

        switch mode {
        case .messageEffects:
            let messageEffects = context.engine.stickers.availableMessageEffects()
            actionsDisposable.add(combineLatest(queue: prepareQueue, messageEffects, search, searchCategories).startStrict(next: { messageEffects, search, searchCategories in
                updateState { current in
                    var current = current
                    current.messageEffects = messageEffects?.messageEffects ?? []
                    current.searchCategories = searchCategories
                    var sections: [State.Section] = []
                    
                   
                    let emojiItems: [StickerPackItem] = current.messageEffects.filter({ value in
                        if value.effectAnimation != nil {
                            if let search = search.values {
                                let emoji = value.effectSticker._parse().customEmojiText ?? value.effectSticker._parse().stickerText ?? ""
                                return search.contains(emoji)
                            } else {
                                return true
                            }
                        }
                        return false
                    }).map {
                        .init(index: .init(index: 0, id: 0), file: $0.effectSticker._parse(), indexKeys: [])
                    }
                    
                    let stickerItems: [StickerPackItem] = current.messageEffects.filter({ value in
                        if value.effectAnimation == nil {
                            if let search = search.values {
                                let emoji = value.effectSticker._parse().customEmojiText ?? value.effectSticker._parse().stickerText ?? ""
                                return search.contains(emoji)
                            } else {
                                return true
                            }
                        }
                        return false
                    }).map {
                        .init(index: .init(index: 0, id: 0), file: $0.effectSticker._parse(), indexKeys: [])
                    }
                    
                    
                    
                    var stickerDict: [MediaId : StickerPackItem] = [:]
                    for item in stickerItems {
                        stickerDict[item.file.fileId] = item
                    }
                    
                    var emojiDict: [MediaId : StickerPackItem] = [:]
                    for item in emojiItems {
                        emojiDict[item.file.fileId] = item
                    }
                    
                    if !emojiItems.isEmpty {
                        sections.append(.init(info: .init(id: .init(namespace: 0, id: 0), flags: .init(), accessHash: 0, title: "", shortName: "", thumbnail: nil, thumbnailFileId: nil, immediateThumbnailData: nil, hash: 0, count: 0), items: emojiItems, dict: emojiDict, installed: true))
                    }
                    
                    
                    if !stickerItems.isEmpty {
                        sections.append(.init(info: .init(id: .init(namespace: 0, id: 1), flags: .init(), accessHash: 0, title: strings().emojiesMessageEffectsTitle, shortName: "", thumbnail: nil, thumbnailFileId: nil, immediateThumbnailData: nil, hash: 0, count: 0), items: stickerItems, dict: stickerDict, installed: true, isBig: true))
                    }
                    current.search = search.values
                    current.searchLoading = search.isLoading
                    current.sections = sections
                    
                    return current
                }
                if !search.isLoading {
                    DispatchQueue.main.async {
                        updateSearchCommand()
                    }
                }
            }))
        default:
            let orderedTags = self.orderedTags
            let signal = combineLatest(queue: prepareQueue, emojies, featured, peer, search, reactions, recentUsedEmoji(postbox: context.account.postbox), reactionSettings, iconStatusEmoji, groupEmojiPack, forumTopic, searchCategories, context.reactions.stateValue, onStage.get()) |> filter { $0.12 }
            actionsDisposable.add(signal.start(next: { view, featured, peer, search, reactions, recentEmoji, reactionSettings, iconStatusEmoji, groupEmojiPack, forumTopic, searchCategories, availableReactions, _ in
                
                            
                var featuredStatusEmoji: OrderedItemListView?
                var recentStatusEmoji: OrderedItemListView?
                var recentReactionsView: OrderedItemListView?
                var topReactionsView: OrderedItemListView?
                var featuredBackgroundIconEmoji: OrderedItemListView?
                var featuredChannelStatusEmoji: OrderedItemListView?
                var defaultTagReactions: OrderedItemListView?
                var uniqueStarGifts: OrderedItemListView?

                for orderedView in view.orderedItemListsViews {
                    if orderedView.collectionId == Namespaces.OrderedItemList.CloudFeaturedStatusEmoji {
                        featuredStatusEmoji = orderedView
                    } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudRecentStatusEmoji {
                        recentStatusEmoji = orderedView
                    } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudRecentReactions {
                        recentReactionsView = orderedView
                    } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudTopReactions {
                        topReactionsView = orderedView
                    } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudFeaturedBackgroundIconEmoji {
                        featuredBackgroundIconEmoji = orderedView
                    } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudFeaturedChannelStatusEmoji {
                        featuredChannelStatusEmoji = orderedView
                    } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudDefaultTagReactions {
                        defaultTagReactions = orderedView
                    } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudUniqueStarGifts {
                        uniqueStarGifts = orderedView
                    }
                }
                var recentStatusItems:[RecentMediaItem] = []
                var featuredStatusItems:[RecentMediaItem] = []
                var recentReactionsItems:[RecentReactionItem] = []
                var topReactionsItems:[RecentReactionItem] = []
                var featuredBackgroundIconEmojiItems: [RecentMediaItem] = []
                var featuredChannelStatusEmojiItems : [RecentMediaItem] = []
                var defaultTagReactionsItems: [RecentReactionItem] = []
                var uniqueStarGiftsItems: [RecentStarGiftItem] = []
                if let recentStatusEmoji = recentStatusEmoji {
                    for item in recentStatusEmoji.items {
                        guard let item = item.contents.get(RecentMediaItem.self) else {
                            continue
                        }
                        recentStatusItems.append(item)
                    }
                }
                if let featuredStatusEmoji = featuredStatusEmoji {
                    for item in featuredStatusEmoji.items {
                        guard let item = item.contents.get(RecentMediaItem.self) else {
                            continue
                        }
                        featuredStatusItems.append(item)
                    }
                }
                if let featuredBackgroundIconEmoji = featuredBackgroundIconEmoji {
                    for item in featuredBackgroundIconEmoji.items {
                        guard let item = item.contents.get(RecentMediaItem.self) else {
                            continue
                        }
                        featuredBackgroundIconEmojiItems.append(item)
                    }
                }
                if let featuredChannelStatusEmoji = featuredChannelStatusEmoji {
                    for item in featuredChannelStatusEmoji.items {
                        guard let item = item.contents.get(RecentMediaItem.self) else {
                            continue
                        }
                        featuredChannelStatusEmojiItems.append(item)
                    }
                }
                
                
                if let recentReactionsView = recentReactionsView {
                    for item in recentReactionsView.items {
                        guard let item = item.contents.get(RecentReactionItem.self) else {
                            continue
                        }
                        recentReactionsItems.append(item)
                    }
                }
                if let topReactionsView = topReactionsView {
                    for item in topReactionsView.items {
                        guard let item = item.contents.get(RecentReactionItem.self) else {
                            continue
                        }
                        topReactionsItems.append(item)
                    }
                }
                if let defaultTagReactions = defaultTagReactions {
                    for item in defaultTagReactions.items {
                        guard let item = item.contents.get(RecentReactionItem.self) else {
                            continue
                        }
                        defaultTagReactionsItems.append(item)
                    }
                }
                if let uniqueStarGifts = uniqueStarGifts {
                    for item in uniqueStarGifts.items {
                        guard let item = item.contents.get(RecentStarGiftItem.self) else {
                            continue
                        }
                        uniqueStarGiftsItems.append(item)
                    }
                }
                
                updateState { current in
                    var current = current
                    var sections: [State.Section] = []
                    var itemsDict: [MediaId: StickerPackItem] = [:]
                    
                    if let groupEmojiPack = groupEmojiPack {
                        var files: [StickerPackItem] = []
                        var dict: [MediaId: StickerPackItem] = [:]
                        for item in groupEmojiPack.1 {
                            var updated = item
                            let file = item.file._parse()
                            var attrs = file.attributes
                            loop: for (i, attr) in attrs.enumerated() {
                                switch attr {
                                case let .CustomEmoji(_, isSingleColor, alt, packReference):
                                    attrs[i] = .CustomEmoji(isPremium: false, isSingleColor: isSingleColor, alt: alt, packReference: packReference)
                                    break loop;
                                default:
                                    break
                                }
                            }
                            updated = StickerPackItem(index: updated.index, file: file.withUpdatedAttributes(attrs), indexKeys: updated.indexKeys)
                            files.append(updated)
                            dict[item.file.fileId] = updated
                            itemsDict[item.file.fileId] = updated
                        }
                        sections.append(.init(info: groupEmojiPack.0, items: files, dict: dict, installed: true, groupEmojiPack: true))
                    }
                    for (_, info, _) in view.collectionInfos {
                        var files: [StickerPackItem] = []
                        var dict: [MediaId: StickerPackItem] = [:]
                        
                        if let info = info as? StickerPackCollectionInfo, !sections.contains(where: { $0.info.id == info.id }) {
                            let items = view.entries
                            for (i, entry) in items.enumerated() {
                                if entry.index.collectionId == info.id {
                                    if let item = view.entries[i].item as? StickerPackItem {
                                        var pass: Bool = true
                                        if case .backgroundIcon = mode {
                                            pass = item.file.isCustomTemplateEmoji
                                        }
                                        if pass {
                                            files.append(item)
                                            dict[item.file.fileId] = item
                                            itemsDict[item.file.fileId] = item
                                        }
                                    }
                                }
                            }
                            if !files.isEmpty {
                                sections.append(.init(info: info, items: files, dict: dict, installed: true))
                            }
                        }
                    }
                   
                   
                    for item in featured {
                        let contains = sections.contains(where: { $0.info.id == item.info.id })
                        if !contains {
                            let dict = item.topItems.toDictionary(with: {
                                $0.file.fileId
                            }).filter { _, value in
                                if mode == .backgroundIcon {
                                    return value.file.isCustomTemplateEmoji
                                } else {
                                    return true
                                }
                            }
                            let items = item.topItems.filter({ value in
                                if mode == .backgroundIcon {
                                    return value.file.isCustomTemplateEmoji
                                } else {
                                    return true
                                }
                            })
                            if !items.isEmpty {
                                sections.append(.init(info: item.info._parse(), items: items, dict: dict, installed: false))
                            }
                        }
                    }
                    
                    if let peer = peer {
                        current.peer = .init(peer)
                    }
                    current.featuredStatusItems = featuredStatusItems
                    current.recentStatusItems = recentStatusItems
                    current.forumTopicItems = forumTopic
                    current.sections = sections
                    current.itemsDict = itemsDict
                    current.search = search.values
                    current.searchLoading = search.isLoading
                    current.searchContext = search.context
                    current.searchFiles = search.files
                    current.searchSections = panelEmojiMatchingPacks(search.packs, installedIds: Set(view.collectionInfos.map { $0.0 })).map { pack in
                        return .init(info: pack.info, items: pack.items, dict: pack.items.toDictionary(with: { $0.file.fileId }), installed: pack.installed)
                    }
                    current.reactions = reactions
                    current.recent = recentEmoji
                    current.uniqueStarGiftsItems = uniqueStarGiftsItems
                    current.topReactionsItems = orderedTags ?? (mode == .defaultTags ? defaultTagReactionsItems : topReactionsItems)
                    current.recentReactionsItems = orderedTags ?? (mode == .defaultTags ? defaultTagReactionsItems : recentReactionsItems)
                    current.featuredBackgroundIconEmojiItems = featuredBackgroundIconEmojiItems
                    current.featuredChannelStatusEmojiItems = featuredChannelStatusEmojiItems
                    current.reactionSettings = reactionSettings
                    current.iconStatusEmoji = iconStatusEmoji
                    current.searchCategories = searchCategories
                    current.availableReactions = availableReactions
                    return current
                }
                if !search.isLoading {
                    DispatchQueue.main.async {
                        updateSearchCommand()
                    }
                }
            }))
            

        }
        
        

            
         self.onDeinit = {
             actionsDisposable.dispose()
             _ = previousSections.swap([])
             _ = previousPacks.swap([])
         }
        
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.scrollOnAppear?()
        onStage.set(true)
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onStage.set(false)
    }
    
    public func update(with interactions:EntertainmentInteractions?, chatInteraction: any ChatInteractionProtocol) {
        self.interactions = interactions
        self.chatInteraction = chatInteraction
        let context = chatInteraction.interactionContext
        
        if mode == .emoji || mode == .stories {
            if let peer = chatInteraction.peer, peer.isSupergroup {
                let emojiPack = getCachedDataView(peerId: peer.id, postbox: context.account.postbox) |> map { $0 as? CachedChannelData } |> map { $0?.emojiPack }
                groupEmojiPack = emojiPack |> mapToSignal { info in
                    if let info = info {
                        return context.engine.stickers.loadedStickerPack(reference: .id(id: info.id.id, accessHash: info.accessHash), forceActualized: false)
                        |> map { result in
                            switch result {
                            case let .result(info, items, _):
                                return (info._parse(), items)
                            default:
                                return nil
                            }
                        }
                        |> take(1)
                    } else {
                        return .single(nil)
                    }
                    
                }
            } else {
                groupEmojiPack = .single(nil)
            }
        } else {
            groupEmojiPack = .single(nil)
        }
    }
    
    public func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        return nil
    }
    public func isSelectable(row: Int, item: TableRowItem) -> Bool {
        return true
    }
    
    public func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool {
        return !(item is GeneralRowItem)
    }
    
    public func selectionDidChange(row:Int, item:TableRowItem, byClick:Bool, isNew:Bool) {
        
        if byClick {
            let segment = genericView.findSegmentAndScroll(selected: item, animated: true)
            
            updateState? { current in
                var current = current
                current.emojiState.selected = segment
                return current
            }
        }
    }
    
    public func setExternalForumTitle(_ title: String, iconColor: Int32 = 0, selectedItem: EmojiesSectionRowItem.SelectedItem? = nil) {
        updateState? { current in
            var current = current
            current.externalTopic = .init(title: title, iconColor: iconColor)
            if let selectedItem = selectedItem {
                current.selectedItems = [selectedItem]
            } else {
                current.selectedItems = []
            }
            return current
        }
    }
    public func setSelectedItem(_ selectedItem: EmojiesSectionRowItem.SelectedItem? = nil) {
        updateState? { current in
            var current = current
            if let selectedItem = selectedItem {
                current.selectedItems = [selectedItem]
            } else {
                current.selectedItems = []
            }
            return current
        }
    }
    public func setSelectedItems(_ selectedItems: [EmojiesSectionRowItem.SelectedItem]) {
        updateState? { current in
            var current = current
            current.selectedItems = selectedItems
            return current
        }
    }
    
    public override func scrollup(force: Bool = false) {
        
        self.updateState? { current in
            var current = current
            if current.selectedEmojiCategory != nil {
                current.selectedEmojiCategory = nil
            }
            return current
        }
        self.makeSearchCommand?(.close)

        genericView.tableView.scroll(to: .up(true))
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        var cancelled: Bool = false
        self.updateState? { current in
            var current = current
            if current.selectedEmojiCategory != nil {
                cancelled = true
                current.selectedEmojiCategory = nil
            }
            return current
        }
        if searchState.state == .Focus {
            cancelled = true
        }
        if cancelled {
            self.updateSearchState(.init(state: .None, request: nil))
            return .invoked
        } else {
            return super.escapeKeyAction()
        }
    }
    
    public override var supportSwipes: Bool {
        if let categories = genericView.categories, categories._mouseInside() || genericView.searchContainer._mouseInside() {
            return false
        }
        return !genericView.packsView._mouseInside()
    }
}

public extension MessageReaction.Reaction {
    var emojiString: String {
        switch self {
        case let .builtin(value):
            return value
        default:
            return ""
        }
    }
}
