//
//  disk_hogTests.swift
//  disk_hogTests
//
//

import AppKit
import Combine
import Foundation
import Testing
@testable import disk_hog

@MainActor
struct ApplicationStateRestorationTests {
    @Test func applicationDoesNotSaveOrRestoreWindowState() {
        let delegate: DiskHogApplicationDelegate = DiskHogApplicationDelegate()

        #expect(delegate.applicationShouldSaveApplicationState(NSApp) == false)
        #expect(delegate.applicationShouldRestoreApplicationState(NSApp) == false)
    }

    @Test func scanWindowIsMarkedNonRestorableWhenRegistered() {
        let source: ScanSource = ScanSource(path: "/scan", displayName: "scan")
        let session: ScanSession = ScanSession(source: source)
        let registrationView: ScanWindowRegistrationNSView = ScanWindowRegistrationNSView(
            session: session,
            source: source
        )
        let window: NSWindow = NSWindow()
        window.isRestorable = true

        window.contentView?.addSubview(registrationView)

        #expect(window.isRestorable == false)
        registrationView.removeFromSuperview()
    }
}

@MainActor
struct WindowCloseDelegateProxyTests {
    @Test func retainsDisplacedDelegateUntilRestored() {
        let window: NSWindow = NSWindow()
        var delegate: WindowDelegateTestDouble? = WindowDelegateTestDouble()
        weak let weakDelegate: WindowDelegateTestDouble? = delegate
        window.delegate = delegate

        let proxy: WindowCloseDelegateProxy = WindowCloseDelegateProxy { _ in true }
        proxy.install(on: window)
        delegate = nil

        #expect(weakDelegate != nil)
        #expect(window.delegate === proxy)
        var forwardingTarget: AnyObject? = proxy.forwardingTarget(
            for: #selector(WindowDelegateTestDouble.sentinel)
        ) as AnyObject?
        #expect(
            forwardingTarget === weakDelegate
        )

        forwardingTarget = nil
        proxy.restore()
        #expect(
            proxy.forwardingTarget(
                for: #selector(WindowDelegateTestDouble.sentinel)
            ) == nil
        )
    }
}

@MainActor
struct ScanSessionPackageContentsSynchronizationTests {
    @Test func reportsWhetherExistingResultsMatchCurrentPreference() {
        let source: ScanSource = ScanSource(
            path: "/scan",
            displayName: "scan",
            scanSettings: DiskScanSettings(
                usePhysicalSize: true,
                lookInsidePackages: false,
                ignoreCreatorCode: false
            )
        )
        let session: ScanSession = ScanSession(source: source)

        session.updatePackageContentsSynchronization(with: true)
        #expect(session.isPackageContentsSettingOutOfSync)

        session.updatePackageContentsSynchronization(with: false)
        #expect(session.isPackageContentsSettingOutOfSync == false)
    }
}

@MainActor
struct SourceWindowViewModelTests {
    @Test func permissionDeniedVolumeCannotBeScanned() {
        let source: ScanSource = ScanSource(
            path: "/Volumes/Backup",
            displayName: "Backup",
            scanDisabledReason: "Full Disk Access required"
        )
        let viewModel: SourceWindowViewModel = SourceWindowViewModel(
            sources: [source],
            filter: SourceVolumeFilter(
                includesExternalVolumes: true,
                includesNetworkVolumes: true,
                includesDiskImages: true
            )
        )
        SourceWindowCommandState.shared.canScanSelectedVolume = true

        viewModel.select(source.id)

        #expect(viewModel.selectedSource == source)
        #expect(source.canScan == false)
        #expect(SourceWindowCommandState.shared.canScanSelectedVolume == false)
    }

    @Test func deactivatingUnchangedCommandStateDoesNotPublish() {
        let commandState: ScanWindowCommandState = ScanWindowCommandState()
        var changeCount: Int = 0
        let cancellable: AnyCancellable = commandState.objectWillChange.sink {
            changeCount += 1
        }

        commandState.deactivate()

        #expect(changeCount == 0)
        _ = cancellable
    }

    @Test func changingFilterPublishesOnceWithoutChangingSelectionOrCommandState() {
        let internalSource: ScanSource = ScanSource(
            path: "/",
            displayName: "Internal",
            isLocalVolume: true,
            isInternalVolume: true
        )
        let externalSource: ScanSource = ScanSource(
            path: "/Volumes/External",
            displayName: "External",
            isLocalVolume: true,
            isRemovableVolume: true,
            isInternalVolume: false
        )
        let viewModel: SourceWindowViewModel = SourceWindowViewModel(
            sources: [internalSource, externalSource]
        )
        SourceWindowCommandState.shared.canScanSelectedVolume = false
        var viewModelChangeCount: Int = 0
        var commandStateChangeCount: Int = 0
        let viewModelCancellable: AnyCancellable = viewModel.objectWillChange.sink {
            viewModelChangeCount += 1
        }
        let commandStateCancellable: AnyCancellable = SourceWindowCommandState.shared.objectWillChange.sink {
            commandStateChangeCount += 1
        }

        viewModel.setFilter(SourceVolumeFilter(
            includesExternalVolumes: true,
            includesNetworkVolumes: true,
            includesDiskImages: true
        ))
        viewModel.select(nil)

        #expect(viewModel.filteredSources.count == 2)
        #expect(viewModelChangeCount == 1)
        #expect(commandStateChangeCount == 0)
        _ = (viewModelCancellable, commandStateCancellable)
    }

    @Test func settingAnUnchangedFilterDoesNotPublish() {
        let filter: SourceVolumeFilter = SourceVolumeFilter(
            includesExternalVolumes: true,
            includesNetworkVolumes: true,
            includesDiskImages: true
        )
        let viewModel: SourceWindowViewModel = SourceWindowViewModel(
            sources: [],
            filter: filter
        )
        var changeCount: Int = 0
        let cancellable: AnyCancellable = viewModel.objectWillChange.sink {
            changeCount += 1
        }

        viewModel.setFilter(filter)

        #expect(changeCount == 0)
        _ = cancellable
    }
}

