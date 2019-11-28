//
//  AudioEncoder.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/11/20.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AudioToolbox
import CoreAudio
import CocoaLumberjack

class AudioEncoder {

    var isComplete = false

    let sampleRate: Int
    let channels: Int = 2
    
    let inputFileURL: URL
    var inputFileId: AudioFileID!
    var inputFilePosition: Int64 = 0
    var inputAudioStreamFormat = AudioStreamBasicDescription()
    var inputBufferSize: UInt32 = 32768
    var inputBuffer: UnsafeMutablePointer<UInt8>!
    var inputSizePerPacket: UInt32!
    var inputPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>? = nil

    let outputFileURL: URL
    var outputFileId: AudioFileID!
    var outputFilePosition: Int64 = 0
    var outputAudioStreamFormat = AudioStreamBasicDescription()
    var outputBufferSize: UInt32 = 32768
    var outputBuffer: UnsafeMutablePointer<UInt8>!
    var outputSizePerPacket: UInt32!
    var outputPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>? = nil

    var audioConverter: AudioConverterRef!

    init(sampleRate: Int, inputFileURL: URL, outputFileURL: URL) {
        self.sampleRate = sampleRate
        self.inputFileURL = inputFileURL
        self.outputFileURL = outputFileURL
        setupEncoder()
    }
    
    func startEncode() {
        var statusCode = noErr
        var totalOutputFrames: UInt64 = 0
        while !isComplete {
                var outAudioBufferList = AudioBufferList()
                outAudioBufferList.mNumberBuffers = 1
                outAudioBufferList.mBuffers.mNumberChannels = UInt32(channels)
                outAudioBufferList.mBuffers.mDataByteSize = outputBufferSize
                outAudioBufferList.mBuffers.mData = UnsafeMutableRawPointer(outputBuffer)

                var ioOutputDataPackets = outputBufferSize / outputSizePerPacket
                statusCode = AudioConverterFillComplexBuffer(audioConverter,
                                                             inputDataProc,
                                                             UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                                             &ioOutputDataPackets,
                                                             &outAudioBufferList,
                                                             outputPacketDescriptions)
                if statusCode == noErr {
                    let inNumBytes = outAudioBufferList.mBuffers.mDataByteSize
                    statusCode = AudioFileWritePackets(outputFileId, false, inNumBytes, outputPacketDescriptions, outputFilePosition, &ioOutputDataPackets, outputBuffer)
                    if statusCode != noErr {
                        DDLogError("AudioFileWritePackets failed \(statusCode)")
                        exit(1)
                    }

                    DDLogDebug("write \(ioOutputDataPackets) packets with \(inNumBytes) btyes at position \(outputFilePosition)")

                    outputFilePosition += Int64(ioOutputDataPackets)
                    
                    if outputAudioStreamFormat.mFramesPerPacket != 0 {
                        totalOutputFrames += UInt64(ioOutputDataPackets * outputAudioStreamFormat.mFramesPerPacket)
                    } else if let outputPacketDescriptions = outputPacketDescriptions {
                        for i in 0..<Int(ioOutputDataPackets) {
                            totalOutputFrames += UInt64(outputPacketDescriptions[i].mVariableFramesInPacket)
                        }
                    }
                } else {
                    if statusCode == kAudioConverterErr_HardwareInUse {
                        DDLogError("Audio Converter returned kAudioConverterErr_HardwareInUse")
                    } else {
                        DDLogError("AudioConverterFillComplexBuffer failed \(statusCode)")
                    }
                }
        }
        DDLogDebug("Total number of output frames counted: \(totalOutputFrames)")
        DDLogDebug("Audio Encoder Complete")
    }
        
    private func setupEncoder() {
        var statusCode = noErr
        var size: UInt32 = 0
        
        statusCode = AudioFileOpenURL(inputFileURL as CFURL, .readPermission, 0, &inputFileId)
        guard statusCode == noErr, let inputFileId = inputFileId else {
            DDLogError("AudioFileOpenURL failed for input file with URL: \(inputFileURL)")
            exit(1)
        }
        
        size = UInt32(MemoryLayout.stride(ofValue: inputAudioStreamFormat))
        statusCode = AudioFileGetProperty(inputFileId, kAudioFilePropertyDataFormat, &size, &inputAudioStreamFormat)
        if statusCode != noErr {
            DDLogError("AudioFileGetProperty couldn't get the inputAudioStreamFormat data format")
            exit(1)
        }

        bzero(&outputAudioStreamFormat, MemoryLayout.size(ofValue: outputAudioStreamFormat))
        outputAudioStreamFormat.mSampleRate = inputAudioStreamFormat.mSampleRate
        outputAudioStreamFormat.mFormatID = kAudioFormatMPEG4AAC
        outputAudioStreamFormat.mChannelsPerFrame = inputAudioStreamFormat.mChannelsPerFrame
        
        size = UInt32(MemoryLayout.stride(ofValue: outputAudioStreamFormat))
        statusCode = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &size, &outputAudioStreamFormat)
        if statusCode != noErr {
            DDLogError("AudioFormatGetProperty couldn't fill out the outputAudioStreamFormat data format")
            exit(1)
        }

