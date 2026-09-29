//
//  Utility.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import CryptoKit
import SwiftUI
import Dispatch
import Foundation

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
#if canImport(MobileCoreServices)
import MobileCoreServices.UTType
#endif

final class GIFCreator {
    private let destination: CGImageDestination
    private let frameProperties: CFDictionary
    private(set) var firstImage: UIImage?
    init(savePath: URL, imagesCount: Int) {
        try? FileManager.default.removeItem(at: savePath)
        frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.25]] as CFDictionary
        destination = CGImageDestinationCreateWithURL(savePath as CFURL, kUTTypeGIF, imagesCount, nil)!
        let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
    }

    func add(image: CGImage) {
        if firstImage == nil {
            firstImage = UIImage(cgImage: image)
        }
        CGImageDestinationAddImage(destination, image, frameProperties)
    }

    func finalize() -> Bool {
        let result = CGImageDestinationFinalize(destination)
        return result
    }
}

public extension String {
    static func systemClockTime(second: Bool = false) -> String {
        let date = Date()
        let calendar = Calendar.current
        let component = calendar.dateComponents([.hour, .minute, .second], from: date)
        if second {
            return String(format: "%02i:%02i:%02i", component.hour!, component.minute!, component.second!)
        } else {
            return String(format: "%02i:%02i", component.hour!, component.minute!)
        }
    }

    /// 把字符串时间转为对应的秒
    /// - Parameter fromStr: srt 00:02:52,184 ass 0:30:11.56 vtt 00:00.430
    /// - Returns: 秒
    func parseDuration() -> TimeInterval {
        let scanner = Scanner(string: self)

        var hour: Double = 0
        if split(separator: ":").count > 2 {
            hour = scanner.scanDouble() ?? 0.0
            _ = scanner.scanString(":")
        }

        let min = scanner.scanDouble() ?? 0.0
        _ = scanner.scanString(":")
        let sec = scanner.scanDouble() ?? 0.0
        // Forward 0x1019f0b70: no ","/"." millisecond scan — the cue scanner already rewrote "," to ".",
        // so `sec` carries the fraction. Sum is hour*3600 + min*60 + sec.
        return (hour * 3600.0) + (min * 60.0) + sec
    }

    func md5() -> String {
        Data(utf8).md5()
    }
}

extension AVAsset {
    public func generateGIF(beginTime: TimeInterval, endTime: TimeInterval, interval: Double = 0.2, savePath: URL, progress: @escaping (Double) -> Void, completion: @escaping @Sendable (Error?) -> Void) { // ⚑[tool=member_surface ref=AVAsset.generateGIF:0x1019e5948 result=completion Yb @Sendable; no swift_task_*/ScM call]
        let count = Int(ceil((endTime - beginTime) / interval))
        let timesM = (0 ..< count).map { NSValue(time: CMTime(seconds: beginTime + Double($0) * interval)) }
        let imageGenerator = createImageGenerator()
        let gifCreator = GIFCreator(savePath: savePath, imagesCount: count)
        var i = 0
        imageGenerator.generateCGImagesAsynchronously(forTimes: timesM) { _, imageRef, _, result, error in
            switch result {
            case .succeeded:
                guard let imageRef else { return }
                i += 1
                gifCreator.add(image: imageRef)
                progress(Double(i) / Double(count))
                guard i == count else { return }
                if gifCreator.finalize() {
                    completion(nil)
                } else {
                    let error = NSError(domain: AVFoundationErrorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: "Generate Gif Failed!"])
                    completion(error)
                }
            case .failed:
                if let error {
                    completion(error)
                }
            case .cancelled:
                break
            @unknown default:
                break
            }
        }
    }

    private func createComposition(beginTime: TimeInterval, endTime: TimeInterval) async throws -> AVMutableComposition {
        let compositionM = AVMutableComposition()
        let audioTrackM = compositionM.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let videoTrackM = compositionM.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let cutRange = CMTimeRange(start: beginTime, end: endTime)
        #if os(xrOS)
        if let assetAudioTrack = try await loadTracks(withMediaType: .audio).first {
            try audioTrackM?.insertTimeRange(cutRange, of: assetAudioTrack, at: .zero)
        }
        if let assetVideoTrack = try await loadTracks(withMediaType: .video).first {
            try videoTrackM?.insertTimeRange(cutRange, of: assetVideoTrack, at: .zero)
        }
        #else
        if let assetAudioTrack = tracks(withMediaType: .audio).first {
            try audioTrackM?.insertTimeRange(cutRange, of: assetAudioTrack, at: .zero)
        }
        if let assetVideoTrack = tracks(withMediaType: .video).first {
            try videoTrackM?.insertTimeRange(cutRange, of: assetVideoTrack, at: .zero)
        }
        #endif
        return compositionM
    }

    func createExportSession(beginTime: TimeInterval, endTime: TimeInterval) async throws -> AVAssetExportSession? {
        let compositionM = try await createComposition(beginTime: beginTime, endTime: endTime)
        guard let exportSession = AVAssetExportSession(asset: compositionM, presetName: "") else {
            return nil
        }
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.outputFileType = .mp4
        return exportSession
    }

    func exportMp4(beginTime: TimeInterval, endTime: TimeInterval, outputURL: URL, progress: @escaping @Sendable (Double) -> Void, completion: @escaping @Sendable (Result<URL, Error>) -> Void) throws {
        try FileManager.default.removeItem(at: outputURL)
        nonisolated(unsafe) let asset = self
        Task {
            guard let exportSession = try await asset.createExportSession(beginTime: beginTime, endTime: endTime) else { return }
            exportSession.outputURL = outputURL
            await exportSession.export()
            switch exportSession.status {
            case .exporting:
                progress(Double(exportSession.progress))
            case .completed:
                progress(1)
                completion(.success(outputURL))
                exportSession.cancelExport()
            case .failed:
                if let error = exportSession.error {
                    completion(.failure(error))
                }
                exportSession.cancelExport()
            case .cancelled:
                exportSession.cancelExport()
            case .unknown, .waiting:
                break
            @unknown default:
                break
            }
        }
    }

    func exportMp4(beginTime: TimeInterval, endTime: TimeInterval, progress: @escaping @Sendable (Double) -> Void, completion: @escaping @Sendable (Result<URL, Error>) -> Void) throws {
        guard var exportURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        exportURL = exportURL.appendingPathExtension("Export.mp4")
        try exportMp4(beginTime: beginTime, endTime: endTime, outputURL: exportURL, progress: progress, completion: completion)
    }
}