@MainActor
struct InspectorWindowLayoutTests {
    @Test func informationTabUsesPreferredSize() {
        #expect(InspectorWindowTab.information.layout.preferredContentSize.width == 720)
        #expect(InspectorWindowTab.information.layout.preferredContentSize.height == 720)
    }

    @Test func diskUsageTabUsesPreferredHeight() {
        #expect(InspectorWindowTab.diskUsage.layout.preferredContentSize.height == 420)
        #expect(InspectorWindowTab.diskUsage.layout.minimumContentSize.height == 400)
        #expect(InspectorWindowLayout.compactDiskUsage.preferredContentSize.height == 350)
        #expect(DiskUsageLayoutMetrics.pieDiameter == 200)
        #expect(DiskUsageLayoutMetrics.bottomPadding == 20)
    }

    @Test func inactiveDiskUsagePaneRequestsVolumeSelection() {
        #expect(InspectorWindowTab.diskUsage.inactiveTitle == "No Volume Selected")
        #expect(InspectorWindowTab.diskUsage.inactiveDescription.contains("volume scan window"))
    }

    @Test func scanItemContextMenuIncludesInspectorCommand() {
        let item: DiskItem = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 8,
            logicalSizeValue: 8,
            kindName: "Plain Text"
        ).freeze()
        let actionTarget: DiskItemContextMenuActionTarget = DiskItemContextMenuActionTarget()
        let menu: NSMenu = DiskItemContextMenuBuilder.menu(
            for: item,
            actionTarget: actionTarget,
            treeActionsEnabled: true
        )

        let inspectorItem: NSMenuItem? = menu.item(withTitle: "Show Inspector")
        #expect(inspectorItem?.action == #selector(DiskItemContextMenuActionTarget.showInspectorMenuItem(_:)))
        #expect(inspectorItem?.target === actionTarget)
    }

    @Test func showingItemInformationSelectsInformationTab() {
        let controller: InspectorWindowController = .shared
        controller.selectedTab = .selectionList
        let item: DiskItem = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 8,
            logicalSizeValue: 8
        ).freeze()

        controller.showInformation(for: item, from: nil)

        #expect(controller.selectedTab == .information)
    }

    @Test func selectedSourceBecomesInspectorVolumeContext() {
        let source: ScanSource = ScanSource(
            path: "/Volumes/Test",
            displayName: "Test",
            totalCapacity: 1_000,
            availableCapacity: 250,
            isLocalVolume: true,
            isInternalVolume: false
        )
        let controller: InspectorWindowController = .shared
        controller.deactivate()
        var changeCount: Int = 0
        let cancellable: AnyCancellable = controller.objectWillChange.sink {
            changeCount += 1
        }

        controller.activate(source: nil)
        controller.activate(source: source)
        controller.activate(source: source)

        #expect(controller.activeContext == nil)
        #expect(controller.activeSource == source)
        #expect(changeCount == 1)
        controller.deactivate()
        _ = cancellable
    }

    @Test func sourceDiskUsageUsesVolumeCapacityWithoutScanResults() throws {
        let source: ScanSource = ScanSource(
            path: "/Volumes/Nonexistent-Disk-Hog-Test",
            displayName: "Test",
            totalCapacity: 1_000,
            availableCapacity: 250,
            isLocalVolume: true,
            isInternalVolume: false
        )

        let usage: DiskUsage = try #require(DiskUsage.make(for: source))

        #expect(usage.totalBytes == 1_000)
        #expect(usage.primaryUsedBytes == 750)
        #expect(usage.otherUsedBytes == 0)
        #expect(usage.freeBytes == 250)
    }

    @Test func informationContextMenuIncludesOnlyInformationCommands() {
        let coordinator: InformationContextMenuCoordinator = InformationContextMenuCoordinator()
        let menu: NSMenu = coordinator.makeContextMenu()

        #expect(menu.items.map(\.title) == ["Copy Information", "Reveal in Finder"])
    }

    @Test func multilineInformationRowsAreNotCollapsed() {
        #expect(FileInformationRow("Attribute", "11 bytes\nactual value").isMultiline)
        #expect(!FileInformationRow("Attribute", "11 bytes").isMultiline)
    }
}

struct ScanSourceAccessTests {
    @Test func permissionFailureDisablesLocalVolumeScan() {
        let reason: String? = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/Volumes/Backup"),
            isLocalVolume: true,
            directoryContents: { _ in
                throw CocoaError(.fileReadNoPermission)
            }
        )

        #expect(reason == "Full Disk Access required")
    }

    @Test func permissionFailureDoesNotPreflightNetworkVolume() {
        let reason: String? = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/Volumes/Network"),
            isLocalVolume: false,
            directoryContents: { _ in
                throw CocoaError(.fileReadNoPermission)
            }
        )

        #expect(reason == nil)
    }

    @Test func protectedFolderFailureDisablesBootVolumeScan() {
        let protectedURL: URL = URL(fileURLWithPath: "/Users/test/Library/Mail")
        let reason: String? = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/"),
            isLocalVolume: true,
            protectedURLs: [protectedURL],
            fileExists: { $0 == protectedURL }
        ) { url in
            if url == protectedURL {
                throw CocoaError(.fileReadNoPermission)
            }
            return []
        }

        #expect(reason == "Full Disk Access required")
    }

    @Test func accessibleProtectedFoldersAllowBootVolumeScan() {
        let protectedURL: URL = URL(fileURLWithPath: "/Users/test/Library/Mail")
        let reason: String? = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/"),
            isLocalVolume: true,
            protectedURLs: [protectedURL],
            fileExists: { $0 == protectedURL }
        ) { _ in
            []
        }

        #expect(reason == nil)
    }

    @Test func protectedFolderOnAnotherVolumeDoesNotDisableScan() {
        let protectedURL: URL = URL(fileURLWithPath: "/Users/test/Library/Mail")
        var inspectedProtectedFolder: Bool = false
        let reason: String? = ScanSourceProvider.scanDisabledReason(
            for: URL(fileURLWithPath: "/Volumes/Backup"),
            isLocalVolume: true,
            protectedURLs: [protectedURL],
            fileExists: { _ in true }
        ) { url in
            if url == protectedURL {
                inspectedProtectedFolder = true
                throw CocoaError(.fileReadNoPermission)
            }
            return []
        }

        #expect(reason == nil)
        #expect(inspectedProtectedFolder == false)
    }
}

