# KSPlayer

![Build Status](https://img.shields.io/badge/build-%20passing%20-blue.svg)
![Platform](https://img.shields.io/badge/Platform-%20iOS%20macOS%20tvOS%20visionOS%20-blue.svg)
![License](https://img.shields.io/badge/license-GPL-blue.svg)

KSPlayer is a powerful media play framework for iOS, tvOS, macOS, xrOS, visionOS, Mac Catalyst. based on AVPlayer and FFmpeg, support AppKit/UIKit/SwiftUI. This is a reconstruction from Forward\* v1.3.17.

English | [简体中文](./README_CN.md)

## License
KSPlayer defaults to the GPL license (requires open-sourcing your own project code), and we hope everyone will consciously respect the licensing agreement of the KSPlayer project. Additionally, there is a paid version that adopts the LGPL license (contact us).

If due to commercial reasons, you prefer not to adhere to the GPL license  or the LGPL license, you can contact us. Through our authorization, you can obtain a more flexible licensing agreement.

## Features
Functional differences between GPL version, LGPL version and this forward branch (Forward column).
Some features of the LGPL version require a one-time payment, which I have used 💰 to mark them out.

To experience the powerful features of the LGPL version, you can download the app from the App Store. [App Store Link](https://apps.apple.com/app/tracyplayer/id6450770064)


| Feature     | LGPL      | GPL    | Forward |
| ----------- | --------- | ------ | ------- |
|Video upscaling |💰|❌|✅|
|ProgressBar Preview |💰|❌|✅|
|Precache data to Hard Drive|💰|❌|✅|
|Video switching with zero delay|💰|❌|✅|
|Audio Passthrough Output by Wi-Fi|💰|❌|❌|
|Dovi P5 displays HDR (not overheating)|💰|❌|✅|
|Live streaming supports rewind viewing|💰|❌|❌|
|ISO Blu-ray disc playback on all Apple platforms|💰|❌|❌|
|Simultaneous playback of separate audio and video URLs|💰|❌|❌|
|Offline AI real-time subtitle generation and translation|💰|❌|❌|
|ProAVPlayer supports MKV, native Dolby Vision and Dolby Atmos.|💰|❌|✅|
|Play videos in a small window in the App (resumable, supports iOS and tvOS)|💰|❌|❌|
|Dolby AC-4|✅|❌|❌|
|Swift Concurrency|✅|❌|✅|
|AV1 hardware decoding|✅|❌|✅|
|Word-by-word subtitles|✅|❌|✅|
|All demuxers, All decoders|✅|❌|❌|
|Text subtitle translation|✅|❌|✅|
|Use System Caption Appearance|✅|❌|✅|
|Record video clips at any time|✅|❌|✅|
|Smoothly Play 8K or 120 FPS Video|✅|❌|✅|
|Display Subtitles with HDR Effects|✅|❌|✅|
|Video download and format conversion|✅|❌|✅|
|External image subtitles, such as SUP|✅|❌|✅|
|Main subtitles and Secondary subtitles|✅|❌|✅|
|Adjust Saturation, Brightness, and Contrast|✅|❌|✅|
|Picture in Picture supports subtitle display|✅|❌|✅|
|Annex-B async hardware decoding(Live Stream)|✅|❌|✅|
|Use the fonts in the video to render subtitles|✅|❌|✅|
|Use memory cache for fast seek in short time range|✅|❌|✅|
|KSMEPlayer supports all demuxing and decoding formats|✅|❌|❌|
|Full display of ass subtitles effect(Render as image using libass)|✅|❌|✅|
|FFmpeg version|8.0.1|6.1.0|8.1.1|
|Record video|✅|✅|✅|
|360° panorama video|✅|✅|✅|
|Picture in Picture|✅|✅|✅|
|Hardware accelerator|✅|✅|✅|
|Seamless loop playback|✅|✅|✅|
|De-interlace auto detect|✅|✅|✅|
|Multichannel Audio/Spatial Audio|✅|✅|✅|
|4k/HDR/HDR10/HDR10+/Dolby Vision|✅|✅|✅|
|Custom url protocols such as nfs/smb/UPnP |✅|✅|✅|
|Text subtitle/Image subtitle/Closed Captions|✅|✅|✅|
|Search Online Subtitles(shooter/assrt/opensubtitles)|✅|✅|✅|
|Low latency 4K live video streaming (less than 200ms on LAN)|✅|✅|✅|
|Automatically switch to multi-bitrate streams based on network|✅|✅|✅|


## Requirements

- iOS 13+, macOS 10.15+, tvOS 13+, xrOS 1+
