//
//  CameraViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/5.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AVFoundation
import DTMessageBar

class CameraViewController: UIViewController {
    
    static let repeatingInterval = 100
    
    var source: MediaSource {
        didSet {
            if oldValue != source {
                sessionQueue.async { [weak self] in
                    self?.toggleSource()
                }
            }
        }
    }
    
    private let mode: MediaMode

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    private var setupResult: SessionSetupResult = .success
    
    private let sessionQueue = DispatchQueue(label: "camera session queue", attributes: [], target: nil)
    private let videoDataOutputQueue = DispatchQueue(label: "camera video data output queue", attributes: [], target: nil)
    private let audioDataOutputQueue = DispatchQueue(label: "camera audio data output queue", attributes: [], target: nil)

    private let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput!
    private let stillImageOutput = AVCaptureStillImageOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var videoConnection: AVCaptureConnection?
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private var audioConnection: AVCaptureConnection?
    
    private var isFirstTimeDidMoveToParent = true
    private var isCapturing = false
    private var timer: DispatchSourceTimer?
    private var timeRemain = 0
    private var maxDuration: Int {
        return mode.config.maxDuration * 1000 + CameraViewController.repeatingInterval
    }
    private var minDuration: Int {
        return mode.config.minDuration * 1000
    }
    private var currentDuration: Int {
        return maxDuration - timeRemain
    }
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
    private var ratioMode: CameraRatioMode
    private var positionMode: CameraPositionMode

    private var flashModeObservation: NSKeyValueObservation?

    private var effectFilter: EffectFilter!
    private let retainedBufferCountHint = 6
    private var videoFormatDescription: CMFormatDescription?
    private var audioFormatDescription: CMFormatDescription?
    private var videoCompressionSettings: [String : Any] = [:]
    private var audioCompressionSettings: [String : Any] = [:]
    private let isRenderingEnabledQueue = DispatchQueue(label: "camera isRendering enabled queue", attributes: [.concurrent], target: nil)
    private var _isRenderingEnabled = false
    private var isRenderingEnabled: Bool {
        get {
            isRenderingEnabledQueue.sync {
                return _isRenderingEnabled
            }
        }
        set {
            isRenderingEnabledQueue.async(flags: .barrier) { [weak self] in
                self?._isRenderingEnabled = newValue
            }
        }
    }
    private let previewPixelBufferQueue = DispatchQueue(label: "camera preview pixel buffer queue", attributes: [.concurrent], target: nil)
    private var _previewPixelBuffer: CVPixelBuffer?
    private var previewPixelBuffer: CVPixelBuffer? {
        get {
            previewPixelBufferQueue.sync {
                return _previewPixelBuffer
            }
        }
        set {
            previewPixelBufferQueue.async(flags: .barrier) { [weak self] in
                self?._previewPixelBuffer = newValue
            }
        }
    }

    private enum RecordingStatus: Int {
        case idle = 0
        case startingRecording
        case recording
        case stoppingRecording
    }
    private let recordingStatusQueue = DispatchQueue(label: "camera recording status queue", attributes: [.concurrent], target: nil)
    private var _recordingStatus: RecordingStatus = .idle
    private var recordingStatus: RecordingStatus {
        get {
            recordingStatusQueue.sync {
                return _recordingStatus
            }
        }
        set {
            recordingStatusQueue.async(flags: .barrier) { [weak self] in
                self?._recordingStatus = newValue
            }
        }
    }
    private var recorder: AssetRecorder!
    private var outputFileURL: URL?

    private let previewView = OpenGLPreviewView()
    private let dismissButton = UIButton()
    private let flashButton = UIButton()
    private let ratioButton = UIButton()
    private var collectionView: UICollectionView!
    private let minDurationLabel = UILabel()
    private let shutterButton = UIButton()
    private let countLabel = UILabel()
    private let previewImageButton = UIButton()
    private let previewButton = UIButton()
    private let doneButton = UIButton()
    private let bottomBg = UIView()
    private let durationLabel = UILabel()
    private let recordingControl = RecordingControl()
    private let thumbnailCellIdentifier = "PhotoThumbnailCell"
    
    private let frameRateLabel = UILabel()
    private let dimensionsLabel = UILabel()
    private var previousSecondTimestamps: [CMTime] = []
    private var videoFrameRate: Float = 0.0
    private var videoDimensions: CMVideoDimensions = CMVideoDimensions(width: 0, height: 0)
    private var debugLabelsTimer: Timer?

