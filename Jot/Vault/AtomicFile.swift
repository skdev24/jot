import Foundation

enum AtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let tmp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        let fd = open(tmp.path, O_RDONLY)
        if fd >= 0 {
            fsync(fd)
            close(fd)
        }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
            do {
                if fm.fileExists(atPath: coordinated.path) {
                    let result = try fm.replaceItemAt(coordinated, withItemAt: tmp)
                    if result == nil, fm.fileExists(atPath: tmp.path) {
                        try? fm.removeItem(at: tmp)
                    }
                } else {
                    try fm.moveItem(at: tmp, to: coordinated)
                }
            } catch {
                writeError = error
                try? fm.removeItem(at: tmp)
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    static func write(_ string: String, to url: URL) throws {
        try write(Data(string.utf8), to: url)
    }
}