@MainActor
struct ApplicationWindowOrganizerTests {
    @Test func placesInspectorBesideScanWindowWithinVisibleFrame() {
        let visibleFrame: NSRect = NSRect(x: 0, y: 40, width: 1440, height: 860)
        let scanFrame: NSRect = NSRect(x: 301, y: 40, width: 837, height: 860)
        let inspectorFrame: NSRect = NSRect(x: 490, y: 260, width: 460, height: 420)

        let frames: OrganizedWindowFrames = ApplicationWindowOrganizer.frames(
            primary: scanFrame,
            accessory: inspectorFrame,
            visibleFrame: visibleFrame
        )

        #expect(frames.primary.intersects(frames.accessory) == false)
        #expect(frames.accessory.minX - frames.primary.maxX == ApplicationWindowOrganizer.windowGap)
        #expect(visibleFrame.contains(frames.primary))
        #expect(visibleFrame.contains(frames.accessory))
    }
}

struct DiskItemTests {

    @Test func builderFreezePreservesChildAncestryAndUpdatesSizes() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let childBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12,
            kindName: "Plain Text"
        )

        rootBuilder.appendChild(childBuilder)
        let root: DiskItem = rootBuilder.freeze()
        let child: DiskItem = root.child(at: 0)

        #expect(root.childCount == 1)
        #expect(root.child(at: 0) == child)
        #expect(root.descendantsMatchingAncestorPath(of: child) == [root, child])
        #expect(root.allocatedSizeValue == 4096)
        #expect(root.logicalSizeValue == 12)
    }

    @Test func sizeValueUsesSelectedPhysicalOrLogicalMode() {
        let item: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12
        )

        #expect(item.sizeValue(usePhysicalSize: true) == 4096)
        #expect(item.sizeValue(usePhysicalSize: false) == 12)
    }

    @Test func filesOfKindFindsNestedFilesAndExcludesFoldersAndOtherKinds() {
        let root: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let folder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder"),
            kindName: "Plain Text",
            isDirectory: true
        )
        folder.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/folder/nested.txt"),
                kindName: "Plain Text"
            )
        )
        root.appendChild(folder)
        root.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/top.txt"),
                kindName: "Plain Text"
            )
        )
        root.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/image.png"),
                kindName: "PNG image"
            )
        )

        let frozenRoot: DiskItem = root.freeze()
        let matches: [DiskItem] = frozenRoot.files(ofKind: "Plain Text")
        let allFiles: [DiskItem] = frozenRoot.allFiles()

        #expect(Set(matches.map(\.path)) == ["/scan/folder/nested.txt", "/scan/top.txt"])
        #expect(Set(allFiles.map(\.path)) == [
            "/scan/folder/nested.txt",
            "/scan/top.txt",
            "/scan/image.png"
        ])
    }

    @Test func fileInformationIncludesSecurityAndFileSystemSections() throws {
        let temporaryURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("metadata".utf8).write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let item: DiskItem = DiskItemBuilder(
            url: temporaryURL,
            allocatedSizeValue: 8,
            logicalSizeValue: 8
        ).freeze()
        let snapshot: FileInformationSnapshot = FileInformationSnapshot.load(
            item: item,
            usePhysicalSize: true
        )
        let sectionTitles: Set<String> = Set(snapshot.sections.map(\.title))

        #expect(sectionTitles.contains("Identity"))
        #expect(sectionTitles.contains("Ownership and Access"))
        #expect(sectionTitles.contains("File System"))
        #expect(sectionTitles.contains("Extended Attributes"))
        #expect(!sectionTitles.contains("Volume"))

        let copiedText: String = snapshot.plainText(
            itemName: item.displayName,
            kindDescription: "File"
        )
        #expect(copiedText.hasPrefix("\(item.displayName)\nFile\n\nIdentity\n"))
        #expect(copiedText.contains("Path: \(temporaryURL.path)"))
        #expect(copiedText.contains("\n\nOwnership and Access\n"))
        #expect(copiedText.contains("\n\nFile System\n"))
    }

    @Test func descendantsMatchingAncestorPathRejectsSiblingPathPrefixes() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let folderBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true
        )
        let siblingWithPrefixBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder-other"),
            isDirectory: true
        )

        folderBuilder.appendChild(DiskItemBuilder(url: URL(fileURLWithPath: "/scan/folder/file.txt")))
        rootBuilder.appendChild(folderBuilder)
        rootBuilder.appendChild(siblingWithPrefixBuilder)

        let root: DiskItem = rootBuilder.freeze()
        let folder: DiskItem = root.child(at: 0)
        let file: DiskItem = folder.child(at: 0)
        let siblingWithPrefix: DiskItem = root.child(at: 1)

        #expect(folder.descendantsMatchingAncestorPath(of: file) == [folder, file])
        #expect(folder.descendantsMatchingAncestorPath(of: siblingWithPrefix).isEmpty)
    }

    @Test func recalculatesRecursiveFolderSizesAndSortsLikeDiskInventoryZ() {
        let root: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let smallFile: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/2-small.bin"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        let largeFile: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/10-large.bin"),
            allocatedSizeValue: 900,
            logicalSizeValue: 900
        )
        let sameSizeByName: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/1-same.bin"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )

        root.appendChild(smallFile, updateSize: false)
        root.appendChild(largeFile, updateSize: false)
        root.appendChild(sameSizeByName, updateSize: false)
        root.recalculateSize(usePhysicalSize: true)
        let frozenRoot: DiskItem = root.freeze()

        #expect(frozenRoot.allocatedSizeValue == 1100)
        #expect(frozenRoot.children.map(\.displayName) == ["10-large.bin", "2-small.bin", "1-same.bin"])
    }

    @Test func recalculatingLogicalSizeSortsChildrenByLogicalSize() {
        let root: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let allocatedOnly: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/allocated-only.bin"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 0
        )
        let logicalContent: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/logical-content.bin"),
            allocatedSizeValue: 512,
            logicalSizeValue: 128
        )

        root.appendChild(allocatedOnly, updateSize: false)
        root.appendChild(logicalContent, updateSize: false)
        root.recalculateSize(usePhysicalSize: false)
        let frozenRoot: DiskItem = root.freeze()

        #expect(frozenRoot.logicalSizeValue == 128)
        #expect(frozenRoot.children.map(\.displayName) == ["logical-content.bin", "allocated-only.bin"])
    }

    @Test func duplicateHardlinkContributesZeroSize() {
        let root: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let duplicate: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/duplicate.dat"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 128,
            isHardlinkDuplicate: true
        )

        root.appendChild(duplicate, updateSize: false)
        root.recalculateSize(usePhysicalSize: true)
        let frozenRoot: DiskItem = root.freeze()
        let frozenDuplicate: DiskItem = frozenRoot.child(at: 0)

        #expect(frozenDuplicate.allocatedSizeValue == 0)
        #expect(frozenDuplicate.logicalSizeValue == 0)
        #expect(frozenRoot.allocatedSizeValue == 0)
    }

    @Test func opaquePackageKeepsPrestampedSize() {
        let package: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/App.app"),
            isDirectory: true,
            isPackage: true
        )
        package.setOpaquePackageSize(allocated: 12345, logical: 6789)

        package.recalculateSize(usePhysicalSize: true)
        let frozenPackage: DiskItem = package.freeze()

        #expect(frozenPackage.allocatedSizeValue == 12345)
        #expect(frozenPackage.logicalSizeValue == 6789)
    }

    @Test func addingChildToOpaquePackageUsesChildDerivedSize() {
        let package: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/App.app"),
            isDirectory: true,
            isPackage: true
        )
        package.setOpaquePackageSize(allocated: 12345, logical: 6789)
        package.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/App.app/Contents/file"),
                allocatedSizeValue: 4096,
                logicalSizeValue: 128
            ),
            updateSize: false
        )

        package.recalculateSize(usePhysicalSize: true)

        #expect(package.allocatedSizeValue == 4096)
        #expect(package.logicalSizeValue == 128)
    }

    @Test func childURLIsStoredAfterFreeze() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let childBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true
        )

        rootBuilder.appendChild(childBuilder)
        let child: DiskItem = rootBuilder.freeze().child(at: 0)

        #expect(child.path == "/scan/folder")
        #expect(child.url.path == "/scan/folder")
    }

    @Test func replacingSubtreeRebuildsAncestorsAndRestoresItemsByPath() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan"), isDirectory: true)
        let folderBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan/folder"), isDirectory: true)
        folderBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder/old.txt"),
            allocatedSizeValue: 10,
            logicalSizeValue: 10
        ))
        rootBuilder.appendChild(folderBuilder)
        let root: DiskItem = rootBuilder.freeze()

        let replacementBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan/folder"), isDirectory: true)
        replacementBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder/new.txt"),
            allocatedSizeValue: 25,
            logicalSizeValue: 25
        ))
        let replacement: DiskItem = replacementBuilder.freeze(isRoot: false)
        let updatedRoot: DiskItem? = root.replacingSubtree(
            atPath: "/scan/folder",
            with: replacement,
            usePhysicalSize: true
        )

        #expect(updatedRoot?.isRoot == true)
        #expect(updatedRoot?.allocatedSizeValue == 25)
        #expect(updatedRoot?.item(atPath: "/scan/folder/new.txt")?.name == "new.txt")
        #expect(updatedRoot?.item(atPath: "/scan/folder/old.txt") == nil)
    }

    @Test func removingSubtreeRecalculatesSizeAndAllowsAncestorFallback() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan"), isDirectory: true)
        let folderBuilder: DiskItemBuilder = DiskItemBuilder(url: URL(fileURLWithPath: "/scan/folder"), isDirectory: true)
        folderBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder/file.txt"),
            allocatedSizeValue: 40,
            logicalSizeValue: 20
        ))
        rootBuilder.appendChild(folderBuilder)
        let root: DiskItem = rootBuilder.freeze()
        let updatedRoot: DiskItem? = root.removingSubtree(
            atPath: "/scan/folder/file.txt",
            usePhysicalSize: true
        )

        #expect(updatedRoot?.allocatedSizeValue == 0)
        #expect(updatedRoot?.item(atPath: "/scan/folder/file.txt") == nil)
        #expect(updatedRoot?.item(atPath: "/scan/folder/file.txt", allowAncestors: true)?.path == "/scan/folder")
    }
}

