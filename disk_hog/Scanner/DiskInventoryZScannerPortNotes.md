# Disk Inventory Z Scanner Port Notes

Phase 3 ports the scanner path used by Disk Inventory Z:

- `FileSystemDoc.m` `startBackgroundScanForURL:`
- `FileSystemDoc.m` `runTopLevelOrchestrationForURL:usePhysicalSize:showPackageContents:`
- `FSItem.m` private `initWithURL:parent:setKindString:usePhysicalSize:`
- `FSItem.m` `loadChildrenAndSetKindStrings:usePhysicalSize:`
- `FSItem.m` `setKindStringIncludingChildren:`
- `NSURL-Extensions.m` firmlink and resource-value helper behavior

The goal is mechanical parity. Intentional translation differences are listed here.

## Translation Differences

1. Objective-C retain/release/autorelease calls are omitted.
   Swift ARC owns object lifetimes.

2. `FSItem` is represented by `DiskItem`.
   The field mapping is direct: URL, weak parent, children, item type, size, kind name, directory/package/alias/hardlink flags.

3. `NSException` cancellation is translated to `Task.checkCancellation()` and `CancellationError`.
   Swift does not use exceptions for ordinary cancellation.

4. Z's `NSURL` temporary resource-value cache is translated to repeated `URLResourceValues` reads.
   This is the closest pure-Swift Foundation equivalent. If scanner time remains meaningfully slower, this is the first candidate for an Objective-C bridge.

5. Z's firmlink file loader is ported in `DiskInventoryZFirmlinkTable`.
   Swift stores standardized path strings rather than `NSURL` dictionary keys.

6. Z's 64-entry continuation poll is preserved as a cancellation/progress checkpoint.
   UI publication remains time-gated to 0.25 seconds, matching `maybeRefreshScanCheckpoint`.

7. Z can splice completed top-level orphans into `_rootItem` on main.
   Disk Hog currently publishes the completed root after the worker finishes, because this phase still has placeholder outline/treemap UI. The scan tree shape and diagnostics input remain the same.

8. Z asks `UTType.localizedDescription` by cached UTI and then falls back to `NSURLLocalizedTypeDescriptionKey`.
   Disk Hog does the same in `DiskInventoryZKindResolver`.

9. Z's opaque package sizing uses `NSURLTotalFileAllocatedSizeKey` or `NSURLFileAllocatedSizeKey`.
   Disk Hog mirrors those keys for package internals.

10. Z's top-level orchestration uses public `initWithURL:` for detached orphans, but the same method does not stamp file size or kind; Z's own comment says top-level regular-file size is already set in init.
    Disk Hog uses the private initializer's effective behavior for top-level scanned entries so top-level files receive the size/kind data that Z's diagnostics require.
