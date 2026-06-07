//
//  CacheFileEntry.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 (TranscodeIO.md)
//
//  Represents a single cached segment of downloaded data. Wraps an NSFileHandle
//  over an on-disk cache file and tracks the segment's position and size.
//
//  Binary class metadata: _TtC16PreLoadIOContext14CacheFileEntry
//  (Plain "CacheFileEntry" string @ 0x102ef6828, mangled @ 0x103343840.)
//
//  Binary fields (6) per TranscodeIO.md lines 605-612 (refreshed 1.3.15 inventory):
//    1. file:     NSFileHandle  -- open file handle over the on-disk cache file (self+0x10)
//    2. url:      URL           -- source URL the segment was downloaded from
//    3. position: UInt64        -- byte offset of this segment in the cache layout
//    4. saveFile: Bool          -- whether this segment is persisted to disk
//    5. size:     UInt32        -- number of cached bytes in this segment (GOT +0x1a0)
//    6. maxSize:  UInt32?       -- optional size cap (GOT +0x1a8, Optional<UInt32>)
//
//  Cache segments stored at NSTemporaryDirectory()/videoCaches/<md5>/<position>.
//
//  NOTE: EOF / logical-vs-physical-position bookkeeping lives on the parent
//  CacheIOContext (logicalPos, eof, urlPos, end), NOT on the per-segment
//  CacheFileEntry (doc line 620).
//
//  Method table @ 0x103d15670 (7 slots, read_memory-verified):
//    slot 0: 0x101564ebc (alloc/init variant)
//    slot 1: 0x10155d8a4 (constructor shim)
//    slot 2: 0x101565500 (constructor shim variant)
//    slot 3: 0x1015658ec (description / CustomStringConvertible)
//    slot 4: 0x101565a78 (shouldRoll predicate, mis-named "updateSize")
//    slot 5: 0x101565b1c (append, mis-named "closeHandle")
//    slot 6: 0x101565cf8 (readData)
//  Metadata destroy slot @ 0x103d155a0: 0x101565de0 (deinit)
//  metadataInit @ 0x10156b214: _swift_updateClassMetadata2(self, 0x100, 6, ...)
//    confirms 6 stored properties.
//

import Foundation

// MARK: - CacheFileEntry

/// RE: 0x10156b214 (metadataInit, 1.3.15) — 6 stored properties confirmed
public class CacheFileEntry: CustomStringConvertible {
    // MARK: - RE-verified binary fields (6)

    /// RE: Binary field 1 of 6 — open file handle over the on-disk cache file
    /// (self+0x10). Opened inline by the factory FUN_101562650 via
    /// URL.appendingPathComponent + NSFileManager/NSFileHandle, NOT by the
    /// mislabeled ensureFileHandle or openFileHandle functions.
    private var file: FileHandle?

    /// RE: Binary field 2 of 6 — source URL the segment was downloaded from.
    public let url: URL

    /// RE: Binary field 3 of 6 — byte offset of this segment in the cache layout.
    /// Getter: getPosition @ 0x101565fc4 reads *(self + ::position).
    /// NOTE (G-R15-6): setPosition @ 0x101565fd8 is mis-named — it actually
    /// reads the size field, not position.
    public let position: UInt64

    /// RE: Binary field 4 of 6 — whether this segment is persisted to disk.
    /// The deinit (0x101565de0) checks saveFile to decide whether to delete
    /// the on-disk cache file. Transient (saveFile=false) entries are cleaned
    /// up on teardown.
    public var saveFile: Bool

    /// RE: Binary field 5 of 6 — number of cached bytes in this segment.
    /// Plain UInt32 at GOT slot 0x104459000+0x1a0.
    /// NOTE (G-R15-6): the mis-named "setPosition" @ 0x101565fd8 is actually
    /// a size GETTER (ldr w0,[x19,x20] from GOT +0x1a0).
    public private(set) var size: UInt32

    /// RE: Binary field 6 of 6 — optional maximum size cap.
    /// Optional<UInt32> at GOT slot 0x104459000+0x1a8 (4-byte payload +
    /// 1-byte discriminator; bit 0: 0 = .some, 1 = .none).
    /// NOTE (G-R15-6): Ghidra's getSize @ 0x101564e18 actually reads maxSize
    /// (payload ldr w8,[x19] + discriminator ldrb w9,[x19,#0x4]),
    /// and setSize @ 0x101564e6c actually writes maxSize.
    public var maxSize: UInt32?

    // MARK: - Init

    public init(url: URL,
                position: UInt64 = 0,
                saveFile: Bool = true,
                size: UInt32 = 0,
                maxSize: UInt32? = nil) {
        self.url = url
        self.position = position
        self.saveFile = saveFile
        self.size = size
        self.maxSize = maxSize
    }

    // MARK: - File handle management

