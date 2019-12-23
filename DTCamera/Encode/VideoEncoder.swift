//
//  VideoEncoder.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/11/6.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import CoreMedia
import VideoToolbox
import CocoaLumberjack

protocol VideoEncoderDelegate: class {
    func videoEncoderEncodedFailed(_ encoder: VideoEncoder)
    func videoEncoderInitFailed(_ encoder: VideoEncoder)
    func videoEncoder(_ encoder: VideoEncoder, encoded sps: Data, pps: Data, timestamp: Float64)
    func videoEncoder(_ encoder: VideoEncoder, encoded data: Data, isKeyframe: Bool, timestamp: Float64)
    func videoEncoderFinished(_ encoder: VideoEncoder)
}

class VideoEncoder {

    weak var delegate: VideoEncoderDelegate?
    
    private let width: Int
    private let height: Int
    private let fps: Int
    private let maxBitRate: Int
    private let avgBitRate: Int
    
    private let encodeQueue = DispatchQueue(label: "video encoder encode queue", attributes: [], target: nil)

    private var isReady = false
    private var encodingTimeMills: Int64 = -1
    
    private var session: VTCompressionSession!
    
    init(width: Int, height: Int, fps: Int, maxBitRate: Int, avgBitRate: Int) {
        self.width = width
        self.height = height
        self.fps = fps
        self.maxBitRate = maxBitRate
        self.avgBitRate = avgBitRate
        
        encodeQueue.async { [weak self] in
            guard let self = self else { return }
            let statusCode = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                        width: Int32(width),
                                                        height: Int32(height),
                                                        codecType: kCMVideoCodecType_H264,
                                                        encoderSpecification: nil,
                                                        imageBufferAttributes: nil,
                                                        compressedDataAllocator: nil,
                                                        outputCallback: didCompressH264,
                                                        refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                                        compressionSessionOut: &self.session)
            if statusCode != noErr {
                DDLogError("H264: Unable to create a H264 session status is \(statusCode)")
                self.delegate?.videoEncoderInitFailed(self)
                return
            }
            
            VTSessionSetProperty(self.session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            VTSessionSetProperty(self.session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
            VTSessionSetProperty(self.session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse) // 不产生 B 帧
            self.setMaxBitRate(maxBitRate, avgBitRate: avgBitRate, fps: fps)
            
            VTCompressionSessionPrepareToEncodeFrames(self.session)
            
            self.isReady = true
            encodingSessionValid = true
        }
    }
    
    func setMaxBitRate(_ maxBitRate: Int, avgBitRate: Int, fps: Int) {
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: fps as CFTypeRef) // 关键帧间隔, gop size
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFTypeRef) // 帧率
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [maxBitRate / 8, 1] as CFArray) // 控制码率
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: avgBitRate as CFTypeRef) // 控制码率
    }
    
    func encode(pixelBuffer: CVPixelBuffer) {
        if continuousEncodeFailureTimes > continuousEncodeFailureTimesTreshold {
            delegate?.videoEncoderEncodedFailed(self)
        }
        encodeQueue.async { [weak self] in
            guard let self = self, self.isReady else {
                    return
            }
            let currentTimeMills = Int64(CFAbsoluteTimeGetCurrent() * 1000)
            if self.encodingTimeMills == -1 {
                self.encodingTimeMills = currentTimeMills
            }
            let encodingDuration = currentTimeMills - self.encodingTimeMills
            
            let pts = CMTimeMake(value: encodingDuration, timescale: 1000) // 当前编码视频帧的时间戳，单位为毫秒
            let duration = CMTimeMake(value: 1, timescale: Int32(self.fps)) // 当前编码视频帧的时长
            
            let statusCode = VTCompressionSessionEncodeFrame(self.session,
                                                             imageBuffer: pixelBuffer,
                                                             presentationTimeStamp: pts,
                                                             duration: duration,
                                                             frameProperties: nil,
                                                             sourceFrameRefcon: nil,
                                                             infoFlagsOut: nil)
            
            if statusCode != noErr {
                DDLogError("H264: VTCompressionSessionEncodeFrame failed \(statusCode)")
                return
            }
        }
    }
    
    func stopEncode() {
        isReady = false
        encodingSessionValid = false
        // Mark the completion
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        // End the session
        VTCompressionSessionInvalidate(session)
        session = nil
        delegate?.videoEncoderFinished(self)
    }
        
}