struct SelectionListPipelineTests {
    @Test func snapshotIncludesAllFilesAndBuildsSelectionIndex() throws {
        let root: DiskItem = selectionListRoot()

        let snapshot: SelectionListSnapshot = try SelectionListPipeline.makeSnapshot(
            rootItem: root,
            filter: .all,
            usePhysicalSize: true
        )

        #expect(Set(snapshot.rows.map(\.fullPath)) == [
            "/scan/Notes/Read Me.TXT",
            "/scan/Notes/todo.md",
            "/scan/photo.png"
        ])
        #expect(snapshot.rowsByID.count == snapshot.rows.count)
        #expect(snapshot.rows.allSatisfy { snapshot.rowsByID[$0.id]?.item == $0.item })
    }

    @Test func snapshotFiltersByKindAndUsesRequestedSize() throws {
        let root: DiskItem = selectionListRoot()

        let snapshot: SelectionListSnapshot = try SelectionListPipeline.makeSnapshot(
            rootItem: root,
            filter: .kind("Plain Text"),
            usePhysicalSize: false
        )

        #expect(snapshot.rows.map(\.name) == ["Read Me.TXT"])
        #expect(snapshot.rows.first?.size == 12)
    }

    @Test func querySearchesCaseInsensitivelyInTheSelectedScope() throws {
        let snapshot: SelectionListSnapshot = try SelectionListPipeline.makeSnapshot(
            rootItem: selectionListRoot(),
            filter: .all,
            usePhysicalSize: true
        )
        let descriptors: [SelectionListSortDescriptor] = [
            SelectionListSortDescriptor(field: .name, isAscending: true)
        ]

        let nameMatches: [SelectionListRow] = try SelectionListPipeline.visibleRows(
            from: snapshot.rows,
            searchText: "read me",
            scope: .name,
            sortDescriptors: descriptors
        )
        let pathMatches: [SelectionListRow] = try SelectionListPipeline.visibleRows(
            from: snapshot.rows,
            searchText: "NOTES",
            scope: .path,
            sortDescriptors: descriptors
        )
        let kindMatches: [SelectionListRow] = try SelectionListPipeline.visibleRows(
            from: snapshot.rows,
            searchText: "markdown",
            scope: .all,
            sortDescriptors: descriptors
        )

        #expect(nameMatches.map(\.name) == ["Read Me.TXT"])
        #expect(pathMatches.map(\.name) == ["Read Me.TXT", "todo.md"])
        #expect(kindMatches.map(\.name) == ["todo.md"])
    }

    @Test func queryUsesRequestedSortOrder() throws {
        let snapshot: SelectionListSnapshot = try SelectionListPipeline.makeSnapshot(
            rootItem: selectionListRoot(),
            filter: .all,
            usePhysicalSize: true
        )

        let ascendingNames: [SelectionListRow] = try SelectionListPipeline.visibleRows(
            from: snapshot.rows,
            searchText: "",
            scope: .all,
            sortDescriptors: [SelectionListSortDescriptor(field: .name, isAscending: true)]
        )
        let descendingSizes: [SelectionListRow] = try SelectionListPipeline.visibleRows(
            from: snapshot.rows,
            searchText: "",
            scope: .all,
            sortDescriptors: [SelectionListSortDescriptor(field: .size, isAscending: false)]
        )

        #expect(ascendingNames.map(\.name) == ["photo.png", "Read Me.TXT", "todo.md"])
        #expect(descendingSizes.map(\.size) == [12_288, 8_192, 4_096])
    }

    @Test func canceledQueryStopsBeforePublishingResults() async {
        let row: SelectionListRow = SelectionListRow(
            item: DiskItem(
                url: URL(fileURLWithPath: "/scan/file.txt"),
                displayName: "file.txt",
                allocatedSizeValue: 4_096,
                logicalSizeValue: 4,
                kindName: "Plain Text"
            ),
            size: 4_096
        )
        let worker = Task.detached {
            try SelectionListPipeline.visibleRows(
                from: Array(repeating: row, count: 10_000),
                searchText: "file",
                scope: .all,
                sortDescriptors: [SelectionListSortDescriptor(field: .size, isAscending: false)]
            )
        }

        worker.cancel()

        await #expect(throws: CancellationError.self) {
            try await worker.value
        }
    }

    private func selectionListRoot() -> DiskItem {
        let root: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let notes: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/Notes"),
            isDirectory: true
        )
        notes.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/Notes/Read Me.TXT"),
                displayName: "Read Me.TXT",
                allocatedSizeValue: 4_096,
                logicalSizeValue: 12,
                kindName: "Plain Text"
            )
        )
        notes.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/Notes/todo.md"),
                allocatedSizeValue: 8_192,
                logicalSizeValue: 24,
                kindName: "Markdown document"
            )
        )
        root.appendChild(notes)
        root.appendChild(
            DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/photo.png"),
                allocatedSizeValue: 12_288,
                logicalSizeValue: 36,
                kindName: "PNG image"
            )
        )
        return root.freeze()
    }
}

