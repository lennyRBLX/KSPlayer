//
//  CustomProgressView.swift
//  KSPlayer
//
//  Forward addition (RE): Custom progress display view that mirrors
//  the toolbar's time slider and labels for alternate layout.
//
//  Binary: _TtC8KSPlayer18CustomProgressView (2 functions)
//  RE source: Forward v1.3.15
//

#if canImport(UIKit)
import UIKit

public class CustomProgressView: UIView {
    weak var playView: PlayerView?
    private var progressSlider: KSSlider?
    private var currentTimeLabel: UILabel?
    private var totalTimeLabel: UILabel?

    // RE: CustomProgressView_init_withPlayView @ 0x1014eabfc (0x120 = 288 bytes)
    public init(playView: PlayerView) {
        self.playView = playView
        self.progressSlider = playView.toolBar.timeSlider
        self.currentTimeLabel = playView.toolBar.currentTimeLabel
        self.totalTimeLabel = playView.toolBar.totalTimeLabel
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // RE: CustomProgressView_setupUI @ 0x1014ead28 (0x798 = 1944 bytes).
    // Per UIComponents.md §5.3: does NOT create its own slider. Re-parents the
    // same `toolBar.timeSlider`, `currentTimeLabel`, `totalTimeLabel` from
    // PlayerToolBar into a minimal fullscreen layout.
    //
    // Fullscreen appearance: min track = white, max track = gray, thumb = 1x1pt
    // (invisible), height constraint = 30pt, label font =
    // monospacedDigitSystemFont 14pt bold. Layout:
    //   [currentTime] --12pt-- [====slider====] --12pt-- [totalTime]
    private func setupUI() {
        guard let currentTimeLabel, let totalTimeLabel, let progressSlider else {
            return
        }

        // Re-parent the toolbar's slider + labels into this view.
        currentTimeLabel.removeFromSuperview()
        totalTimeLabel.removeFromSuperview()
        progressSlider.removeFromSuperview()
        addSubview(currentTimeLabel)
        addSubview(progressSlider)
        addSubview(totalTimeLabel)

        // Fullscreen appearance overrides.
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        totalTimeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        currentTimeLabel.textColor = .white
        totalTimeLabel.textColor = .white
        progressSlider.minimumTrackTintColor = .white
        progressSlider.maximumTrackTintColor = .gray
        // Invisible 1x1 thumb so only the track shows.
        let invisibleThumb = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        progressSlider.setThumbImage(invisibleThumb, for: .normal)
        progressSlider.setThumbImage(invisibleThumb, for: .highlighted)

        // Constraints: 12pt gap on each side, 30pt height.
        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        totalTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            currentTimeLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            currentTimeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 12),
            progressSlider.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressSlider.trailingAnchor.constraint(equalTo: totalTimeLabel.leadingAnchor, constant: -12),
            totalTimeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            totalTimeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
#endif
