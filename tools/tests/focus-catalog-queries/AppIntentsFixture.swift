import Foundation

#if os(Linux)
public typealias LocalizedStringResource = String

public extension String {
    init(localized resource: LocalizedStringResource) {
        self = resource
    }
}
#endif

public struct TypeDisplayRepresentation {
    public let name: String

    public init(name: LocalizedStringResource) {
        self.name = String(localized: name)
    }
}

public struct DisplayRepresentation {
    public let title: String
    public let subtitle: String?

    public init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) {
        self.title = String(localized: title)
        self.subtitle = subtitle.map { String(localized: $0) }
    }
}

public protocol AppEntity: Identifiable {
    var displayRepresentation: DisplayRepresentation { get }
}

public protocol EntityStringQuery {
    associatedtype Entity: AppEntity

    func entities(for identifiers: [Entity.ID]) async throws -> [Entity]
    func entities(matching string: String) async throws -> [Entity]
    func suggestedEntities() async throws -> [Entity]
}