    /// RE: Inline in factory FUN_101562650 (1.3.15)
    /// The binary's factory opens the file handle inline via
    /// URL.appendingPathComponent + NSFileManager/NSFileHandle (_objc_msgSend)
    /// and stores it at self+0x10. This method exposes that capability so
    /// CacheIOContext's factory (FUN_101562650) can populate the handle after
    /// constructing the entry.
    ///
    /// Creates or opens the on-disk cache file at the given URL for writing,
    /// creating the file first via FileManager if it does not exist.
    func openFile(at fileURL: URL) throws {
        // Match the binary's inline pattern: NSFileManager createFile + NSFileHandle(forWritingTo:)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        file = try FileHandle(forWritingTo: fileURL)
    }

    /// RE: Companion to openFile(at:) — allows the factory to assign a
    /// pre-opened FileHandle directly (matching the binary's inline store
    /// to self+0x10 in the factory path).
    func setFileHandle(_ handle: FileHandle?) {
        file = handle
    }

    // MARK: - Position accessor

    /// RE: 0x101565fc4 (getPosition, 1.3.15)
    /// Reads *(self + ::position). Returns the segment's byte offset.
    public func getPosition() -> UInt64 { position }

    // MARK: - shouldRoll (mis-named "updateSize" in Ghidra)

    /// RE: 0x101565a78 (updateSize, 1.3.15)
    /// Pure boolean predicate — determines whether to roll a new segment file.
    /// Mutates nothing (G-R10-2 TRACE verified). Ghidra auto-name "updateSize"
    /// is a misnomer.
    ///
    /// Returns true (roll) if:
    ///   - size >= 0x2000001 (32 MiB + 1), OR
    ///   - maxSize is non-nil AND size + extra > maxSize
    ///
    /// The 32 MiB cap is 0x2000000 (mov w8,#0x2000000; cmp w21,w8; b.ls).
    /// Overflow on size + extra is trapped (adds w8,w21,w19; b.cs -> brk #0x1).
    ///
    /// Liveness: LIVE-via-method-table (slot 4) only; both real call sites
    /// (cleanupAfterFlush, writeData) open-code the same predicate inline.
    public func shouldRoll(extra: UInt32) -> Bool {
        if size >= 0x2000001 {
            return true
        }
        if let cap = maxSize {
            // Overflow-trapped addition in the binary (adds + b.cs -> brk)
            let (sum, overflow) = size.addingReportingOverflow(extra)
            precondition(!overflow, "CacheFileEntry.shouldRoll: size + extra overflow")
            return sum > cap
        }
        return false
    }

    // MARK: - append (mis-named "closeHandle" in Ghidra)

    /// RE: 0x101565b1c (closeHandle, 1.3.15)
    /// Per-segment append/flush primitive. Ghidra auto-name "closeHandle" is
    /// a misnomer — this method does NOT close the handle.
    ///
    /// Body: seekToOffset + NSFileHandle.write(contentsOf:Data) +
    /// overflow-checked self.size += n.
    ///
    /// Callers: cleanupAfterFlush @ 0x101562038, factory FUN_101562650.
    public func append(_ data: Data) {
        guard let handle = file else { return }
        // Seek to end of current segment data
        handle.seek(toFileOffset: UInt64(size))
        handle.write(data)
        // Overflow-checked size increment (binary uses adds + b.cs -> brk)
        let count = UInt32(data.count)
        let (newSize, overflow) = size.addingReportingOverflow(count)
        precondition(!overflow, "CacheFileEntry.append: size overflow")
        size = newSize
    }

    // MARK: - readData

    /// RE: 0x101565cf8 (readData, 1.3.15)
    /// Cache-HIT read: seekToOffset + NSFileHandle.read(upToCount:) -> Data.
    /// Feeds the avio read callback.
    ///
    /// Callers: setFormatContextOptions @ 0x10156b89c (avio read cb),
    /// FUN_10155dc40, FUN_10157fb6c.
    public func readData(at offset: UInt64, length: Int) -> Data? {
        guard let handle = file else { return nil }
        handle.seek(toFileOffset: offset)
        let data = handle.readData(ofLength: length)
        return data.isEmpty ? nil : data
    }

    // MARK: - CustomStringConvertible (mis-named "loadResource" in Ghidra)

    /// RE: 0x1015658ec (loadResource, 1.3.15)
    /// CustomStringConvertible.description — debug dump that builds
    /// "position=\(position),size=\(size),maxSize=\(maxSize)" + print_unlocked.
    /// Ghidra auto-name "loadResource" is a misnomer; this is diagnostic-only.
    ///
    /// Liveness: LIVE-via-method-table (slot 3).
    public var description: String {
        "position=\(position),size=\(size),maxSize=\(String(describing: maxSize))"
    }

    // MARK: - deinit

