//
//  DebugHelper.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/12.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import CoreVideo
import CocoaLumberjack

class DebugHelper: NSObject {
    
    static let shared = DebugHelper()

    func DDLogDebugResultCode(_ resultCode: CVReturn) {
        switch resultCode {
        // Common
        case kCVReturnAllocationFailed:
            DDLogDebug("kCVReturnAllocationFailed")
        case kCVReturnError:
            DDLogDebug("kCVReturnError")
        case kCVReturnInvalidArgument:
            DDLogDebug("kCVReturnInvalidArgument")
        case kCVReturnUnsupported:
            DDLogDebug("kCVReturnUnsupported")
        case kCVReturnLast:
            DDLogDebug("kCVReturnLast")
        case kCVReturnFirst:
            DDLogDebug("kCVReturnFirst")
        // Pixel Buffer
        case kCVReturnInvalidPixelBufferAttributes:
            DDLogDebug("kCVReturnInvalidPixelBufferAttributes")
        case kCVReturnInvalidPixelFormat:
            DDLogDebug("kCVReturnInvalidPixelFormat")
        case kCVReturnInvalidSize:
            DDLogDebug("kCVReturnInvalidSize")
        case kCVReturnPixelBufferNotMetalCompatible:
            DDLogDebug("kCVReturnPixelBufferNotMetalCompatible")
        case kCVReturnPixelBufferNotOpenGLCompatible:
            DDLogDebug("kCVReturnPixelBufferNotOpenGLCompatible")
        // Buffer Pool
        case kCVReturnRetry:
            DDLogDebug("kCVReturnRetry")
        case kCVReturnInvalidPoolAttributes:
            DDLogDebug("kCVReturnInvalidPoolAttributes")
        case kCVReturnPoolAllocationFailed:
            DDLogDebug("kCVReturnPoolAllocationFailed")
        case kCVReturnWouldExceedAllocationThreshold:
            DDLogDebug("kCVReturnWouldExceedAllocationThreshold")
        // Display Link
        case kCVReturnInvalidDisplay:
            DDLogDebug("kCVReturnInvalidDisplay")
        case kCVReturnDisplayLinkAlreadyRunning:
            DDLogDebug("kCVReturnDisplayLinkAlreadyRunning")
        case kCVReturnDisplayLinkNotRunning:
            DDLogDebug("kCVReturnDisplayLinkNotRunning")
        case kCVReturnDisplayLinkCallbacksNotSet:
            DDLogDebug("kCVReturnDisplayLinkCallbacksNotSet")
        default:
            DDLogDebug("unknown")
        }
    }
    
}
