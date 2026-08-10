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
    typealias SourceLoader = @Sendable () async -> [ScanSource]

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
    private let sourceLoader: SourceLoader
    private var refreshGeneration: Int = 0
    private var refreshTask: Task<Void, Never>?

    nonisolated static func defaultSourceLoader() async -> [ScanSource] {
        await Task.detached(priority: .utility) {
            ScanSourceProvider.mountedVolumes()
        }.value
    }

    convenience init() {
        let defaults: UserDefaults = .standard
        self.init(
            sources: [],
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
            ),
            sourceLoader: Self.defaultSourceLoader
        )
        refresh()
    }

    init(sources: [ScanSource]) {
        self.sources = sources
        self.filter = SourceVolumeFilter()
        self.selectedSourceID = nil
        self.sourceLoader = Self.defaultSourceLoader
    }

    init(
        sources: [ScanSource],
        filter: SourceVolumeFilter,
        sourceLoader: @escaping SourceLoader = SourceWindowViewModel.defaultSourceLoader
    ) {
        self.sources = sources
        self.filter = filter
        selectedSourceID = nil
        self.sourceLoader = sourceLoader
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

    @discardableResult
    func refresh() -> Task<Void, Never> {
        refreshGeneration += 1
        let generation: Int = refreshGeneration
        let sourceLoader: SourceLoader = sourceLoader
        let task: Task<Void, Never> = Task { [weak self] in
            let loadedSources: [ScanSource] = await sourceLoader()
            guard !Task.isCancelled else {
                return
            }
            self?.installLoadedSources(loadedSources, generation: generation)
        }
        refreshTask?.cancel()
        refreshTask = task
        return task
    }

    private func installLoadedSources(_ loadedSources: [ScanSource], generation: Int) {
        guard generation == refreshGeneration else {
            return
        }
        sources = loadedSources
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
        let canScanSelectedVolume: Bool = selectedSource?.canScan == true
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