extension UIImageView {
    func image(url: URL?) {
        guard let url else { return }
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let data = try? Data(contentsOf: url)
            let image = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.image = image
            }
        }
    }
}

#if canImport(UIKit)
extension AVPlayer.HDRMode {
    var dynamicRange: DynamicRange {
        if contains(.dolbyVision) {
            return .dolbyVision
        } else if contains(.hlg) {
            return .hlg
        } else if contains(.hdr10) {
            return .hdr10
        } else {
            return .sdr
        }
    }
}
#endif

public extension FourCharCode {
    var string: String {
        // Forward 0x101a03e58: `rev` of self stored at sp+0x28 = (sp+8)+0x20 — the element base of a
        // header-less ("bare") stack array object — then String._fromUTF8Repairing(count: 4); no NUL
        // byte, no Int8 range traps, no stack protector. A 4-byte [UInt8] literal decoded as UTF-8.
        let bytes: [UInt8] = [
            UInt8(self >> 24 & 0xFF),
            UInt8(self >> 16 & 0xFF),
            UInt8(self >> 8 & 0xFF),
            UInt8(self & 0xFF),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}

extension CMTime {
    init(seconds: TimeInterval) {
        // Forward passes a NANOsecond timescale here, not USEC_PER_SEC — a factor of 1000.
        // Read at the inlined site inside KSAVPlayer.seek(time:completion:) @0x1019a4300
        // (extent 0x1019a4300-0x1019a47e4). KSAVPlayer.swift:381 calls the ONE-argument
        // `CMTime(seconds: time)`, i.e. this init, and it lowers to:
        //   0x1019a46a8  mov.16b v0, v8              d0 = seconds
        //   0x1019a46ac  mov     w0, #0xca00
        //   0x1019a46b0  movk    w0, #0x3b9a, lsl #16   w0 = 0x3B9ACA00 = 1_000_000_000
        //   0x1019a46b4  bl      0x103458560          stub -> __got 0x1041132c8 ->
        //     `_$sSo6CMTimea9CoreMediaE7seconds18preferredTimescaleABSd_s5Int32VtcfC`
        //     = CMTime.init(seconds: Double, preferredTimescale: Int32)
        // Spelled as the literal to match the sibling call sites that already pass this
        // timescale explicitly (AudioRendererPlayer.swift:107 and :142).
        self.init(seconds: seconds, preferredTimescale: 1_000_000_000)
    }
}

extension CMTimeRange {
    init(start: TimeInterval, end: TimeInterval) {
        self.init(start: CMTime(seconds: start), end: CMTime(seconds: end))
    }
}

extension CGPoint {
    var reverse: CGPoint {
        CGPoint(x: y, y: x)
    }
}

extension CGSize {
    var reverse: CGSize {
        @used get { CGSize(width: height, height: width) }
    }

    var toPoint: CGPoint {
        CGPoint(x: width, y: height)
    }

    var isHorizonal: Bool {
        width > height
    }
}

// Forward 0x1019e76c4 `CGSize.string.getter`: Int(width) + "x" + Int(height) (trapping Int
// conversions). Callers: IOSVideoPlayerView.getVideoMeta() and ProAVPlayer 0x101b6c180.
public extension CGSize {
    var string: String {
        "\(Int(width))x\(Int(height))"
    }
}

func * (left: CGSize, right: CGFloat) -> CGSize {
    CGSize(width: left.width * right, height: left.height * right)
}

func * (left: CGPoint, right: CGFloat) -> CGPoint {
    CGPoint(x: left.x * right, y: left.y * right)
}

func * (left: CGRect, right: CGFloat) -> CGRect {
    CGRect(origin: left.origin * right, size: left.size * right)
}

// 0x1019e7b40 (228i, Forward Utility.swift): x0 = [CGRect], result CGRect in d0-d3; min(minX)/min(minY)/max(maxX)/
// max(maxY) over the array, .zero when empty. Called by AssImageRenderer.search 0x101a93b14 (`bl 0x1019e7b40`).
// Not exported → internal.
extension Array where Element == CGRect {
    var boundingRect: CGRect { // INFERRED
        guard let minX = map(\.minX).min(), let minY = map(\.minY).min(), let maxX = map(\.maxX).max(), let maxY = map(\.maxY).max() else {
            return .zero
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

func - (left: CGSize, right: CGSize) -> CGSize {
    CGSize(width: left.width - right.width, height: left.height - right.height)
}

@inline(__always)
public func runOnMainThread(block: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block, file: "KSPlayer/Utility.swift", line: 22)
    } else {
        Task {
            await MainActor.run(body: block)
        }
    }
}

/// Allows to "box" another value.
final class Box<T> {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

extension Array {
    init(tuple: (Element, Element, Element, Element, Element, Element, Element, Element)) {
        self.init([tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, tuple.5, tuple.6, tuple.7])
    }

    init(tuple: (Element, Element, Element, Element)) {
        self.init([tuple.0, tuple.1, tuple.2, tuple.3])
    }

    var tuple8: (Element, Element, Element, Element, Element, Element, Element, Element) {
        (self[0], self[1], self[2], self[3], self[4], self[5], self[6], self[7])
    }

    var tuple4: (Element, Element, Element, Element) {
        (self[0], self[1], self[2], self[3])
    }

    // 归并排序才是稳定排序。系统默认是快排
    func mergeSortBottomUp(isOrderedBefore: (Element, Element) -> Bool) -> [Element] {
        let n = count
        var z = [self, self] // the two working arrays
        var d = 0 // z[d] is used for reading, z[1 - d] for writing
        var width = 1
        while width < n {
            var i = 0
            while i < n {
                var j = i
                var l = i
                var r = i + width

                let lmax = Swift.min(l + width, n)
                let rmax = Swift.min(r + width, n)

                while l < lmax, r < rmax {
                    if isOrderedBefore(z[d][l], z[d][r]) {
                        z[1 - d][j] = z[d][l]
                        l += 1
                    } else {
                        z[1 - d][j] = z[d][r]
                        r += 1
                    }
                    j += 1
                }
                while l < lmax {
                    z[1 - d][j] = z[d][l]
                    j += 1
                    l += 1
                }
                while r < rmax {
                    z[1 - d][j] = z[d][r]
                    j += 1
                    r += 1
                }

                i += width * 2
            }

            width *= 2 // in each step, the subarray to merge becomes larger
            d = 1 - d // swap active array
        }
        return z[d]
    }
}

//  Binary-faithful reconstruction (Forward 1.3.17, KSPlayer module).
//  Fires on HLS-segment directory changes; consumed later by HLSCacheIOContext.
//  Provenance / scope (honest 5-of-9 vtable coverage):
//    - `DirectoryWatcher` is a Swift `actor` — slot-4 init calls
//      `_swift_defaultActor_initialize()` (the executor-init the compiler
//      synthesizes for `actor`); we declare `actor` and do NOT emit that call
//      or the `$defaultActor` ivar ourselves.
//    - ONE real stored field: `source` @ +0x70 (binary __swift5_fieldmd, after
//      filtering the synthesized actor-executor ivar). Type taken from the
//      makeFileSystemObjectSource call in slots 5/6 (the binary wins; its
//      property descriptor is stripped → l2_field_gate marks it UNCHECKED).
//    - Slots 0–2 are `source`'s getter/setter/read accessors — SYNTHESIZED by
//      declaring the stored `var source`; nothing is written for them.
//    - Slots 3 (isWatching), 4 (init), 7 (stop) are small + fully reconstructed.
//    - Slots 5 & 6 are substantive (379 / 434 instr): the observable SPINE
//      (open → makeFileSystemObjectSource(eventMask:) → setEventHandler /
//      setCancelHandler → activate → store source) is reconstructed faithfully;
//      the event/cancel-handler CLOSURE INTERNALS are not cleanly recoverable
//      from the decompile and are left `// UNRESOLVED` with compiling stubs
//      (fabricating 379 instr of closure logic is the cardinal failure).
//    - All method NAMES are INFERRED — every slot is devirtualized (no symbols).
//      ⚠️ s97: FALSE for slot 3. The orphaned export trie names it outright —
//      `$s8KSPlayer16DirectoryWatcherC10isWatchingSbvg` = DirectoryWatcher.isWatching.getter :
//      Swift.Bool, one symbol at 0x101a04e10, not folded. The blanket "no symbols" claim came from
//      a tool that cannot see that trie; re-check the other slots against it before trusting them.
//    - Slot 8 (descriptor 0x1039ee5b0, Impl dead-stripped) is the method the event-handler Tasks
//      call; its inlined body is `source = nil` (0x101a05698..0x101a056a4). Name INFERRED.
/// Watches an HLS-segment directory (or a not-yet-existing file's container)
/// via a `DispatchSource` file-system-object source, firing a caller-supplied
/// handler on `.write` / `.delete` events.
///
/// `actor` (binary: init calls `_swift_defaultActor_initialize`). Mangled
/// `_TtC8KSPlayer16DirectoryWatcher`. Method names below are INFERRED — the
/// vtable is devirtualized so no symbol survives.
// P3b: `public` — the Forward-new ProAVPlayer module (a separate SPM target) references this type
// cross-module (RemuxerIOAction/ConversionInfo hold a `directoryWatcher: DirectoryWatcher` field;
// field-record symref → KSPlayer.DirectoryWatcher desc 0x1039ee53c). A separate target can only see a
// public type, so Forward made it public. Type-level public suffices (members stay internal until M2).
public actor DirectoryWatcher {
    // FAITHFUL field (binary __swift5_fieldmd @ +0x70). Built by
    // `DispatchSource.makeFileSystemObjectSource(...)` in slots 5/6, whose static
    // return type is `any DispatchSourceFileSystemObject` → declared as such.
    // (Accessors = vtable slots 0–2, synthesized by this stored `var`.)
    // private: Forward pfi `source05_51A3…LL…vpfi` carries this file's private discriminator
    // _51A3A3F37FF8E3161AF3B4630C320057 = MD5("KSPlayer" + "Utility.swift").
    private var source: DispatchSourceFileSystemObject?   // @ +0x70

    // MARK: idx3 slot15 @0x101a04e10 — isWatching (4 instr) · name RECOVERED, not inferred (s97)
    // ⚑[tool=export_trie_oracle ref=KSPlayer.DirectoryWatcher.isWatching:0x101a04e10 result=name-recovered]

    /// `true` while a source is installed. Binary: `return *(self+0x70) != 0`.
    public var isWatching: Bool {
        return source != nil
    }

    // MARK: slot 4 @0x101a04e20 — init() (14 instr)

    /// Parameter-less designated init. Body sets `source = nil` only; the
    /// `_swift_defaultActor_initialize()` the binary emits here is the
    /// compiler-synthesized actor executor setup — NOT written by hand.
    public init() {                              // public (was internal, P34): ConversionInfo (ProAVPlayer) constructs it cross-module
        // Forward 0x101a04e58 stores *(self+0x70) = 0 exactly once — the stored `var source: …?`
        // implicit nil default; an explicit `source = nil` here emitted a second store.
    }

    // MARK: slot 5 @0x101a04e78 — watchModify(fileURL:completion:) (379 instr) · name RECOVERED (s109)

    /// Watches `fileURL`'s own path.
    ///
    /// ⚑ s109 RENAME + RE-SIGNATURE. This was `startWatching(url:handler:qos:)`, self-declared
    /// "name inferred" with labels "inferred (no symbol)". The trie names 0x101a04e78
    /// `KSPlayer.DirectoryWatcher.watchModify(fileURL: Foundation.URL, completion: @Sendable (Swift.Bool) -> ())`
    /// — so the name, both labels, the completion's `Bool` parameter, and the ARITY were all wrong.
    /// The old third parameter `qos: DispatchQoS` did not exist: the note above admitted it came
    /// from decompiler `param_3`, but the demangled signature takes two parameters and the
    /// `DispatchQoS` in the body is the argument to `DispatchQueue.global(qos:)`, not an input.
    @used package func watchModify(fileURL: URL, completion: @escaping @Sendable (Bool) -> Void) {
        // Tear down any existing source first (identical to stop()'s body —
        // binary inlines it at the top: cancel live source, then *(self+0x70)=0).
        source?.cancel()
        source = nil

        // open(fileURL.path, O_EVTONLY) — implicit String→pointer argument (Forward calls
        // String.utf8CString then open on its base, no withCString fast path). 0x8000 == O_EVTONLY.
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0, source == nil else { return }     // (-1 < fd) && *(self+0x70)==0

        // Forward evaluates eventMask ([.delete, .write]: element 0 = _get_delete, 1 = _get_write) before
        // DispatchQueue.global(qos: .default), which is an inline argument released right after the call.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.delete, .write], queue: DispatchQueue.global(qos: .default)
        )

        // setEventHandler — block @0x101a06254 forwards to the body @0x101a05464: weak-self load (return
        // when nil), NSFileManager `fileExistsAtPath:` passed straight to the completion, then close(fd).
        // The body then starts `Task { [weak self] in await self?.<slot 8>() }` (priority nil, fresh weak box
        // of the strong self, Task spec 0x101a03fd4, async fp 0x1035697f0) whose inlined callee does
        // `source = nil` only (0x101a05698).
        // ⚑[tool=bind_oracle ref=_OBJC_CLASS_$_NSFileManager:0x104410520 result=Foundation]
        source.setEventHandler { [weak self] in
            guard let self else { return }
            completion(FileManager.default.fileExists(atPath: fileURL.path))
            close(fd)
            Task { [weak self] in
                await self?.removeSource()
            }
        }
        // setCancelHandler — block @0x101a062b8 → 0x101a063ec: completion(false) then close(fd)
        // (context = completion fn/ctx + fd).
        source.setCancelHandler {
            completion(false)
            close(fd)
        }

        source.activate()                          // OS_dispatch_source.activate()
        self.source = source                       // *(self+0x70) = source; release old
    }

    // MARK: slot 6 @0x101a0578c — watchNew(fileURL:completion:) (434 instr) · name RECOVERED (s109)

    /// Watches the CONTAINER of `url` (its parent directory) — used to detect a
    /// not-yet-existing file appearing. Distinct vtable slot → a SECOND method.
    /// Same spine as `watchModify(fileURL:completion:)` but it derives the path
    /// via `url.deletingLastPathComponent().path` (keeping `lastPathComponent`)
    /// and the eventMask is `[.write]` ONLY (the decompile calls `_get_write`
    /// but NOT `_get_delete`, unlike slot 5).
    /// ⚑ s109 RENAME + RE-SIGNATURE, same as slot 5. The trie names 0x101a0578c
    /// `KSPlayer.DirectoryWatcher.watchNew(fileURL: Foundation.URL, completion: @Sendable (Swift.Bool) -> ())`.
    /// Name, labels, completion type and arity were all inferred and all wrong; there is no
    /// `qos:` parameter.
    @used func watchNew(fileURL: URL, completion: @escaping @Sendable (Bool) -> Void) {
        // Tear down any existing source first (inlined cancel + clear).
        source?.cancel()
        source = nil

        // lastPathComponent is captured (binary: get_lastPathComponent → SVar32,
        // retained across the call); the watched path is the parent directory.
        let lastPathComponent = fileURL.lastPathComponent
        let parent = fileURL.deletingLastPathComponent()   // URL.deletingLastPathComponent()

        // open(parent.path, O_EVTONLY) — implicit String→pointer argument (Forward: utf8CString + open).
        let fd = open(parent.path, O_EVTONLY)
        guard fd >= 0, source == nil else { return }       // fd<0 → cleanup+return; else needs *(self+0x70)==0

        // eventMask = [.write]  (binary slot 6: only _get_write — no _get_delete), evaluated before the
        // inline DispatchQueue.global(qos: .default) argument (Forward order).
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: DispatchQueue.global(qos: .default)
        )

        // setEventHandler — block @0x101a06364 forwards to the body @0x101a05e54: weak-self load (return
        // when nil), then `parent.appendingPathComponent(lastPathComponent)` + `fileExistsAtPath:`; only
        // the exists path calls completion(true) and close(fd). Context order: weak self, parent,
        // lastPathComponent, completion, fd.
        // The exists path then starts `Task { [weak self] in await self?.<slot 8>() }` (Task spec 0x101a03fd4,
        // async fp 0x1035697d8) whose inlined callee does `source = nil` only.
        // ⚑[tool=bind_oracle ref=Foundation.URL.appendingPathComponent:0x104109a70 result=appendingPathComponent]
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: parent.appendingPathComponent(lastPathComponent).path) {
                completion(true)
                close(fd)
                Task { [weak self] in
                    await self?.removeSource()
                }
            }
        }
        // setCancelHandler — block @0x101a07b58 is a thunk of 0x101a063ec (slot 5's cancel body):
        // completion(false) then close(fd).
        source.setCancelHandler {
            completion(false)
            close(fd)
        }

        source.activate()                          // OS_dispatch_source.activate()
        self.source = source                       // *(self+0x70) = source; release old
    }

