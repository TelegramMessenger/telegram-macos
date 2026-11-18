import Foundation

public enum SettingsSearchableItemId: Hashable {
    case profile(Int32)
    case proxy(Int32)
    case savedMessages(Int32)
    case calls(Int32)
    case stickers(Int32)
    case notifications(Int32)
    case privacy(Int32)
    case data(Int32)
    case appearance(Int32)
    case language(Int32)
    case watch(Int32)
    case passport(Int32)
    case wallet(Int32)
    case support(Int32)
    case faq(Int32)
    case general(Int32)
    case settings(Int32)
    
    private var namespace: Int32 {
        switch self {
        case .profile:
            return 1
        case .proxy:
            return 2
        case .savedMessages:
            return 3
        case .calls:
            return 4
        case .stickers:
            return 5
        case .notifications:
            return 6
        case .privacy:
            return 7
        case .data:
            return 8
        case .appearance:
            return 9
        case .language:
            return 10
        case .watch:
            return 11
        case .passport:
            return 12
        case .wallet:
            return 13
        case .support:
            return 14
        case .faq:
            return 15
        case .general:
            return 16
        case .settings:
            return 17
        }
    }
    
    private var id: Int32 {
        switch self {
        case let .profile(id),
             let .proxy(id),
             let .savedMessages(id),
             let .calls(id),
             let .stickers(id),
             let .notifications(id),
             let .privacy(id),
             let .data(id),
             let .appearance(id),
             let .language(id),
             let .watch(id),
             let .passport(id),
             let .wallet(id),
             let .support(id),
             let .faq(id),
             let .general(id),
             let .settings(id):
            return id
        }
    }
    
    public var index: Int64 {
        return (Int64(self.namespace) << 32) | Int64(self.id)
    }
    
    public init?(index: Int64) {
        let namespace = Int32((index >> 32) & 0x7fffffff)
        let id = Int32(bitPattern: UInt32(index & 0xffffffff))
        switch namespace {
        case 1:
            self = .profile(id)
        case 2:
            self = .proxy(id)
        case 3:
            self = .savedMessages(id)
        case 4:
            self = .calls(id)
        case 5:
            self = .stickers(id)
        case 6:
            self = .notifications(id)
        case 7:
            self = .privacy(id)
        case 8:
            self = .data(id)
        case 9:
            self = .appearance(id)
        case 10:
            self = .language(id)
        case 11:
            self = .watch(id)
        case 12:
            self = .passport(id)
        case 13:
            self = .wallet(id)
        case 14:
            self = .support(id)
        case 15:
            self = .faq(id)
        case 16:
            self = .general(id)
        case 17:
            self = .settings(id)
        default:
            return nil
        }
    }
}