struct TreemapDiskItemDataSourceTests {

    @Test func weightUsesSelectedPhysicalOrLogicalSizeMode() {
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12
        )

        let physicalDataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(
            rootItem: root,
            usePhysicalSize: true
        )
        let logicalDataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(
            rootItem: root,
            usePhysicalSize: false
        )

        #expect(physicalDataSource.weight(of: root) == 4096)
        #expect(logicalDataSource.weight(of: root) == 12)
    }

    @Test func kindStatisticsUseSelectedPhysicalOrLogicalSizeMode() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let textFile: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12,
            kindName: "Plain Text"
        )
        rootBuilder.appendChild(textFile)
        let root: DiskItem = rootBuilder.freeze()

        let physicalStatistics: [TreemapKindStatistic] = TreemapDiskItemDataSource.kindStatistics(
            for: root,
            usePhysicalSize: true
        )
        let logicalStatistics: [TreemapKindStatistic] = TreemapDiskItemDataSource.kindStatistics(
            for: root,
            usePhysicalSize: false
        )

        #expect(physicalStatistics.map(\.size) == [4096])
        #expect(logicalStatistics.map(\.size) == [12])
    }

    @Test func presentationMetricsReportMeasuredTraversalProgress() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        rootBuilder.appendChild(DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4_096,
            logicalSizeValue: 12,
            kindName: "Plain Text"
        ))
        let recorder: TreemapProgressRecorder = TreemapProgressRecorder()

        let metrics: TreemapPresentationMetrics = TreemapPresentationMetrics(
            rootItem: rootBuilder.freeze(),
            usePhysicalSize: true
        ) {
            recorder.record($0)
        }
        let progressValues: [Double] = recorder.values

        #expect(progressValues.first == 0)
        #expect(progressValues.last == 1)
        #expect(zip(progressValues, progressValues.dropFirst()).allSatisfy { $0.0 <= $0.1 })
        #expect(metrics.kindStatistics.first?.kindName == "Plain Text")
    }

    @Test func visibleVolumeSpaceItemsAreAppendedAndIncludedInRootWeight() {
        let file: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan/file.dat"),
            allocatedSizeValue: 40,
            logicalSizeValue: 40,
            isRoot: false
        )
        let root: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            allocatedSizeValue: 40,
            logicalSizeValue: 40,
            isDirectory: true,
            children: [file]
        )
        let freeSpace: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            itemType: .freeSpace,
            allocatedSizeValue: 50,
            logicalSizeValue: 50
        )
        let otherSpace: DiskItem = DiskItem(
            url: URL(fileURLWithPath: "/scan"),
            itemType: .otherSpace,
            allocatedSizeValue: 10,
            logicalSizeValue: 10
        )
        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(
            rootItem: root,
            showFreeSpace: true,
            showOtherSpace: true,
            freeSpaceItem: freeSpace,
            otherSpaceItem: otherSpace
        )

        #expect(dataSource.numberOfChildren(of: root) == 3)
        #expect(dataSource.child(1, of: root).itemType == .otherSpace)
        #expect(dataSource.child(2, of: root).itemType == .freeSpace)
        #expect(dataSource.weight(of: root) == 100)
    }
}

