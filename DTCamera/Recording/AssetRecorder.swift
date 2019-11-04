//
//  AssetRecorder.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/22.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMedia
import CocoaLumberjack

protocol AssetRecorderDelegate: class {
    func assetRecorderDidFinishPreparing(_ recorder: AssetRecorder)
    func assetRecorder(_ recorder: AssetRecorder, didFailWithError error: Error?)
    func assetRecorderDidFinishRecording(_ recorder: AssetRecorder)
}

class AssetRecorder {
    
    private let url: URL
    private weak var delegate: AssetRecorderDelegate?
    private var delegateCallbackQueue: DispatchQueue

    private enum RecorderStatus: Int, CustomStringConvertible {
        case idle = 0
        case preparingToRecord
        case recording
        // waiting for inflight buffers to be appended
        case finishingRecordingPart1
        // calling finish writing on the asset writer
        case finishingRecordingPart2
        // terminal state
        case finished
        // terminal state
        case failed
        
        var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .preparingToRecord:
                return "PreparingToRecord"
            case .recording:
                return "Recording"
            case .finishingRecordingPart1:
                return "FinishingRecordingPart1"
            case .finishingRecordingPart2:
                return "FinishingRecordingPart2"
            case .finished:
                return "Finished"
            case .failed:
                return "Failed"
            }
        }
    }  // internal state machine
    private let statusQueue = DispatchQueue(label: "asset recorder status queue", attributes: [.concurrent], target: nil)
    private var _status: RecorderStatus = .idle
    private var status: RecorderStatus {
        get {
            statusQueue.sync {
                return _status
            }
        }
        set {
            statusQueue.async(flags: .barrier) { [weak self] in
                self?._status = newValue
            }
        }
    }

    private let writingQueue = DispatchQueue(label: "asset recorder writing queue", attributes: [], target: nil)

    private var videoTrackSourceFormatDescription: CMFormatDescription?
    private var videoTrackSettings: [String: Any] = [:]
    private var videoInput: AVAssetWriterInput!
    
    private var audioTrackSourceFormatDescription: CMFormatDescription?
    private var audioTrackSettings: [String: Any] = [:]
    private var audioInput: AVAssetWriterInput!
    
    private var assetWriter: AVAssetWriter?
    private var isSessionStarted: Bool = false

    init(url: URL, delegate: AssetRecorderDelegate, callbackQueue queue: DispatchQueue) {
        self.url = url
        self.delegate = delegate
        self.delegateCallbackQueue = queue
    }
    
    func addVideoTrack(with formatDescription: CMFormatDescription, settings videoSettings: [String : Any]) {
        if status != .idle {
            DDLogError("Cannot add tracks while not idle")
            exit(1)
        }
        
        if videoTrackSourceFormatDescription != nil {
            DDLogError("Cannot add more than one video track")
            exit(1)
        }
        
        videoTrackSourceFormatDescription = formatDescription
        videoTrackSettings = videoSettings
    }
    
    func addAudioTrack(with formatDescription: CMFormatDescription, settings audioSettings: [String : Any]) {
        if status != .idle {
            DDLogError("Cannot add tracks while not idle")
            exit(1)
        }
        
        if audioTrackSourceFormatDescription != nil {
            DDLogError("Cannot add more than one audio track")
            exit(1)
        }
        
        audioTrackSourceFormatDescription = formatDescription
        audioTrackSettings = audioSettings
    }
    
    func prepareToRecord() {
        if status != .idle {
            DDLogError("Already prepared, cannot prepare again")
            exit(1)
        }
        
        transitionToStatus(.preparingToRecord, error: nil)
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            var error: Error? = nil
            
            do {
                self.assetWriter = try AVAssetWriter(outputURL: self.url, fileType: .mp4)
                
                // Create and add inputs
                self.setupAssetWriterVideoInput()
                self.setupAssetWriterAudioInput()
                
                let success = self.assetWriter?.startWriting() ?? false
                if !success {
                    error = self.assetWriter?.error
                }
            } catch let err {
                error = err
            }
            
            if let error = error {
                self.transitionToStatus(.failed, error: error)
            } else {
                self.transitionToStatus(.recording, error: nil)
            }
        }
    }
    
    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        appendSampleBuffer(sampleBuffer, ofMediaType: .video)
    }
    
    func appendVideoPixelBuffer(_ pixelBuffer: CVPixelBuffer, withPresentationTime presentationTime: CMTime) {
        guard let formatDescription = videoTrackSourceFormatDescription else {
            DDLogError("Cannot append video pixel buffer")
            exit(1)
        }

        var sampleBuffer: CMSampleBuffer?
        
        var timingInfo = CMSampleTimingInfo()
        timingInfo.duration = .invalid
        timingInfo.decodeTimeStamp = .invalid
        timingInfo.presentationTimeStamp = presentationTime
        
        let resultCode = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                            imageBuffer: pixelBuffer,
                                                            dataReady: true,
                                                            makeDataReadyCallback: nil,
                                                            refcon: nil,
                                                            formatDescription: formatDescription,
                                                            sampleTiming: &timingInfo,
                                                            sampleBufferOut: &sampleBuffer)
        
        if let sampleBuffer = sampleBuffer {
            self.appendSampleBuffer(sampleBuffer, ofMediaType: .video)
        } else {
            DDLogError("sample buffer create failed (\(resultCode))")
            exit(1)
        }
    }

    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        appendSampleBuffer(sampleBuffer, ofMediaType: .audio)
    }
    
    func finishRecording() {
        var shouldFinishRecording = false
        switch status {
        case .idle,
             .preparingToRecord,
             .finishingRecordingPart1,
             .finishingRecordingPart2,
             .finished:
            DDLogError("Not recording")
            exit(1)
        case .failed:
            // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
            // Because of this we are lenient when finishRecording is called and we are in an error state.
            DDLogWarn("Recording has failed, nothing to do")
        case .recording:
            shouldFinishRecording = true
        }
        
        if shouldFinishRecording {
            transitionToStatus(.finishingRecordingPart1, error: nil)
        } else {
            return
        }

        writingQueue.async { [weak self] in
            guard let self = self else { return }
            // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
            if self.status != .finishingRecordingPart1 {
                return
            }
            
            // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
            // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more buffers will be appended.
            self.transitionToStatus(.finishingRecordingPart2, error: nil)
            self.assetWriter?.finishWriting { [weak self] in
                guard let self = self else { return }
                if let error = self.assetWriter?.error {
                    self.transitionToStatus(.failed, error: error)
                } else {
                    self.transitionToStatus(.finished, error: nil)
                }
            }
        }
    }

    private func setupAssetWriterVideoInput() {
        guard let formatDescription = videoTrackSourceFormatDescription,
            let assetWriter = assetWriter else {
                DDLogError("Cannot setup asset writer`s video input")
                exit(1)
        }
        
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        var videoSettings = videoTrackSettings
        if videoSettings.isEmpty {
            DDLogWarn("No video settings provided, using default settings")

            var bitsPerPixel: Float
            let numPixels = dimensions.width * dimensions.height
            var bitsPerSecond: Int
            
            // Assume that lower-than-SD resolutions are intended for streaming, and use a lower bitrate
            if numPixels < 640 * 480 {
                bitsPerPixel = 4.05 // This bitrate approximately matches the quality produced by AVCaptureSessionPresetMedium or Low.
            } else {
                bitsPerPixel = 10.1 // This bitrate approximately matches the quality produced by AVCaptureSessionPresetHigh.
            }
            
            bitsPerSecond = Int(Float(numPixels) * bitsPerPixel)
            
            let compressionProperties: NSDictionary = [AVVideoAverageBitRateKey : bitsPerSecond,
                                                       AVVideoExpectedSourceFrameRateKey : 30,
                                                       AVVideoMaxKeyFrameIntervalKey : 30]
            
            videoSettings = [AVVideoCodecKey : AVVideoCodecH264,
                             AVVideoWidthKey : dimensions.width,
                             AVVideoHeightKey : dimensions.height,
                             AVVideoCompressionPropertiesKey : compressionProperties]
        } else {
            videoSettings[AVVideoWidthKey] = dimensions.width
            videoSettings[AVVideoHeightKey] = dimensions.height
        }
        
        if assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) {
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings, sourceFormatHint: formatDescription)
            videoInput.expectsMediaDataInRealTime = true
            
            if assetWriter.canAdd(videoInput) {
                assetWriter.add(videoInput)
            } else {
                DDLogError("Cannot add video input to asset writer")
                exit(1)
            }
        } else {
            DDLogError("Cannot apply video settings to asset writer")
            exit(1)
        }
    }
    
    private func setupAssetWriterAudioInput() {
        guard let formatDescription = audioTrackSourceFormatDescription,
            let assetWriter = assetWriter else {
                DDLogError("Cannot setup asset writer`s audio input")
                exit(1)
        }

        var audioSettings = audioTrackSettings
        if audioSettings.isEmpty {
            DDLogWarn("No audio settings provided, using default settings")
            audioSettings = [AVFormatIDKey : kAudioFormatMPEG4AAC]
        }
        
        if assetWriter.canApply(outputSettings: audioSettings, forMediaType: .audio) {
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: formatDescription)
            audioInput.expectsMediaDataInRealTime = true
            
            if assetWriter.canAdd(audioInput) {
                assetWriter.add(audioInput)
            } else {
                DDLogError("Cannot add audio input to asset writer")
                exit(1)
            }
        } else {
            DDLogError("Cannot apply audio settings to asset writer")
            exit(1)
        }
    }
    
    private func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, ofMediaType mediaType: AVMediaType) {
        if status.rawValue < RecorderStatus.recording.rawValue {
            DDLogError("Not ready to record yet")
            exit(1)
        }

        writingQueue.async { [weak self] in
            guard let self = self else { return }
            // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
            // Because of this we are lenient when samples are appended and we are no longer recording.
            // Instead of throwing an exception we just release the sample buffers and return.
            if self.status.rawValue > RecorderStatus.finishingRecordingPart1.rawValue {
                return
            }

            if !self.isSessionStarted {
                self.assetWriter?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                self.isSessionStarted = true
            }
            
            let input = (mediaType == .video) ? self.videoInput : self.audioInput
            
            if let input = input {
                if input.isReadyForMoreMediaData {
                    let success = input.append(sampleBuffer)
                    if !success {
                        let error = self.assetWriter?.error
                        self.transitionToStatus(.failed, error: error)
                    }
                } else {
                    DDLogWarn("\(mediaType) input not ready for more media data, dropping buffer")
                }
            }
        }
    }

    private func transitionToStatus(_ status: RecorderStatus, error: Error?) {
        if let error = error {
            DDLogWarn("state transition from \(self.status.description) to \(status.description) with error: \(error)")
        }

        var shouldNotifyDelegate = false
        
        if status != self.status {
            // terminal states
            if status == .finished || status == .failed {
                shouldNotifyDelegate = true
                // make sure there are no more sample buffers in flight before we tear down the asset writer and inputs
                writingQueue.async { [weak self] in
                    self?.teardownAssetWriterAndInputs()
                }
            } else if status == .recording {
                shouldNotifyDelegate = true
            }
            self.status = status
        }
        
        if shouldNotifyDelegate {
            delegateCallbackQueue.async { [weak self] in
                guard let self = self else { return }
                switch status {
                case .recording:
                    self.delegate?.assetRecorderDidFinishPreparing(self)
                case .finished:
                    self.delegate?.assetRecorderDidFinishRecording(self)
                case .failed:
                    self.delegate?.assetRecorder(self, didFailWithError: error)
                default:
                    DDLogError("Unexpected recording status (\(status)) for delegate callback")
                    exit(1)
                }
            }
        }
    }
    
    private func teardownAssetWriterAndInputs() {
        videoInput = nil
        audioInput = nil
        assetWriter = nil
    }
    
}
