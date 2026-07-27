//
//  MPVShader.swift
//  KSPlayer
//
//  Forward 1.3.17 reconstruction. `MPVShader` is one parsed mpv-format GLSL user shader (the
//  `//!HOOK` / `//!BIND` / `//!SAVE` / `//!WIDTH` / … directive set). `Anime4K.shaders` and
//  `Anime4K.enabledShaders` are `[MPVShader]`; it is a LEAF of the Anime4K subsystem — all 10
//  fields are stdlib types and it references no other subsystem type.
//
//  FULLY DECODED — nothing inferred except the access level:
//    • kind=struct + 10 stored fields + order + types = the struct field descriptor @0x103cbd7f4
//      (nominal desc 0x1039f0de0; Kind=0/Struct, NumFields=10; every FieldRecord concrete —
//      mangles SS / SSSg / SaySSG / SiSg / SS_SftSg / SdSg).
//    • all 10 fields `var` — FieldRecordFlags IsVar (0x2) set on every record (dump_field_bindings).
//    • no protocol conformances — superclass_conformance_gate confs=[] (GOT-aware): not Codable
//      (the .hook text is parsed field-by-field, not decoded through Codable).
//    • access level ⚑ INFERRED public ⚑[tool=nm ref=MPVShader result=local-symbols-stripped]
//      (linkage unavailable in the stripped, statically-linked image; subsystem-sibling
//      convention). Fields left internal `var` — no per-field access signal survives.
//
//  Binary source org: the subsystem's Swift lives in `KSPlayer/Anime4K.swift` +
//  `KSPlayer/Anime4KPipeline.swift`; per-type file attribution for the value types is not preserved
//  in the binary, so this gets its own file (binary-indifferent placement; Anime4KFrameDump /
//  Anime4KPreset precedent).
//

public struct MPVShader {
    var name: String
    var hook: String?
    var binds: [String]
    var save: String?
    var components: Int?
    var width: (String, Float)?
    var height: (String, Float)?
    var when: String?
    var sigma: Double?
    var code: [String]

