import Combine
import Foundation

struct SourceVolumeFilter: Equatable {
    var includesExternalVolumes: Bool = false
    var includesNetworkVolumes: Bool = false
    var includesDiskImages: Bool = false

    func includes(_ source: ScanSource) -> Bool {
        switch source.volumeKind {
        case .internalVolume, .folder:
            return true
        case .externalVolume:
            return includesExternalVolumes
        case .networkVolume:
            return includesNetworkVolumes
        case .diskImage:
            return includesDiskImages
        }
    }
}

@MainActor
final class SourceWindowViewModel: ObservableObject {
    @Published private(set) var sources: [ScanSource]
    @Published var selectedSourceID: ScanSource.ID? {
        didSet {
            updateCommandState()
        }
    }
    var filter: SourceVolumeFilter = SourceVolumeFilter() {
        didSet {
            guard filter != oldValue else {
                return
            }

            reconcileSelection()
            updateCommandState()
        }
    }

    convenience init() {
        self.init(sources: ScanSourceProvider.mountedVolumes())
    }

    init(sources: [ScanSource]) {
        self.sources = sources
        selectedSourceID = nil
        updateCommandState()
    }

    var filteredSources: [ScanSource] {
        sources
            .filter(filter.includes)
            .sorted { first, second in
                if first.volumeKind.sortRank != second.volumeKind.sortRank {
                    return first.volumeKind.sortRank < second.volumeKind.sortRank
                }

                return first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
            }
    }

    var selectedSource: ScanSource? {
        guard let selectedSourceID else {
            return nil
        }

        return filteredSources.first { source in
            source.id == selectedSourceID
        }
    }

    func select(_ sourceID: ScanSource.ID?) {
        selectedSourceID = sourceID
    }

    func refresh() {
        sources = ScanSourceProvider.mountedVolumes()
        reconcileSelection()
        updateCommandState()
    }

    private func reconcileSelection() {
        guard let selectedSourceID,
              filteredSources.contains(where: { $0.id == selectedSourceID }) else {
            self.selectedSourceID = nil
            return
        }
    }

    private func updateCommandState() {
        SourceWindowCommandState.shared.canScanSelectedVolume = selectedSource != nil
    }
}

extension ScanSourceVolumeKind {
    fileprivate var sortRank: Int {
        switch self {
        case .internalVolume:
            return 0
        case .externalVolume:
            return 1
        case .diskImage:
            return 2
        case .networkVolume:
            return 3
        case .folder:
            return 4
        }
    }
}