    // MARK: slot 7 @0x101a06150 — stop (24 instr) · name inferred

    /// Cancels the installed source and clears it. Binary: if `source != nil`
    /// → retain, `OS_dispatch_source.cancel()`, release; then `source = nil`.
    // ⚑ s105 RENAME: was `stop()`, self-declared "name inferred". The trie names
    // 0x101a06150 `cancel()` and carries exactly ONE symbol there, and no `stop` symbol
    // exists on this class. Body unchanged — only the name was invented.
    // ⚑[tool=export_trie_oracle ref=DirectoryWatcher.cancel:0x101a06150 result=name-recovered]
    @used func cancel() {
        source?.cancel()                          // guarded cancel on the live source
        source = nil                              // *(self+0x70) = 0; release old
    }

    // MARK: slot 8 @descriptor 0x1039ee5b0 — Impl dead-stripped (VFE); only reached inlined from the
    // watchModify/watchNew event-handler Tasks (async fp 0x1035697f0 / 0x1035697d8), whose body after the
    // executor hop is: ldr x0,[self,#0x70]; str xzr,[self,#0x70]; release. Flags 0x10 = sync instance method.
    func removeSource() { // INFERRED name — evidence: vtable slot 8 descriptor 0x1039ee5b0, inlined body 0x101a05698
        source = nil
    }