let continuousEncodeFailureTimesTreshold = 100
var continuousEncodeFailureTimes = 0
var encodingSessionValid = false

func didCompressH264(outputCallbackRefCon: UnsafeMutableRawPointer?,
                     sourceFrameRefCon: UnsafeMutableRawPointer?,
                     status: OSStatus,
                     infoFlags: VTEncodeInfoFlags,
                     sampleBuffer: CMSampleBuffer?) -> Void {
    if status != noErr {
        continuousEncodeFailureTimes += 1
        return
    }
    continuousEncodeFailureTimes = 0
    
    guard let sampleBuffer = sampleBuffer,
        CMSampleBufferDataIsReady(sampleBuffer),
        encodingSessionValid else {
            return
    }
    
    let encoder: VideoEncoder = Unmanaged.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
    
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
        let rawDictionary: UnsafeRawPointer = CFArrayGetValueAtIndex(attachments, 0)
        let dictionary: CFDictionary = Unmanaged.fromOpaque(rawDictionary).takeUnretainedValue()
        let isKeyframe = !CFDictionaryContainsKey(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
        if isKeyframe { // 每一个关键帧前面都会输出 SPS 和 PPS 信息
            let format = CMSampleBufferGetFormatDescription(sampleBuffer)
            // sps
            var spsSize: Int = 0
            var spsCount: Int = 0
            var nalHeaderLength: Int32 = 0
            var sps: UnsafePointer<UInt8>!
            var statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format!,
                                                                                parameterSetIndex: 0,
                                                                                parameterSetPointerOut: &sps,
                                                                                parameterSetSizeOut: &spsSize,
                                                                                parameterSetCountOut: &spsCount,
                                                                                nalUnitHeaderLengthOut: &nalHeaderLength)
            if statusCode == noErr {
                // pps
                var ppsSize: Int = 0
                var ppsCount: Int = 0
                var pps: UnsafePointer<UInt8>!
                statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format!,
                                                                                parameterSetIndex: 1,
                                                                                parameterSetPointerOut: &pps,
                                                                                parameterSetSizeOut: &ppsSize,
                                                                                parameterSetCountOut: &ppsCount,
                                                                                nalUnitHeaderLengthOut: &nalHeaderLength)
                if statusCode == noErr {
                    let spsData = Data(bytes: sps, count: spsSize)
                    let ppsData = Data(bytes: pps, count: ppsSize)
                    let timeMills = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000
                    DDLogDebug("videoEncoder spsSize: \(spsSize) nalHeaderLength: \(nalHeaderLength) ppsSize: \(ppsSize) nalHeaderLength: \(nalHeaderLength)")
                    encoder.delegate?.videoEncoder(encoder, encoded: spsData, pps: ppsData, timestamp: timeMills)
                }
            }
        }
        
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>!
        let statusCode = CMBlockBufferGetDataPointer(dataBuffer,
                                                     atOffset: 0,
                                                     lengthAtOffsetOut: &lengthAtOffset,
                                                     totalLengthOut: &totalLength,
                                                     dataPointerOut: &dataPointer)
        if statusCode == noErr {
            var bufferOffset: Int = 0
            let AVCCHeaderLength = 4
            while bufferOffset < totalLength - AVCCHeaderLength {
                var NALUnitLength: UInt32 = 0
                // first four character is NAL Unit length
                memcpy(&NALUnitLength, dataPointer.advanced(by: bufferOffset), AVCCHeaderLength)
                // big endian to host endian. in iOS it's little endian
                NALUnitLength = CFSwapInt32BigToHost(NALUnitLength)
                
                let data: Data = Data(bytes: dataPointer.advanced(by: bufferOffset + AVCCHeaderLength), count: Int(NALUnitLength))
                let timeMills = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000
                DDLogDebug("videoEncoder encodedData: \(Int(NALUnitLength))")
                encoder.delegate?.videoEncoder(encoder, encoded: data, isKeyframe: isKeyframe, timestamp: timeMills)
                
                // move forward to the next NAL Unit
                bufferOffset += Int(AVCCHeaderLength)
                bufferOffset += Int(NALUnitLength)
            }
        }
    }
    

}
