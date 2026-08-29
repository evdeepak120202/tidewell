import Foundation
import CoreServices

/// Watches a set of folders and reports when their contents change.
///
/// FSEvents rather than a timer: the kernel already knows when a directory changed,
/// so an always-running app has no business polling. At idle this costs nothing.
///
/// Events are coalesced by a debounce because a single download produces a burst —
/// create, several writes, rename off `.crdownload` — and filing should happen once,
/// after the burst, not five times during it.
@MainActor
public final class FolderWatcher {

    /// Called with the folders that changed, after the burst has settled.
    public var onChange: (@MainActor ([URL]) -> Void)?

    /// How long the folder must be quiet before the callback fires.
    public var debounce: Duration = .seconds(2)

    private var stream: FSEventStreamRef?
    private var watched: [URL] = []
    private var pending: Set<URL> = []
    private var debounceTask: Task<Void, Never>?

    public init() {}

    // `isolated deinit` (Swift 6.2): the stream is main-actor state, so tearing it
    // down here requires the deinit to run on the main actor too.
    isolated deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    public var isRunning: Bool { stream != nil }

    /// Replace the watch set. Safe to call repeatedly; rebuilds only when it differs.
    public func watch(_ folders: [URL]) {
        let unique = Array(Set(folders.map(\.standardizedFileURL)))
        guard unique.map(\.path).sorted() != watched.map(\.path).sorted() else { return }
        stop()
        watched = unique
        guard !unique.isEmpty else { return }
        start()
    }

    public func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        pending.removeAll()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func start() {
        let paths = watched.map(\.path) as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        // kFSEventStreamCreateFlagFileEvents gives per-file granularity; without it
        // FSEvents reports only that "something under this path changed".
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagIgnoreSelf
        )

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info,
                  let cfPaths = unsafeBitCast(paths, to: CFArray.self) as? [String]
            else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = Array(cfPaths.prefix(count))

            // The stream is scheduled on the main queue below, so this callback is
            // already running on the main thread.
            MainActor.assumeIsolated { watcher.absorb(changed) }
        }

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, flags
        ) else { return }

        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
        stream = created
    }

    /// Map changed paths back to the watched folder that owns them, then debounce.
    private func absorb(_ changedPaths: [String]) {
        for path in changedPaths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard let owner = watched.first(where: {
                url.path == $0.path || url.deletingLastPathComponent().path == $0.path
            }) else { continue }
            // Only immediate children matter — the organiser never recurses, so a
            // change deep inside Images/2026-08 is not our business.
            pending.insert(owner)
        }
        guard !pending.isEmpty else { return }

        debounceTask?.cancel()
        let wait = debounce
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, !self.pending.isEmpty else { return }
            let batch = Array(self.pending)
            self.pending.removeAll()
            self.onChange?(batch)
        }
    }
}
