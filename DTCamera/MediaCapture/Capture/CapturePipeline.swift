//
//  CapturePipeline.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/30.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import AVFoundation
import CocoaLumberjack

protocol CapturePipelineDelegate: class {
    func capturePipelineConfigSuccess(_ pipeline: CapturePipeline)
    func capturePipelineNotAuthorized(_ pipeline: CapturePipeline)
    func capturePipelineConfigFailed(_ pipeline: CapturePipeline)
    func capturePipeline(_ pipeline: CapturePipeline, capture photo: UIImage)
    func capturePipeline(_ pipeline: CapturePipeline, flashMode: AVCaptureDevice.FlashMode)
}

class CapturePipeline {
    
    weak var delegate: CapturePipelineDelegate?

    private let isCapturingQueue = DispatchQueue(label: "capture isCapturing queue", attributes: [.concurrent], target: nil)
    private var _isCapturing = false
    var isCapturing: Bool {
        get {
            isCapturingQueue.sync {
                return _isCapturing
            }
        }
        set {
            isCapturingQueue.async(flags: .barrier) { [weak self] in
                self?._isCapturing = newValue
            }
        }
    }

    private let mode: MediaMode
    var ratioMode: CameraRatioMode
    var positionMode: CameraPositionMode
    private var flashModeObservation: NSKeyValueObservation?

    private var setupResult: SessionSetupResult = .success
    private let sessionQueue = DispatchQueue(label: "capture session queue", attributes: [], target: nil)
    let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let stillImageOutput = AVCaptureStillImageOutput()

    deinit {
        flashModeObservation?.invalidate()
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
    
    func reconfigure() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    func startSessionRunning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            switch self.setupResult {
            case .success:
                self.session.startRunning()
            case .notAuthorized:
                self.delegate?.capturePipelineNotAuthorized(self)
            case .configurationFailed:
                self.delegate?.capturePipelineConfigFailed(self)
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
    
    func capture() {
        guard !isCapturing,
            let captureConnection = stillImageOutput.connection(with: .video) else {
                return
        }
        isCapturing = true
        stillImageOutput.captureStillImageAsynchronously(from: captureConnection) { [weak self] sampleBuffer, error in
            if error == nil {
                guard let sampleBuffer = sampleBuffer,
                    let data = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer),
                    let uncorrectPhoto = UIImage(data: data),
                    let uncorrectImage = uncorrectPhoto.cgImage,
                    let self = self else {
                        return
                }
                let photo = UIImage(cgImage: uncorrectImage,
                                    scale: uncorrectPhoto.scale,
                                    orientation: self.positionMode == .front ? .leftMirrored : .right)
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
                self.delegate?.capturePipeline(self, capture: croppedPhoto)
            } else {
                DDLogError("Could not capture still image: \(error.debugDescription)")
                self?.isCapturing = false
            }
        }
    }
    
    func toggleFlash() {
        sessionQueue.async { [weak self] in
            guard let self = self, let videoDeviceInput = self.videoDeviceInput else { return }
            do {
                let videoDevice = videoDeviceInput.device
                try videoDevice.lockForConfiguration()
                if videoDevice.flashMode == .off {
                    videoDevice.flashMode = .on
                } else {
                    videoDevice.flashMode = .off
                }
                videoDevice.unlockForConfiguration()
            } catch {
                DDLogError("Could not config video device flash mode: \(error)")
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
        configFlash(for: videoDevice)
        
        session.commitConfiguration()
        
        self.delegate?.capturePipelineConfigSuccess(self)
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
        if #available(iOS 9, *) {
            presets.append(.hd4K3840x2160)
        }
        presets.append(.hd1920x1080)
        presets.append(.photo)
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
    }
    
    private func configSessionOutput() {
        session.removeOutput(stillImageOutput)
        if session.canAddOutput(stillImageOutput) {
            session.addOutput(stillImageOutput)
        } else {
            DDLogError("Could not add still image output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
    }
    
    private func configFlash(for videoDevice: AVCaptureDevice) {
        do {
            if videoDevice.hasFlash {
                flashModeObservation = videoDevice.observe(\.flashMode) { [weak self] device, _ in
                    guard let self = self else { return }
                    self.delegate?.capturePipeline(self, flashMode: device.flashMode)
                }
                
                try videoDevice.lockForConfiguration()
                videoDevice.flashMode = .off
                videoDevice.unlockForConfiguration()
            }
        } catch {
            DDLogError("Could not config video device flash mode: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
    }

}
