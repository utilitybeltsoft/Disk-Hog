import Foundation

nonisolated enum SelectionListFilter: Hashable, Sendable {
    case all
    case kind(String)

    var title: String {
        switch self {
        case .all:
            "All"
        case .kind(let kindName):
            kindName
        }
    }
}
