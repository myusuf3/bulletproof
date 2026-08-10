import Foundation

/// On-disk layout for downloaded models:
/// <root>/<org>/<name> for installed snapshots, <root>/<org>/<name>.partial
/// while a download is in flight. Installed == final directory exists.
nonisolated struct ModelStore: Sendable {
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bulletproof/Models", isDirectory: true)
    }

    func directory(for repoID: String) -> URL {
        root.appendingPathComponent(repoID, isDirectory: true)
    }

    func partialDirectory(for repoID: String) -> URL {
        root.appendingPathComponent("\(repoID).partial", isDirectory: true)
    }

    func isInstalled(_ repoID: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: directory(for: repoID).path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func installedModelIDs() -> [String] {
        let fm = FileManager.default
        guard let orgs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var ids: [String] = []
        for org in orgs where org.hasDirectoryPath {
            let names = (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for name in names where name.hasDirectoryPath && !name.lastPathComponent.hasSuffix(".partial") {
                ids.append("\(org.lastPathComponent)/\(name.lastPathComponent)")
            }
        }
        return ids.sorted()
    }

    func sizeOnDisk(of repoID: String) -> Int64 {
        directorySize(directory(for: repoID))
    }

    func totalSizeOnDisk() -> Int64 {
        installedModelIDs().reduce(0) { $0 + sizeOnDisk(of: $1) }
    }

    func availableDiskSpace() -> Int64? {
        // The models root doesn't exist until the first download; capacity is
        // per-volume, so any existing directory answers the same question.
        let target = FileManager.default.fileExists(atPath: root.path)
            ? root
            : FileManager.default.homeDirectoryForCurrentUser
        let values = try? target.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    func delete(_ repoID: String) throws {
        try FileManager.default.removeItem(at: directory(for: repoID))
    }

    /// Promotes a completed download without a remove-then-move gap - a crash
    /// there would strand the finished download as .partial for
    /// cleanupPartials() to delete.
    func finalize(_ repoID: String) throws {
        let fm = FileManager.default
        let final = directory(for: repoID)
        let partial = partialDirectory(for: repoID)
        if fm.fileExists(atPath: final.path) {
            _ = try fm.replaceItemAt(final, withItemAt: partial)
        } else {
            try fm.moveItem(at: partial, to: final)
        }
    }

    /// Removes leftovers from downloads interrupted by a crash or quit.
    func cleanupPartials() {
        let fm = FileManager.default
        guard let orgs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }
        for org in orgs where org.hasDirectoryPath {
            let names = (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for name in names where name.lastPathComponent.hasSuffix(".partial") {
                try? fm.removeItem(at: name)
            }
        }
    }

    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}
