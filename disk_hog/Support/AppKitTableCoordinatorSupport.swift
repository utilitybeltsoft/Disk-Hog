import AppKit

@MainActor
final class AppKitSelectionMutationGate {
    private(set) var isApplyingSelection: Bool = false

    func perform(_ mutation: () -> Void) {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        mutation()
    }
}

extension NSTableView {
    @MainActor
    func reusableView<View: NSView>(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        owner: Any?,
        make: () -> View
    ) -> View {
        let view: View = makeView(withIdentifier: identifier, owner: owner) as? View ?? make()
        view.identifier = identifier
        return view
    }
}

struct AppKitSortDescriptorBridge<Field: Equatable> {
    let keyForField: (Field) -> String
    let fieldForKey: (String) -> Field?

    func field(for descriptor: NSSortDescriptor) -> Field? {
        descriptor.key.flatMap(fieldForKey)
    }

    func descriptor(for field: Field, ascending: Bool) -> NSSortDescriptor {
        NSSortDescriptor(key: keyForField(field), ascending: ascending)
    }

    func descriptor(
        _ descriptor: NSSortDescriptor?,
        matches field: Field,
        ascending: Bool
    ) -> Bool {
        guard let descriptor else {
            return false
        }
        return self.field(for: descriptor) == field && descriptor.ascending == ascending
    }
}
