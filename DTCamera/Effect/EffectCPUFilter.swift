//
//  EffectCPUFilter.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/21.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import CoreMedia

class EffectCPUFilter: EffectFilter {
    
    func prepare(with ratioMode: CameraRatioMode, positionMode: CameraPositionMode,
                 formatDescription: CMFormatDescription, retainedBufferCountHint: Int) {
        
    }
    
    func filter(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        let bytesPerPixel = 4
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        
        for row in 0..<bufferHeight {
            var pixel = baseAddress.advanced(by: Int(row * bytesPerRow))
            for _ in 0..<bufferWidth {
                pixel[0] = 0 // De-blue (second pixel in BGRA is blue)
                pixel += bytesPerPixel
            }
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        
        return pixelBuffer
    }

}
