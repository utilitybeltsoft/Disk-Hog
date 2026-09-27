import Foundation

nonisolated enum FilePathContainment {
    /// Lexical containment, including the directory itself, with a separator
    /// boundary so /folder-other is not inside /folder. Callers supply paths in
    /// the same representation: this does not standardize paths, resolve symlinks,
    /// fold case, or access the filesystem. Tree identities must stay unchanged;
    /// filesystem policy callers perform their own normalization first.
    static func contains(_ candidatePath: String, in directoryPath: String) -> Bool {
        if candidatePath == directoryPath { return true }
        let prefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        return candidatePath.hasPrefix(prefix)
    }
}
