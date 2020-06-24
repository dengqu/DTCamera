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
    private let isFile: Bool

    private var isFirstTimeDidMoveToParent = true

    private let previewView = OpenGLPreviewView()
    
    private let dismissButton = UIButton()
    private let positionButton = UIButton()
    private let ratioButton = UIButton()
    
    private let shutterButton = UIButton()

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
    
    init(mode: MediaMode, isFile: Bool) {
        self.mode = mode
        self.isFile = isFile
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
                
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
        dismissButton.setImage(#imageLiteral(resourceName: "close_white"), for: .normal)
        dismissButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        
        ratioButton.setImage(pipeline.ratioMode.icon, for: .normal)
        ratioButton.addTarget(self, action: #selector(toggleRatio), for: .touchUpInside)

        let positionButtonTitle = NSAttributedString(string: pipeline.positionMode.title,
                                                  attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                               .foregroundColor: UIColor.white])
        positionButton.setAttributedTitle(positionButtonTitle, for: .normal)
        positionButton.addTarget(self, action: #selector(togglePosition), for: .touchUpInside)

        updateShutterButton(isRecording: false)
        shutterButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
                        
        videoInfosLabel.font = UIFont.boldSystemFont(ofSize: 11)
        videoInfosLabel.textColor = UIColor.white
        videoInfosLabel.textAlignment = .right
        videoInfosLabel.numberOfLines = 0
        
        view.addSubview(dismissButton)
        view.addSubview(positionButton)
        view.addSubview(ratioButton)
        view.addSubview(shutterButton)
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
        shutterButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(-53)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top).offset(-53)
            }
        }
        videoInfosLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-6)
            make.top.equalTo(shutterButton)
        }
    }

    private func toggleControls(isHidden: Bool) {
        ratioButton.isHidden = isHidden
        positionButton.isHidden = isHidden
        shutterButton.isHidden = isHidden
        videoInfosLabel.isHidden = isHidden
    }
    
    private func toggleRecordingControls(isHidden: Bool) {
        dismissButton.isHidden = !isHidden
        ratioButton.isHidden = !isHidden
        positionButton.isHidden = !isHidden
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
    
    @objc private func toggleRecording() {
        if pipeline.recordingStatus == .recording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        pipeline.startRecording()
        toggleRecordingControls(isHidden: false)
    }
    
    private func stopRecording() {
        pipeline.stopRecording()
        DispatchQueue.main.async { [weak self] in
            self?.toggleRecordingControls(isHidden: true)
            self?.updateShutterButton(isRecording: false)
        }
    }
    
    private func updateShutterButton(isRecording: Bool) {
        var title = ""
        var color = UIColor.white
        if isRecording {
            title = isFile ? "停录" : "停播"
            color = UIColor.red
        } else {
            title = isFile ? "录制" : "直播"
        }
        let shutterButtonTitle = NSAttributedString(string: title,
                                                    attributes: [.font: UIFont.systemFont(ofSize: 64),
                                                                 .foregroundColor: color])
        shutterButton.setAttributedTitle(shutterButtonTitle, for: .normal)
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
        updateShutterButton(isRecording: true)
    }
    
    func recordingPipeline(_ pipeline: RecordingPipeline, recorderDidFail error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.toggleRecordingControls(isHidden: true)
        }
    }
    
}