private final class TreemapProgressRecorder: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var storedValues: [Double] = []

    var values: [Double] {
        lock.withLock { storedValues }
    }

    func record(_ progress: Double) {
        lock.withLock {
            storedValues.append(progress)
        }
    }
}

@MainActor
struct TreemapViewRendererTests {

    @Test func renderedItemSelectionWorksImmediatelyAfterReload() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let childBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/file.txt"),
            allocatedSizeValue: 4096,
            logicalSizeValue: 12,
            kindName: "Plain Text"
        )
        rootBuilder.appendChild(childBuilder)
        let root: DiskItem = rootBuilder.freeze()
        let child: DiskItem = root.child(at: 0)

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: root)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)

        renderer.reloadData()

        #expect(renderer.selectItem(byRenderedItem: child) == true)
        #expect(renderer.selectedItem == child)
    }

    @Test func rendererReloadDoesNotMaterializeFullTree() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let selectedFolder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/selected"),
            isDirectory: true
        )
        let selectedFile: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/selected/file.txt"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        let siblingFolder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/sibling"),
            isDirectory: true
        )
        let siblingFile: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/sibling/file.txt"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        selectedFolder.appendChild(selectedFile)
        siblingFolder.appendChild(siblingFile)
        rootBuilder.appendChild(selectedFolder)
        rootBuilder.appendChild(siblingFolder)
        let root: DiskItem = rootBuilder.freeze()
        let frozenSelectedFile: DiskItem = root.child(at: 0).child(at: 0)

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: root)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)

        renderer.reloadData()

        #expect(renderer.materializedRendererCount == 1)
        #expect(renderer.selectItem(byRenderedItem: frozenSelectedFile) == true)
        #expect(renderer.selectedItem == frozenSelectedFile)
        #expect(renderer.materializedRendererCount == 4)
    }

    @Test func layoutDiagnosticsAccumulateDisplayPathDuringTraversal() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let folderBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder"),
            isDirectory: true
        )
        let fileBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/folder/file.txt"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        folderBuilder.appendChild(fileBuilder)
        rootBuilder.appendChild(folderBuilder)
        rootBuilder.recalculateSize(usePhysicalSize: true)
        let root: DiskItem = rootBuilder.freeze()

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: root)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)

        renderer.reloadData()
        renderer.calcLayout(NSRect(x: 0, y: 0, width: 100, height: 100))

        let displayPaths: [String] = renderer.layoutDiagnosticsRows().compactMap { row in
            row["displayPath"] as? String
        }
        #expect(displayPaths == ["scan", "scan/folder", "scan/folder/file.txt"])
    }

    @Test func squarifiedLayoutArrangesRowsByDescendingWeight() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let large: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/large.bin"),
            allocatedSizeValue: 600,
            logicalSizeValue: 600
        )
        let medium: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/medium.bin"),
            allocatedSizeValue: 300,
            logicalSizeValue: 300
        )
        let small: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/small.bin"),
            allocatedSizeValue: 100,
            logicalSizeValue: 100
        )
        rootBuilder.appendChild(large, updateSize: false)
        rootBuilder.appendChild(medium, updateSize: false)
        rootBuilder.appendChild(small, updateSize: false)
        rootBuilder.recalculateSize(usePhysicalSize: true)
        let root: DiskItem = rootBuilder.freeze()
        let frozenLarge: DiskItem = root.child(at: 0)
        let frozenMedium: DiskItem = root.child(at: 1)
        let frozenSmall: DiskItem = root.child(at: 2)

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: root)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)

        renderer.reloadData()
        renderer.calcLayout(NSRect(x: 0, y: 0, width: 100, height: 100))

        #expect(renderer.itemRect(byPathToItem: [root, frozenLarge]) == NSRect(x: 0, y: 0, width: 100, height: 60))
        #expect(renderer.itemRect(byPathToItem: [root, frozenMedium]) == NSRect(x: 0, y: 60, width: 75, height: 40))
        #expect(renderer.itemRect(byPathToItem: [root, frozenSmall]) == NSRect(x: 75, y: 60, width: 25, height: 40))
    }

    @Test func wideFlatDirectoryLayoutReconcilesChildrenOnce() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        for index: Int in 0..<2_000 {
            let child: DiskItemBuilder = DiskItemBuilder(
                url: URL(fileURLWithPath: "/scan/file-\(index).bin"),
                allocatedSizeValue: 1,
                logicalSizeValue: 1
            )
            rootBuilder.appendChild(child, updateSize: false)
        }
        rootBuilder.recalculateSize(usePhysicalSize: true)
        let root: DiskItem = rootBuilder.freeze()

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: root)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)

        renderer.reloadData()
        renderer.calcLayout(NSRect(x: 0, y: 0, width: 1_000, height: 1_000))

        #expect(renderer.materializedRendererCount == 2_001)
        #expect(renderer.childRendererReconciliationCount == 1)
    }

    @Test func emptyFolderCanBeMappedToItsTreemapRectWhenItHasArea() {
        let rootBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan"),
            isDirectory: true
        )
        let emptyFolderBuilder: DiskItemBuilder = DiskItemBuilder(
            url: URL(fileURLWithPath: "/scan/empty"),
            isDirectory: true
        )
        rootBuilder.appendChild(emptyFolderBuilder)
        let root: DiskItem = rootBuilder.freeze()
        let emptyFolder: DiskItem = root.child(at: 0)

        let dataSource: TreemapDiskItemDataSource = TreemapDiskItemDataSource(rootItem: root)
        let renderer: TreemapViewRenderer = TreemapViewRenderer(dataSource: dataSource)
        let bounds: NSRect = NSRect(x: 0, y: 0, width: 200, height: 100)

        renderer.reloadData()
        renderer.calcLayout(bounds)

        #expect(renderer.selectItem(byRenderedItem: emptyFolder) == true)
        #expect(renderer.itemRect(by: renderer.selectedCellID) == bounds)
        #expect(renderer.item(by: renderer.cellID(by: NSPoint(x: 100, y: 50), inViewCoordinates: false)!) == emptyFolder)
    }

    @Test func wholeTreemapSelectionRectLeavesRoomForStroke() {
        let visibleRect: NSRect = TreemapSelectionRect.visibleRect(
            for: NSRect(x: 0, y: 0, width: 200, height: 100),
            in: NSRect(x: 0, y: 0, width: 200, height: 100),
            minimumSide: 12,
            edgeInset: 2.5
        )

        #expect(visibleRect == NSRect(x: 2.5, y: 2.5, width: 195, height: 95))
    }

    @Test func zeroSizedSelectionRectExpandsAroundItsPosition() {
        let visibleRect: NSRect = TreemapSelectionRect.visibleRect(
            for: NSRect(x: 150, y: 40, width: 0, height: 0),
            in: NSRect(x: 0, y: 0, width: 200, height: 100),
            minimumSide: 12,
            edgeInset: 2.5
        )

        #expect(visibleRect == NSRect(x: 144, y: 34, width: 12, height: 12))
    }
}

