//
//  RecordingViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/30.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AVFoundation
import DTMessageBar

class RecordingViewController: UIViewController {
                
    private let mode: MediaMode

    private var isFirstTimeDidMoveToParent = true

    private let previewView = OpenGLPreviewView()
    
    private let dismissButton = UIButton()
    private let positionButton = UIButton()
    private let ratioButton = UIButton()
    
    private let minDurationLabel = UILabel()
    private let shutterButton = UIButton()
    private let durationLabel = UILabel()
    private let recordingControl = RecordingControl()
    static let repeatingInterval = 100
    private var recordingTimer: DispatchSourceTimer?
    private var timeRemain = 0
    private var maxDuration: Int {
        return mode.config.maxDuration * 1000 + RecordingViewController.repeatingInterval
    }
    private var minDuration: Int {
        return mode.config.minDuration * 1000
    }
    private var currentDuration: Int {
        return maxDuration - timeRemain
    }

    private let videoInfosLabel = UILabel()
    private var videoInfosTimer: Timer?
    
    private var pipeline: RecordingPipeline!
    
    deinit {
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.willEnterForegroundNotification,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.didEnterBackgroundNotification,
                                                  object: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(mode: MediaMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        timeRemain = maxDuration
        
        pipeline = RecordingPipeline(mode: mode)
        pipeline.isRenderingEnabled = UIApplication.shared.applicationState != .background
        pipeline.delegate = self

        setupPreview()
        setupControls()
        toggleControls(isHidden: true)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(enterForeground(_:)),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(enterBackground(_:)),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        
        pipeline.configure()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        pipeline.startSessionRunning()
        startVideoInfosTimer()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        pipeline.stopSessionRunning()
        cancelVideoInfosTimer()
    }
    
    override func didMove(toParent parent: UIViewController?) {
        if !isFirstTimeDidMoveToParent {
            if parent != nil {
                pipeline.reconfigure()
                pipeline.startSessionRunning()
                startVideoInfosTimer()
            } else {
                pipeline.stopSessionRunning()
                cancelVideoInfosTimer()
            }
        } else {
            isFirstTimeDidMoveToParent = false
        }
    }
    
    private func setupPreview() {
        view.addSubview(previewView)
        updatePreview()
    }
    
    private func updatePreview() {
        previewView.snp.remakeConstraints { make in
            make.left.right.equalToSuperview()
            let offset: CGFloat = pipeline.ratioMode == .r1to1 ? 58 : 0
            if #available(iOS 11, *) {
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top).offset(offset)
            } else {
                make.top.equalTo(self.topLayoutGuide.snp.bottom).offset(offset)
            }
            make.height.equalTo(previewView.snp.width).multipliedBy(pipeline.ratioMode.ratio)
        }
    }
    
    private func setupControls() {
        let dismissButtonTitle = NSAttributedString(string: "关闭",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                 .foregroundColor: UIColor.white])
        dismissButton.setAttributedTitle(dismissButtonTitle, for: .normal)
        dismissButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        
        ratioButton.setImage(pipeline.ratioMode.icon, for: .normal)
        ratioButton.addTarget(self, action: #selector(toggleRatio), for: .touchUpInside)

        let positionButtonTitle = NSAttributedString(string: pipeline.positionMode.title,
                                                  attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                               .foregroundColor: UIColor.white])
        positionButton.setAttributedTitle(positionButtonTitle, for: .normal)
        positionButton.addTarget(self, action: #selector(togglePosition), for: .touchUpInside)

        minDurationLabel.font = UIFont.boldSystemFont(ofSize: 11)
        minDurationLabel.textColor = UIColor(hex: "#C8C8C8")
        minDurationLabel.text = "请拍摄\(mode.config.minDuration)秒以上视频"

        let shutterButtonTitle = NSAttributedString(string: "录制",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 64),
                                                                 .foregroundColor: UIColor.white])
        shutterButton.setAttributedTitle(shutterButtonTitle, for: .normal)
        shutterButton.addTarget(self, action: #selector(startRecording), for: .touchUpInside)
        
        durationLabel.font = UIFont.boldSystemFont(ofSize: 14)
        durationLabel.textColor = UIColor.white
        durationLabel.isHidden = true

        recordingControl.controlButton.addTarget(self, action: #selector(stopRecording), for: .touchUpInside)
        recordingControl.isHidden = true
                
        videoInfosLabel.font = UIFont.boldSystemFont(ofSize: 11)
        videoInfosLabel.textColor = UIColor.white
        videoInfosLabel.textAlignment = .right
        videoInfosLabel.numberOfLines = 0

        updateDuration()
        
        view.addSubview(dismissButton)
        view.addSubview(positionButton)
        view.addSubview(ratioButton)
        view.addSubview(minDurationLabel)
        view.addSubview(shutterButton)
        view.addSubview(durationLabel)
        view.addSubview(recordingControl)
        view.addSubview(videoInfosLabel)

        dismissButton.snp.makeConstraints { make in
            if #available(iOS 11, *) {
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top).offset(12)
            } else {
                make.top.equalTo(self.topLayoutGuide.snp.bottom).offset(12)
            }
            make.left.equalToSuperview().offset(12)
        }
        positionButton.snp.makeConstraints { make in
            make.centerY.equalTo(dismissButton)
            make.right.equalTo(ratioButton.snp.left).offset(-24)
        }
        ratioButton.snp.makeConstraints { make in
            make.centerY.equalTo(dismissButton)
            make.right.equalToSuperview().offset(-12)
        }
        minDurationLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(shutterButton.snp.top).offset(-18)
        }
        shutterButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(-53)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top).offset(-53)
            }
        }
        durationLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(recordingControl.snp.top).offset(-8)
        }
        recordingControl.snp.makeConstraints { make in
            make.size.equalTo(82)
            make.centerX.equalToSuperview()
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(-44)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top).offset(-44)
            }
        }
        videoInfosLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-6)
            make.top.equalTo(recordingControl)
        }
    }

    private func toggleControls(isHidden: Bool) {
        ratioButton.isHidden = isHidden
        positionButton.isHidden = isHidden
        shutterButton.isHidden = isHidden
        minDurationLabel.isHidden = isHidden
        videoInfosLabel.isHidden = isHidden
    }
    
    private func toggleRecordingControls(isHidden: Bool) {        
        dismissButton.isHidden = !isHidden
        ratioButton.isHidden = !isHidden
        positionButton.isHidden = !isHidden
        minDurationLabel.isHidden = !isHidden
        shutterButton.isHidden = !isHidden
        
        durationLabel.isHidden = isHidden
        recordingControl.isHidden = isHidden
    }
        
    private func updateDuration() {
        if pipeline.recordingStatus == .recording {
            let duration = currentDuration
            let progress = CGFloat(duration) / CGFloat(maxDuration)
            durationLabel.text = "\(duration / 1000).\((duration % 1000) / RecordingViewController.repeatingInterval)秒"
            recordingControl.setProgress(progress)
            recordingControl.toggleEnable(isEnable: duration >= self.minDuration)
        } else {
            durationLabel.text = "0.0秒"
            recordingControl.toggleEnable(isEnable: false)
        }
    }
        
    private func cancelRecordingTimer() {
        recordingTimer?.cancel()
        recordingTimer = nil
        timeRemain = maxDuration
    }
    
    private func startRecordingTimer() {
        if recordingTimer == nil {
            let queue = DispatchQueue.global()
            recordingTimer = DispatchSource.makeTimerSource(queue: queue)
            recordingTimer?.schedule(deadline: .now(), repeating: .milliseconds(RecordingViewController.repeatingInterval))
        }
        recordingTimer?.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            self.countDownRecordingTimer()
        })
        recordingTimer?.resume()
    }
    
    private func countDownRecordingTimer() {
        timeRemain -= RecordingViewController.repeatingInterval
        if timeRemain == 0 {
            stopRecording()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateDuration()
            }
        }
    }
    
    private func cancelVideoInfosTimer() {
        videoInfosTimer?.invalidate()
        videoInfosTimer = nil
    }
    
    private func startVideoInfosTimer() {
        videoInfosTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self,
                                               selector: #selector(updateVideoInfo),
                                               userInfo: nil, repeats: true)
    }
    
    @objc private func updateVideoInfo() {
        videoInfosLabel.text = "\(Int(roundf(pipeline.videoFrameRate))) FPS\n"
            + "C \(pipeline.videoDimensions.width) x \(pipeline.videoDimensions.height) px\n"
            + "E \(pipeline.effectFilterVideoDimensions.width) x \(pipeline.effectFilterVideoDimensions.height) px\n"
            + "L \(Int(previewView.bounds.width)) x \(Int(previewView.bounds.height)) p"
    }
            
    private func previewVideo(_ video: URL) {
        let previewVideoVC = PreviewVideoViewController(mode: mode, video: video)
        previewVideoVC.delegate = self
        previewVideoVC.modalPresentationStyle = .fullScreen
        present(previewVideoVC, animated: true, completion: nil)
    }
        
    @objc private func enterForeground(_ notificaton: Notification) {
        if isViewLoaded && view.window != nil {
            pipeline.isRenderingEnabled = true
            pipeline.startSessionRunning()
            startVideoInfosTimer()
        }
    }
    
    @objc private func enterBackground(_ notificaton: Notification) {
        if isViewLoaded && view.window != nil {
            pipeline.isRenderingEnabled = false
            pipeline.stopSessionRunning()
            cancelVideoInfosTimer()
            stopRecording()
        }
    }

    @objc private func close() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    @objc private func toggleRatio() {
        pipeline.isRenderingEnabled = false
        pipeline.stopSessionRunning()
        
        switch pipeline.ratioMode {
        case .r1to1:
            pipeline.ratioMode = .r3to4
        case .r3to4:
            pipeline.ratioMode = .r9to16
        case .r9to16:
            pipeline.ratioMode = .r1to1
        }

        ratioButton.setImage(pipeline.ratioMode.icon, for: .normal)
        updatePreview()
        previewView.resetInputAndOutputDimensions()
        pipeline.reprepareEffectFilter()
        
        pipeline.startSessionRunning()
        pipeline.isRenderingEnabled = true
    }
    
    @objc private func togglePosition() {
        pipeline.isRenderingEnabled = false
        pipeline.stopSessionRunning()
        
        switch pipeline.positionMode {
        case .front:
            pipeline.positionMode = .back
        case .back:
            pipeline.positionMode = .front
        }

        let positionButtonTitle = NSAttributedString(string: pipeline.positionMode.title,
                                                  attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                               .foregroundColor: UIColor.white])
        positionButton.setAttributedTitle(positionButtonTitle, for: .normal)
        pipeline.reconfigure(needReprepareEffectFilter: true)
        previewView.resetInputAndOutputDimensions()
        
        pipeline.startSessionRunning()
        pipeline.isRenderingEnabled = true
    }
    
    @objc private func startRecording() {
        pipeline.startRecording()
        toggleRecordingControls(isHidden: false)
    }
    
    @objc private func stopRecording() {
        pipeline.stopRecording()
        cancelRecordingTimer()
        DispatchQueue.main.async { [weak self] in
            self?.toggleRecordingControls(isHidden: true)
            self?.updateDuration()
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let touchPoint = touch.location(in: previewView)
        let glPoint = CGPoint(x: touchPoint.x / previewView.bounds.width, y: touchPoint.y / previewView.bounds.height)
        let aspectRatio = previewView.bounds.width / previewView.bounds.height
        let x = (glPoint.x * 2.0) - 1.0
        let y = ((glPoint.y * 2.0) - 1.0) * (-1.0 / aspectRatio)
        pipeline.addEmitter(x: x, y: y)
    }
    
}

