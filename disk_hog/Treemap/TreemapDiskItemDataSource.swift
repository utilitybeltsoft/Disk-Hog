import AppKit // ✓ Swift-only: Swift/AppKit import replacing TreeMapViewController.m:17-22 imports used for colors and treemap callbacks.

nonisolated final class TreemapDiskItemDataSource: TreemapViewRendererDataSource, TreemapViewRendererDelegate, @unchecked Sendable { // ✓ Z: TreeMapViewController.h:6 @interface TreeMapViewController : NSObject.
    private let rootItem: DiskItem // ✓ Z: TreeMapViewController.h:11 IBOutlet FileSystemDoc *_document stores access to the root item.
    private let showFreeSpace: Bool // ✓ Z: TreeMapViewController.m:146 [doc showFreeSpace].
    private let showOtherSpace: Bool // ✓ Z: TreeMapViewController.m:148 [doc showOtherSpace].
    private let freeSpaceItem: DiskItem? // ✓ Z: TreeMapViewController.h:15 FSItem *_freeSpaceItem.
    private let otherSpaceItem: DiskItem? // ✓ Z: TreeMapViewController.h:14 FSItem *_otherSpaceItem.
    private let colorTable: TreemapDiskItemColorTable // ✓ Z: TreeMapViewController.m:192 [[[self document] fileTypeColors] colorForItem:fsItem].
    private let usePhysicalSize: Bool // ✓ Swift-only: selects physical or logical sizes for UI display.

    init(rootItem: DiskItem, usePhysicalSize: Bool = true, showFreeSpace: Bool = false, showOtherSpace: Bool = false, freeSpaceItem: DiskItem? = nil, otherSpaceItem: DiskItem? = nil) { // ✓ Z: TreeMapViewController.m:80-87 creates special items and reloads data.
        self.rootItem = rootItem // ✓ Z: TreeMapViewController.m:82 FSItem *rootItem = [[self document] rootItem].
        self.usePhysicalSize = usePhysicalSize // ✓ Swift-only: preserves scan size mode for treemap and kind totals.
        self.showFreeSpace = showFreeSpace // ✓ Z: TreeMapViewController.m:146 reads showFreeSpace option.
        self.showOtherSpace = showOtherSpace // ✓ Z: TreeMapViewController.m:148 reads showOtherSpace option.
        self.freeSpaceItem = freeSpaceItem // ✓ Z: TreeMapViewController.m:85 _freeSpaceItem = [[FSItem alloc] initAsFreeSpaceItemForParent:rootItem].
        self.otherSpaceItem = otherSpaceItem // ✓ Z: TreeMapViewController.m:84 _otherSpaceItem = [[FSItem alloc] initAsOtherSpaceItemForParent:rootItem].
        self.colorTable = TreemapDiskItemColorTable(rootItem: rootItem, usePhysicalSize: usePhysicalSize) // ✓ Z: TreeMapViewController.m:192 document owns FileTypeColors used by willDisplayItem.
    } // ✓ Swift-only: closes Swift initializer replacing awakeFromNib setup.

    var root: DiskItem { // ✓ Z: TreeMapViewController.m:106 - rootItem.
        rootItem // ✓ Z: TreeMapViewController.m:108 return [[self document] zoomedItem].
    } // ✓ Z: TreeMapViewController.m:109 closes rootItem.

    static func kindStatistics(for rootItem: DiskItem, usePhysicalSize: Bool = true) -> [TreemapKindStatistic] { // ✓ Swift-only: exposes Z FileTypeColors/table data to the SwiftUI kind list.
        TreemapDiskItemColorTable.kindStatistics(from: rootItem, usePhysicalSize: usePhysicalSize) // ✓ Swift-only: reuse the same kind order and colors as treemap drawing.
    } // ✓ Swift-only: closes kind-statistics bridge.

    func treemapItemRendererChild(_ index: Int, of item: AnyObject) -> AnyObject { // ✓ Z: TreeMapViewController.m:113 treeMapView:child:ofItem:.
        let diskItem: DiskItem = itemAsDiskItem(item) // ✓ Z: TreeMapViewController.m:115 FSItem *fsItem = (item == nil ? [self rootItem] : item).
        if diskItem === rootItem && index >= diskItem.childCount { // ✓ Z: TreeMapViewController.m:117-118 root special-space child branch.
            if (index - diskItem.childCount) == 0 { // ✓ Z: TreeMapViewController.m:120 if first special child slot.
                return (showOtherSpace ? otherSpaceItem : freeSpaceItem) ?? diskItem // ✓ Z: TreeMapViewController.m:121 return showOtherSpace ? _otherSpaceItem : _freeSpaceItem.
            } else { // ✓ Z: TreeMapViewController.m:122 else.
                return freeSpaceItem ?? diskItem // ✓ Z: TreeMapViewController.m:123 return _freeSpaceItem.
            } // ✓ Z: TreeMapViewController.m:120-124 closes special child selection.
        } else { // ✓ Z: TreeMapViewController.m:125 else.
            return diskItem.child(at: index) // ✓ Z: TreeMapViewController.m:126 return [fsItem childAtIndex:index].
        } // ✓ Z: TreeMapViewController.m:117-127 closes child lookup.
    } // ✓ Z: TreeMapViewController.m:127 closes treeMapView:child:ofItem:.

    func treemapItemRendererIsNode(_ item: AnyObject) -> Bool { // ✓ Z: TreeMapViewController.m:129 treeMapView:isNode:.
        let diskItem: DiskItem = itemAsDiskItem(item) // ✓ Z: TreeMapViewController.m:131 FSItem *fsItem = (item == nil ? [self rootItem] : item).
        return !diskItem.isSpecialItem && itemIsNode(diskItem) // ✓ Z: TreeMapViewController.m:133 return ![fsItem isSpecialItem] && [[self document] itemIsNode:fsItem].
    } // ✓ Z: TreeMapViewController.m:134 closes treeMapView:isNode:.

    func treemapItemRendererNumberOfChildren(of item: AnyObject) -> Int { // ✓ Z: TreeMapViewController.m:136 treeMapView:numberOfChildrenOfItem:.
        let diskItem: DiskItem = itemAsDiskItem(item) // ✓ Z: TreeMapViewController.m:138 FSItem *fsItem = (item == nil ? [self rootItem] : item).
        var childCount: Int = diskItem.childCount // ✓ Z: TreeMapViewController.m:140 unsigned childCount = [fsItem childCount].
        if diskItem === rootItem { // ✓ Z: TreeMapViewController.m:143 if (fsItem == [self rootItem]).
            if showFreeSpace { // ✓ Z: TreeMapViewController.m:146 if ([doc showFreeSpace]).
                childCount += 1 // ✓ Z: TreeMapViewController.m:147 childCount++.
            } // ✓ Z: TreeMapViewController.m:146-147 closes showFreeSpace branch.
            if showOtherSpace { // ✓ Z: TreeMapViewController.m:148 if ([doc showOtherSpace]).
                childCount += 1 // ✓ Z: TreeMapViewController.m:149 childCount++.
            } // ✓ Z: TreeMapViewController.m:148-149 closes showOtherSpace branch.
        } // ✓ Z: TreeMapViewController.m:143-150 closes root special-count branch.
        return childCount // ✓ Z: TreeMapViewController.m:152 return childCount.
    } // ✓ Z: TreeMapViewController.m:153 closes treeMapView:numberOfChildrenOfItem:.

    func treemapItemRendererWeight(of item: AnyObject) -> UInt64 { // ✓ Z: TreeMapViewController.m:155 treeMapView:weightByItem:.
        let diskItem: DiskItem = itemAsDiskItem(item) // ✓ Z: TreeMapViewController.m:157 FSItem *fsItem = (item == nil ? [self rootItem] : item).
        var size: UInt64 = diskItem.sizeValue(usePhysicalSize: usePhysicalSize) // ✓ Z: TreeMapViewController.m:159 unsigned long long size = [fsItem sizeValue].
        if diskItem === rootItem { // ✓ Z: TreeMapViewController.m:162 if (fsItem == [self rootItem]).
            if showFreeSpace, let freeSpaceItem: DiskItem = freeSpaceItem { // ✓ Z: TreeMapViewController.m:165 if ([doc showFreeSpace]).
                size += freeSpaceItem.sizeValue(usePhysicalSize: usePhysicalSize) // ✓ Z: TreeMapViewController.m:166 size += [_freeSpaceItem sizeValue].
            } // ✓ Z: TreeMapViewController.m:165-166 closes free-space size branch.
            if showOtherSpace, let otherSpaceItem: DiskItem = otherSpaceItem { // ✓ Z: TreeMapViewController.m:167 if ([doc showOtherSpace]).
                size += otherSpaceItem.sizeValue(usePhysicalSize: usePhysicalSize) // ✓ Z: TreeMapViewController.m:168 size += [_otherSpaceItem sizeValue].
            } // ✓ Z: TreeMapViewController.m:167-168 closes other-space size branch.
        } // ✓ Z: TreeMapViewController.m:162-169 closes root special-size branch.
        return size // ✓ Z: TreeMapViewController.m:171 return size.
    } // ✓ Z: TreeMapViewController.m:172 closes treeMapView:weightByItem:.

    func treemapItemRendererWillDisplay(_ item: AnyObject, with renderer: TreemapItemRenderer) { // ✓ Z: TreeMapViewController.m:183 treeMapView:willDisplayItem:withRenderer:.
        let diskItem: DiskItem = itemAsDiskItem(item) // ✓ Z: TreeMapViewController.m:185 FSItem *fsItem = (item == nil ? [self rootItem] : item).
        let color: NSColor = colorTable.color(for: diskItem) // ✓ Z: TreeMapViewController.m:187-204 determines NSColor *color for item type.
        renderer.setCushionColor(color) // ✓ Z: TreeMapViewController.m:206 [renderer setCushionColor:color].
    } // ✓ Z: TreeMapViewController.m:207 closes treeMapView:willDisplayItem:withRenderer:.

    func treemapViewRendererShouldSelectItem(_ item: AnyObject) -> Bool { // ✓ Z: TreeMapView.h:88 treeMapView:shouldSelectItem: optional delegate method.
        !itemAsDiskItem(item).isSpecialItem // ✓ Z: TreeMapViewController.m:223 if (![fsItem isSpecialItem]) allows document selection.
    } // ✓ Swift-only: closes selection-veto helper matching Z's special-item behavior.

    private func itemAsDiskItem(_ item: AnyObject) -> DiskItem { // ✓ Swift-only: Swift root renderer stores root item instead of Z's nil root convention.
        item as! DiskItem // ✓ Z: TreeMapViewController.m:115 casts item to FSItem after nil-root replacement.
    } // ✓ Swift-only: closes DiskItem cast helper.

    private func itemIsNode(_ item: DiskItem) -> Bool { // ✓ Z: TreeMapViewController.m:133 delegates node decision to [[self document] itemIsNode:fsItem].
        item.isFolder && !item.isPackage // ✓ Z: TreeMapViewController.m:133 document itemIsNode result is true for visible non-package folders.
    } // ✓ Swift-only: closes current Disk Hog itemIsNode bridge.
} // ✓ Z: TreeMapViewController.m:409 closes TreeMapViewController implementation.