    // Forward deinit 0x101a0641c / __deallocating_deinit 0x101a06488 (27 insns each): load +0x70; when
    // non-nil retain, OS_dispatch_source.cancel(), release; then the field release + defaultActor_destroy.
    deinit {
        source?.cancel()
    }
}

public extension Dictionary {
    mutating func value(for key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        if let value = self[key] {
            return value
        } else {
            let value = defaultValue()
            self[key] = value
            return value
        }
    }
}

public extension URL {
    var isMovie: Bool {
        if let typeID = try? resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier as CFString? {
            return UTTypeConformsTo(typeID, kUTTypeMovie)
        }
        // Forward 0x1019f28f0 falls back to a 23-entry static [String] (object @0x1044e7128, raw Mach-O read).
        return ["3gp", "aac", "aiff", "alac", "avi", "flac", "flv", "iso", "m3u8", "m4a", "m4v", "mkv", "mov", "mp3", "mp4", "mpg", "ogg", "opus", "ts", "wav", "webm", "wma", "wmv"].contains(pathExtension.lowercased())
    }

    var isAudio: Bool {
        if let typeID = try? resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier as CFString? {
            return UTTypeConformsTo(typeID, kUTTypeAudio)
        }
        return false
    }

    var isSubtitle: Bool {
        // Forward 1.3.17 added "sup" (PGS) — binary static ext-array @0x1044e72c0 = [ass,srt,ssa,vtt,sup]
        // (session 19; recon base had 4; decoded via the DirectorySubtitleDataSource.searchSubtitle filter).
        ["ass", "srt", "ssa", "vtt", "sup"].contains(pathExtension.lowercased())
    }

