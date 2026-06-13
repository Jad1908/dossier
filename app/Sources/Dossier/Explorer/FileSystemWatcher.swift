import Foundation
import CoreServices

// Watches a directory tree for on-disk changes — a file added, removed, or
// renamed anywhere under `url`, by this app or any other process — and fires
// `onChange` on the main queue, coalesced. Keeps the file explorer in sync with
// reality so files that appear outside the in-app actions become usable without
// reopening the project (DESKTOP_APP_SPEC §7).
//
// Backed by FSEvents, which is recursive by nature: one stream covers the whole
// project. The watcher owns the stream for its lifetime; drop it to stop.
final class FileSystemWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        // The C callback hops back to the Swift instance through `info`.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileSystemWatcher>.fromOpaque(info)
                .takeUnretainedValue()
                .onChange()
        }

        // 0.3s latency coalesces bursts (a checkout or build touching many
        // files fires once, not hundreds of times).
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
                                     | kFSEventStreamCreateFlagNoDefer))
        else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
