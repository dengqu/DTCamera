//
//  RecordingPipeline.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/30.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AVFoundation
import CocoaLumberjack

protocol RecordingPipelineDelegate: class {
    func recordingPipelineConfigSuccess(_ pipeline: RecordingPipeline)
    func recordingPipelineNotAuthorized(_ pipeline: RecordingPipeline)
    func recordingPipelineConfigFailed(_ pipeline: RecordingPipeline)
    func recordingPipeline(_ pipeline: RecordingPipeline, display pixelBuffer: CVPixelBuffer)
    func recordingPipelineRecorderDidFinishPreparing(_ pipeline: RecordingPipeline)
    func recordingPipeline(_ pipeline: RecordingPipeline, recorderDidFail error: Error?)
    func recordingPipeline(_ pipeline: RecordingPipeline, recorderDidFinish video: URL)
}

class RecordingPipeline: NSObject {
    
    weak var delegate: RecordingPipelineDelegate?

    // Mode
    private let mode: MediaMode
    var ratioMode: CameraRatioMode
    var positionMode: CameraPositionMode

    // Pipeline
    private var setupResult: SessionSetupResult = .success
    private let sessionQueue = DispatchQueue(label: "recording session queue", attributes: [], target: nil)
    private let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoDataOutputQueue = DispatchQueue(label: "recording video data output queue", attributes: [], target: nil)
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var videoConnection: AVCaptureConnection?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private let audioDataOutputQueue = DispatchQueue(label: "recording audio data output queue", attributes: [], target: nil)
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private var audioConnection: AVCaptureConnection?

    // Effect
    private var effectFilter: EffectFilter!
    private let retainedBufferCountHint = 6
    private var videoFormatDescription: CMFormatDescription?
    private var audioFormatDescription: CMFormatDescription?
    private var videoCompressionSettings: [String : Any] = [:]
    private var audioCompressionSettings: [String : Any] = [:]
    
    // Preview
    private let previewPixelBufferQueue = DispatchQueue(label: "recording preview pixel buffer queue", attributes: [.concurrent], target: nil)
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

    // Recording
    enum RecordingStatus: Int {
        case idle = 0
        case startingRecording
        case recording
        case stoppingRecording
    }
    private let recordingStatusQueue = DispatchQueue(label: "recording recording status queue", attributes: [.concurrent], target: nil)
    private var _recordingStatus: RecordingStatus = .idle
    var recordingStatus: RecordingStatus {
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
    private var recorder: AssetRecorder?
    private var videoFile: URL?
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?

    // Miscellaneous
    private var previousSecondTimestamps: [CMTime] = []
    var videoFrameRate: Float = 0.0
    var videoDimensions: CMVideoDimensions = CMVideoDimensions(width: 0, height: 0)
    var effectFilterVideoDimensions: CMVideoDimensions = CMVideoDimensions(width: 0, height: 0)
    private let isRenderingEnabledQueue = DispatchQueue(label: "recording isRendering enabled queue", attributes: [.concurrent], target: nil)
    private var _isRenderingEnabled = false
    var isRenderingEnabled: Bool { // if allow to use GPU
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

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(mode: MediaMode) {
        self.mode = mode
        ratioMode = mode.config.ratioMode
        positionMode = mode.config.positionMode
    }
    
    func configure() {
        effectFilter = EffectOpenGLFilter()
        
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
    }
    
    func reconfigure(needReprepareEffectFilter: Bool = false) {
        sessionQueue.async { [weak self] in
            self?.configureSession()
            if needReprepareEffectFilter {
                self?.reprepareEffectFilter()
            }
        }
    }
    
    func reprepareEffectFilter() {
        videoFormatDescription = nil
    }
    
    func startSessionRunning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            switch self.setupResult {
            case .success:
                self.session.startRunning()
            case .notAuthorized:
                self.delegate?.recordingPipelineNotAuthorized(self)
            case .configurationFailed:
                self.delegate?.recordingPipelineConfigFailed(self)
            }
        }
    }
    
