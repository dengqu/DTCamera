//
//  PlayerView.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/7/16.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AVFoundation
import SnapKit
import Action
import DTMessageBar

class PlayerView: UIView {
    
    enum Style {
        case inline
        case fullScreen
        case simple
    }
    
    private let style: Style
    
    private var indicatorView: UIActivityIndicatorView!
    private var switchScreenButton: UIButton!
    private var controlButton: UIButton!
    private var sliderView: UIView!
    private var progressView: UIProgressView!
    private var currentTimeLabel: UILabel!
    private var slider: UISlider!
    private var totalTimeLabel: UILabel!
    private var dismissButton: UIButton!

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    private var playerLayer: AVPlayerLayer? {
        return layer as? AVPlayerLayer
    }
    
    private var player: AVPlayer? {
        get {
            return playerLayer?.player
        }
        set {
            playerLayer?.player = newValue
        }
    }
    
    private var duration: Float64 = 0
    private var isPlaying = false {
        didSet {
            if isPlaying {
                if isEnded {
                    player?.seek(to: .zero)
                    isEnded = false
                }
                player?.play()
                let controlButtonTitle = NSAttributedString(string: "暂停",
                                                            attributes: [.font: UIFont.systemFont(ofSize: 48),
                                                                         .foregroundColor: UIColor.white])
                controlButton.setAttributedTitle(controlButtonTitle, for: .normal)
                hideControlButtonLater()
                if style == .inline {
                    sliderView.isHidden = false
                }
                if let action = playingAction {
                    action.execute(())
                }
            } else {
                player?.pause()
                let controlButtonTitle = NSAttributedString(string: "播放",
                                                            attributes: [.font: UIFont.systemFont(ofSize: 48),
                                                                         .foregroundColor: UIColor.white])
                controlButton.setAttributedTitle(controlButtonTitle, for: .normal)
                cancelHideControlButton()
            }
        }
    }
    private var isEnded = false
    private var isSliding = false
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var currentTimeObservation: Any?
    private var timer: DispatchSourceTimer?
    private var autoPlayWhenReady = false
    
    var fullScreenAction: CocoaAction?
    var playingAction: CocoaAction?
    var finishPlayingAction: CocoaAction?
    var networkWarningAction: CocoaAction?
    var exitAction: CocoaAction?
    
    var currentPlayer: AVPlayer? { // don`t use this control playing
        return player
    }
    
    var isPlayingNow: Bool {
        return isPlaying
    }
    
    deinit {
        if let currentTimeObservation = currentTimeObservation {
            player?.removeTimeObserver(currentTimeObservation)
            self.currentTimeObservation = nil
        }
        cancelHideControlButton()
        NotificationCenter.default.removeObserver(self,
                                                  name: .AVPlayerItemDidPlayToEndTime,
                                                  object: player?.currentItem)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(style: Style) {
        self.style = style
        
        super.init(frame: .zero)
        
        backgroundColor = .black
        
        indicatorView = UIActivityIndicatorView(style: .white)
        addSubview(indicatorView)
        indicatorView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        controlButton = UIButton()
        let controlButtonTitle = NSAttributedString(string: "播放",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 48),
                                                                 .foregroundColor: UIColor.white])
        controlButton.setAttributedTitle(controlButtonTitle, for: .normal)
        controlButton.addTarget(self, action: #selector(onControl), for: .touchUpInside)
        addSubview(controlButton)
        controlButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        if style != .simple {
            sliderView = UIView()
            sliderView.backgroundColor = UIColor(white: 0, alpha: 0.48)
            addSubview(sliderView)
            sliderView.snp.makeConstraints { make in
                make.left.right.equalToSuperview()
                make.height.equalTo(self.style == .inline ? 24 : 36)
                if #available(iOS 11, *) {
                    make.bottom.equalTo(self.safeAreaLayoutGuide.snp.bottom)
                } else {
                    make.bottom.equalToSuperview()
                }
            }
            
            setupCurrentTimeLabel()
        }
        
        if style == .inline {
            setupProgressView()
        } else if style == .fullScreen {
            setupSlider()
            
            dismissButton = UIButton()
            let dismissButtonTitle = NSAttributedString(string: "关闭",
                                                        attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                     .foregroundColor: UIColor.white])
            dismissButton.setAttributedTitle(dismissButtonTitle, for: .normal)
            dismissButton.addTarget(self, action: #selector(onExit), for: .touchUpInside)
            addSubview(dismissButton)
            dismissButton.snp.makeConstraints { make in
                make.top.equalToSuperview().offset(10)
                if #available(iOS 11, *) {
                    make.left.equalTo(self.safeAreaLayoutGuide.snp.left).offset(10)
                } else {
                    make.left.equalToSuperview().offset(10)
                }
            }
            