    var isPlaylist: Bool {
        ["cue", "m3u", "pls"].contains(pathExtension.lowercased())
    }

    func parsePlaylist() async throws -> [(String, URL, [String: String])] {
        let data = try await data()
        var entrys = data.parsePlaylist()
        for i in 0 ..< entrys.count {
            var entry = entrys[i]
            if entry.1.path.hasPrefix("./") {
                entry.1 = deletingLastPathComponent().appendingPathComponent(entry.1.path).standardized
                entrys[i] = entry
            }
        }
        return entrys
    }

    func data(userAgent: String? = nil) async throws -> Data {
        if isFileURL {
            return try Data(contentsOf: self)
        } else {
            var request = URLRequest(url: self)
            if let userAgent {
                request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        }
    }
    public func string(userAgent: String?, encoding: String.Encoding?) async throws -> String? {
        let data = try await data(userAgent: userAgent)
        var string: String?
        let encodes = [encoding ?? String.Encoding.utf8,
                       String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))),
                       String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
                       String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsHebrew.rawValue))),
                       String.Encoding.unicode]
        for encode in encodes {
            string = String(data: data, encoding: encode)
            if string != nil {
                break
            }
        }
        return string
    }

    // ⚑[tool=member_surface ref=URL.download:0x1019f457c result=completion Yb @Sendable; no swift_task_*/ScM call]
    func download(userAgent: String? = nil, completion: @escaping @Sendable (String, URL) -> Void) {
        var request = URLRequest(url: self)
        if let userAgent {
            request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        let task = URLSession.shared.downloadTask(with: request) { url, response, _ in
            guard let url, let response else {
                return
            }
            // 下载的临时文件要马上就用。不然可能会马上被清空
            completion(response.suggestedFilename ?? url.lastPathComponent, url)
        }
        task.resume()
    }

    func relativePath(base: URL) -> String {
        guard scheme == base.scheme, host == base.host else {
            return path
        }
        let baseComponents = base.standardized.pathComponents
        let components = standardized.pathComponents
        var i = 0
        while i < baseComponents.count, i < components.count, baseComponents[i] == components[i] {
            i += 1
        }
        return components[i...].joined(separator: "/")
    }
    public func parseSubtitle(userAgent: String?, encoding: String.Encoding?) async throws -> (KSSubtitleProtocol, SubtitleRenderMode) {
        if pathExtension == "sup" {
            return (try FFmpegSubtitle(url: self), .image)
        }
        guard let string = try await string(userAgent: userAgent, encoding: encoding) else {
            return (try FFmpegSubtitle(url: self), .image)
        }
        let scanner = Scanner(string: string)
        _ = scanner.scanCharacters(from: .controlCharacters)
        let parse = KSOptions.subtitleParses.first { $0.canParse(scanner: scanner) }
        guard let parse else {
            throw KSPlayerError(code: 0, description: "Current subtitle format is not supported")
        }
        let renderMode: SubtitleRenderMode
        if parse is SrtParse {
            renderMode = .srtView
        } else if parse is AssParse {
            renderMode = .assView
        } else {
            renderMode = .image
        }
        return (try parse.parse(url: self, scanner: scanner), renderMode)
    }

    // The string Forward hands to FFmpeg for a URL. 232 B / 58 instr @0x1019f59c4.
    // ⚑[tool=export_trie_oracle ref=$s10Foundation3URLV8KSPlayerE12ffmpegStringSSvg:0x1019f59c4 result=public-get-only]
    // public: the trie carries `vg` AND the `vpMV` property descriptor. Get-only: a whole-trie prefix
    // walk finds exactly TWO ffmpegString symbols — no `vs`, no `vM`, no `vpfi`. Not folded.
    // Body, read instruction by instruction and with every callee resolved through its stub's __got
    // slot in `llvm-objdump --macho --bind`:
    //   0x1019f59d8  bl → __got 0x1041099d0 = Foundation.URL.isFileURL.getter; `tbz w0,#0` splits.
    //   0x1019f59f0  the true arm is a TAIL `b` → __got 0x104109ac8 = Foundation.URL.path.getter.
    //   0x1019f59f4  bl → __got 0x104109a10 = Foundation.URL.absoluteString.getter. Its value is
    //                held in x21/x19 and returned on EVERY remaining exit. It is called ONCE, and a
    //                `scheme` getter call sits between the uses, so the optimiser could not have
    //                merged three separate reads — one call means one source-level access, i.e. a
    //                local binding rather than three `absoluteString` mentions.
    //   0x1019f5a00  bl → __got 0x104109ae8 = Foundation.URL.scheme.getter; `cbz x1` sends nil
    //                straight to the binding, which is how `Optional == "ftp"` compiles.
    //   "ftp" is a Swift small string, not a __cstring: w8 = 0x00707466 ('f','t','p') with
    //                discriminator 0xe3 (count 3). Compared inline at 0x1019f5a10/0x1019f5a1c, then
    //                via __got 0x104112638 = Swift._stringCompareWithSmolCheck with w4 = 0
    //                (`expecting: .equal`) on the slow path.
    //   0x1019f5a70  bl → __got 0x10410a668 = (extension in Foundation):StringProtocol
    //                .removingPercentEncoding.getter, handed the String metadata (0x104111500 =
    //                `_$sSSN`) and the String : StringProtocol witness table from the one-time cache
    //                at 0x1019c46e0. `cbz x1` falls back to the binding — that is the `??`.
    // ⚑ The local's NAME is not in the binary; `string` is recon-chosen (P28). Everything else is read.
    var ffmpegString: String {
        if isFileURL {
            return path
        }
        let string = absoluteString
        if scheme == "ftp" {
            return string.removingPercentEncoding ?? string
        }
        return string
    }
}