extension RecordingViewController: RecordingPipelineDelegate {
    
    func recordingPipelineConfigSuccess(_ pipeline: RecordingPipeline) {
        DispatchQueue.main.async { [weak self] in
            self?.toggleControls(isHidden: false)
        }
    }
    
    func recordingPipelineNotAuthorized(_ pipeline: RecordingPipeline) {
        DispatchQueue.main.async {
            DTMessageBar.error(message: "相机未授权", position: .bottom)
        }
    }
    
    func recordingPipelineConfigFailed(_ pipeline: RecordingPipeline) {
        DispatchQueue.main.async {
            DTMessageBar.error(message: "相机没法用", position: .bottom)
        }
    }
    
    func recordingPipeline(_ pipeline: RecordingPipeline, display pixelBuffer: CVPixelBuffer) {
        previewView.display(pixelBuffer: pixelBuffer)
    }
    
    func recordingPipelineRecorderDidFinishPreparing(_ pipeline: RecordingPipeline) {
        startRecordingTimer()
    }
    
    func recordingPipeline(_ pipeline: RecordingPipeline, recorderDidFail error: Error?) {
        cancelRecordingTimer()
        DispatchQueue.main.async { [weak self] in
            self?.toggleRecordingControls(isHidden: true)
            self?.updateDuration()
        }
    }
    
    func recordingPipeline(_ pipeline: RecordingPipeline, recorderDidFinish video: URL) {
        DispatchQueue.main.async { [weak self] in
            self?.previewVideo(video)
        }
    }
    
}

extension RecordingViewController: PreviewVideoViewControllerDelegate {
    
    func previewVideo(viewController: PreviewVideoViewController, didFinish video: URL) {
        dismiss(animated: false) { [weak self] in
            self?.close()
        }
    }
    
}