            dismissButton.isHidden = true
        }
        
        if style != .simple {
            setupTotalTimeLabel()
            
            switchScreenButton = UIButton()
            if style == .inline {
                switchScreenButton.addTarget(self, action: #selector(onFullScreen), for: .touchUpInside)
                let switchScreenButtonTitle = NSAttributedString(string: "全屏",
                                                            attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                         .foregroundColor: UIColor.white])
                switchScreenButton.setAttributedTitle(switchScreenButtonTitle, for: .normal)
            } else {
                switchScreenButton.addTarget(self, action: #selector(onExit), for: .touchUpInside)
                let switchScreenButtonTitle = NSAttributedString(string: "缩小",
                                                            attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                         .foregroundColor: UIColor.white])
                switchScreenButton.setAttributedTitle(switchScreenButtonTitle, for: .normal)
            }
            sliderView.addSubview(switchScreenButton)
            switchScreenButton.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview()
                make.width.equalTo(32 + 6 + 6)
                make.left.equalTo(totalTimeLabel.snp.right).offset(2)
                make.right.equalToSuperview().offset(-10)
            }
            
            sliderView.isHidden = true
        }
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap)))
        controlButton.isHidden = true
    }
    
    private func setupCurrentTimeLabel() {
        currentTimeLabel = UILabel()
        currentTimeLabel.textColor = .white
        currentTimeLabel.font = UIFont.systemFont(ofSize: 11)
        currentTimeLabel.text = "--:--"
        currentTimeLabel.textAlignment = .center
        sliderView.addSubview(currentTimeLabel)
        currentTimeLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        currentTimeLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(10)
            make.centerY.equalToSuperview()
            make.width.equalTo(30 + 6 + 6)
        }
    }
    
    private func setupProgressView() {
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.progress = 0
        sliderView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.left.equalTo(currentTimeLabel.snp.right).offset(2)
            make.centerY.equalToSuperview()
            make.height.equalTo(4)
        }
    }
    
    private func setupSlider() {
        slider = UISlider()
        slider.minimumValue = 0
        
        slider.isContinuous = false
        // slider开始滑动事件
        slider.addTarget(self, action: #selector(sliderTouchBegin(_:)), for: .touchDown)
        // slider滑动中事件
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        sliderView.addSubview(slider)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.snp.makeConstraints { make in
            make.left.equalTo(currentTimeLabel.snp.right).offset(2)
            make.centerY.equalToSuperview()
        }
    }
    
    private func setupTotalTimeLabel() {
        totalTimeLabel = UILabel()
        totalTimeLabel.textColor = .white
        totalTimeLabel.font = UIFont.systemFont(ofSize: 11)
        totalTimeLabel.text = "--:--"
        totalTimeLabel.textAlignment = .center
        sliderView.addSubview(totalTimeLabel)
        totalTimeLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        totalTimeLabel.snp.makeConstraints { make in
            if style == .inline {
                make.left.equalTo(progressView.snp.right).offset(2)
            } else {
                make.left.equalTo(slider.snp.right).offset(2)
            }
            make.centerY.equalToSuperview()
            make.width.equalTo(30 + 6 + 6)
        }
    }
    
    func setURL(_ url: URL) {
        let asset = AVURLAsset(url: url)
        setAsset(asset)
    }
    
    func setAsset(_ asset: AVAsset) {
        let item = AVPlayerItem(asset: asset)
        setPlayerItem(item)
    }
    
    func setPlayerItem(_ item: AVPlayerItem) {
        if player == nil {
            indicatorView.startAnimating()
            let player = AVPlayer()
            player.actionAtItemEnd = .none
            self.player = player
            player.replaceCurrentItem(with: item) // decoding audio and video
            statusObservation = item.observe(\.status) { [weak self] item, _ in
                self?.itemStatusChanged(item)
            }
        }
    }

    func setPlayer(_ player: AVPlayer) {
        if self.player == nil {
            self.player = player
            if let item = player.currentItem {
                durationChanged(item)
            }
        }
    }
    
    func play() {
        if let status = player?.currentItem?.status,
            status == .readyToPlay {
            isPlaying = true
        } else {
            autoPlayWhenReady = true
        }
    }
    
    func pause() {
        if let status = player?.currentItem?.status,
            status == .readyToPlay {
            isPlaying = false
            controlButton.isHidden = false
        }
    }
    
    private func itemStatusChanged(_ item: AVPlayerItem) {
        statusObservation?.invalidate()
        if item.status == .readyToPlay {
            if !item.duration.isIndefinite {
                durationChanged(item)
            } else {
                durationObservation = item.observe(\.duration) { [weak self] item, _ in
                    self?.durationChanged(item)
                }
            }
        } else {
            indicatorView.stopAnimating()
            DTMessageBar.error(message: "视频无法播放", position: .bottom)
        }
    }
    
    private func durationChanged(_ item: AVPlayerItem) {
        if !item.duration.isIndefinite {
            durationObservation?.invalidate()
            indicatorView.stopAnimating()
            duration = CMTimeGetSeconds(item.duration)
            let current = CMTimeGetSeconds(item.currentTime())
            if style == .inline {
                progressView.progress = Float(current / duration)
            } else if style == .fullScreen {
                slider.value = Float(current)
                slider.maximumValue = Float(duration)
            }
            if style != .simple {
                updateTime(for: currentTimeLabel, time: current)
                updateTime(for: totalTimeLabel, time: duration)
            }
            if style == .fullScreen {
                sliderView.isHidden = false
                dismissButton.isHidden = false
            }
            controlButton.isHidden = false
            
            let timeScale = CMTimeScale(NSEC_PER_SEC)
            var time = CMTime(seconds: 1, preferredTimescale: timeScale)
            currentTimeObservation =
                player?.addPeriodicTimeObserver(forInterval: time, queue: .main) { [weak self] time in
                    self?.itemCurrentTimeChanged(time)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying(_ :)),
                                                   name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
            
            if style == .inline {
                time = CMTime(seconds: 0.1, preferredTimescale: timeScale)
                player?.seek(to: time) // show first frame
            }
            
            if autoPlayWhenReady {
                isPlaying = true
            }
        }
    }
    
    private func itemCurrentTimeChanged(_ time: CMTime) {
        let current = CMTimeGetSeconds(time)
        if style != .simple {
            updateTime(for: currentTimeLabel, time: current)
        }
        if let slider = slider {
            if !isSliding {
                slider.setValue(Float(current), animated: true)
            }
        }
        if let progressView = progressView {
            progressView.setProgress(Float(current/duration), animated: true)
        }
    }
    
    @objc private func playerDidFinishPlaying(_ note: Notification) {
        isEnded = true
        isPlaying = false
        controlButton.isHidden = false
        if style == .inline {
            sliderView.isHidden = true
        } else if style == .fullScreen {
            sliderView.isHidden = false
            dismissButton.isHidden = false
        }
        if let action = finishPlayingAction {
            action.execute(())
        }
    }
    
    @objc private func sliderValueChanged(_ slider: UISlider) {
        let seconds = Double(slider.value)
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: seconds, preferredTimescale: timeScale)
        player?.seek(to: time, completionHandler: { _ in
            self.isSliding = false
        })
    }
    
    @objc private func sliderTouchBegin(_ slider: UISlider) {
        isSliding = true
    }
    
    @objc private func onTap() {
        if controlButton.isHidden {
            controlButton.isHidden = false
            if style == .fullScreen {
                sliderView.isHidden = false
                dismissButton.isHidden = false
            }
            if isPlaying {
                hideControlButtonLater()
            }
        } else {
            controlButton.isHidden = true
            if style == .fullScreen {
                sliderView.isHidden = true
                dismissButton.isHidden = true
            }
        }
    }
    
    @objc private func onControl() {
        if isPlaying {
            isPlaying = false
        } else {
            isPlaying = true
        }
    }
    
    @objc private func onFullScreen() {
        if let action = fullScreenAction {
            action.execute(())
        }
    }
    
    @objc private func onExit() {
        if let action = exitAction {
            action.execute(())
        }
    }
    
    private func updateTime(for label: UILabel, time: Float64) {
        let seconds = Int(time)
        let minute = seconds / 60
        let second = seconds - minute * 60
        label.text = String(format: "%02d:%02d", minute, second)
    }
    
    private func cancelHideControlButton() {
        timer?.cancel()
        timer = nil
    }
    
    private func hideControlButtonLater() {
        cancelHideControlButton()
        if timer == nil {
            let queue = DispatchQueue.global()
            timer = DispatchSource.makeTimerSource(queue: queue)
            timer?.schedule(deadline: .now() + .seconds(2))
        }
        timer?.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            if self.isPlaying {
                DispatchQueue.main.async {
                    self.controlButton.isHidden = true
                    if self.style == .fullScreen {
                        self.sliderView.isHidden = true
                        self.dismissButton.isHidden = true
                    }
                }
            }
        })
        timer?.resume()
    }
    
}