    private var photos: [UIImage] = []
    
    deinit {
        flashModeObservation?.invalidate()
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
        if mode.source == .library {
            source = mode.type == .video ? .recording : .capture
        } else {
            source = mode.source
        }
        ratioMode = mode.config.ratioMode
        positionMode = mode.config.positionMode
        
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        effectFilter = EffectOpenGLFilter()
        isRenderingEnabled = UIApplication.shared.applicationState != .background
        
        timeRemain = maxDuration
        
        setupPreview()
        setupCollectionView()
        setupControls()
        
        toggleControls(isHidden: true)

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            }
        default:
            setupResult = .notAuthorized
        }
        
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(enterForeground(_:)),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(enterBackground(_:)),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        startSessionRunning()
        
        debugLabelsTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self,
                                                selector: #selector(updateDebugLabels),
                                                userInfo: nil, repeats: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        debugLabelsTimer?.invalidate()
        debugLabelsTimer = nil
        
        stopSessionRunning()
        
        super.viewWillDisappear(animated)
    }
    
    override func didMove(toParent parent: UIViewController?) {
        if !isFirstTimeDidMoveToParent {
            if parent != nil {
                startSessionRunning()
            } else {
                stopSessionRunning()
            }
        } else {
            isFirstTimeDidMoveToParent = false
        }
    }

    private func startSessionRunning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            switch self.setupResult {
            case .success:
                self.session.startRunning()
            case .notAuthorized:
                DispatchQueue.main.async {
                    DTMessageBar.error(message: "相机未授权")
                }
            case .configurationFailed:
                DispatchQueue.main.async {
                    DTMessageBar.error(message: "相机没法用")
                }
            }
        }
    }
    
    private func stopSessionRunning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.setupResult == .success {
                self.session.stopRunning()
            }
        }
    }
    
    private func setupPreview() {
        view.addSubview(previewView)
        
        updatePreview()
    }
    
    private func updatePreview() {
        previewView.snp.remakeConstraints { make in
            make.left.right.equalToSuperview()
            let offset: CGFloat = ratioMode == .r1to1 ? 58 : 0
            if #available(iOS 11, *) {
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top).offset(offset)
            } else {
                make.top.equalTo(self.topLayoutGuide.snp.bottom).offset(offset)
            }
            make.height.equalTo(previewView.snp.width).multipliedBy(ratioMode.ratio)
        }
    }
    
    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.sectionInset = .init(top: 0, left: 9, bottom: 0, right: 9)
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 0
        layout.itemSize = .init(width: 55, height: 55)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = UIColor(white: 0, alpha: 0.2)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(PhotoThumbnailCell.self, forCellWithReuseIdentifier: thumbnailCellIdentifier)
        collectionView.dataSource = self

        view.addSubview(collectionView)
        
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.height.equalTo(73)
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(-167)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top).offset(-167)
            }
        }
    }

    private func setupControls() {
        dismissButton.setImage(#imageLiteral(resourceName: "close_white"), for: .normal)
        dismissButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)

        ratioButton.setImage(ratioMode.icon, for: .normal)
        ratioButton.addTarget(self, action: #selector(toggleRatio), for: .touchUpInside)

        minDurationLabel.font = UIFont.boldSystemFont(ofSize: 11)
        minDurationLabel.textColor = UIColor(hex: "#C8C8C8")
        minDurationLabel.text = "请拍摄\(mode.config.minDuration)秒以上视频"

        shutterButton.setImage(#imageLiteral(resourceName: "shutter"), for: .normal)
        shutterButton.addTarget(self, action: #selector(shutter), for: .touchUpInside)

        countLabel.font = UIFont.boldSystemFont(ofSize: 18)
        
        bottomBg.backgroundColor = UIColor(white: 0, alpha: 0.2)

        let previewView = UIView()
        previewImageButton.setImage(#imageLiteral(resourceName: "preview"), for: .normal)
        previewImageButton.addTarget(self, action: #selector(previewOrEditPhotos), for: .touchUpInside)
        let previewButtonTitle = NSAttributedString(string: "预览",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 12),
                                                                 .foregroundColor: UIColor.white])
        previewButton.setAttributedTitle(previewButtonTitle, for: .normal)
        previewButton.addTarget(self, action: #selector(previewOrEditPhotos), for: .touchUpInside)

        doneButton.backgroundColor = MediaViewController.theme.themeColor
        doneButton.layer.cornerRadius = 2.0
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
        
        durationLabel.font = UIFont.boldSystemFont(ofSize: 14)
        durationLabel.textColor = UIColor.white
        durationLabel.isHidden = true

        recordingControl.controlButton.addTarget(self, action: #selector(stopRecording), for: .touchUpInside)
        recordingControl.isHidden = true
        
        frameRateLabel.font = UIFont.boldSystemFont(ofSize: 11)
        frameRateLabel.textColor = UIColor.white
        
        dimensionsLabel.font = UIFont.boldSystemFont(ofSize: 11)
        dimensionsLabel.textColor = UIColor.white

        updateDuration()
        updateCountLabel()
        
        view.addSubview(dismissButton)
        view.addSubview(flashButton)
        view.addSubview(ratioButton)
        view.addSubview(bottomBg)
        previewView.addSubview(previewImageButton)
        previewView.addSubview(previewButton)
        view.addSubview(previewView)
        view.addSubview(minDurationLabel)
        view.addSubview(shutterButton)
        view.addSubview(countLabel)
        view.addSubview(doneButton)
        view.addSubview(durationLabel)
        view.addSubview(recordingControl)
        view.addSubview(frameRateLabel)
        view.addSubview(dimensionsLabel)

        dismissButton.snp.makeConstraints { make in
            if #available(iOS 11, *) {
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top).offset(12)
            } else {
                make.top.equalTo(self.topLayoutGuide.snp.bottom).offset(12)
            }
            make.left.equalToSuperview().offset(12)
        }
        flashButton.snp.makeConstraints { make in
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
        countLabel.snp.makeConstraints { make in
            make.center.equalTo(shutterButton)
        }
        previewView.snp.makeConstraints { make in
            make.centerY.equalTo(shutterButton)
            make.left.equalToSuperview().offset(28)
        }
        previewImageButton.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
        }
        previewButton.snp.makeConstraints { make in
            make.top.equalTo(previewImageButton.snp.bottom)
            make.centerX.equalToSuperview().offset(1)
            make.bottom.equalToSuperview()
        }
        doneButton.snp.makeConstraints { make in
            make.centerY.equalTo(shutterButton)
            make.right.equalToSuperview().offset(-28)
            make.width.equalTo(60)
            make.height.equalTo(32)
        }
        bottomBg.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(collectionView.snp.bottom).offset(1)
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top)
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
        dimensionsLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-6)
            make.bottom.equalTo(recordingControl.snp.centerY).offset(-2)
        }
        frameRateLabel.snp.makeConstraints { make in
            make.right.equalTo(dimensionsLabel)
            make.top.equalTo(recordingControl.snp.centerY).offset(2)
        }
    }

    private func toggleControls(isHidden: Bool) {
        collectionView.isHidden = true
        flashButton.isHidden = true
        ratioButton.isHidden = true
        shutterButton.isHidden = true
        countLabel.isHidden = true
        minDurationLabel.isHidden = true
        dimensionsLabel.isHidden = true
        frameRateLabel.isHidden = true
        if source == .capture {
            collectionView.isHidden = isHidden
            flashButton.isHidden = isHidden
            ratioButton.isHidden = isHidden
            shutterButton.isHidden = isHidden
            countLabel.isHidden = isHidden
        } else {
            shutterButton.isHidden = isHidden
            minDurationLabel.isHidden = isHidden
            dimensionsLabel.isHidden = isHidden
            frameRateLabel.isHidden = isHidden
        }
    }
    
    private func toggleRecordingControls(isHidden: Bool) {
        guard let mediaVC = parent as? MediaViewController else { return }
        
        mediaVC.toggleButtons(isHidden: !isHidden)
        
        dismissButton.isHidden = !isHidden
        minDurationLabel.isHidden = !isHidden
        shutterButton.isHidden = !isHidden
        bottomBg.isHidden = !isHidden
        
        durationLabel.isHidden = isHidden
        recordingControl.isHidden = isHidden
    }
    
    private func updateCountLabel() {
        guard let mediaVC = parent as? MediaViewController else { return }

        mediaVC.toggleButtons(isHidden: !photos.isEmpty)

        let remain = mode.config.limitOfPhotos - photos.count
        countLabel.textColor = remain == 0 ? UIColor(hex: "#B9BEC3") : MediaViewController.theme.themeColor
        countLabel.text = "\(remain)"
        previewImageButton.isHidden = photos.isEmpty
        previewButton.isHidden = photos.isEmpty
        doneButton.isHidden = photos.isEmpty
        let doneButtonTitle = NSAttributedString(string: "完成(\(photos.count))",
            attributes: [.font: UIFont.systemFont(ofSize: 14),
                         .foregroundColor: UIColor.white])
        doneButton.setAttributedTitle(doneButtonTitle, for: .normal)
    }
    
    private func updateDuration() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.recordingStatus == .recording {
                let duration = self.currentDuration
                let progress = CGFloat(duration) / CGFloat(self.maxDuration)
                self.durationLabel.text = "\(duration / 1000).\((duration % 1000) / CameraViewController.repeatingInterval)秒"
                self.recordingControl.setProgress(progress)
                self.recordingControl.toggleEnable(isEnable: duration >= self.minDuration)
            } else {
                self.durationLabel.text = "0.0秒"
                self.recordingControl.toggleEnable(isEnable: false)
            }
        }
    }
    
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        var defaultVideoDevice: AVCaptureDevice?
        var backCameraDevice: AVCaptureDevice?
        var frontCameraDevice: AVCaptureDevice?
        for cameraDevice in AVCaptureDevice.devices(for: .video) {
            if cameraDevice.position == .back {
                backCameraDevice = cameraDevice
            }
            if cameraDevice.position == .front {
                frontCameraDevice = cameraDevice
            }
        }
        if positionMode == .back {
            if let backCameraDevice = backCameraDevice {
                defaultVideoDevice = backCameraDevice
            } else {
                defaultVideoDevice = frontCameraDevice
                positionMode = .front
            }
        } else {
            if let frontCameraDevice = frontCameraDevice {
                defaultVideoDevice = frontCameraDevice
            } else {
                defaultVideoDevice = backCameraDevice
                positionMode = .back
            }
        }
        guard let videoDevice = defaultVideoDevice else {
            print("Could not find video device")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        configSessionPreset(for: videoDevice)
        
        do {
            if videoDevice.hasFlash {
                flashModeObservation = videoDevice.observe(\.flashMode) { [weak self] device, _ in
                    self?.flashModeChanged(device)
                }
                
                try videoDevice.lockForConfiguration()
                videoDevice.flashMode = .off
                videoDevice.unlockForConfiguration()
            }
        } catch {
            print("Could not config video device flash mode: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                print("Could not add video device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("Could not find audio device")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        do {
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Could not create audio device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        configSessionOutput()
        configRecordingFPS(for: videoDevice)
        configRecordingVideoOrientation()

        session.commitConfiguration()
        
        DispatchQueue.main.async { [weak self] in
            self?.toggleControls(isHidden: false)
        }
    }
    
    private func configSessionPreset(for videoDevice: AVCaptureDevice) {
        var presets: [AVCaptureSession.Preset] = []
        if source == .capture {
            if #available(iOS 9, *) {
                presets.append(.hd4K3840x2160)
            }
            presets.append(.hd1920x1080)
            presets.append(.photo)
            for preset in presets {
                if videoDevice.supportsSessionPreset(preset) {
                    session.sessionPreset = preset
                    break
                }
            }
        } else {
            presets.append(.hd1280x720)
            presets.append(.medium)
            for preset in presets {
                if videoDevice.supportsSessionPreset(preset) {
                    session.sessionPreset = preset
                    break
                }
            }
        }
    }
    
    private func configRecordingFPS(for videoDevice: AVCaptureDevice) {
        guard source == .recording else { return }
        let desiredFrameRate = mode.config.recordingFrameRate
        var isFPSSupported = false
        for range in videoDevice.activeFormat.videoSupportedFrameRateRanges {
            if Double(desiredFrameRate) <= range.maxFrameRate,
                Double(desiredFrameRate) >= range.minFrameRate {
                isFPSSupported = true
            }
        }
        if isFPSSupported {
            do {
                try videoDevice.lockForConfiguration()
                videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(desiredFrameRate))
                videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(desiredFrameRate))
                videoDevice.unlockForConfiguration()
            } catch {
                print("Could not config video device frame duration: \(error)")
            }
        }
        videoCompressionSettings = videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)!
        audioCompressionSettings = audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) as! [String: Any]
    }
    
    private func configSessionOutput() {
        if source == .capture {
            videoDataOutput.setSampleBufferDelegate(nil, queue: videoDataOutputQueue)
            audioDataOutput.setSampleBufferDelegate(nil, queue: audioDataOutputQueue)
            session.removeOutput(videoDataOutput)
            session.removeOutput(audioDataOutput)
            videoConnection = nil
            audioConnection = nil
            if session.canAddOutput(stillImageOutput) {
                session.addOutput(stillImageOutput)
            } else {
                print("Could not add still image output to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } else {
            session.removeOutput(stillImageOutput)
            videoDataOutput.alwaysDiscardsLateVideoFrames = false
            videoDataOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            audioDataOutput.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            } else {
                print("Could not add vidoe data output to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            if session.canAddOutput(audioDataOutput) {
                session.addOutput(audioDataOutput)
            } else {
                print("Could not add audio data output to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            videoConnection = videoDataOutput.connection(with: .video)
            audioConnection = audioDataOutput.connection(with: .audio)
        }
    }
        
    private func configRecordingVideoOrientation() {
        guard source == .recording else { return }
        if let videoConnection = videoDataOutput.connection(with: .video) {
            videoConnection.videoOrientation = .portrait
        }
    }
    
    func cancelTimer() {
        timer?.cancel()
        timer = nil
        timeRemain = maxDuration
    }
    
    func startTimer() {
        if timer == nil {
            let queue = DispatchQueue.global()
            timer = DispatchSource.makeTimerSource(queue: queue)
            timer?.schedule(deadline: .now(), repeating: .milliseconds(CameraViewController.repeatingInterval))
        }
        timer?.setEventHandler(handler: { [weak self] in
            guard let `self` = self else { return }
            self.countDown()
        })
        timer?.resume()
    }
    
    private func countDown() {
        timeRemain -= CameraViewController.repeatingInterval
        if timeRemain == 0 {
            stopRecording()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateDuration()
            }
        }
    }
    
    private func flashModeChanged(_ videoDevice: AVCaptureDevice) {
        var icon = #imageLiteral(resourceName: "flash_on")
        if videoDevice.flashMode == .off {
            icon = #imageLiteral(resourceName: "flash_off")
        }
        DispatchQueue.main.async { [weak self] in
            self?.flashButton.setImage(icon, for: .normal)
        }
    }

    private func capture() {
        guard !isCapturing,
            let captureConnection = stillImageOutput.connection(with: .video) else {
                return
        }
        guard photos.count < mode.config.limitOfPhotos else {
            DTMessageBar.info(message: "单次最多允许拍照\(mode.config.limitOfPhotos)张")
            return
        }
        isCapturing = true
        stillImageOutput.captureStillImageAsynchronously(from: captureConnection) { [weak self] sampleBuffer, error in
            if error == nil {
                guard let sampleBuffer = sampleBuffer,
                    let data = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer),
                    let photo = UIImage(data: data),
                    let self = self else {
                        return
                }
                let cropRectHeight = photo.size.width * self.ratioMode.ratio
                let cropRectY = (photo.size.height - cropRectHeight) / 2.0
                let cropRect = CGRect(x: 0,
                                      y: cropRectY,
                                      width: photo.size.width,
                                      height: cropRectHeight)
                guard let correctImage = photo.cgImageCorrectedOrientation(),
                    let croppedImage = correctImage.cropping(to: cropRect) else {
                        return
                }
                let croppedPhoto = UIImage(cgImage: croppedImage)
                self.photos.append(croppedPhoto)
                let photosCount = self.photos.count
                DispatchQueue.main.async { [weak self] in
                    self?.updateCountLabel()
                    self?.collectionView.reloadData()
                    self?.collectionView.scrollToItem(at: IndexPath(item: photosCount - 1, section: 0),
                                                      at: .centeredHorizontally, animated: true)
                    self?.isCapturing = false
                }
            } else {
                print("Could not capture still image: \(error.debugDescription)")
                self?.isCapturing = false
            }
        }
    }
    
    private func recording() {
        if recordingStatus == .idle {
            if let outputURL = MediaViewController.videoFile {
                DispatchQueue.main.async { [weak self] in
                    self?.toggleRecordingControls(isHidden: false)
                }
                let recorder = AssetRecorder(url: outputURL, delegate: self, callbackQueue: .main)
                recorder.addVideoTrack(with: self.videoFormatDescription!, settings: self.videoCompressionSettings)
                recorder.addAudioTrack(with: self.audioFormatDescription!, settings: self.audioCompressionSettings)
                self.recorder = recorder
                outputFileURL = outputURL
                recorder.prepareToRecord()
                recordingStatus = .startingRecording
                if UIDevice.current.isMultitaskingSupported {
                    backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                        print("video capture pipeline background task expired")
                    })
                }
            } else {
                print("Could not create video file")
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.toggleRecordingControls(isHidden: true)
            }
            recorder.finishRecording()
            recordingStatus = .stoppingRecording
        }
    }
    
    private func cleanupRecording() {
        self.recorder = nil
        self.recordingStatus = .idle
        if let currentBackgroundRecordingID = backgroundRecordingID {
            backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
            if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
            }
        }
    }
    
    private func toggleSource() {
        guard isViewLoaded else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.session.beginConfiguration()
            
            self.configSessionPreset(for: self.videoDeviceInput.device)
            self.configSessionOutput()
            self.configRecordingFPS(for: self.videoDeviceInput.device)
            self.configRecordingVideoOrientation()

            self.session.commitConfiguration()
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updatePreview()
            self.toggleControls(isHidden: false)
        }
    }

    private func previewVideo(_ video: URL) {
        let previewVideoVC = PreviewVideoViewController(mode: mode, video: video)
        previewVideoVC.delegate = self
        previewVideoVC.modalPresentationStyle = .fullScreen
        present(previewVideoVC, animated: true, completion: nil)
    }
    
    private func calculateFrameRate(at timestamp: CMTime) {
        previousSecondTimestamps.append(timestamp)
        
        let oneSecond = CMTimeMake(value: 1, timescale: 1)
        let oneSecondAgo = CMTimeSubtract(timestamp, oneSecond)
        
        while previousSecondTimestamps[0] < oneSecondAgo {
            previousSecondTimestamps.remove(at: 0)
        }
        
        if previousSecondTimestamps.count > 1 {
            let duration: Double = CMTimeGetSeconds(CMTimeSubtract(previousSecondTimestamps.last!, previousSecondTimestamps[0]))
            videoFrameRate = Float(previousSecondTimestamps.count - 1) / Float(duration)
        }
    }

    @objc private func updateDebugLabels() {
        frameRateLabel.text = "\(Int(roundf(videoFrameRate))) FPS"
        dimensionsLabel.text = "\(videoDimensions.width) x \(videoDimensions.height)"
    }
    
    @objc private func enterForeground(_ notificaton: Notification) {
        if isViewLoaded && view.window != nil {
            startSessionRunning()
            isRenderingEnabled = true
        }
    }
    
    @objc private func enterBackground(_ notificaton: Notification) {
        if isViewLoaded && view.window != nil {
            stopSessionRunning()
            isRenderingEnabled = false
            stopRecording()
        }
    }

    @objc private func close() {
        guard let mediaVC = parent as? MediaViewController else { return }
        mediaVC.delegate?.mediaDidDismiss(viewController: mediaVC)
    }
    
    @objc private func toggleFlash() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let videoDevice = self.videoDeviceInput.device
                try videoDevice.lockForConfiguration()
                if videoDevice.flashMode == .off {
                    videoDevice.flashMode = .on
                } else {
                    videoDevice.flashMode = .off
                }
                videoDevice.unlockForConfiguration()
            } catch {
                print("Could not config video device flash mode: \(error)")
            }
        }
    }

    @objc private func toggleRatio() {
        switch ratioMode {
        case .r1to1:
            ratioMode = .r3to4
        case .r3to4:
            ratioMode = .r9to16
        case .r9to16:
            ratioMode = .r1to1
        }
        
        ratioButton.setImage(ratioMode.icon, for: .normal)
        updatePreview()
    }
    
    @objc private func shutter() {
        if source == .capture {
            capture()
        } else {
            recording()
        }
    }
    
    @objc private func stopRecording() {
        cancelTimer()
        recording()
        DispatchQueue.main.async { [weak self] in
            self?.updateDuration()
        }
    }
    
    @objc private func previewOrEditPhotos() {
        let previewPhotosVC = PreviewPhotosViewController(mode: mode, photos: photos)
        previewPhotosVC.handler = self
        previewPhotosVC.modalPresentationStyle = .fullScreen
        present(previewPhotosVC, animated: true, completion: nil)
    }
    
    @objc private func done() {
        guard let mediaVC = parent as? MediaViewController else { return }
        mediaVC.delegate?.media(viewController: mediaVC, didFinish: photos)
    }

}