nonisolated struct TreemapKindStatistic: Identifiable, Sendable { // ✓ Swift-only: immutable row model for Z-style file-kind table.
    let kindName: String // ✓ Z: FileKindsTableController.m:72 table column uses represented kind name.
    let size: UInt64 // ✓ Z: FileKindsTableController.m:97 size column comes from FileTypeStatistics.
    let fileCount: Int // ✓ Z: FileKindsTableController.m:108 files column comes from FileTypeStatistics.
    let color: NSColor // ✓ Z: FileKindsTableController.m:82 color column asks document FileTypeColors.

    var id: String { // ✓ Swift-only: SwiftUI row identity.
        kindName // ✓ Swift-only: one row per kind.
    } // ✓ Swift-only: closes row identity.
} // ✓ Swift-only: closes kind-statistic row model.

private nonisolated final class TreemapDiskItemColorTable: @unchecked Sendable { // ✓ Z: FileTypeColors.m:20 @implementation FileTypeColors.
    private var colorsByKind: [String: NSColor] // ✓ Z: FileTypeColors.m:36 _colors = [[NSMutableDictionary alloc] init].
    private let predefinedColors: [NSColor] // ✓ Z: FileTypeColors.m:40 _predefinedColors = [[NSMutableArray alloc] initWithObjects:...].
    private let fallbackFolderColor: NSColor // ✓ Swift-only: folder/package color comes from the next available Z color slot after collected kinds.

    init(rootItem: DiskItem, usePhysicalSize: Bool) { // ✓ Z: FileTypeColors.m:32 - init.
        self.predefinedColors = Self.makePredefinedColors() // ✓ Z: FileTypeColors.m:40-76 initializes predefined colors.
        self.colorsByKind = [:] // ✓ Z: FileTypeColors.m:36 _colors = [[NSMutableDictionary alloc] init].
        let orderedKinds: [String] = Self.orderedKinds(from: rootItem, usePhysicalSize: usePhysicalSize) // ✓ Swift-only: mirrors diagnostic/Z prepared kind order before willDisplay traversal.
        for kindIndex: Int in 0..<orderedKinds.count { // ✓ Z: FileTypeColors.m:80-85 normalizes colors before use, then colorForKind assigns by count.
            colorsByKind[orderedKinds[kindIndex]] = Self.color(at: kindIndex, predefinedColors: predefinedColors) // ✓ Z: FileTypeColors.m:116-118 color = predefinedColors[count]; setObject:forKey:.
        } // ✓ Swift-only: closes prepared kind color assignment.
        self.fallbackFolderColor = Self.color(at: orderedKinds.count, predefinedColors: predefinedColors) // ✓ Swift-only: diagnostics reserve next Z color slot for folders.
    } // ✓ Z: FileTypeColors.m:88 closes init.

    func color(for item: DiskItem) -> NSColor { // ✓ Z: FileTypeColors.m:103 - colorForItem:.
        switch item.itemType { // ✓ Z: TreeMapViewController.m:189 switch ([fsItem type]).
        case .fileOrFolder: // ✓ Z: TreeMapViewController.m:191 case FileFolderItem.
            return colorForKind(Self.kindName(for: item)) // ✓ Z: FileTypeColors.m:105 return [self colorForKind:[item kindName]].
        case .freeSpace: // ✓ Z: TreeMapViewController.m:194 case FreeSpaceItem.
            return TreemapCushionRenderer.normalizeColor(NSColor(calibratedRed: 0.66, green: 0.66, blue: 0.66, alpha: 1)) // ✓ Z: TreeMapViewController.m:197-198 normalize free-space color.
        case .otherSpace: // ✓ Z: TreeMapViewController.m:200 case OtherSpaceItem.
            return TreemapCushionRenderer.normalizeColor(NSColor(calibratedRed: 0.33, green: 0.33, blue: 0.33, alpha: 1)) // ✓ Z: TreeMapViewController.m:201-202 normalize other-space color.
        } // ✓ Z: TreeMapViewController.m:189-204 closes type switch.
    } // ✓ Z: TreeMapViewController.m:207 closes willDisplay color use.

    private func colorForKind(_ kind: String) -> NSColor { // ✓ Z: FileTypeColors.m:108 - colorForKind:.
        if let color: NSColor = colorsByKind[kind] { // ✓ Z: FileTypeColors.m:110 NSColor *color = [_colors objectForKey:kind].
            return color // ✓ Z: FileTypeColors.m:135 return color.
        } // ✓ Z: FileTypeColors.m:112 skips allocation when color exists.
        let color: NSColor = color(at: colorsByKind.count) // ✓ Z: FileTypeColors.m:114-127 choose predefined or fallback gray by _colors count.
        colorsByKind[kind] = color // ✓ Z: FileTypeColors.m:118 or m:131 [_colors setObject:color forKey:kind].
        return color // ✓ Z: FileTypeColors.m:135 return color.
    } // ✓ Z: FileTypeColors.m:136 closes colorForKind:.

    private func color(at index: Int) -> NSColor { // ✓ Swift-only: instance wrapper for Z colorForKind count-based color lookup.
        Self.color(at: index, predefinedColors: predefinedColors) // ✓ Z: FileTypeColors.m:114-127 computes color from predefinedColors or fallback.
    } // ✓ Swift-only: closes color lookup wrapper.

    private static func color(at index: Int, predefinedColors: [NSColor]) -> NSColor { // ✓ Z: FileTypeColors.m:114 if predefined count > color count.
        if predefinedColors.count > index { // ✓ Z: FileTypeColors.m:114 if ([_predefinedColors count] > [_colors count]).
            return predefinedColors[index] // ✓ Z: FileTypeColors.m:116 color = [_predefinedColors objectAtIndex:[_colors count]].
        } // ✓ Z: FileTypeColors.m:114-119 closes predefined branch.
        var rgbComponent: CGFloat = CGFloat(index) * 0.05 // ✓ Z: FileTypeColors.m:122 float rgbComponent = [_colors count] * 0.05.
        if rgbComponent > 0.9 { // ✓ Z: FileTypeColors.m:124 if (rgbComponent > 0.9).
            rgbComponent = 0.9 // ✓ Z: FileTypeColors.m:125 rgbComponent = 0.9.
        } // ✓ Z: FileTypeColors.m:124-125 closes clamp.
        return TreemapCushionRenderer.normalizeColor(NSColor(calibratedRed: rgbComponent, green: rgbComponent, blue: rgbComponent, alpha: 1)) // ✓ Z: FileTypeColors.m:127-129 create calibrated gray and normalize.
    } // ✓ Z: FileTypeColors.m:132 closes fallback branch.

    private static func makePredefinedColors() -> [NSColor] { // ✓ Z: FileTypeColors.m:40 initializes _predefinedColors.
        let rawColors: [NSColor] = [ // ✓ Z: FileTypeColors.m:40 _predefinedColors = [[NSMutableArray alloc] initWithObjects:.
            NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1), // ✓ Z: FileTypeColors.m:42 COLOR(0, 0, 1).
            NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1), // ✓ Z: FileTypeColors.m:43 COLOR(1, 0, 0).
            NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1), // ✓ Z: FileTypeColors.m:44 COLOR(0, 1, 0).
            NSColor(calibratedRed: 0, green: 1, blue: 1, alpha: 1), // ✓ Z: FileTypeColors.m:45 COLOR(0, 1, 1).
            NSColor(calibratedRed: 1, green: 0, blue: 1, alpha: 1), // ✓ Z: FileTypeColors.m:46 COLOR(1, 0, 1).
            NSColor(calibratedRed: 1, green: 1, blue: 0, alpha: 1), // ✓ Z: FileTypeColors.m:47 COLOR(1, 1, 0).
            NSColor(calibratedRed: 0.58, green: 0.58, blue: 1, alpha: 1), // ✓ Z: FileTypeColors.m:49 COLOR(0.58, 0.58, 1).
            NSColor(calibratedRed: 1, green: 0.58, blue: 0.58, alpha: 1), // ✓ Z: FileTypeColors.m:50 COLOR(1, 0.58, 0.58).
            NSColor(calibratedRed: 0.58, green: 1, blue: 0.58, alpha: 1), // ✓ Z: FileTypeColors.m:51 COLOR(0.58, 1, 0.58).
            NSColor(calibratedRed: 0.58, green: 1, blue: 1, alpha: 1), // ✓ Z: FileTypeColors.m:52 COLOR(0.58, 1, 1).
            NSColor(calibratedRed: 1, green: 0.58, blue: 1, alpha: 1), // ✓ Z: FileTypeColors.m:53 COLOR(1, 0.58, 1).
            NSColor(calibratedRed: 1, green: 1, blue: 0.58, alpha: 1), // ✓ Z: FileTypeColors.m:54 COLOR(1, 1, 0.58).
            NSColor(calibratedRed: 1, green: 0.5, blue: 0, alpha: 1), // ✓ Z: FileTypeColors.m:56 COLOR(1, 0.5, 0).
            NSColor(calibratedRed: 0.5, green: 0, blue: 1, alpha: 1), // ✓ Z: FileTypeColors.m:57 COLOR(0.5, 0, 1).
            NSColor(calibratedRed: 0, green: 0.5, blue: 0.5, alpha: 1), // ✓ Z: FileTypeColors.m:58 COLOR(0, 0.5, 0.5).
            NSColor(calibratedRed: 1, green: 0.4, blue: 0.7, alpha: 1), // ✓ Z: FileTypeColors.m:59 COLOR(1, 0.4, 0.7).
            NSColor(calibratedRed: 0.5, green: 1, blue: 0, alpha: 1), // ✓ Z: FileTypeColors.m:60 COLOR(0.5, 1, 0).
            NSColor(calibratedRed: 0.6, green: 0.3, blue: 0, alpha: 1), // ✓ Z: FileTypeColors.m:61 COLOR(0.6, 0.3, 0).
            NSColor(calibratedRed: 1, green: 0.78, blue: 0.55, alpha: 1), // ✓ Z: FileTypeColors.m:63 COLOR(1, 0.78, 0.55).
            NSColor(calibratedRed: 0.78, green: 0.55, blue: 1, alpha: 1), // ✓ Z: FileTypeColors.m:64 COLOR(0.78, 0.55, 1).
            NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.85, alpha: 1), // ✓ Z: FileTypeColors.m:65 COLOR(0.55, 0.85, 0.85).
            NSColor(calibratedRed: 1, green: 0.75, blue: 0.85, alpha: 1), // ✓ Z: FileTypeColors.m:66 COLOR(1, 0.75, 0.85).
            NSColor(calibratedRed: 0.78, green: 1, blue: 0.55, alpha: 1), // ✓ Z: FileTypeColors.m:67 COLOR(0.78, 1, 0.55).
            NSColor(calibratedRed: 0.85, green: 0.7, blue: 0.55, alpha: 1), // ✓ Z: FileTypeColors.m:68 COLOR(0.85, 0.7, 0.55).
            NSColor(calibratedRed: 0, green: 0, blue: 0.65, alpha: 1), // ✓ Z: FileTypeColors.m:70 COLOR(0, 0, 0.65).
            NSColor(calibratedRed: 0.65, green: 0, blue: 0, alpha: 1), // ✓ Z: FileTypeColors.m:71 COLOR(0.65, 0, 0).
            NSColor(calibratedRed: 0, green: 0.65, blue: 0, alpha: 1), // ✓ Z: FileTypeColors.m:72 COLOR(0, 0.65, 0).
            NSColor(calibratedRed: 0, green: 0.65, blue: 0.65, alpha: 1), // ✓ Z: FileTypeColors.m:73 COLOR(0, 0.65, 0.65).
            NSColor(calibratedRed: 0.65, green: 0, blue: 0.65, alpha: 1), // ✓ Z: FileTypeColors.m:74 COLOR(0.65, 0, 0.65).
            NSColor(calibratedRed: 0.65, green: 0.65, blue: 0, alpha: 1) // ✓ Z: FileTypeColors.m:75 COLOR(0.65, 0.65, 0).
        ] // ✓ Z: FileTypeColors.m:76 nil terminates predefined color list.
        return rawColors.map { color in // ✓ Z: FileTypeColors.m:80-81 for i < [_predefinedColors count].
            TreemapCushionRenderer.normalizeColor(color) // ✓ Z: FileTypeColors.m:83-84 replace color with [TMVCushionRenderer normalizeColor:color].
        } // ✓ Z: FileTypeColors.m:80-85 closes predefined normalization loop.
    } // ✓ Z: FileTypeColors.m:88 closes init color setup.

    private static func orderedKinds(from rootItem: DiskItem, usePhysicalSize: Bool) -> [String] { // ✓ Swift-only: prepares FileTypeColors assignment order to match existing Z diagnostics.
        var sizeByKind: [String: UInt64] = [:] // ✓ Swift-only: mirrors diagnostic palette's kind-size collection.
        collectLeafKindSizes(from: rootItem, usePhysicalSize: usePhysicalSize, into: &sizeByKind) // ✓ Swift-only: gathers visible leaf kind sizes for deterministic Z color assignment.
        return sizeByKind.keys.sorted { leftKind, rightKind in // ✓ Swift-only: sorts kinds using the accepted diagnostic/Z parity order.
            let leftSize: UInt64 = sizeByKind[leftKind] ?? 0 // ✓ Swift-only: reads accumulated left kind size.
            let rightSize: UInt64 = sizeByKind[rightKind] ?? 0 // ✓ Swift-only: reads accumulated right kind size.
            if leftSize != rightSize { // ✓ Swift-only: primary order is size descending.
                return leftSize > rightSize // ✓ Swift-only: larger kind gets earlier Z predefined color.
            } // ✓ Swift-only: closes size comparison.
            return leftKind.localizedStandardCompare(rightKind) == .orderedAscending // ✓ Swift-only: tie-breaker matches existing diagnostic parity script output.
        } // ✓ Swift-only: closes ordered kind sort.
    } // ✓ Swift-only: closes ordered kind computation.

    static func kindStatistics(from rootItem: DiskItem, usePhysicalSize: Bool) -> [TreemapKindStatistic] { // ✓ Swift-only: builds the visible file-kind table using the treemap palette order.
        var statisticsByKind: [String: TreemapKindStatisticAccumulator] = [:] // ✓ Swift-only: accumulates Z-style file type statistics by kind.
        collectLeafKindStatistics(from: rootItem, usePhysicalSize: usePhysicalSize, into: &statisticsByKind) // ✓ Swift-only: gather visible leaf kind size and file count.
        let orderedKinds: [String] = statisticsByKind.keys.sorted { leftKind, rightKind in // ✓ Swift-only: same deterministic order used for color assignment.
            let leftSize: UInt64 = statisticsByKind[leftKind]?.size ?? 0 // ✓ Swift-only: reads accumulated left kind size.
            let rightSize: UInt64 = statisticsByKind[rightKind]?.size ?? 0 // ✓ Swift-only: reads accumulated right kind size.
            if leftSize != rightSize { // ✓ Swift-only: primary order is size descending.
                return leftSize > rightSize // ✓ Swift-only: larger kind appears earlier and receives earlier Z color.
            } // ✓ Swift-only: closes size comparison.
            return leftKind.localizedStandardCompare(rightKind) == .orderedAscending // ✓ Swift-only: deterministic tie-breaker.
        } // ✓ Swift-only: closes kind order sort.
        let colorTable: TreemapDiskItemColorTable = TreemapDiskItemColorTable(rootItem: rootItem, usePhysicalSize: usePhysicalSize) // ✓ Swift-only: use the exact same colors as the renderer.
        return orderedKinds.map { kindName in // ✓ Swift-only: convert accumulated kind data into table rows.
            let accumulator: TreemapKindStatisticAccumulator = statisticsByKind[kindName] ?? TreemapKindStatisticAccumulator() // ✓ Swift-only: retrieve accumulated row values.
            return TreemapKindStatistic( // ✓ Swift-only: immutable table row.
                kindName: kindName, // ✓ Z: FileKindsTableController.m:72 kind column.
                size: accumulator.size, // ✓ Z: FileKindsTableController.m:97 size column.
                fileCount: accumulator.fileCount, // ✓ Z: FileKindsTableController.m:108 files column.
                color: colorTable.colorForKind(kindName) // ✓ Z: FileKindsTableController.m:82 color image uses FileTypeColors colorForKind.
            ) // ✓ Swift-only: closes table row construction.
        } // ✓ Swift-only: closes row mapping.
    } // ✓ Swift-only: closes file-kind table statistics.

    private static func collectLeafKindSizes(from item: DiskItem, usePhysicalSize: Bool, into sizeByKind: inout [String: UInt64]) { // ✓ Swift-only: mirrors TreemapInputDiagnostics leaf-kind collection.
        if item.isFolder && !item.isPackage { // ✓ Z: TreeMapViewController.m:133 folders are nodes and not colored as leaves.
            for child: DiskItem in item.children { // ✓ Z: TreeMapViewController.m:113-127 descends through child items.
                collectLeafKindSizes(from: child, usePhysicalSize: usePhysicalSize, into: &sizeByKind) // ✓ Swift-only: recursively collect leaf kind sizes.
            } // ✓ Swift-only: closes child traversal.
            return // ✓ Swift-only: folders do not contribute a leaf kind size.
        } // ✓ Swift-only: closes folder-node branch.
        let kindName: String = kindName(for: item) // ✓ Z: FileTypeColors.m:105 [item kindName].
        sizeByKind[kindName, default: 0] += item.sizeValue(usePhysicalSize: usePhysicalSize) // ✓ Swift-only: add leaf size used by treemap to kind bucket.
    } // ✓ Swift-only: closes leaf kind collection.

    private static func collectLeafKindStatistics(from item: DiskItem, usePhysicalSize: Bool, into statisticsByKind: inout [String: TreemapKindStatisticAccumulator]) { // ✓ Swift-only: mirrors collectLeafKindSizes while keeping file counts for table display.
        if item.isFolder && !item.isPackage { // ✓ Z: TreeMapViewController.m:133 folders are nodes and not colored as leaves.
            for child: DiskItem in item.children { // ✓ Z: TreeMapViewController.m:113-127 descends through child items.
                collectLeafKindStatistics(from: child, usePhysicalSize: usePhysicalSize, into: &statisticsByKind) // ✓ Swift-only: recursively collect leaf kind statistics.
            } // ✓ Swift-only: closes child traversal.
            return // ✓ Swift-only: folders do not contribute a file-kind table row.
        } // ✓ Swift-only: closes folder-node branch.
        let kindName: String = kindName(for: item) // ✓ Z: FileTypeColors.m:105 [item kindName].
        guard !kindName.isEmpty else { // ✓ Swift-only: omit unclassified empty kinds from the file-kind table.
            return // ✓ Swift-only: closes empty-kind omission.
        } // ✓ Swift-only: closes empty-kind guard.
        var accumulator: TreemapKindStatisticAccumulator = statisticsByKind[kindName] ?? TreemapKindStatisticAccumulator() // ✓ Swift-only: existing or new kind bucket.
        accumulator.size += item.sizeValue(usePhysicalSize: usePhysicalSize) // ✓ Z: FileKindsTableController.m:97 size is accumulated per kind.
        accumulator.fileCount += 1 // ✓ Z: FileKindsTableController.m:108 file count is accumulated per kind.
        statisticsByKind[kindName] = accumulator // ✓ Swift-only: store updated kind bucket.
    } // ✓ Swift-only: closes leaf kind statistics collection.

    private static func kindName(for item: DiskItem) -> String { // ✓ Z: FileTypeColors.m:105 asks item for kindName.
        if let kindName: String = item.kindName { // ✓ Z: FileTypeColors.m:105 uses [item kindName] from FSItem.
            return kindName // ✓ Z: FileTypeColors.m:105 uses [item kindName].
        } // ✓ Swift-only: closes known kind branch.
        if item.isFolder && !item.isPackage { // ✓ Z: TreeMapViewController.m:133 document treats non-package folders as nodes.
            return "Folder" // ✓ Swift-only: folder fallback mirrors TreemapInputDiagnostics folder kind.
        } // ✓ Swift-only: closes folder fallback.
        return "" // ✓ Swift-only: empty fallback mirrors TreemapInputDiagnostics empty kind.
    } // ✓ Swift-only: closes kind-name helper.
} // ✓ Z: FileTypeColors.m:138 closes FileTypeColors implementation.

private nonisolated struct TreemapKindStatisticAccumulator: Sendable { // ✓ Swift-only: mutable accumulator for kind table rows.
    var size: UInt64 = 0 // ✓ Swift-only: accumulated byte size.
    var fileCount: Int = 0 // ✓ Swift-only: accumulated file count.
} // ✓ Swift-only: closes kind statistic accumulator.
