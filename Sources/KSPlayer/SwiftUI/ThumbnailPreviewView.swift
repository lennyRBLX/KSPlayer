//
//  ThumbnailPreviewView.swift
//  KSPlayer
//
//  RE source: Forward v1.3.15
//  - SwipeTimeInfoView gesture integration with thumbQueue (RE/64)
//  - RealtimeThumbnailGenerator @Published → SwiftUI overlay
//  - Velocity calculation (velocity / 262144, ±0.01 clamping)
//

import Combine
import SwiftUI

// MARK: - ThumbnailPreviewView (scrub preview overlay)

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
public struct ThumbnailPreviewView: View {
    @ObservedObject var thumbState: ThumbState
    let sliderWidth: CGFloat

    public init(thumbState: ThumbState, sliderWidth: CGFloat) {
        self.thumbState = thumbState
        self.sliderWidth = sliderWidth
    }

    public var body: some View {
        if thumbState.isSeeking || thumbState.currentImage != nil {
            VStack(spacing: 4) {
                thumbnailImage
                if let time = thumbState.currentDisplayedTime {
                    Text(formatTime(time))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.white)
                }
            }
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(.easeOut(duration: 0.15), value: thumbState.currentImage != nil)
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let cgImage = thumbState.currentImage {
            #if canImport(UIKit)
            Image(uiImage: UIImage(cgImage: cgImage))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: thumbnailWidth, height: thumbnailHeight(for: cgImage))
                .cornerRadius(4)
            #else
            Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: thumbnailWidth, height: thumbnailHeight(for: cgImage))
                .cornerRadius(4)
            #endif
        } else if thumbState.isSeeking {
            ProgressView()
                .frame(width: thumbnailWidth, height: thumbnailWidth * 9 / 16)
        }
    }

    private var thumbnailWidth: CGFloat {
        min(200, sliderWidth * 0.4)
    }

    private func thumbnailHeight(for image: CGImage) -> CGFloat {
        let aspect = CGFloat(image.height) / CGFloat(image.width)
        return thumbnailWidth * aspect
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - ScrubPreviewSlider (integrated slider + thumbnail preview)

@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
public struct ScrubPreviewSlider: View {
    @Binding var currentTime: Float
    let totalTime: Float
    let generator: RealtimeThumbnailGenerator?
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false

    public init(currentTime: Binding<Float>, totalTime: Float,
                generator: RealtimeThumbnailGenerator?,
                onEditingChanged: @escaping (Bool) -> Void) {
        self._currentTime = currentTime
        self.totalTime = totalTime
        self.generator = generator
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if isDragging, let generator {
                    ThumbnailPreviewView(thumbState: generator.thumbState, sliderWidth: geo.size.width)
                        .frame(maxWidth: .infinity)
                        .offset(x: previewOffset(in: geo.size.width))
                }

                Slider(value: $currentTime, in: 0 ... max(1, totalTime)) { editing in
                    isDragging = editing
                    if editing {
                        requestThumbnail()
                    }
                    onEditingChanged(editing)
                }
                .frame(maxHeight: 20)
                .onChange(of: currentTime) { _ in
                    if isDragging {
                        requestThumbnail()
                    }
                }
            }
        }
        .frame(height: isDragging ? 160 : 20)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }

    private func requestThumbnail() {
        guard let generator, totalTime > 0 else { return }
        let fraction = Double(currentTime / totalTime)
        let duration = generator.videoDuration
        let time = fraction * duration
        let frameCount = max(10, Int(duration / (duration / 100)))
        let index = max(0, min(frameCount - 1, Int(fraction * Double(frameCount))))
        generator.seekToFrame(at: index)
    }

    private func previewOffset(in width: CGFloat) -> CGFloat {
        guard totalTime > 0 else { return 0 }
        let fraction = CGFloat(currentTime / totalTime)
        let rawOffset = (fraction - 0.5) * width * 0.6
        return rawOffset
    }
}
