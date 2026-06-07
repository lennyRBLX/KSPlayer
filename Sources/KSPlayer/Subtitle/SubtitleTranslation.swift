//
//  SubtitleTranslation.swift
//  KSPlayer
//
//  RE: 0x10149299c (SubtitleModel.translateAndLayoutSecondarySubtitle, 1.3.15)
//  This cluster reconstructs ONLY branch B of that dual-purpose continuation: the
//  on-device translation path (no secondarySubtitleActor), using Apple's
//  TranslationSession (iOS 17.4+). Branch A — aspect-ratio + subtitleDelay
//  positioning at VerticalAlignment.top — lives in VideoSubtitleView.swift /
//  KSSubtitle.swift and must not be duplicated here.
//  Integrates with existing secondarySubtitleActor / secondParts infrastructure.
//

import Foundation
import SwiftUI

// MARK: - Translation Configuration

public struct SubtitleTranslationConfig {
    public var sourceLanguage: Locale.Language?
    public var targetLanguage: Locale.Language
    public var isEnabled: Bool

    public init(targetLanguage: Locale.Language = .init(identifier: "en"),
                sourceLanguage: Locale.Language? = nil,
                isEnabled: Bool = false) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.isEnabled = isEnabled
    }
}

// MARK: - TranslationSubtitleInfo

/// RE: 0x10149299c (SubtitleModel.translateAndLayoutSecondarySubtitle, 1.3.15).
/// That continuation is DUAL-PURPOSE: branch A computes secondary-subtitle
/// vertical positioning (16:9 = 1.77778 aspect threshold + `subtitleDelay`,
/// anchored at `VerticalAlignment.top`, with `secondarySubtitleActor`), and
/// branch B performs `TranslationSession` on-device translation (without
/// `secondarySubtitleActor`). This type reconstructs ONLY branch B. The
/// positioning half (branch A) already lives in VideoSubtitleView.swift and
/// KSSubtitle.swift — do not duplicate it here.
public class TranslationSubtitleInfo: KSSubtitle, SubtitleInfo {
    public var isEnabled: Bool = false
    public var delay: TimeInterval = 0
    public let subtitleID: String
    public let name: String
    private let sourceInfo: any SubtitleInfo
    private var translationConfig: SubtitleTranslationConfig
    private let lock = NSLock()
    private var translatedCache = [String: String]()

    #if canImport(Translation)
    @available(iOS 17.4, macOS 14.4, *)
    private var session: (any Sendable)?

    @available(iOS 17.4, macOS 14.4, *)
    private func getOrCreateSession() async -> Any? {
        if let session {
            return session
        }
        do {
            let config = TranslationSession.Configuration(
                source: translationConfig.sourceLanguage,
                target: translationConfig.targetLanguage
            )
            let newSession = try await TranslationSession(configuration: config)
            session = newSession as (any Sendable)
            return newSession
        } catch {
            KSLog("[translation] failed to create session: \(error)")
            return nil
        }
    }
    #endif

    public init(source: any SubtitleInfo, config: SubtitleTranslationConfig) {
        self.sourceInfo = source
        self.translationConfig = config
        self.subtitleID = "translation-\(source.subtitleID)-\(config.targetLanguage.minimalIdentifier)"
        self.name = "Translated (\(Locale.current.localizedString(forLanguageCode: config.targetLanguage.minimalIdentifier) ?? config.targetLanguage.minimalIdentifier))"
        super.init()
    }

    override public func search(for time: TimeInterval) -> [SubtitlePart] {
        let sourceParts = sourceInfo.search(for: time)
        guard !sourceParts.isEmpty else { return [] }

        var result = [SubtitlePart]()
        for part in sourceParts {
            guard let text = part.text?.string, !text.isEmpty else { continue }
            lock.lock()
            let cached = translatedCache[text]
            lock.unlock()

            if let cached {
                var translatedPart = SubtitlePart(part.start, part.end, cached)
                translatedPart.textPosition = TextPosition(verticalAlign: .top, horizontalAlign: .center)
                result.append(translatedPart)
            } else {
                Task { await translateText(text) }
                var pendingPart = SubtitlePart(part.start, part.end, text)
                pendingPart.textPosition = TextPosition(verticalAlign: .top, horizontalAlign: .center)
                result.append(pendingPart)
            }
        }
        return result
    }

    private func translateText(_ text: String) async {
        #if canImport(Translation)
        guard #available(iOS 17.4, macOS 14.4, *) else { return }
        guard let session = await getOrCreateSession() as? TranslationSession else { return }
        do {
            let response = try await session.translate(text)
            lock.lock()
            translatedCache[text] = response.targetText
            lock.unlock()
        } catch {
            KSLog("[translation] error: \(error)")
        }
        #endif
    }
}

// MARK: - SubtitleModel extension

public extension SubtitleModel {
    var translationConfig: SubtitleTranslationConfig {
        get { _translationConfig ?? SubtitleTranslationConfig() }
        set { _translationConfig = newValue }
    }

    func enableTranslation(for source: (any SubtitleInfo)?, config: SubtitleTranslationConfig) {
        guard let source, config.isEnabled else {
            selectedSecondSubtitleInfo = nil
            return
        }
        let translationInfo = TranslationSubtitleInfo(source: source, config: config)
        addSubtitle(info: translationInfo)
        selectedSecondSubtitleInfo = translationInfo
    }
}

private var translationConfigKey: UInt8 = 0

private extension SubtitleModel {
    var _translationConfig: SubtitleTranslationConfig? {
        get { objc_getAssociatedObject(self, &translationConfigKey) as? SubtitleTranslationConfig }
        set { objc_setAssociatedObject(self, &translationConfigKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
