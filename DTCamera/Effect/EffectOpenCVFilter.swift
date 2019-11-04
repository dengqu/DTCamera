//
//  EffectOpenCVFilter.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/21.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import CoreMedia

class EffectOpenCVFilter: EffectFilter {
    
    var outputFormatDescription: CMFormatDescription?

    private var openCVWrapper: OpenCVWrapper?
    
    deinit {
        reset()
    }
    
    func prepare(with ratioMode: CameraRatioMode, positionMode: CameraPositionMode,
                 formatDescription: CMFormatDescription, retainedBufferCountHint: Int) {
        openCVWrapper = OpenCVWrapper()
    }
        
    func filter(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let extendedWidth = bytesPerRow / MemoryLayout<UInt32>.size  // each pixel is 4 bytes or 32 bits
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)

        openCVWrapper?.filterImage(baseAddress, width: Int32(extendedWidth), height: Int32(bufferHeight))

        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        
        return pixelBuffer
    }

    private func reset() {
        openCVWrapper = nil
    }

}
