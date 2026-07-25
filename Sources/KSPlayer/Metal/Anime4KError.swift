//
//  Anime4KError.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. `Anime4KError` is the error type thrown by the Anime4K subsystem's
//  shader/encoder paths (OFF the critical path). It conforms to LocalizedError (which refines Error)
//  and carries a custom `errorDescription`.
//
//  DECODED from the binary — access level + the switch-binding identifier are the only inferences:
//    • kind=enum + 4 cases + order = the enum field descriptor @0x103cbd4e4 (nominal 0x1039f0a1c);
//      each case has a single UNLABELED `String` associated value (FieldRecord MangledTypeName "SS"
//      @0x103c2d634, no tuple/label).
//    • conformances {Error, LocalizedError} = superclass_conformance_gate confs=[Error, LocalizedError]
//      (GOT-aware dyld-bind: _$ss5ErrorMp + _$s10Foundation14LocalizedErrorMp). Declaring
//      `: LocalizedError` satisfies both (LocalizedError refines Error).
//    • errorDescription is a CUSTOM resilient witness (thunk @0x101a76880 → body @0x101a767e8); the
//      other LocalizedError requirements (failureReason/recoverySuggestion/helpAnchor) use the default
//      nil-returning witnesses (@0x10003b47x). Body = a switch returning "<prefix>" + payload per case;
//      the four prefixes' lengths 18/18/26/18 = the disasm's small-string length immediates
//      0x12/0x12/0x1a/0x12, and the concat is Swift.String.append (the `+` operator), not interpolation.
//    • access level ⚑ INFERRED `public` ⚑[tool=nm ref=Anime4KError result=local-symbols-stripped];
//      the case-binding identifier is a source local (not binary-encoded) — ⚑ INFERRED `detail`.
//

import Foundation

public enum Anime4KError: LocalizedError {
    case fileNotFound(String)
    case fileCorrupt(String)
    case encoderCreationFail(String)
    case encoderFail(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let detail): return "Cannot find file: " + detail
        case .fileCorrupt(let detail): return "Cannot read file: " + detail
        case .encoderCreationFail(let detail): return "Cannot create encoder for " + detail
        case .encoderFail(let detail): return "Failed to encode: " + detail
        }
    }
}
