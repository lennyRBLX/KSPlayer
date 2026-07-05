//
//  ProAVPlayer.swift
//  ProAVPlayer
//
//  P3b M1 (structure) — Forward-new KSAVPlayer subclass that plays the locally-converted HLS via
//  AVFoundation. Field types resolved deterministically (field-record mangle + a known-answer control
//  for the Task Failure). Method bodies → M2.
//  Binary: desc=0x1039f52c4, superclass=KSAVPlayer (needs `open`), vtable=16, 1 impl body @slot15
//  (the AVPlayer-wrapper method per the module enumeration); rest devirt/inherited → M2.
//

import AVFoundation
import KSPlayer

/// The ProAVPlayer module's player: a KSAVPlayer subclass that plays the locally-served HLS conversion.
/// Forward-new (ProAVPlayer module).
/// P21 (vtable_anchor_diff, later·45): NON-final — the binary gives ProAVPlayer its OWN 16-slot vtable
/// (overrides + new methods on KSAVPlayer), which a `final` subclass would not emit (the SRC `final` gave
/// no own vtable). ⚑ EXACT-LAYOUT = tracked structural debt: matching the 16 own slots needs member-level
/// `final`/override reconstruction not yet done (same class as the LocalHLSServer residual).
class ProAVPlayer: KSAVPlayer, ConversionInfoDelegate {   // + ConversionInfoDelegate (binary conf@0x1035715a0); reqs → M2
    // 4 reflection fields (order = layout). Optionality from the mangle Sg.
    // task's Failure = Error PROVEN (known-answer control: KSAVPlayer.error `Error?` symref → the
    // same protocol descriptor 0x10536d100); Success = AVPlayerItem (So-mangle). Access level is not
    // binary-determined — `private` under-includes (P17); widen at M2 if a usage requires it.
    private var m3u8Info: ConversionInfo? = nil
    private var task: Task<AVPlayerItem, Error>? = nil
    private var hasEndOfStream: Bool = false
    private var seekToTime: CMTime? = nil

    // Adds no designated init + all 4 stored props defaulted ⇒ inherits KSAVPlayer's
    // `required init(url:options:)`. vtable=16; slot15 (replaceCurrentItem) reconstructed below.

    // MARK: slot15 @0x101b7c164 — replaceCurrentItem(needSeek:) (M2)

    /// `FUN_101b7c164`. Name RECOVERED (`recover_swift_function_name` high, 1 label; #file ProAVPlayer.swift;
    /// `param_1 & 1` ⇒ `needSeek: Bool`, P28-clean). ProAVPlayer's own vtable slot15. On `needSeek`: snapshot
    /// `player.currentTime` → `seekToTime` + advance the remuxer live-window `startPlayTime` by the last seekable
    /// range; then, on the main thread, rebuild the `ProPlayerItem` from the current asset and install it.
    /// Disasm-confirmed: needSeek block is `tbz w21,#0`-guarded (@0x101b7c260); `self.player` = KSAVPlayer's
    /// public accessor (FUN_1019a1730); the item-swap runs via `runOnMainThread` (FUN_101a03e88).
    func replaceCurrentItem(needSeek: Bool) {
        // ⚑ leading gated KSLog (base playback state > 2, FUN_1019b4074/c0094) omitted — KSLog form UNRESOLVED (class convention)
        if needSeek {                                                        // [tbz w21,#0 @0x101b7c260]
            seekToTime = player.currentTime()                               // self.player.currentTime() → seekToTime (CMTime?)
            if let lastRange = player.currentItem?.seekableTimeRanges.last?.timeRangeValue,
               let m3u8Info {                                               // self.m3u8Info != nil
                // `.start` (vs .end/.duration) — DISASM-CONFIRMED: CMTimeRangeValue writes the range @sp+0x60,
                // get_seconds loads x0,x1=[sp+0x60]/x2=[sp+0x70] = the CMTime @offset 0 (.start; .duration = sp+0x78)
                m3u8Info.remuxerIOAction.startPlayTime =
                    (m3u8Info.remuxerIOAction.startPlayTime ?? 0) + lastRange.start.seconds  // *(remux+0x10); tag=0 (.some)
            }
        }
        runOnMainThread { [weak self] in                                    // FUN_101a03e88 = Utility.runOnMainThread; weak-self capture (0x1041e1198)
            guard let self,
                  let asset = player.currentItem?.asset as? AVURLAsset else { return }  // currentItem.asset as? AVURLAsset
            let item: ProPlayerItem
            if hasEndOfStream {                                             // self.hasEndOfStream
                item = ProPlayerItem(url: asset.url)                       // initWithURL: (inherited AVPlayerItem init)
                hasEndOfStream = false
            } else {
                item = ProPlayerItem(asset: asset)                        // initWithAsset:
            }
            item.m3u8Info = m3u8Info                                       // ProPlayerItem.m3u8Info = self.m3u8Info
            // ⚑ UNRESOLVED (omitted) — FUN_101b69fc4(m3u8Info.demuxerTime - (m3u8Info.remuxerIOAction.startPlayTime ?? 0)):
            //   71i time-offset method (name unrecovered, self+0x40 store), gated `if m3u8Info != nil` → ProAVPlayer M2 sub-helper.
            //   ⚑[tool=disassemble_function ref=FUN_101b69fc4:0x101b69fc4 result=LOCATED]
            player.automaticallyWaitsToMinimizeStalling = false
            (self as KSAVPlayer).replaceCurrentItem(playerItem: item)     // KSAVPlayer.replaceCurrentItem(playerItem:) — FUN_1019a563c (P34: private→internal). Upcast resolves the base-name shadow from the needSeek: overload (super-in-closure unsupported); ProAVPlayer doesn't override it ⇒ same dispatch as the binary.
        }
    }