public extension Data {
    func parsePlaylist() -> [(String, URL, [String: String])] {
        guard let string = String(data: self, encoding: .utf8) else {
            return []
        }
        let scanner = Scanner(string: string)
        var entrys = [(String, URL, [String: String])]()
        guard let symbol = scanner.scanUpToCharacters(from: .newlines) else {
            return []
        }
        if symbol.contains("#EXTM3U") {
            while !scanner.isAtEnd {
                if let entry = scanner.parseM3U() {
                    entrys.append(entry)
                }
            }
        } else if symbol.contains("[playlist]") {
            // Forward 0x1019e8f2c: `bl 0x1019eefdc` with x20 = scanner; its result is the return value.
            entrys = scanner.parsePls()
        }
        return entrys
    }

    func md5() -> String {
        let digestData = Insecure.MD5.hash(data: self)
        return String(digestData.map { String(format: "%02hhx", $0) }.joined().prefix(32))
    }
}

extension Scanner {
    /*
     #EXTINF:-1 tvg-id="ExampleTV.ua" tvg-logo="https://image.com" group-title="test test", Example TV (720p) [Not 24/7]
     #EXTVLCOPT:http-referrer=http://example.com/
     #EXTVLCOPT:http-user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64)
     http://example.com/stream.m3u8
     */
    func parseM3U() -> (String, URL, [String: String])? {
        if scanString("#EXTINF:") == nil {
            _ = scanUpToCharacters(from: .newlines)
            return nil
        }
        var extinf = [String: String]()
        if let duration = scanDouble() {
            extinf["duration"] = String(duration)
        }
        while scanString(",") == nil {
            let key = scanUpToString("=")
            _ = scanString("=\"")
            let value = scanUpToString("\"")
            _ = scanString("\"")
            if let key, let value {
                extinf[key] = value
            }
        }
        let title = scanUpToCharacters(from: .newlines)
        while scanString("#EXT") != nil {
            if scanString("VLCOPT:") != nil {
                let key = scanUpToString("=")
                _ = scanString("=")
                let value = scanUpToCharacters(from: .newlines)
                if let key, let value {
                    extinf[key] = value
                }
            } else {
                let key = scanUpToString(":")
                _ = scanString(":")
                let value = scanUpToCharacters(from: .newlines)
                if let key, let value {
                    extinf[key] = value
                }
            }
        }
        let urlString = scanUpToCharacters(from: .newlines)
        if let urlString, let url = URL(string: urlString) {
            return (title ?? url.lastPathComponent, url, extinf)
        }
        return nil
    }