    /// Rewrites this shader's mpv-format GLSL into a compilable Metal kernel: a fixed Metal
    /// preamble, one `#define` macro block per bind, the `MAIN` special case, then a regex-driven
    /// rewrite of each GLSL function signature into a Metal one, and finally the `kernel void`
    /// entry point that calls `hook(...)` and writes the result.
    ///
    /// ⚑ INFERRED name ⚑[tool=recover_swift_function_name ref=transformSource:0x101a7cd84 result=none]
    ///   — `#function` is absent from the stripped image and the tool returns no name (the committed
    ///   `regexMatches` is in the same position). The body bakes no `#function`/`#file` literal.
    ///
    /// Ownership (settled in session 56, and it corrected the earlier plan): this is an **MPVShader
    /// instance method**, not an `Anime4K` one. The body dereferences `x20` at 0x00/0x10/0x18/0x20/
    /// 0x98 — exactly `name` / `hook` / `binds` / `code` above — and the `MetalShaderExporter` call
    /// site @0x101a812f8 copies 0xa0 bytes (this struct's exact size) into a stack slot and does
    /// `sub x20, x29, #0x100` immediately before the `bl`, i.e. passes it as indirect self.
    ///
    /// Signature: the prologue (0x101a7cd84–0x101a7cda4) reads **only** `x20` (`mov x23, x20`) and
    /// no `x0`–`x7`, so there are no parameters; `self` is a read-only indirect, so non-mutating.
    ///
    /// Decode notes (every construct below was derived from disassembly, not the decompile — the
    /// decompile aliases the append destination through `param_3`/`param_4` and its `if`/`else`
    /// nesting around the `self.code` loop does not match the real CFG):
    ///   • the three signature accumulators are frame slots, each identified by the store that
    ///     seeds it AND the `x20` of every append that targets it: `hookArgs` @[x29,-0xa0] (seeded
    ///     0x101a7cec0), `hookCall` @[x29,-0xb0] (0x101a7ced8), `kernelArgs` @[x29,-0xc0] (0x101a7cee8,
    ///     empty). `source` is @[x29,-0x80] and `newCode` @[x29,-0xd0].
    ///   • `hookArgs` and `kernelArgs` are interpolations, `hookCall` is `+`. `hookArgs` emits
    ///     `_StringGuts.grow(0x25)` = 37 = literals (33 + 2) + 2*1 and `kernelArgs` `grow(0x35)` = 53
    ///     = literals (33 + 11 + 5) + 2*2, both compile-time constants that only
    ///     `DefaultStringInterpolation.init(literalCapacity:interpolationCount:)` can produce.
    ///     `hookCall` has NO grow: 0x101a7cf94 seeds the temp directly with the bind String and
    ///     appends `", "`. IN-BINARY CONTROL for reading that absence as meaningful — `hookArgs`'
    ///     grow two instructions earlier is DEAD (its storage is released at 0x101a7cf34 and
    ///     overwritten at 0x101a7cf3c) and the optimizer still keeps it, so this optimizer does not
    ///     delete dead grows.
    ///   • the texture counter starts at 0 (`mov x25, #0x0`, 0x101a7cef4) and is still live after
    ///     the loop — the MAIN-not-in-binds branch increments it again (0x101a7d204) and its final
    ///     value is what `output [[texture(n)]]` interpolates (0x101a7d23c). A counter that outlives
    ///     the loop is declared outside it, so this is `for bind in binds` with a manual index, not
    ///     `binds.enumerated()`.
    ///   • ⭐ `index` is written and never read. That is genuine source, not an artifact: `+= 1` on
    ///     `Int` traps on overflow, a trap is an observable side effect the optimizer may not
    ///     delete, and the increment (with its `SCARRY8` check) therefore survives inside the
    ///     outlined per-bind block @0x101a7dc3c, which takes `(&bind, &index, &source)`. Dropping it
    ///     would not reproduce the binary. It is NOT the texture index — that is the separate
    ///     0-based counter above. Swift emits only a "never read" warning.
    ///     Its position WITHIN the loop body is not recoverable and is not claimed: 0x101a7dc3c
    ///     performs the `adds`/`b.vs` before even `sub sp, sp, #0x60`, i.e. the check is scheduled
    ///     ahead of the frame setup, which source statements cannot be — so the instruction order
    ///     is a scheduling artifact, not evidence. Nothing reads `index` and `source` does not
    ///     depend on it, so the two statements commute and the choice is unobservable either way.
    ///   • the per-bind macro block is one interpolation with 12 substitutions of `bind`; its 13
    ///     literal segments are 8, 20, 13, 14, 23, 18, 15, 10, 37, 13, 5, 7, 17 = 200, and
    ///     200 + 2*12 = 224 = the `grow(0xe0)` in 0x101a7dc3c. It deliberately differs from the
    ///     `MAIN` block below, which is a single 278-char literal @0x103d37d80 that orders `_pt`
    ///     before `_size` and spells both out with `vec2` instead of reusing `_size`.
    ///   • `self.code` loop: `x22` is the state flag. It is a `String?`, not a `Bool` — only the
    ///     bridgeObject half is live (the `.str` half is dead-code-eliminated because nothing reads
    ///     it) and it is retained/released, which a `Bool` never is; `cbz` tests the nil
    ///     discriminator. It is set to `matches[2]` on a signature match and cleared by a `"}"`
    ///     line, so it means "inside a hook function body".
    ///   • a line that does NOT match while the flag is nil falls through to the same rewrite path
    ///     (`b.ne 0x101a7d4c0`); the `x22 = 0` there is a redundant merge with the `"}"` arm, since
    ///     that path is only reached when `x22` is already 0.
    ///   • `matches.count == 5` is a single compare (0x101a7d3d8); the four subscript traps
    ///     (<2, ==2, <4, ==4) that follow are the bounds preconditions for indices 1…4.
    ///   • `args` is a COPY: 0x101a7d490 copies `hookArgs` to a scratch slot BEFORE the emptiness
    ///     test at 0x101a7d4ac, and `removeSubrange` is applied to the copy (0x101a7d6a8), leaving
    ///     the accumulator intact for later lines.
    ///   • the rewritten signature is a `+` chain, not an interpolation: 0x101a7d6b4–0x101a7d7ec
    ///     seeds a temp with `matches[1]` and performs seven plain appends with no `grow` anywhere.
    ///     Same for `newCode += newLine + "\n"` (0x101a7d328).
    ///   • the final block IS an interpolation: `grow(0x9c)` = 156 = literals (12 + 1 + 126 + 11 =
    ///     150) + 2*3. ⭐ And the filter is INLINE inside it rather than precomputed — the filter
    ///     loop (0x101a7d8d4–0x101a7d9e8) runs AFTER `grow(156)` and AFTER the `"kernel void "`
    ///     literal append, i.e. exactly at its own interpolation segment, whereas `hookCallArgs`'
    ///     `removeLast(2)` demonstrably runs BEFORE the grow (0x101a7d890). Swift has no statement
    ///     expressions, so an inline filter must be a method call. The inner test is
    ///     `Sequence.contains` walking the 4-char literal `".-()"` (x23 = 0x29282d2e, count 0xe4),
    ///     not a `CharacterSet`.
    ///   • `return source + newCode`, not `source += newCode`: 0x101a7da94 copies `source` into a
    ///     fresh slot and retains it before appending, which an in-place `+=` would not do.
    ///   • callees resolved rather than assumed: 0x10001e034 is `Array<String>.contains(_:)` (a
    ///     linear scan with a pointer-equality fast path then `_stringCompareWithSmolCheck`,
    ///     returning `count != 0`) — session 56 had it only inferred from the call shape;
    ///     0x1000223a4 is an outlined `String` value-witness destroy and is ARC only, no source;
    ///     0x101a973c0 is `String.removeLast(_:)`.
    ///   • every string literal below was read byte-for-byte out of the on-disk binary through the
    ///     Mach-O segment map (P72: the emitted object pointer is chars − 0x20), not inferred from
    ///     context. The 154/278/126-char blocks and the 28-char pattern all match their length
    ///     immediates exactly.
    ///   • spelling choices the binary cannot decide: multi-line `"""` versus escaped `\n`, and the
    ///     escaped pattern versus a raw string, produce identical bytes. The escaped pattern matches
    ///     the sibling call in `Anime4K.parseShaders`.
    ///   • ⚑ access level INFERRED internal ⚑[tool=nm ref=transformSource:0x101a7cd84 result=local-symbols-stripped]
    ///     — `internal` is the minimum that satisfies the observed `MetalShaderExporter` call site
    ///     given this reconstruction's per-type file split, exactly as for `regexMatches`.
    func transformSource() -> String {
        var source = """
        #include <metal_stdlib>
        using namespace metal;

        using vec2 = float2;
        using vec3 = float3;
        using vec4 = float4;
        using ivec2 = int2;
        using mat4 = float4x4;

        """
        var index = 1
        for bind in binds {
            source += """
            #define \(bind)_pos mtlPos
            #define \(bind)_size float2(\(bind).get_width(), \(bind).get_height())
            #define \(bind)_pt (vec2(1, 1) / \(bind)_size)
            #define \(bind)_tex(pos) \(bind).sample(textureSampler, pos)
            #define \(bind)_texOff(off) \(bind)_tex(\(bind)_pos + \(bind)_pt * vec2(off))

            """
            index += 1
        }
        if hook == "MAIN" {
            source += """
            #define MAIN_pos mtlPos
            #define MAIN_pt (vec2(1, 1) / vec2(MAIN.get_width(), MAIN.get_height()))
            #define MAIN_size vec2(MAIN.get_width(), MAIN.get_height())
            #define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
            #define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * vec2(off))

            """
        }
        var hookArgs = "float2 mtlPos, sampler textureSampler, "
        var hookCall = "mtlPos, textureSampler, "
        var kernelArgs = ""
        var textureIndex = 0
        for bind in binds {
            hookArgs += "texture2d<float, access::sample> \(bind), "
            hookCall += bind + ", "
            kernelArgs += "texture2d<float, access::sample> \(bind) [[texture(\(textureIndex))]], "
            textureIndex += 1
        }
        if hook == "MAIN", !binds.contains("MAIN") {
            hookArgs += "texture2d<float, access::sample> MAIN, "
            hookCall += "MAIN, "
            kernelArgs += "texture2d<float, access::sample> MAIN [[texture(\(textureIndex))]], "
            textureIndex += 1
        }
        kernelArgs += "texture2d<float, access::write> output [[texture(\(textureIndex))]], "
        kernelArgs += "uint2 gid [[thread_position_in_grid]], "
        kernelArgs += "sampler textureSampler [[sampler(0)]]"
        var newCode = ""
        var functionNames = [String]()
        var currentFunction: String?
        for line in code {
            if currentFunction == nil {
                let matches = regexMatches("(\\w*\\s+)(\\w+)\\((.*)\\)(\\s+\\{)", line)
                if matches.count == 5 {
                    functionNames.append(matches[2])
                    var args = hookArgs
                    if matches[3].isEmpty {
                        args.removeLast(2)
                    }
                    newCode += matches[1] + matches[2] + "(" + args + matches[3] + ")" + matches[4] + "\n"
                    currentFunction = matches[2]
                    continue
                }
            } else if line == "}" {
                currentFunction = nil
            }
            var newLine = line
            for functionName in functionNames {
                newLine = newLine.replacingOccurrences(of: functionName + "(", with: functionName + "(" + hookCall)
                newLine = newLine.replacingOccurrences(of: ", )", with: ")")
            }
            newCode += newLine + "\n"
        }
        var hookCallArgs = hookCall
        hookCallArgs.removeLast(2)
        newCode += """
        kernel void \(name.filter { !".-()".contains($0) })(\(kernelArgs)) {
            float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
            output.write(hook(\(hookCallArgs)), gid);
        }

        """
        return source + newCode
    }
}
