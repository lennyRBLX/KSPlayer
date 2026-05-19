//
//  FormatContext.swift
//  KSPlayer
//
//  Forward addition (RE): Wrapper around AVFormatContext providing
//  format name resolution from URL.
//
//  Binary: _TtC8KSPlayer13FormatContext (1 function)
//  RE source: Forward v1.3.15
//

import Foundation
import Libavformat

public class FormatContext {
    // RE: FormatContext_getOutputFormatName @ 0x101416dfc
    public static func getOutputFormatName(for url: URL) -> String {
        if url.isFileURL {
            return url.path
        }
        let absoluteString = url.absoluteString
        if let scheme = url.scheme {
            if scheme == "ftp" {
                if let decoded = absoluteString.removingPercentEncoding {
                    return decoded
                }
            }
        }
        return absoluteString
    }
}
