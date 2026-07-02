import Foundation

/// Watches one file via a vnode DispatchSource and calls back (debounced, on
/// the main queue) after writes. Editors and atomic saves replace the file
/// (rename), so the watcher reopens the path when the vnode dies.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: CInt = -1
    private var debounce: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        open()
    }

    deinit {
        close()
    }

    private func open() {
        fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File missing right now (e.g. mid-rename): retry shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.open() }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if events.contains(.rename) || events.contains(.delete) {
                self.close()
                self.open()          // reattach to the new vnode at this path
            }
            self.fire()
        }
        source.setCancelHandler { [fd] in
            if fd >= 0 { Darwin.close(fd) }
        }
        source.resume()
        self.source = source
    }

    private func close() {
        source?.cancel()
        source = nil
        fd = -1
    }

    private func fire() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
