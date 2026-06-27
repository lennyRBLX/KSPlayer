import Foundation

// TimeIndexEntry — a value type recovered from __swift5_fieldmd (struct; not in the
// class classmap → no vtable). Referenced by PreLoadIOContext._timeIndex and
// LimitSeparatePreLoadIOContext._timeIndex (both `[TimeIndexEntry]`). Reconstructed
// inline (deterministic small struct; shared dependency — lands before its consumers).
//   fields (reflection field-record order): position (unmapped → UInt64 by the
//   position-field pattern, ⚑), time (Double, field-record concrete).
struct TimeIndexEntry {
    var position: UInt64   // ⚑ field-record unmapped; UInt64 by width + position-field pattern
    var time: Double       // field-record concrete
}