struct TreemapCushionRendererTests {

    @Test func colorNormalizationRedistributesOverflowAcrossRemainingChannels() {
        var red: CGFloat = 1.4
        var green: CGFloat = 0.8
        var blue: CGFloat = 0.2

        TreemapCushionRenderer.normalizeColorRed(&red, green: &green, blue: &blue)

        #expect(Self.isNearlyEqual(red, 1.0))
        #expect(Self.isNearlyEqual(green, 1.0))
        #expect(Self.isNearlyEqual(blue, 0.4))
    }

    @Test func normalizeColorBalancesBrightnessAndPreservesAlpha() {
        let normalizedColor: NSColor = TreemapCushionRenderer.normalizeColor(
            NSColor(calibratedRed: 0, green: 0, blue: 0.9, alpha: 0.25)
        )

        #expect(Self.isNearlyEqual(normalizedColor.redComponent, 0.4))
        #expect(Self.isNearlyEqual(normalizedColor.greenComponent, 0.4))
        #expect(Self.isNearlyEqual(normalizedColor.blueComponent, 1.0))
        #expect(Self.isNearlyEqual(normalizedColor.alphaComponent, 0.25))
    }

    private static func isNearlyEqual(_ first: CGFloat, _ second: CGFloat) -> Bool {
        abs(first - second) < 0.0001
    }
}

struct DiskInventoryZScannerTests {

    @Test func concurrentScansKeepHardlinkDedupStateIsolated() async throws {
        let firstRootURL: URL = try Self.makeHardlinkFixture(named: "first")
        let secondRootURL: URL = try Self.makeHardlinkFixture(named: "second")
        defer {
            try? FileManager.default.removeItem(at: firstRootURL)
            try? FileManager.default.removeItem(at: secondRootURL)
        }

        async let firstScan: DiskItem = DiskInventoryZScanner().scan(
            source: ScanSource(path: firstRootURL.path, displayName: firstRootURL.lastPathComponent)
        )
        async let secondScan: DiskItem = DiskInventoryZScanner().scan(
            source: ScanSource(path: secondRootURL.path, displayName: secondRootURL.lastPathComponent)
        )

        let firstRoot: DiskItem = try await firstScan
        let secondRoot: DiskItem = try await secondScan

        #expect(Self.hardlinkDuplicateCount(in: firstRoot) == 1)
        #expect(Self.hardlinkDuplicateCount(in: secondRoot) == 1)
    }

    @Test func parallelTopLevelScanDeduplicatesHardlinksAcrossSubtrees() async throws {
        let rootURL: URL = try Self.makeCrossTopLevelHardlinkFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let root: DiskItem = try await DiskInventoryZScanner().scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        )