extension CameraViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photos.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: thumbnailCellIdentifier, for: indexPath) as! PhotoThumbnailCell
        cell.delegate = self
        cell.photoImageView.image = photos[indexPath.row]
        return cell
    }
    
}

extension CameraViewController: PhotoThumbnailCellDelegate {
    
    func photoThumbnailCellDidDelete(_ cell: PhotoThumbnailCell) {
        guard !isCapturing,
            let indexPath = collectionView.indexPath(for: cell) else { return }
        isCapturing = true
        photos.remove(at: indexPath.row)
        updateCountLabel()
        collectionView.deleteItems(at: [indexPath])
        isCapturing = false
    }
    
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        if connection === videoConnection {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            calculateFrameRate(at: timestamp)
            if videoFormatDescription == nil {
                if let formatDescription = formatDescription {
                    videoDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                    effectFilter.prepare(with: ratioMode, positionMode: positionMode,
                                         formatDescription: formatDescription, retainedBufferCountHint: retainedBufferCountHint)
                    if let outputFormatDescription = effectFilter.outputFormatDescription {
                        videoFormatDescription = outputFormatDescription
                    } else {
                        videoFormatDescription = formatDescription
                    }
                }
            } else if isRenderingEnabled, let inputPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let outputPixelBuffer = effectFilter.filter(pixelBuffer: inputPixelBuffer)
                previewPixelBuffer = outputPixelBuffer
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let previewPixelBuffer = self.previewPixelBuffer else { return }
                    self.previewView.display(pixelBuffer: previewPixelBuffer, ratioMode: self.ratioMode)
                }
                if recordingStatus == .recording {
                    recorder.appendVideoPixelBuffer(outputPixelBuffer, withPresentationTime: timestamp)
                }
            }
        } else if connection === audioConnection {
            audioFormatDescription = formatDescription
            if recordingStatus == .recording {
                recorder.appendAudioSampleBuffer(sampleBuffer)
            }
        }
    }
    
}

