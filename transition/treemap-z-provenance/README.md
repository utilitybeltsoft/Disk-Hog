# Treemap port provenance

The annotated transition snapshots are preserved in Git at commit
`378ece462ae7f39dd76d0a0eec5d61d9ede0845b`. They recorded the original
Objective-C-to-Swift mapping with per-line `Z` and `Swift-only` comments.
The duplicate Swift files were removed from the working tree because they
were unused historical copies, not maintained implementations.

From the repository root, list the archived files:

```sh
git ls-tree -r --name-only 378ece462ae7f39dd76d0a0eec5d61d9ede0845b -- transition/treemap-z-provenance
```

Read an annotated snapshot without restoring obsolete source files:

```sh
git show 378ece462ae7f39dd76d0a0eec5d61d9ede0845b:transition/treemap-z-provenance/TreemapViewRenderer.swift
```

Current rendering code lives in [disk_hog/Treemap](../../disk_hog/Treemap/).
Use the archived snapshots only to investigate the original port mapping;
do not reintroduce their per-line provenance comments into production code.
