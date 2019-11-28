//
//  DebugHelper.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/10/12.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import CoreVideo
import CoreAudio
import CocoaLumberjack

class DebugHelper: NSObject {
    
    static let shared = DebugHelper()

    func debugResultCode(_ resultCode: CVReturn) {
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
    
    func debugAudioStreamBasicDescription(_ asbd: AudioStreamBasicDescription) {
        DDLogDebug("Sample Rate: \(asbd.mSampleRate)")
        DDLogDebug("Format ID: \(asbd.mFormatID.fourCharString)")
        DDLogDebug("Format Flags: \(getReadableFormatFlags(asbd.mFormatFlags))")
        DDLogDebug("Bits per Channel: \(asbd.mBitsPerChannel)")
        DDLogDebug("Channels per Frame: \(asbd.mChannelsPerFrame)")
        DDLogDebug("Bytes per Frame: \(asbd.mBytesPerFrame)")
        DDLogDebug("Frames per Packet: \(asbd.mFramesPerPacket)")
        DDLogDebug("Bytes per Packet: \(asbd.mBytesPerPacket)")
    }
    
    private func getReadableFormatFlags(_ mFormatFlags: UInt32) -> String {
        var description = ""
        if (mFormatFlags & kAudioFormatFlagIsFloat) != 0 {
            description += " kAudioFormatFlagIsFloat"
        }
        if (mFormatFlags & kAudioFormatFlagIsBigEndian) != 0 {
            description += " kAudioFormatFlagIsBigEndian"
        }
        if (mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0 {
            description += " kAudioFormatFlagIsSignedInteger"
        }
        if (mFormatFlags & kAudioFormatFlagIsPacked) != 0 {
            description += " kAudioFormatFlagIsPacked"
        }
        if (mFormatFlags & kAudioFormatFlagIsAlignedHigh) != 0 {
            description += " kAudioFormatFlagIsAlignedHigh"
        }
        if (mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0 {
            description += " kAudioFormatFlagIsNonInterleaved"
        }
        if (mFormatFlags & kAudioFormatFlagIsNonMixable) != 0 {
            description += " kAudioFormatFlagIsNonMixable"
        }
        if (mFormatFlags & kAudioFormatFlagsAreAllClear) != 0 {
            description += " kAudioFormatFlagsAreAllClear"
        }
        if (mFormatFlags & kLinearPCMFormatFlagIsFloat) != 0 {
            description += " kLinearPCMFormatFlagIsFloat"
        }
        if (mFormatFlags & kLinearPCMFormatFlagIsBigEndian) != 0 {
            description += " kLinearPCMFormatFlagIsBigEndian"
        }
        if (mFormatFlags & kLinearPCMFormatFlagIsSignedInteger) != 0 {
            description += " kLinearPCMFormatFlagIsSignedInteger"
        }
        if (mFormatFlags & kLinearPCMFormatFlagIsPacked) != 0 {
            description += " kLinearPCMFormatFlagIsPacked"
        }
        if (mFormatFlags & kLinearPCMFormatFlagIsAlignedHigh) != 0 {
            description += " kLinearPCMFormatFlagIsAlignedHigh"
        }
        if (mFormatFlags & kLinearPCMFormatFlagIsNonInterleaved) != 0 {
            description += " kLinearPCMFormatFlagIsNonInterleaved"
        }
        if (mFormatFlags & kLinearPCMFormatFlagIsNonMixable) != 0 {
            description += " kLinearPCMFormatFlagIsNonMixable"
        }
        if (mFormatFlags & kLinearPCMFormatFlagsSampleFractionShift) != 0 {
            description += " kLinearPCMFormatFlagsSampleFractionShift"
        }
        if (mFormatFlags & kLinearPCMFormatFlagsSampleFractionMask) != 0 {
            description += " kLinearPCMFormatFlagsSampleFractionMask"
        }
        if (mFormatFlags & kLinearPCMFormatFlagsAreAllClear) != 0 {
            description += " kLinearPCMFormatFlagsAreAllClear"
        }
        if (mFormatFlags & kAppleLosslessFormatFlag_16BitSourceData) != 0 {
            description += " kAppleLosslessFormatFlag_16BitSourceData"
        }
        if (mFormatFlags & kAppleLosslessFormatFlag_20BitSourceData) != 0 {
            description += " kAppleLosslessFormatFlag_20BitSourceData"
        }
        if (mFormatFlags & kAppleLosslessFormatFlag_24BitSourceData) != 0 {
            description += " kAppleLosslessFormatFlag_24BitSourceData"
        }
        if (mFormatFlags & kAppleLosslessFormatFlag_32BitSourceData) != 0 {
            description += " kAppleLosslessFormatFlag_32BitSourceData"
        }
        return description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
}