    // ── ConversionInfoDelegate conformance (binary conf@0x1035715a0, wt 0x1041e1340 → req0 101b7cc78 /
    //    req1 101b7cc80 / req2 101b7d3b4). ProAVPlayer receives the coordinator's lifecycle callbacks.
    //    Names inferred from ConversionInfo's forwards; behaviors reconstructed from the witness bodies.

    /// req0 witness `FUN_101b7cc78` = `FUN_101b7c164(0)` — refresh the current item without seeking.
    func conversionDidUpdate() {
        replaceCurrentItem(needSeek: false)
    }

    /// req1 witness `FUN_101b7cc80` — mark end-of-stream; if the un-drained lead
    /// (`currentItem.duration - remuxerIOAction.startPlayTime`) exceeds `maxBufferDuration`, schedule the
    /// end-of-stream item work on the main actor.
    func conversionDidReachEnd() {
        hasEndOfStream = true                                            // [*(self+hasEndOfStream)=1]
        guard let currentItem = player.currentItem else { return }       // [player=FUN_1019a1730; currentItem==0 -> return]
        if let m3u8Info {                                                // self.m3u8Info != nil
            if m3u8Info.maxBufferDuration < currentItem.duration.seconds - (m3u8Info.remuxerIOAction.startPlayTime ?? 0) {  // [+0x48 < duration.seconds - startPlayTime]
                Task { @MainActor in                                    // [true: MainActor Task; alloc 0x38 @0x1041e1328]
                    // ⚑ UNRESOLVED — reach-end true-branch async body (FUN_101b78394, captures currentItem + m3u8Info):
                    //   ProAVPlayer M2 deep-async sub-unit (deferred, shape captured).
                    //   ⚑[tool=prefetch_decompiles ref=FUN_101b78394:0x101b78394 result=LOCATED]
                }
            } else {                                                    // [false path — audit-caught: NOT omitted]
                runOnMainThread {                                       // [false: runOnMainThread; weak-self ctx @0x1041e1198 + currentItem @0x1041e1300]
                    // ⚑ UNRESOLVED — reach-end false-branch closure (FUN_101b7d628, weak self + captures currentItem):
                    //   ProAVPlayer M2 sub-unit (deferred, shape captured).
                    //   ⚑[tool=prefetch_decompiles ref=FUN_101b7d628:0x101b7d628 result=LOCATED]
                }
            }
        }
    }

    /// req2 witness `FUN_101b7d3b4` = a thunk to `KSAVPlayer.prepareToPlay()` (FUN_1019a9e20) — on conversion
    /// failure, re-prepare the player. `error` is received by the protocol req but unused (the witness thunk
    /// drops it; `prepareToPlay()` takes no args).
    func conversionDidFail(_ error: any Error) {
        prepareToPlay()
    }
}
