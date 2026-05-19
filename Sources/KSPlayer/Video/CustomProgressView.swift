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
    private var progressSlider: UIView?
    private var currentTimeLabel: UILabel?
    private var totalTimeLabel: UILabel?

    // RE: CustomProgressView_init_withPlayView @ 0x1014eabfc
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

    // RE: CustomProgressView_setupUI @ 0x1014ead28
    private func setupUI() {
        // Layout progress slider and time labels
    }
}
#endif
