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
            guard selectedSourceID != oldValue else {
                return
            }
            updateCommandState()
        }
    }
    @Published private(set) var filter: SourceVolumeFilter

    convenience init() {
        let defaults: UserDefaults = .standard
        self.init(
            sources: ScanSourceProvider.mountedVolumes(),
            filter: SourceVolumeFilter(
                includesExternalVolumes: defaults.bool(
                    forKey: SourceWindowPreferences.showExternalVolumesKey
                ),
                includesNetworkVolumes: defaults.bool(
                    forKey: SourceWindowPreferences.showNetworkVolumesKey
                ),
                includesDiskImages: defaults.bool(
                    forKey: SourceWindowPreferences.showDiskImagesKey
                )
            )
        )
    }

    init(sources: [ScanSource]) {
        self.sources = sources
        filter = SourceVolumeFilter()
        selectedSourceID = nil
    }

    init(sources: [ScanSource], filter: SourceVolumeFilter) {
        self.sources = sources
        self.filter = filter
        selectedSourceID = nil
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
        guard selectedSourceID != sourceID else {
            return
        }
        selectedSourceID = sourceID
    }

    func setFilter(_ filter: SourceVolumeFilter) {
        guard self.filter != filter else {
            return
        }

        self.filter = filter
        reconcileSelection()
    }

    func refresh() {
        sources = ScanSourceProvider.mountedVolumes()
        reconcileSelection()
    }

    private func reconcileSelection() {
        guard let selectedSourceID else {
            return
        }

        if filteredSources.contains(where: { $0.id == selectedSourceID }) == false {
            self.selectedSourceID = nil
        }
    }

    private func updateCommandState() {
        let canScanSelectedVolume: Bool = selectedSource != nil
        guard SourceWindowCommandState.shared.canScanSelectedVolume != canScanSelectedVolume else {
            return
        }
        SourceWindowCommandState.shared.canScanSelectedVolume = canScanSelectedVolume
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