    func stopSessionRunning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.setupResult == .success {
                self.session.stopRunning()
            }
        }
    }
    
    func startRecording() {
        if recordingStatus != .idle {
            DDLogError("Expected to be in idle state")
            exit(1)
        }

        let videoFile = MediaViewController.videoFile
        if let videoFile = videoFile,
            let videoFormatDescription = videoFormatDescription,
            let audioFormatDescription = audioFormatDescription {
            let recorder = AssetRecorder(url: videoFile, delegate: self, callbackQueue: .main)
            recorder.addVideoTrack(with: videoFormatDescription, settings: videoCompressionSettings)
            recorder.addAudioTrack(with: audioFormatDescription, settings: audioCompressionSettings)
            self.recorder = recorder
            self.videoFile = videoFile
            recorder.prepareToRecord()
            recordingStatus = .startingRecording
            if UIDevice.current.isMultitaskingSupported {
                backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: {
                    DDLogError("video capture pipeline background task expired")
                })
            }
        } else {
            DDLogError("Could not start recording")
            if videoFile == nil {
                DDLogError("videoFile is nil")
            }
            if videoFormatDescription == nil {
                DDLogError("videoFormatDescription is nil")
            }
            if audioFormatDescription == nil {
                DDLogError("audioFormatDescription is nil")
            }
        }
    }
    
    func stopRecording() {
        recordingStatus = .stoppingRecording
        recorder?.finishRecording()
    }

    private func cleanupRecording() {
        recorder = nil
        recordingStatus = .idle
        if let currentBackgroundRecordingID = backgroundRecordingID {
            backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
            if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
            }
        }
    }

    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        guard let videoDevice = configVideoDevice() else {
            DDLogError("Could not find video device")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        configSessionPreset(for: videoDevice)
        configSessionInput(for: videoDevice)
        configSessionOutput()
        configRecordingFPS(for: videoDevice)
        configRecordingVideoOrientation()
        
        session.commitConfiguration()
        
        self.delegate?.recordingPipelineConfigSuccess(self)
    }
    
    private func configVideoDevice() -> AVCaptureDevice? {
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
        return defaultVideoDevice
    }
    
    private func configSessionPreset(for videoDevice: AVCaptureDevice) {
        var presets: [AVCaptureSession.Preset] = []
        presets.append(.hd1280x720)
        presets.append(.medium)
        for preset in presets {
            if videoDevice.supportsSessionPreset(preset),
                session.canSetSessionPreset(preset) {
                session.sessionPreset = preset
                break
            }
        }
    }
    
    private func configSessionInput(for videoDevice: AVCaptureDevice) {
        do {
            if let videoDeviceInput = videoDeviceInput {
                session.removeInput(videoDeviceInput)
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                DDLogError("Could not add video device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            DDLogError("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            DDLogError("Could not find audio device")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        do {
            if let audioDeviceInput = audioDeviceInput {
                session.removeInput(audioDeviceInput)
            }
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
                self.audioDeviceInput = audioDeviceInput
            } else {
                DDLogError("Could not add audio device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            DDLogError("Could not create audio device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
    }
    
    private func configSessionOutput() {
        session.removeOutput(videoDataOutput)
        session.removeOutput(audioDataOutput)
        videoDataOutput.alwaysDiscardsLateVideoFrames = false
        videoDataOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        audioDataOutput.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        } else {
            DDLogError("Could not add video data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        if session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
        } else {
            DDLogError("Could not add audio data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        videoConnection = videoDataOutput.connection(with: .video)
        audioConnection = audioDataOutput.connection(with: .audio)
    }

    private func configRecordingFPS(for videoDevice: AVCaptureDevice) {
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
                DDLogError("Could not config video device frame duration: \(error)")
            }
        }
        if let settings = videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4) {
            videoCompressionSettings = settings
        }
        if let settings =  audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) as? [String: Any] {
            audioCompressionSettings = settings
        }
    }
    
    private func configRecordingVideoOrientation() {
        videoConnection?.videoOrientation = .portrait
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
    
}

extension RecordingPipeline: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
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
                    if let videoFormatDescription = videoFormatDescription {
                        effectFilterVideoDimensions = CMVideoFormatDescriptionGetDimensions(videoFormatDescription)
                    }
                }
            } else if isRenderingEnabled, let inputPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let outputPixelBuffer = effectFilter.filter(pixelBuffer: inputPixelBuffer)
                previewPixelBuffer = outputPixelBuffer
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let previewPixelBuffer = self.previewPixelBuffer else { return }
                    self.delegate?.recordingPipeline(self, display: previewPixelBuffer)
                }
                if recordingStatus == .recording {
                    recorder?.appendVideoPixelBuffer(outputPixelBuffer, withPresentationTime: timestamp)
                }
            }
        } else if connection === audioConnection {
            audioFormatDescription = formatDescription
            if recordingStatus == .recording {
                recorder?.appendAudioSampleBuffer(sampleBuffer)
            }
        }
    }
    
}

extension RecordingPipeline: AssetRecorderDelegate {
    
    func assetRecorderDidFinishPreparing(_ recorder: AssetRecorder) {
        if recordingStatus != .startingRecording {
            DDLogError("Expected to be in StartingRecording state")
            exit(1)
        }
        recordingStatus = .recording
        delegate?.recordingPipelineRecorderDidFinishPreparing(self)
    }
    
    func assetRecorder(_ recorder: AssetRecorder, didFailWithError error: Error?) {
        cleanupRecording()
        delegate?.recordingPipeline(self, recorderDidFail: error)
    }
    
    func assetRecorderDidFinishRecording(_ recorder: AssetRecorder) {
        if recordingStatus != .stoppingRecording {
            DDLogError("Expected to be in StoppingRecording state")
            exit(1)
        }
        cleanupRecording()
        delegate?.recordingPipeline(self, recorderDidFinish: videoFile!)
    }

}
