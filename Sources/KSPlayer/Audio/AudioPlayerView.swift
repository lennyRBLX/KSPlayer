//
//  AudioPlayerView.swift
//  VoiceNote
//
//  Created by kintan on 2018/8/16.
//

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
/// RE: 0x1013CAF2C (AudioPlayerView class metadata, 1.3.15)
/// ObjC-rooted UIView, parent KSPlayer.PlayerView, 0 stored fields.
/// Audio-only sibling of VideoPlayerView; inherits the full PlayerView
/// field set (playerLayer, delegate, toolBar, playTimeDidChange, backBlock)
/// and adds no state of its own.
open class AudioPlayerView: PlayerView {
    /// RE: 0x1013CA8E4 (AudioPlayerView.init(frame:) — toolBar setup + constraints, 1.3.15)
    override public init(frame: CGRect) {
        super.init(frame: frame)
        toolBar.timeType = .min
        toolBar.spacing = 5
        toolBar.addArrangedSubview(toolBar.playButton)
        toolBar.addArrangedSubview(toolBar.currentTimeLabel)
        toolBar.addArrangedSubview(toolBar.timeSlider)
        toolBar.addArrangedSubview(toolBar.totalTimeLabel)
        toolBar.playButton.tintColor = UIColor(rgb: 0x2166FF)
        toolBar.timeSlider.setThumbImage(UIColor(rgb: 0x2980FF).createImage(size: CGSize(width: 2, height: 15)), for: .normal)
        toolBar.timeSlider.minimumTrackTintColor = UIColor(rgb: 0xC8C7CC)
        toolBar.timeSlider.maximumTrackTintColor = UIColor(rgb: 0xEDEDED)
        toolBar.timeSlider.trackHeight = 7
        addSubview(toolBar)
        toolBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            toolBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            toolBar.topAnchor.constraint(equalTo: topAnchor),
            toolBar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
