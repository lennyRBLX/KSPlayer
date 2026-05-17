//
//  SpeechRecognizeSubtitle.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15 — AudioRecognize protocol + SFSpeechRecognizer integration
//  KSOptions.audioRecognizes field #40 (Forward addition)
//

import AVFoundation
import Foundation
#if canImport(Speech)
import Speech
#endif

#if canImport(Speech)
@available(iOS 10.0, macOS 10.15, *)
public final class SpeechRecognizeSubtitle: NSObject, AudioRecognize, @unchecked Sendable {
    public var subtitleID: String { "speech-\(locale.identifier)" }
    public var name: String { "AI Subtitles (\(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier))" }
    public var delay: TimeInterval = 0
    public var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startRecognition()
            } else {
                stopRecognition()
            }
        }
    }

    private let locale: Locale
    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var subtitle = KSSubtitle()
    private var lastSegmentCount = 0
    private var baseTime: TimeInterval = 0
    private var currentTime: TimeInterval = 0

    public init(locale: Locale = .current) {
        self.locale = locale
        self.recognizer = SFSpeechRecognizer(locale: locale)
        super.init()
        recognizer?.defaultTaskHint = .dictation
    }

    public func append(frame: AudioFrame) {
        guard isEnabled, recognitionRequest != nil else { return }
        currentTime = frame.timebase.cmtime(for: frame.timestamp).seconds
        guard let pcmBuffer = frame.toPCMBuffer() else { return }
        recognitionRequest?.append(pcmBuffer)
    }

    public func search(for time: TimeInterval) -> [SubtitlePart] {
        lock.lock()
        let result = subtitle.search(for: time - delay)
        lock.unlock()
        return result
    }

    private func startRecognition() {
        guard let recognizer, recognizer.isAvailable else {
            KSLog("[speech] recognizer unavailable for \(locale.identifier)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13.0, macOS 10.15, *) {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.processResult(result)
            }
            if error != nil || (result?.isFinal ?? false) {
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }

        lastSegmentCount = 0
        baseTime = currentTime
    }

    private func stopRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func processResult(_ result: SFSpeechRecognitionResult) {
        let segments = result.bestTranscription.segments
        guard segments.count > lastSegmentCount else { return }

        lock.lock()
        for i in lastSegmentCount ..< segments.count {
            let segment = segments[i]
            let start = baseTime + segment.timestamp
            let end = start + segment.duration
            if end > start {
                let part = SubtitlePart(start, end, segment.substring)
                subtitle.parts.append(part)
            }
        }
        subtitle.parts.sort()
        lastSegmentCount = segments.count
        lock.unlock()
    }
}
#endif