    /*
     [playlist]
     File1=http://example.com/stream.mp3
     Title1=Example
     Length1=-1
     NumberOfEntries=1
     Version=2
     */
    // Forward 0x1019eefdc (1045 insns, self = Scanner in x20), emitted right after parseM3U 0x1019ee3f0; sole
    // caller Data.parsePlaylist 0x1019e8f2c ("[playlist]" arm). Keys are small-string literals "File", "Title",
    // "Length", "NumberOfEntries", "Version", "=", "duration"; NumberOfEntries/Version exit the loop
    // (0x1019effd0 -> 0x1019ef26c). The tail is urls.keys.sorted() (0x101673080 copy + 0x1019f0030 sort)
    // then an inlined compactMap building Optional<(String, URL, [String: String])>.
    func parsePls() -> [(String, URL, [String: String])] { // INFERRED name — evidence: Forward 0x1019eefdc
        var urls = [Int: URL]()
        var titles = [Int: String]()
        var lengths = [Int: String]()
        while !isAtEnd {
            if scanString("File") != nil {
                if let index = scanInt(), scanString("=") != nil, let value = scanUpToCharacters(from: .newlines), let url = URL(string: value) {
                    urls[index] = url
                }
            } else if scanString("Title") != nil {
                if let index = scanInt(), scanString("=") != nil, let value = scanUpToCharacters(from: .newlines) {
                    titles[index] = value
                }
            } else if scanString("Length") != nil {
                if let index = scanInt(), scanString("=") != nil, let value = scanUpToCharacters(from: .newlines) {
                    lengths[index] = value
                }
            } else if scanString("NumberOfEntries") != nil || scanString("Version") != nil {
                break
            }
        }
        return urls.keys.sorted().compactMap { index in
            guard let url = urls[index] else {
                return nil
            }
            let title = titles[index]
            var extinf = [String: String]()
            extinf["duration"] = lengths[index]
            return (title ?? url.lastPathComponent, url, extinf)
        }
    }
}

extension HTTPURLResponse {
    var filename: String? {
        let httpFileName = "attachment; filename="
        if var disposition = value(forHTTPHeaderField: "Content-Disposition"), disposition.hasPrefix(httpFileName) {
            disposition.removeFirst(httpFileName.count)
            return disposition
        }
        return nil
    }
}

public extension Double {
    var kmFormatted: String {
        //        return .formatted(.number.notation(.compactName))
        if self >= 1_000_000 {
            return String(format: "%.1fM", locale: Locale.current, self / 1_000_000)
            //                .replacingOccurrences(of: ".0", with: "")
        } else if self >= 10000, self <= 999_999 {
            return String(format: "%.1fK", locale: Locale.current, self / 1000)
            //                .replacingOccurrences(of: ".0", with: "")
        } else {
            return String(format: "%.0f", locale: Locale.current, self)
        }
    }
}

extension TextAlignment: RawRepresentable {
    public typealias RawValue = String
    public init?(rawValue: RawValue) {
        if rawValue == "Leading" {
            self = .leading
        } else if rawValue == "Center" {
            self = .center
        } else if rawValue == "Trailing" {
            self = .trailing
        } else {
            return nil
        }
    }

    public var rawValue: RawValue {
        switch self {
        case .leading:
            return "Leading"
        case .center:
            return "Center"
        case .trailing:
            return "Trailing"
        }
    }
}

extension TextAlignment: Identifiable {
    public var id: Self { self }
}

extension HorizontalAlignment: Hashable, RawRepresentable {
    public typealias RawValue = String
    public init?(rawValue: RawValue) {
        if rawValue == "Leading" {
            self = .leading
        } else if rawValue == "Center" {
            self = .center
        } else if rawValue == "Trailing" {
            self = .trailing
        } else {
            return nil
        }
    }

    public var rawValue: RawValue {
        switch self {
        case .leading:
            return "Leading"
        case .center:
            return "Center"
        case .trailing:
            return "Trailing"
        default:
            return ""
        }
    }
}

extension HorizontalAlignment: Identifiable {
    public var id: Self { self }
}

extension VerticalAlignment: Hashable, RawRepresentable {
    public typealias RawValue = String
    public init?(rawValue: RawValue) {
        if rawValue == "Top" {
            self = .top
        } else if rawValue == "Center" {
            self = .center
        } else if rawValue == "Bottom" {
            self = .bottom
        } else {
            return nil
        }
    }

