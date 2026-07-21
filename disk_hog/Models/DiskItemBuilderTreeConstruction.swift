import Foundation

extension DiskItemBuilder {
    nonisolated func appendChild(_ child: DiskItemBuilder, updateSize: Bool = true) {
        childStorage.append(child)

        if updateSize {
            allocatedSizeValue += child.allocatedSizeValue
            logicalSizeValue += child.logicalSizeValue
        }
    }

    nonisolated func removeAllChildren() {
        childStorage.removeAll()
        allocatedSizeValue = 0
        logicalSizeValue = 0
    }

    @discardableResult
    nonisolated func recalculateSize(usePhysicalSize: Bool) -> UInt64 {
        switch itemType {
        case .fileOrFolder:
            recalculateFileOrFolderSize(usePhysicalSize: usePhysicalSize)
        case .otherSpace, .freeSpace:
            break
        }

        return sizeValue(usePhysicalSize: usePhysicalSize)
    }

    nonisolated private func recalculateFileOrFolderSize(usePhysicalSize: Bool) {
        guard isFolder else {
            if isHardlinkDuplicate {
                allocatedSizeValue = 0
                logicalSizeValue = 0
            }
            return
        }

        if childStorage.isEmpty && isPackage && allocatedSizeValue > 0 {
            return
        }

        var allocatedSize: UInt64 = 0
        var logicalSize: UInt64 = 0
        #if SCAN_PERFORMANCE_PROFILING
        let childRecalculationStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        #endif

        for child: DiskItemBuilder in itemChildren {
            child.recalculateSize(usePhysicalSize: usePhysicalSize)
            allocatedSize += child.allocatedSizeValue
            logicalSize += child.logicalSizeValue
        }
        #if SCAN_PERFORMANCE_PROFILING
        ScanPerformanceRecorder.shared.addTime(
            "recalculate.children.total",
            seconds: CFAbsoluteTimeGetCurrent() - childRecalculationStartTime
        )
        #endif

        allocatedSizeValue = allocatedSize
        logicalSizeValue = logicalSize
        #if SCAN_PERFORMANCE_PROFILING
        let sortStartTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        #endif
        sortChildrenInDiskInventoryZOrder(recursive: false, usePhysicalSize: usePhysicalSize)
        #if SCAN_PERFORMANCE_PROFILING
        ScanPerformanceRecorder.shared.addTime(
            "recalculate.sort.total",
            seconds: CFAbsoluteTimeGetCurrent() - sortStartTime
        )
        #endif
    }
}