extension CameraViewController: AssetRecorderDelegate {
    
    func assetRecorderDidFinishPreparing(_ recorder: AssetRecorder) {
        if recordingStatus != .startingRecording {
            fatalError("Expected to be in StartingRecording state")
        }
        recordingStatus = .recording
        startTimer()
    }
    
    func assetRecorder(_ recorder: AssetRecorder, didFailWithError error: Error?) {
        cancelTimer()
        cleanupRecording()
        DispatchQueue.main.async { [weak self] in
            self?.toggleRecordingControls(isHidden: true)
            self?.updateDuration()
        }
    }
    
    func assetRecorderDidFinishRecording(_ recorder: AssetRecorder) {
        if recordingStatus != .stoppingRecording {
            fatalError("Expected to be in StoppingRecording state")
        }
        cleanupRecording()
        DispatchQueue.main.async { [weak self] in
            if let outputFileURL = self?.outputFileURL {
                self?.previewVideo(outputFileURL)
            }
        }
    }

}

extension CameraViewController: PreviewPhotosViewControllerHandler {
    
    func previewPhotos(viewController: PreviewPhotosViewController, didFinish photos: [UIImage]) {
        dismiss(animated: false) { [weak self] in
            guard let mediaVC = self?.parent as? MediaViewController else { return }
            mediaVC.delegate?.media(viewController: mediaVC, didFinish: photos)
        }
    }
    
}

extension CameraViewController: PreviewVideoViewControllerDelegate {
    
    func previewVideo(viewController: PreviewVideoViewController, didFinish video: URL) {
        dismiss(animated: false) { [weak self] in
            guard let mediaVC = self?.parent as? MediaViewController else { return }
            mediaVC.delegate?.media(viewController: mediaVC, didFinish: video)
        }
    }
    
}