        DDLogDebug("Input Audio Stream Format:")
        DebugHelper.shared.debugAudioStreamBasicDescription(inputAudioStreamFormat)
        DDLogDebug("Output Audio Stream Format:")
        DebugHelper.shared.debugAudioStreamBasicDescription(outputAudioStreamFormat)

        // can not get hardware encoder
        guard var description = getAudioClassDescription(with: kAudioFormatMPEG4AAC, from: kAppleSoftwareAudioCodecManufacturer) else {
            DDLogError("Could not getAudioClassDescription")
            exit(1)
        }
        
        // but directly set hardware encoder is work, so wired...
//        var description = AudioClassDescription(mType: kAudioEncoderComponentType, mSubType: kAudioFormatMPEG4AAC, mManufacturer: kAppleHardwareAudioCodecManufacturer)
        
        statusCode = AudioConverterNewSpecific(&inputAudioStreamFormat, &outputAudioStreamFormat, 1, &description, &audioConverter)
        if statusCode != noErr || audioConverter == nil {
            DDLogError("AudioConverterNew failed \(statusCode)")
            exit(1)
        }
                
        size = UInt32(MemoryLayout.size(ofValue: inputAudioStreamFormat))
        AudioConverterGetProperty(audioConverter, kAudioConverterCurrentInputStreamDescription, &size, &inputAudioStreamFormat)
        size = UInt32(MemoryLayout.size(ofValue: outputAudioStreamFormat))
        AudioConverterGetProperty(audioConverter, kAudioConverterCurrentOutputStreamDescription, &size, &outputAudioStreamFormat)
        
        DDLogDebug("Formats returned from AudioConverter:")
        DDLogDebug("Input Audio Stream Format:")
        DebugHelper.shared.debugAudioStreamBasicDescription(inputAudioStreamFormat)
        DDLogDebug("Output Audio Stream Format:")
        DebugHelper.shared.debugAudioStreamBasicDescription(outputAudioStreamFormat)
                
        /*
         If encoding to AAC set the bitrate kAudioConverterEncodeBitRate is a UInt32 value containing
         the number of bits per second to aim for when encoding data when you explicitly set the bit rate
         and the sample rate, this tells the encoder to stick with both bit rate and sample rate
         but there are combinations (also depending on the number of channels) which will not be allowed
         if you do not explicitly set a bit rate the encoder will pick the correct value for you depending
         on samplerate and number of channels bit rate also scales with the number of channels,
         therefore one bit rate per sample rate can be used for mono cases and if you have stereo or more,
         you can multiply that number by the number of channels.
         */
        if outputAudioStreamFormat.mFormatID == kAudioFormatMPEG4AAC {
            var outputBitRate: UInt32 = 64000
            
            size = UInt32(MemoryLayout.size(ofValue: outputBitRate))
            
            if outputAudioStreamFormat.mSampleRate >= 44100 {
                outputBitRate = 192000
            } else if outputAudioStreamFormat.mSampleRate < 22000 {
                outputBitRate = 32000
            }
            
            // Set the bit rate depending on the sample rate chosen.
            statusCode = AudioConverterSetProperty(audioConverter, kAudioConverterEncodeBitRate, size, &outputBitRate)
            if statusCode != noErr {
                DDLogError("AudioConverterSetProperty kAudioConverterEncodeBitRate failed \(statusCode)")
                exit(1)
            }
            
            // Get it back and print it out.
            AudioConverterGetProperty(audioConverter, kAudioConverterEncodeBitRate, &size, &outputBitRate)
            DDLogDebug("AAC Encode Bitrate: \(outputBitRate)")
        }
        
        statusCode = AudioFileCreateWithURL(outputFileURL as CFURL, kAudioFileAAC_ADTSType, &outputAudioStreamFormat, .eraseFile, &outputFileId)
        if statusCode != noErr {
            DDLogError("AudioFileCreateWithURL failed \(statusCode)")
            exit(1)
        }

        inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(inputBufferSize))
        if inputAudioStreamFormat.mBytesPerPacket == 0 {
            /*
             if the source format is VBR, we need to get the maximum packet size
             use kAudioFilePropertyPacketSizeUpperBound which returns the theoretical maximum packet size
             in the file (without actually scanning the whole file to find the largest packet,
             as may happen with kAudioFilePropertyMaximumPacketSize)
             */
            size = UInt32(MemoryLayout.size(ofValue: inputSizePerPacket))
            statusCode = AudioFileGetProperty(inputFileId, kAudioFilePropertyPacketSizeUpperBound, &size, &inputSizePerPacket)
            if statusCode != noErr {
                DDLogError("AudioFileGetProperty kAudioFilePropertyPacketSizeUpperBound failed \(statusCode)")
                exit(1)
            }
            
            // How many packets can we read for our buffer size?
            let numPacketsPerRead = inputBufferSize / inputSizePerPacket
            
            // Allocate memory for the PacketDescription structs describing the layout of each packet.
            inputPacketDescriptions = .allocate(capacity: Int(numPacketsPerRead))
        } else {
            // CBR source format
            inputSizePerPacket = inputAudioStreamFormat.mBytesPerPacket
            inputPacketDescriptions = nil
        }

        outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(outputBufferSize))
        outputSizePerPacket = outputAudioStreamFormat.mBytesPerPacket
        if outputSizePerPacket == 0 {
            // if the destination format is VBR, we need to get max size per packet from the converter
            var size = UInt32(MemoryLayout.size(ofValue: outputSizePerPacket))
            
            statusCode = AudioConverterGetProperty(audioConverter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &outputSizePerPacket)
            if statusCode != noErr {
                DDLogError("AudioConverterGetProperty kAudioConverterPropertyMaximumOutputPacketSize failed \(statusCode)")
                exit(1)
            }
            
            outputPacketDescriptions = .allocate(capacity: Int(outputBufferSize / outputSizePerPacket))
        }
    }
    
    private func getAudioClassDescription(with subType: UInt32, from manufacturer: UInt32) -> AudioClassDescription? {
        var encoderSubType = subType
        var bufferSize: UInt32 = 0
        var statusCode = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                                    UInt32(MemoryLayout.size(ofValue: encoderSubType)),
                                                    &encoderSubType,
                                                    &bufferSize)
        if statusCode != noErr {
            DDLogError("AudioFormatGetPropertyInfo kAudioFormatProperty_Encoders failed \(statusCode)")
            exit(1)
        }
        
        let count = Int(bufferSize) / MemoryLayout<AudioClassDescription>.size
        var descriptions = Array(repeating: AudioClassDescription(), count: count)
        statusCode = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                                            UInt32(MemoryLayout.size(ofValue: encoderSubType)),
                                            &encoderSubType,
                                            &bufferSize,
                                            &descriptions)
        if statusCode != noErr {
            DDLogError("AudioFormatGetProperty kAudioFormatProperty_Encoders failed \(statusCode)")
            exit(1)
        }

        for i in 0..<count {
            if subType == descriptions[i].mSubType, manufacturer == descriptions[i].mManufacturer {
                return descriptions[i]
            }
        }
        
        return nil
    }
    
}

func inputDataProc(inAudioConverter: AudioConverterRef,
                   ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
                   ioData: UnsafeMutablePointer<AudioBufferList>,
                   outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
                   inUserData: UnsafeMutableRawPointer?) -> OSStatus {
    var statusCode = noErr
    
    let encoder: AudioEncoder = Unmanaged.fromOpaque(inUserData!).takeUnretainedValue()
    
    let maxPackets = encoder.inputBufferSize / encoder.inputSizePerPacket
    if ioNumberDataPackets.pointee > maxPackets {
        ioNumberDataPackets.pointee = maxPackets
    }
    
    var outNumBytes = maxPackets * encoder.inputSizePerPacket
    
    statusCode = AudioFileReadPacketData(encoder.inputFileId, false, &outNumBytes, encoder.inputPacketDescriptions, encoder.inputFilePosition, ioNumberDataPackets, encoder.inputBuffer)
    if statusCode != noErr {
        DDLogError("AudioFileReadPacketData failed \(statusCode)")
        exit(1)
    }
    
    encoder.isComplete = outNumBytes == 0

    // read 1024 pcm packtes, write 1 aac packet
    DDLogDebug("read \(ioNumberDataPackets.pointee) packets with \(outNumBytes) btyes at position \(encoder.inputFilePosition)")

    // advance input file packet position
    encoder.inputFilePosition += Int64(ioNumberDataPackets.pointee)

    // put the data pointer into the buffer list
    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(encoder.inputBuffer)
    ioData.pointee.mBuffers.mDataByteSize = outNumBytes
    ioData.pointee.mBuffers.mNumberChannels = UInt32(encoder.channels)
        
    // don't forget the packet descriptions if required
    if let outDataPacketDescription = outDataPacketDescription {
        if let inputPacketDescriptions = encoder.inputPacketDescriptions {
            outDataPacketDescription.pointee = inputPacketDescriptions
        } else {
            outDataPacketDescription.pointee = nil
        }
    }

    return statusCode
}