    public var rawValue: RawValue {
        switch self {
        case .top:
            return "Top"
        case .center:
            return "Center"
        case .bottom:
            return "Bottom"
        default:
            return ""
        }
    }
}

extension VerticalAlignment: Identifiable {
    public var id: Self { self }
}

extension Color: RawRepresentable {
    public typealias RawValue = String
    public init?(rawValue: RawValue) {
        guard let data = Data(base64Encoded: rawValue),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data)
        else {
            return nil
        }
        self = Color(color)
    }

    public var rawValue: RawValue {
        (try? NSKeyedArchiver.archivedData(withRootObject: UIColor(self), requiringSecureCoding: false))
            .map { $0.base64EncodedString() } ?? ""
    }
}

extension Array: RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else { return nil }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}

extension Date: RawRepresentable {
    public typealias RawValue = String
    public init?(rawValue: RawValue) {
        guard let data = rawValue.data(using: .utf8),
              let date = try? JSONDecoder().decode(Date.self, from: data)
        else {
            return nil
        }
        self = date
    }

    public var rawValue: RawValue {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return result
    }
}

extension CGImage {
    static func combine(images: [(CGRect, CGImage)]) -> CGImage? {
        if images.isEmpty {
            return nil
        }
        if images.count == 1 {
            return images[0].1
        }
        var width = 0
        var height = 0
        for (rect, _) in images {
            width = max(width, Int(rect.maxX))
            height = max(height, Int(rect.maxY))
        }
        let bitsPerComponent = 8
        // RGBA(的bytes) * bitsPerComponent *width
        let bytesPerRow = 4 * 8 * bitsPerComponent * width
        return autoreleasepool {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            guard let context else {
                return nil
            }
            //            context.clear(CGRect(origin: .zero, size: CGSize(width: width, height: height)))
            for (rect, cgImage) in images {
                context.draw(cgImage, in: CGRect(x: rect.origin.x, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
            }
            let cgImage = context.makeImage()
            return cgImage
        }
    }

    func data(type: AVFileType, quality: CGFloat) -> Data? {
        autoreleasepool {
            guard let mutableData = CFDataCreateMutable(nil, 0),
                  let destination = CGImageDestinationCreateWithData(mutableData, type.rawValue as CFString, 1, nil)
            else {
                return nil
            }
            CGImageDestinationAddImage(destination, self, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                return nil
            }
            return mutableData as Data
        }
    }

    static func make(rgbData: UnsafePointer<UInt8>, linesize: Int, width: Int, height: Int, isAlpha: Bool = false) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = isAlpha ? CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue) : CGBitmapInfo.byteOrderMask
        guard let data = CFDataCreate(kCFAllocatorDefault, rgbData, linesize * height), let provider = CGDataProvider(data: data) else {
            return nil
        }
        // swiftlint:disable line_length
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: isAlpha ? 32 : 24, bytesPerRow: linesize, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        // swiftlint:enable line_length
    }
}

public extension AVFileType {
    static let png = AVFileType(kUTTypePNG as String)
    static let jpeg2000 = AVFileType(kUTTypeJPEG2000 as String)
}

extension URL: Identifiable {
    public var id: Self { self }
}

extension String: Identifiable {
    public var id: Self { self }
    public var localeLanguageCode: String? {
        Locale.current.localizedString(forLanguageCode: self)
    }
}

extension Float: Identifiable {
    public var id: Self { self }
    @used func toString(for p0: TimeType) -> String {
        Int(ceil(self)).toString(for: p0)
    }
}

public enum Either<Left, Right> {
    case left(Left), right(Right)
}

public extension Either {
    internal var left: Left? { get {
        if case let .left(value) = self {
            return value
        }
        return nil
    } }
    init(_ left: Left, or _: Right.Type) { self = .left(left) }
    init(_ left: Left) { self = .left(left) }
    init(_ right: Right) { self = .right(right) }
    internal var right: Right? { get {
        if case let .right(value) = self {
            return value
        }
        return nil
    } }
}

// BitWriter @0x1039ee5b8 — declaration shape read from the Forward context descriptor (kind, parent,
// conformances, case names); members not reconstructed. Placement: fwd_file (Utility.swift).
// ⚑[tool=type_surface ref=BitWriter:0x1039ee5b8 result=struct BitWriter]
// ⚑[tool=field_surface ref=BitWriter:fieldmd result=2 var] Lazy owner (no build metadata); fields follow
// Forward's record order, IsVar bits and resolved types.
// bitPosition private + `= 0`: Forward pfi 0x10002d9d4 `bitPosition05_51A3…LLSivpfi` carries this file's
// private discriminator _51A3A3F37FF8E3161AF3B4630C320057 = MD5("KSPlayer" + "Utility.swift").
struct BitWriter {
    var data: [UInt8]
    private var bitPosition: Int = 0
    init(size: Int) {
        // Forward 0x101a064f4 (23 insns) builds only the zeroed buffer and returns bitPosition 0 in x1.
        data = [UInt8](repeating: 0, count: size)
    }
    // mutating: Forward 0x101a06550 reads/writes self through x20 (data +0, bitPosition +8, stored once
    // after the loop).
    mutating func putBits(_ p0: UInt8, _ p1: Int) {
        for i in (0 ..< p1).reversed() {
            if (p0 >> i) & 1 == 1 {
                data[bitPosition / 8] |= 0x80 >> (bitPosition % 8)
            }
            bitPosition += 1
        }
    }
    func toData() -> Data {
        Data(data)
    }
}
