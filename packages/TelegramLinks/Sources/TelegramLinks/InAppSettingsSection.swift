public enum InAppSettingsSection : Equatable {
    case themes
    case devices(DevicesSubSection?)
    case folders(FoldersSubSection?)
    case privacy(PrivacySubSection?)
    case phone_privacy
    case enable_log
    case password
    case send_gift(SendGiftSubSection?)
    case ask_question
    case faq
    case privacy_policy
    case search
    case business(BusinessSubSection?)
    case stars(StarsSubSection?)
    case premium
    case language
    case translation(TranslationSubSection?)
    case ton
    case appearance(AppearanceSubSection?)
    case data(DataSubSection?)
    case notifications(NotificationsSubSection?)
    case calls(CallsSubSection?)
    case edit_profile(EditProfileSubSection?)
    case change_number
    case my_stories
    case general
    case chat

    public enum CallsSubSection : String {
        case start_call = "start-call"
    }

    public enum EditProfileSubSection : String {
        case username = "username"
    }

    public enum PrivacySubSection : Equatable {
        case phone
        case calls
        case p2p
        case forwards
        case profile_photos
        case bio
        case birthday
        case gifts
        case blocked
        case passcode
        case two_step
        case email
        case auto_delete(AutoDeleteSubSection?)
        case data_settings
        case saved_music

        public enum AutoDeleteSubSection : String {
            case delete_all = "delete-all"
        }

        public init?(rawValue: String, components: [String]) {
            switch rawValue {
            case "phone":
                self = .phone
            case "calls":
                self = .calls
            case "p2p":
                self = .p2p
            case "forwards":
                self = .forwards
            case "profile-photos":
                self = .profile_photos
            case "bio":
                self = .bio
            case "birthday":
                self = .birthday
            case "gifts":
                self = .gifts
            case "blocked":
                self = .blocked
            case "passcode":
                self = .passcode
            case "two-step":
                self = .two_step
            case "email":
                self = .email
            case "auto-delete":
                if components.count > 2 {
                    self = .auto_delete(AutoDeleteSubSection(rawValue: components[2]))
                } else {
                    self = .auto_delete(nil)
                }
            case "data-settings":
                self = .data_settings
            case "saved-music":
                self = .saved_music
            default:
                return nil
            }
        }
    }

    public enum DevicesSubSection : String {
        case terminate_sessions = "terminate-sessions"
        case auto_terminate = "auto-terminate"
    }

    public enum FoldersSubSection : String {
        case new = "new"
        case edit = "edit"
    }

    public enum SendGiftSubSection : String {
        case self_ = "self"
    }

    public enum BusinessSubSection : String {
        case do_not_hide_ads = "do-not-hide-ads"
    }

    public enum StarsSubSection : String {
        case top_up = "top-up"
        case stats = "stats"
        case gift = "gift"
        case earn = "earn"
    }

    public enum TranslationSubSection : String {
        case do_not_translate = "do-not-translate"
    }

    public enum AppearanceSubSection : Equatable {
        case text_size
        case wallpapers
        case themes
        case color_theme
        case stickers_and_emoji(StickersSubSection?)

        public enum StickersSubSection : String {
            case emoji = "emoji"
        }

        public init?(rawValue: String, components: [String]) {
            switch rawValue {
            case "text-size":
                self = .text_size
            case "wallpapers":
                self = .wallpapers
            case "themes":
                self = .themes
            case "color-theme":
                self = .color_theme
            case "stickers-and-emoji":
                if components.count > 2 {
                    self = .stickers_and_emoji(StickersSubSection(rawValue: components[2]))
                } else {
                    self = .stickers_and_emoji(nil)
                }
            default:
                return nil
            }
        }
    }

    public enum DataSubSection : Equatable {
        case storage
        case network
        case auto_download
        case proxy(ProxySubSection?)

        public enum ProxySubSection : String {
            case add = "add"
        }

        public init?(rawValue: String, components: [String]) {
            switch rawValue {
            case "storage":
                self = .storage
            case "network":
                self = .network
            case "auto-download":
                self = .auto_download
            case "proxy":
                if components.count > 2 {
                    self = .proxy(ProxySubSection(rawValue: components[2]))
                } else {
                    self = .proxy(nil)
                }
            default:
                return nil
            }
        }
    }

    public enum NotificationsSubSection : Equatable {
        case include_channels
        case include_muted_chats
        case count_unread_messages
        case sound
        case message_effect
        case badge
        case show
        case accounts
        case new_contacts
        case reset
        case private_chats(ChatNotificationSubSection?)
        case groups(ChatNotificationSubSection?)
        case channels(ChatNotificationSubSection?)
        case stories(StoriesNotificationSubSection?)
        case reactions(ReactionsNotificationSubSection?)

        public enum ChatNotificationSubSection : String {
            case edit = "edit"
            case show = "show"
            case preview = "preview"
            case sound = "sound"
            case add_exception = "add-exception"
            case delete_exceptions = "delete-exceptions"
        }

        public enum StoriesNotificationSubSection : String {
            case new = "new"
            case important = "important"
            case show_sender = "show-sender"
            case sound = "sound"
            case add_exception = "add-exception"
            case delete_exceptions = "delete-exceptions"
        }

        public enum ReactionsNotificationSubSection : String {
            case messages = "messages"
            case stories = "stories"
            case show_sender = "show-sender"
            case sound = "sound"
        }

        public init?(rawValue: String, components: [String]) {
            switch rawValue {
            case "include-channels":
                self = .include_channels
            case "include-muted-chats":
                self = .include_muted_chats
            case "count-unread-messages":
                self = .count_unread_messages
            case "sound":
                self = .sound
            case "message-effect":
                self = .message_effect
            case "badge":
                self = .badge
            case "show":
                self = .show
            case "accounts":
                self = .accounts
            case "new-contacts":
                self = .new_contacts
            case "reset":
                self = .reset
            case "stories":
                if components.count > 2 {
                    self = .stories(StoriesNotificationSubSection(rawValue: components[2]))
                } else {
                    self = .stories(nil)
                }
            case "reactions":
                if components.count > 2 {
                    self = .reactions(ReactionsNotificationSubSection(rawValue: components[2]))
                } else {
                    self = .reactions(nil)
                }
            case "private-chats":
                if components.count > 2 {
                    self = .private_chats(ChatNotificationSubSection(rawValue: components[2]))
                } else {
                    self = .private_chats(nil)
                }
            case "groups":
                if components.count > 2 {
                    self = .groups(ChatNotificationSubSection(rawValue: components[2]))
                } else {
                    self = .groups(nil)
                }
            case "channels":
                if components.count > 2 {
                    self = .channels(ChatNotificationSubSection(rawValue: components[2]))
                } else {
                    self = .channels(nil)
                }
            default:
                return nil
            }
        }
    }

    public init?(rawValue: String) {
        let components = rawValue.split(separator: "/").map(String.init)
        guard let first = components.first else { return nil }

        switch first {
        case "themes":
            self = .themes
        case "devices":
            if components.count > 1 {
                self = .devices(DevicesSubSection(rawValue: components[1]))
            } else {
                self = .devices(nil)
            }
        case "folders":
            if components.count > 1 {
                self = .folders(FoldersSubSection(rawValue: components[1]))
            } else {
                self = .folders(nil)
            }
        case "privacy":
            if components.count > 1 {
                self = .privacy(PrivacySubSection(rawValue: components[1], components: components))
            } else {
                self = .privacy(nil)
            }
        case "phone_privacy":
            self = .phone_privacy
        case "enable_log":
            self = .enable_log
        case "password":
            self = .password
        case "send-gift":
            if components.count > 1 {
                self = .send_gift(SendGiftSubSection(rawValue: components[1]))
            } else {
                self = .send_gift(nil)
            }
        case "ask-question":
            self = .ask_question
        case "faq":
            self = .faq
        case "privacy-policy":
            self = .privacy_policy
        case "search":
            self = .search
        case "business":
            if components.count > 1 {
                self = .business(BusinessSubSection(rawValue: components[1]))
            } else {
                self = .business(nil)
            }
        case "stars":
            if components.count > 1 {
                self = .stars(StarsSubSection(rawValue: components[1]))
            } else {
                self = .stars(nil)
            }
        case "premium":
            self = .premium
        case "language":
            self = .language
        case "translation":
            if components.count > 1 {
                self = .translation(TranslationSubSection(rawValue: components[1]))
            } else {
                self = .translation(nil)
            }
        case "ton":
            self = .ton
        case "appearance":
            if components.count > 1 {
                self = .appearance(AppearanceSubSection(rawValue: components[1], components: components))
            } else {
                self = .appearance(nil)
            }
        case "data":
            if components.count > 1 {
                self = .data(DataSubSection(rawValue: components[1], components: components))
            } else {
                self = .data(nil)
            }
        case "notifications":
            if components.count > 1 {
                self = .notifications(NotificationsSubSection(rawValue: components[1], components: components))
            } else {
                self = .notifications(nil)
            }
        case "calls":
            if components.count > 1 {
                self = .calls(CallsSubSection(rawValue: components[1]))
            } else {
                self = .calls(nil)
            }
        case "edit-profile", "edit":
            if components.count > 1 {
                self = .edit_profile(EditProfileSubSection(rawValue: components[1]))
            } else {
                self = .edit_profile(nil)
            }
        case "change-number":
            self = .change_number
        case "my-stories":
            self = .my_stories
        case "chat":
            self = .chat
        default:
            return nil
        }
    }
}

public enum ChatInitialActionBehavior : Equatable {
    case none
    case automatic
}