    /// RE: 0x101565de0 (deallocate/deinit, 1.3.15)
    /// Per-segment destructor: if saveFile == false (transient), deletes the
    /// on-disk cache file via NSFileManager.removeItemAtURL; then unconditionally
    /// closes the file handle via NSFileHandle.closeAndReturnError.
    ///
    /// Body (G-R15-1 TRACE verified):
    ///   1. Reads self.saveFile (ldrb w8,[x19,x8] @ 0x101565e50)
    ///   2. If saveFile == 0 (transient): NSFileManager.default.removeItem(at: url)
    ///   3. Unconditionally: NSFileHandle.closeAndReturnError (self+0x10)
    ///   4. _objc_release(self+0x10), destroy url via value-witness [vwt+8]
    ///
    /// Liveness: LIVE-via-class-metadata-destroy-slot @ 0x103d155a0 (wrapper
    /// FUN_101565fb8 -> body + _swift_deallocClassInstance).
    deinit {
        if !saveFile {
            try? FileManager.default.removeItem(at: url)
        }
        try? file?.close()
    }
}

// MARK: - CacheEntry

/// `Codable` cache-metadata record — the persisted, position-only representation
/// of a cached range (distinct from the runtime, `NSFileHandle`-backed
/// `CacheFileEntry`).
///
/// RE source: Forward v1.3.15 (TranscodeIO.md Audit Log item 24). `KSPlayer.CacheEntry`
/// (module `KSPlayer`, metadata accessor `$s8KSPlayer10CacheEntryCMa` @ 0x1013c9ec4) is the
/// `Codable` on-disk/serialized representation of a cached range — the logical/physical
/// position bookkeeping that is persisted (e.g. to the cache index / `end.txt` metadata),
/// as opposed to the live open-filehandle `CacheFileEntry`. Verified functions:
/// `CacheEntry_encode` @ 0x1013c9134, `CacheEntry_initFromDecoder` @ 0x1013c86c0,
/// `CacheEntry_allocAndDecode` @ 0x100b74830, consumer `PBClass_initFromCacheEntry` @ 0x10143d77c.
///
/// Binary fields (5) per TranscodeIO.md, declaration/layout order:
///   1. logicalPos:  Int64   -- logical (stream-space) byte position of the cached range
///   2. physicalPos: UInt64  -- physical (on-disk) byte position
///   3. size:        UInt32  -- size in bytes of this cached range
///   4. eof:         Bool    -- whether this range reaches end-of-file
///   5. maxSize:     UInt32? -- optional maximum-size cap for the range
public final class CacheEntry: Codable {
    /// RE: Field 1 of 5 — logical (stream-space) byte position.
    public var logicalPos: Int64
    /// RE: Field 2 of 5 — physical (on-disk) byte position.
    public var physicalPos: UInt64
    /// RE: Field 3 of 5 — size in bytes of this cached range.
    public var size: UInt32
    /// RE: Field 4 of 5 — whether this range reaches end-of-file.
    public var eof: Bool
    /// RE: Field 5 of 5 — optional maximum-size cap for the range.
    public var maxSize: UInt32?

    /// RE: `CacheEntry.CodingKeys` (5 cases, declaration order — ENUM_CASES_1.3.15).
    /// One case per stored property (standard synthesized `Codable` keys).
    private enum CodingKeys: String, CodingKey {
        case logicalPos
        case physicalPos
        case size
        case eof
        case maxSize
    }

    public init(logicalPos: Int64, physicalPos: UInt64, size: UInt32, eof: Bool, maxSize: UInt32? = nil) {
        self.logicalPos = logicalPos
        self.physicalPos = physicalPos
        self.size = size
        self.eof = eof
        self.maxSize = maxSize
    }

    // MARK: - Encodable

    /// RE: 0x1013c9134 (CacheEntry_encode, 1.3.15)
    /// Encodable body. Allocates encoder container, encodes keyed fields.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(logicalPos, forKey: .logicalPos)
        try container.encode(physicalPos, forKey: .physicalPos)
        try container.encode(size, forKey: .size)
        try container.encode(eof, forKey: .eof)
        try container.encodeIfPresent(maxSize, forKey: .maxSize)
    }

    // MARK: - Decodable

    /// RE: 0x1013c86c0 (CacheEntry_initFromDecoder, 1.3.15)
    /// Decodable init(from:) — the decode counterpart.
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        logicalPos = try container.decode(Int64.self, forKey: .logicalPos)
        physicalPos = try container.decode(UInt64.self, forKey: .physicalPos)
        size = try container.decode(UInt32.self, forKey: .size)
        eof = try container.decode(Bool.self, forKey: .eof)
        maxSize = try container.decodeIfPresent(UInt32.self, forKey: .maxSize)
    }

    // MARK: - Factory

    /// RE: 0x100b74830 (CacheEntry_allocAndDecode, 1.3.15)
    /// Allocation + decode entry used when rehydrating persisted cache metadata.
    /// Factory method that decodes a CacheEntry from serialized data.
    public static func allocAndDecode(from data: Data) throws -> CacheEntry {
        let decoder = JSONDecoder()
        return try decoder.decode(CacheEntry.self, from: data)
    }
}
