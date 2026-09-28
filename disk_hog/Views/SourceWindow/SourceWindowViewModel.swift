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
    /// True once a refresh has been running longer than `loadingIndicatorDelay` - not
    /// simply "a refresh is in flight" - so a fast (typically local-only) load never
    /// flashes a placeholder that would just flicker by and vanish. Only meaningful
    /// alongside an empty `sources`; a refresh of an already-populated list keeps
    /// showing the previous results and never sets this.
    @Published private(set) var isLoading: Bool = false
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
    private let canRefresh: () -> Bool
    private var refreshGeneration: Int = 0
    private var refreshTask: Task<Void, Never>?

    /// How long a refresh must run before `isLoading` shows a placeholder - long enough
    /// that an ordinary local-only load never shows it at all.
    private static let loadingIndicatorDelay: Duration = .milliseconds(350)

    nonisolated static func defaultSourceLoader() async -> [ScanSource] {
        await Task.detached(priority: .utility) {
            ScanSourceProvider.mountedVolumes()
        }.value
    }

    convenience init(canRefresh: @escaping () -> Bool = { true }) {
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
            sourceLoader: Self.defaultSourceLoader,
            canRefresh: canRefresh
        )
    }

    init(sources: [ScanSource]) {
        self.sources = sources
        self.filter = SourceVolumeFilter()
        self.selectedSourceID = nil
        self.sourceLoader = Self.defaultSourceLoader
        self.canRefresh = { true }
    }

    init(
        sources: [ScanSource],
        filter: SourceVolumeFilter,
        sourceLoader: @escaping SourceLoader = SourceWindowViewModel.defaultSourceLoader,
        canRefresh: @escaping () -> Bool = { true }
    ) {
        self.sources = sources
        self.filter = filter
        selectedSourceID = nil
        self.sourceLoader = sourceLoader
        self.canRefresh = canRefresh
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
        guard canRefresh() else { return Task {} }
        refreshGeneration += 1
        let generation: Int = refreshGeneration
        isLoading = false
        let sourceLoader: SourceLoader = sourceLoader
        let canRefresh = canRefresh
        let task: Task<Void, Never> = Task { [weak self] in
            guard !Task.isCancelled, canRefresh() else { return }
            let loadedSources: [ScanSource] = await sourceLoader()
            guard !Task.isCancelled, canRefresh() else {
                return
            }
            self?.installLoadedSources(loadedSources, generation: generation)
        }
        refreshTask?.cancel()
        refreshTask = task

        Task { [weak self] in
            try? await Task.sleep(for: Self.loadingIndicatorDelay)
            guard !Task.isCancelled, let self, self.refreshGeneration == generation, self.canRefresh() else {
                return
            }
            self.isLoading = true
        }
        return task
    }

    private func installLoadedSources(_ loadedSources: [ScanSource], generation: Int) {
        guard generation == refreshGeneration else {
            return
        }
        sources = loadedSources
        isLoading = false
        reconcileSelection()
        // Warm the icon cache off the main thread so selecting a volume - which fetches its icon
        // synchronously, matching this app's convention elsewhere - doesn't stall on a slow lookup
        // (a spun-down external drive, a network share) right as the user clicks it.
        DiskItemIconCache.shared.prefetch(paths: loadedSources.map(\.url.path))
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
        guard AppCommandRouter.shared.canScanSelectedVolume != canScanSelectedVolume else {
            return
        }
        AppCommandRouter.shared.canScanSelectedVolume = canScanSelectedVolume
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
