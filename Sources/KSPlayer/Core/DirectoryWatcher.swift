//
//  DirectoryWatcher.swift
//  KSPlayer
//
//  Forward addition (RE): File system directory watcher using
//  DispatchSource for monitoring changes.
//
//  Binary: _TtC8KSPlayer16DirectoryWatcher (class metadata only)
//  RE source: Forward v1.3.15
//

import Foundation

public class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let url: URL
    private let queue: DispatchQueue

    public var onChange: (() -> Void)?

    public init(url: URL, queue: DispatchQueue = .global(qos: .utility)) {
        self.url = url
        self.queue = queue
    }

    public func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.onChange?()
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}
