//
//  DebugHelper.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/12.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import CoreVideo

class DebugHelper: NSObject {
    
    static let shared = DebugHelper()

    func printResultCode(_ resultCode: CVReturn) {
        switch resultCode {
        // Common
        case kCVReturnAllocationFailed:
            print("kCVReturnAllocationFailed")
        case kCVReturnError:
            print("kCVReturnError")
        case kCVReturnInvalidArgument:
            print("kCVReturnInvalidArgument")
        case kCVReturnUnsupported:
            print("kCVReturnUnsupported")
        case kCVReturnLast:
            print("kCVReturnLast")
        case kCVReturnFirst:
            print("kCVReturnFirst")
        // Pixel Buffer
        case kCVReturnInvalidPixelBufferAttributes:
            print("kCVReturnInvalidPixelBufferAttributes")
        case kCVReturnInvalidPixelFormat:
            print("kCVReturnInvalidPixelFormat")
        case kCVReturnInvalidSize:
            print("kCVReturnInvalidSize")
        case kCVReturnPixelBufferNotMetalCompatible:
            print("kCVReturnPixelBufferNotMetalCompatible")
        case kCVReturnPixelBufferNotOpenGLCompatible:
            print("kCVReturnPixelBufferNotOpenGLCompatible")
        // Buffer Pool
        case kCVReturnRetry:
            print("kCVReturnRetry")
        case kCVReturnInvalidPoolAttributes:
            print("kCVReturnInvalidPoolAttributes")
        case kCVReturnPoolAllocationFailed:
            print("kCVReturnPoolAllocationFailed")
        case kCVReturnWouldExceedAllocationThreshold:
            print("kCVReturnWouldExceedAllocationThreshold")
        // Display Link
        case kCVReturnInvalidDisplay:
            print("kCVReturnInvalidDisplay")
        case kCVReturnDisplayLinkAlreadyRunning:
            print("kCVReturnDisplayLinkAlreadyRunning")
        case kCVReturnDisplayLinkNotRunning:
            print("kCVReturnDisplayLinkNotRunning")
        case kCVReturnDisplayLinkCallbacksNotSet:
            print("kCVReturnDisplayLinkCallbacksNotSet")
        default:
            print("unknown")
        }
    }
    
}
