# Treemap port provenance

The annotated transition snapshots are preserved in Git at commit
`d8939636ecc87f1d0924e467bf530cdeb0b41332`. They recorded the original
Objective-C-to-Swift mapping with per-line `Z` and `Swift-only` comments.
The duplicate Swift files were removed from the working tree because they
were unused historical copies, not maintained implementations.

From the repository root, list the archived files:

```sh
git ls-tree -r --name-only d8939636ecc87f1d0924e467bf530cdeb0b41332 -- transition/treemap-z-provenance
```

Read an annotated snapshot without restoring obsolete source files:

```sh
git show d8939636ecc87f1d0924e467bf530cdeb0b41332:transition/treemap-z-provenance/TreemapViewRenderer.swift
```

Current rendering code lives in [disk_hog/Treemap](../../disk_hog/Treemap/).
Use the archived snapshots only to investigate the original port mapping;
do not reintroduce their per-line provenance comments into production code.