        #expect(Self.hardlinkDuplicateCount(in: root) == 1)
    }

    @Test func scanProgressBytesDoNotMoveBackwards() async throws {
        let rootURL: URL = try Self.makeCrossTopLevelHardlinkFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let progressRecorder: ProgressRecorder = ProgressRecorder()

        _ = try await DiskInventoryZScanner().scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        ) { progress in
            await progressRecorder.record(progress)
        }

        let byteCounts: [UInt64] = await progressRecorder.byteCounts
        #expect(zip(byteCounts, byteCounts.dropFirst()).allSatisfy { previous, next in
            previous <= next
        })
    }

    @Test func scanCancellationStopsConcurrentSubtreeWork() async throws {
        let rootURL: URL = try Self.makeCancellationFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let resourceValueReadCounter: LockedCounter = LockedCounter()
        let scanner: DiskInventoryZScanner = DiskInventoryZScanner { url, keys in
            resourceValueReadCounter.increment()
            Thread.sleep(forTimeInterval: 0.002)
            return try url.resourceValues(forKeys: keys)
        }

        let scanTask: Task<DiskItem, Error> = Task {
            try await scanner.scan(
                source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
            )
        }

        while resourceValueReadCounter.value == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }

        scanTask.cancel()

        do {
            _ = try await scanTask.value
            Issue.record("Expected scan cancellation to throw CancellationError.")
        } catch is CancellationError {
            #expect(true)
        }
    }

    @Test func recursiveScanSkipsItemsWhoseResourceValuesCannotBeRead() async throws {
        let rootURL: URL = try Self.makeUnreadableResourceValueFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let scanner: DiskInventoryZScanner = DiskInventoryZScanner { url, keys in
            if url.lastPathComponent == "vanished.dat" {
                throw CocoaError(.fileNoSuchFile)
            }

            return try url.resourceValues(forKeys: keys)
        }
        let root: DiskItem = try await scanner.scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        )
        let folder: DiskItem? = root.children.first { $0.name == "folder" }

        #expect(folder != nil)
        #expect(folder?.children.map(\.name) == ["readable.txt"])
    }

    @Test func topLevelScanSkipsItemsWhoseResourceValuesCannotBeRead() async throws {
        let rootURL: URL = try Self.makeUnreadableTopLevelResourceValueFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let scanner: DiskInventoryZScanner = DiskInventoryZScanner { url, keys in
            if url.lastPathComponent == "vanished.dat" {
                throw CocoaError(.fileNoSuchFile)
            }

            return try url.resourceValues(forKeys: keys)
        }
        let root: DiskItem = try await scanner.scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent)
        )

        #expect(root.children.map(\.name) == ["readable.txt"])
    }

    @Test func topLevelScanSortsChildrenByLogicalSizeWhenConfigured() async throws {
        let rootURL: URL = try Self.makeLogicalSortFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let root: DiskItem = try await DiskInventoryZScanner().scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent),
            settings: DiskScanSettings(
                usePhysicalSize: false,
                lookInsidePackages: false,
                ignoreCreatorCode: false
            )
        )

        #expect(root.children.map(\.name) == ["sparse-logical-large.bin", "dense-allocated.bin"])
    }

    @Test func opaquePackageKeepsSeparateAllocatedAndLogicalSizes() async throws {
        let rootURL: URL = try Self.makeOpaquePackageFixture()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let root: DiskItem = try await DiskInventoryZScanner().scan(
            source: ScanSource(path: rootURL.path, displayName: rootURL.lastPathComponent),
            settings: DiskScanSettings(
                usePhysicalSize: false,
                lookInsidePackages: false,
                ignoreCreatorCode: true
            )
        )
        let package: DiskItem? = root.children.first { $0.name == "Example.app" }

        #expect(package != nil)
        #expect(package?.logicalSizeValue == 17)
        #expect(package?.allocatedSizeValue != package?.logicalSizeValue)
    }

    private static func makeHardlinkFixture(named name: String) throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-\(name)-\(UUID().uuidString)", isDirectory: true)
        let folderURL: URL = rootURL.appendingPathComponent("folder", isDirectory: true)
        let originalURL: URL = folderURL.appendingPathComponent("original.dat")
        let linkedURL: URL = folderURL.appendingPathComponent("linked.dat")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 4096).write(to: originalURL)
        try FileManager.default.linkItem(at: originalURL, to: linkedURL)

        return rootURL
    }

    private static func makeCrossTopLevelHardlinkFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-cross-top-hardlinks-\(UUID().uuidString)", isDirectory: true)
        let firstFolderURL: URL = rootURL.appendingPathComponent("first", isDirectory: true)
        let secondFolderURL: URL = rootURL.appendingPathComponent("second", isDirectory: true)
        let originalURL: URL = firstFolderURL.appendingPathComponent("shared.dat")
        let linkedURL: URL = secondFolderURL.appendingPathComponent("shared-link.dat")

        try FileManager.default.createDirectory(at: firstFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolderURL, withIntermediateDirectories: true)
        try Data(repeating: 0x48, count: 4096).write(to: originalURL)
        try FileManager.default.linkItem(at: originalURL, to: linkedURL)

        return rootURL
    }

    private static func makeCancellationFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-cancellation-\(UUID().uuidString)", isDirectory: true)

        for folderIndex: Int in 0..<8 {
            let folderURL: URL = rootURL.appendingPathComponent("folder-\(folderIndex)", isDirectory: true)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for fileIndex: Int in 0..<80 {
                try Data(repeating: UInt8(fileIndex % 255), count: 128)
                    .write(to: folderURL.appendingPathComponent("file-\(fileIndex).dat"))
            }
        }

        return rootURL
    }

    private static func makeUnreadableResourceValueFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-unreadable-values-\(UUID().uuidString)", isDirectory: true)
        let folderURL: URL = rootURL.appendingPathComponent("folder", isDirectory: true)
        let readableURL: URL = folderURL.appendingPathComponent("readable.txt")
        let vanishedURL: URL = folderURL.appendingPathComponent("vanished.dat")

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try "readable".write(to: readableURL, atomically: true, encoding: .utf8)
        try Data(repeating: 0x7A, count: 128).write(to: vanishedURL)

        return rootURL
    }

    private static func makeUnreadableTopLevelResourceValueFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-unreadable-top-level-values-\(UUID().uuidString)", isDirectory: true)
        let readableURL: URL = rootURL.appendingPathComponent("readable.txt")
        let vanishedURL: URL = rootURL.appendingPathComponent("vanished.dat")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try "readable".write(to: readableURL, atomically: true, encoding: .utf8)
        try Data(repeating: 0x7A, count: 128).write(to: vanishedURL)

        return rootURL
    }

    private static func makeLogicalSortFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-logical-sort-\(UUID().uuidString)", isDirectory: true)
        let denseAllocatedURL: URL = rootURL.appendingPathComponent("dense-allocated.bin")
        let sparseLogicalLargeURL: URL = rootURL.appendingPathComponent("sparse-logical-large.bin")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4096).write(to: denseAllocatedURL)
        FileManager.default.createFile(atPath: sparseLogicalLargeURL.path, contents: nil)
        let sparseFileHandle: FileHandle = try FileHandle(forWritingTo: sparseLogicalLargeURL)
        try sparseFileHandle.truncate(atOffset: 1_048_576)
        try sparseFileHandle.close()

        return rootURL
    }

    private static func makeOpaquePackageFixture() throws -> URL {
        let rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("disk-hog-opaque-package-\(UUID().uuidString)", isDirectory: true)
        let contentsURL: URL = rootURL
            .appendingPathComponent("Example.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL: URL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try Data(repeating: 0x49, count: 5).write(to: contentsURL.appendingPathComponent("Info.plist"))
        try Data(repeating: 0x50, count: 12).write(to: resourcesURL.appendingPathComponent("payload.txt"))

        return rootURL
    }

    private static func hardlinkDuplicateCount(in item: DiskItem) -> Int {
        let currentCount: Int = item.isHardlinkDuplicate ? 1 : 0
        return item.children.reduce(currentCount) { count, child in
            count + hardlinkDuplicateCount(in: child)
        }
    }
}

private final class WindowDelegateTestDouble: NSObject, NSWindowDelegate {
    @objc func sentinel() {}
}

private actor ProgressRecorder {
    private(set) var byteCounts: [UInt64] = []

    func record(_ progress: DiskScanProgress) {
        byteCounts.append(progress.scannedByteCount)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var count: Int = 0

    var value: Int {
        lock.withLock {
            count
        }
    }

    func increment() {
        lock.withLock {
            count += 1
        }
    }
}
