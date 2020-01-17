//
//  EffectCIFilter.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/21.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import CoreMedia
import CocoaLumberjack

class EffectCIFilter: EffectFilter {
    
    var outputFormatDescription: CMFormatDescription?

    private var bufferPool: CVPixelBufferPool!
    private var bufferPoolAuxAttributes: NSDictionary!

    private var ciContext: CIContext!
    private var filter: CIFilter!
    
    deinit {
        reset()
    }
    
    func prepare(with ratioMode: CameraRatioMode, positionMode: CameraPositionMode,
                 formatDescription: CMFormatDescription, retainedBufferCountHint: Int) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        createBufferPool(width: Int(dimensions.width),
                         height: Int(dimensions.height),
                         retainedBufferCountHint: retainedBufferCountHint)
        let testPixelBuffer = createPixelBuffer()
        var outputFormatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: testPixelBuffer,
                                                     formatDescriptionOut: &outputFormatDescription)
        self.outputFormatDescription = outputFormatDescription

        let eaglContext = EAGLContext(api: .openGLES2)
        ciContext = CIContext(eaglContext: eaglContext!, options: [.workingColorSpace : NSNull()])
        
        filter = CIFilter(name: "CIColorMatrix")
        let redCoefficients: [CGFloat] = [0, 0, 0, 0]
        filter.setValue(CIVector(values: redCoefficients, count: 4), forKey: "inputRVector")
    }
    
    func filter(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        let inputImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)
        
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        let outputImage = filter.value(forKey: kCIOutputImageKey) as! CIImage

        let outputPixelBuffer = createPixelBuffer()

        ciContext.render(outputImage,
                         to: outputPixelBuffer,
                         bounds: outputImage.extent,
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        
        return outputPixelBuffer
    }
    
    func addEmitter(x: CGFloat, y: CGFloat) {}
    
    private func createPixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer!
        let resultCode = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bufferPool, &pixelBuffer)
        if resultCode != kCVReturnSuccess {
            DDLogError("Could not create pixel buffer in pool \(resultCode)")
            exit(1)
        }
        return pixelBuffer
    }
    
    private func createBufferPool(width: Int, height: Int, retainedBufferCountHint: Int) {
        let pixelBufferPoolOptions: NSDictionary = [kCVPixelBufferPoolMinimumBufferCountKey: retainedBufferCountHint]
        let pixelBufferOptions: NSDictionary = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                                kCVPixelBufferWidthKey: width,
                                                kCVPixelBufferHeightKey: height,
                                                kCVPixelFormatOpenGLESCompatibility: true,
                                                kCVPixelBufferIOSurfacePropertiesKey: NSDictionary()]
        let resultCode = CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                                 pixelBufferPoolOptions,
                                                 pixelBufferOptions,
                                                 &bufferPool)
        if resultCode != kCVReturnSuccess {
            DDLogError("Could not create pixel buffer pool \(resultCode)")
            exit(1)
        }
        bufferPoolAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: retainedBufferCountHint]
        preallocatePixelBuffers(in: bufferPool, with: bufferPoolAuxAttributes)
    }
        
    private func preallocatePixelBuffers(in pool: CVPixelBufferPool, with auxAttributes: NSDictionary) {
        var pixelBuffers: [CVPixelBuffer] = []
        while true {
            var pixelBuffer: CVPixelBuffer!
            let resultCode = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,
                                                                                 pool,
                                                                                 auxAttributes,
                                                                                 &pixelBuffer)
            if resultCode == kCVReturnWouldExceedAllocationThreshold {
                break
            }
            pixelBuffers.append(pixelBuffer)
        }
        pixelBuffers.removeAll()
    }
    
    private func reset() {
        bufferPool = nil
        bufferPoolAuxAttributes = nil
        ciContext = nil
        filter = nil
    }

}
