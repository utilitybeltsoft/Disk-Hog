import Foundation

@MainActor
final class ScanSessionTaskCoordinator {
    enum Kind: Hashable {
        case scan
        case treeUpdate
        case presentationUpdate
        case sizeModeUpdate
    }

    private var tasks: [Kind: Task<Void, Never>] = [:]
    private var operationIDs: [Kind: UUID] = [:]

    func start(_ kind: Kind, makeTask: (UUID) -> Task<Void, Never>) -> UUID {
        tasks[kind]?.cancel()
        let operationID: UUID = UUID()
        operationIDs[kind] = operationID
        tasks[kind] = makeTask(operationID)
        return operationID
    }

    func isCurrent(_ kind: Kind, operationID: UUID) -> Bool {
        operationIDs[kind] == operationID
    }

    func finish(_ kind: Kind, operationID: UUID) -> Bool {
        guard isCurrent(kind, operationID: operationID) else {
            return false
        }
        tasks[kind] = nil
        operationIDs[kind] = nil
        return true
    }

    func cancel(_ kind: Kind) {
        tasks[kind]?.cancel()
    }

    func cancelAll() {
        for task: Task<Void, Never> in tasks.values {
            task.cancel()
        }
    }
}
