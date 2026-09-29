import Foundation

/// Watches one file for changes, including the rename-into-place saves most
/// editors do (which replace the inode the watcher was attached to).
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var lastSignature: (date: Date?, size: Int)?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        lastSignature = signature()
        arm()
        armDirectory()
    }

    deinit {
        source?.cancel()
        directorySource?.cancel()
    }

    private func arm() {
        source?.cancel()
        source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib, .revoke], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let events = src.data
            if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
                // The file was replaced or removed; re-attach to whatever now lives at the path.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.arm() }
            }
            noteChange()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    /// Directory events catch the new file appearing after an atomic save even
    /// if the old inode's events were missed.
    private func armDirectory() {
        let fd = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            if source == nil { arm() }
            noteChange()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        directorySource = src
    }

    private func noteChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let now = signature()
            guard now.size != lastSignature?.size || now.date != lastSignature?.date else { return }
            lastSignature = now
            onChange()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func signature() -> (date: Date?, size: Int) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date, (attributes?[.size] as? NSNumber)?.intValue ?? -1)
    }

    /// Call after the app itself wrote the file, so its own save is not reported.
    func acknowledgeOwnWrite() {
        lastSignature = signature()
    }
}
