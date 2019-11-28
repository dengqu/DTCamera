//
//  AudioRecorder.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/11/11.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AudioToolbox
import CocoaLumberjack

class AudioRecorder {

    let fileURL: URL
    let sampleRate: Int

    var audioFile: ExtAudioFileRef!
    
    var auGraph: AUGraph!
    var ioNode = AUNode()
    var ioUnit: AudioUnit! // element 0: output bus, element 1: input bus
    let inputBus: AudioUnitElement = 1
    let outputBus: AudioUnitElement = 0
    var convertNode = AUNode()
    var convertUnit: AudioUnit!
    var mixerNode = AUNode()
    var mixerUnit: AudioUnit!

    init(fileURL: URL, sampleRate: Int) {
        self.fileURL = fileURL
        self.sampleRate = sampleRate
        createAudioUnitGraph()
    }
    
    func startRecording() {
        prepareAudioFile()
        let statusCode = AUGraphStart(auGraph)
        if statusCode != noErr {
            DDLogError("Could not start AUGraph \(statusCode)")
            exit(1)
        }
        DDLogDebug("start audio recording")
    }
    
    func stopRecording() {
        let statusCode = AUGraphStop(auGraph)
        if statusCode != noErr {
            DDLogError("Could not stop AUGraph \(statusCode)")
            exit(1)
        }
        if let audioFile = audioFile {
            ExtAudioFileDispose(audioFile)
        }
        DDLogDebug("stops audio recording")
    }

    private func createAudioUnitGraph() {
        var statusCode = NewAUGraph(&auGraph)
        if statusCode != noErr {
            DDLogError("Could not create a new AUGraph \(statusCode)")
            exit(1)
        }
        
        addAudioUnitNodes()
        
        statusCode = AUGraphOpen(auGraph)
        if statusCode != noErr {
            DDLogError("Could not open AUGraph \(statusCode)")
            exit(1)
        }
        
        getUnitsFromNodes()
        setAudioUnitsProperties()
        makeNodesConnection()
        
        statusCode = AUGraphInitialize(auGraph)
        if statusCode != noErr {
            DDLogError("Could not initialize AUGraph \(statusCode)")
            exit(1)
        }
    }
    
    private func addAudioUnitNodes() {
        var ioDescription = AudioComponentDescription()
        bzero(&ioDescription, MemoryLayout.size(ofValue: ioDescription))
        ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        ioDescription.componentType = kAudioUnitType_Output
        ioDescription.componentSubType = kAudioUnitSubType_RemoteIO
        var statusCode = AUGraphAddNode(auGraph, &ioDescription, &ioNode)
        if statusCode != noErr {
            DDLogError("Could not add I/O node to AUGraph \(statusCode)")
            exit(1)
        }
        
        var converterDescription = AudioComponentDescription()
        bzero(&converterDescription, MemoryLayout.size(ofValue: converterDescription))
        converterDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        converterDescription.componentType = kAudioUnitType_FormatConverter
        converterDescription.componentSubType = kAudioUnitSubType_AUConverter
        statusCode = AUGraphAddNode(auGraph, &converterDescription, &convertNode)
        if statusCode != noErr {
            DDLogError("Could not add converter node to AUGraph \(statusCode)")
            exit(1)
        }

        var mixerDescription = AudioComponentDescription()
        bzero(&mixerDescription, MemoryLayout.size(ofValue: mixerDescription))
        mixerDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        mixerDescription.componentType = kAudioUnitType_Mixer
        mixerDescription.componentSubType = kAudioUnitSubType_MultiChannelMixer
        statusCode = AUGraphAddNode(auGraph, &mixerDescription, &mixerNode)
        if statusCode != noErr {
            DDLogError("Could not add mixer node to AUGraph \(statusCode)")
            exit(1)
        }
    }
    
    private func getUnitsFromNodes() {
        var statusCode = AUGraphNodeInfo(auGraph, ioNode, nil, &ioUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for I/O node \(statusCode)")
            exit(1)
        }
        statusCode = AUGraphNodeInfo(auGraph, convertNode, nil, &convertUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for convert node \(statusCode)")
            exit(1)
        }
        statusCode = AUGraphNodeInfo(auGraph, mixerNode, nil, &mixerUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for mixer node \(statusCode)")
            exit(1)
        }
    }
    
    private func setAudioUnitsProperties() {
        var enableIO: UInt32 = 1
        var statusCode = AudioUnitSetProperty(ioUnit,
                                              kAudioOutputUnitProperty_EnableIO,
                                              kAudioUnitScope_Input,
                                              inputBus,
                                              &enableIO,
                                              UInt32(MemoryLayout.size(ofValue: enableIO)))
        if statusCode != noErr {
            DDLogError("Could not enable I/O for I/O unit input element 1 \(statusCode)")
            exit(1)
        }

        let bytesPerSample: UInt32 = 2
        var stereoStreamFormat = AudioStreamBasicDescription()
        bzero(&stereoStreamFormat, MemoryLayout.size(ofValue: stereoStreamFormat))
        stereoStreamFormat.mSampleRate = Float64(sampleRate)
        stereoStreamFormat.mFormatID = kAudioFormatLinearPCM
        stereoStreamFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked
        stereoStreamFormat.mBitsPerChannel = 8 * bytesPerSample
        stereoStreamFormat.mChannelsPerFrame = 2
        stereoStreamFormat.mBytesPerFrame = bytesPerSample * 2
        stereoStreamFormat.mFramesPerPacket = 1
        stereoStreamFormat.mBytesPerPacket = stereoStreamFormat.mBytesPerFrame
        
        statusCode = AudioUnitSetProperty(ioUnit,
                                          kAudioUnitProperty_StreamFormat,
                                          kAudioUnitScope_Output,
                                          inputBus,
                                          &stereoStreamFormat,
                                          UInt32(MemoryLayout.size(ofValue: stereoStreamFormat)))
        if statusCode != noErr {
            DDLogError("Could not set stream format for I/O unit output element 1 \(statusCode)")
            exit(1)
        }
        
        statusCode = AudioUnitSetProperty(convertUnit,
                                          kAudioUnitProperty_StreamFormat,
                                          kAudioUnitScope_Output,
                                          0,
                                          &stereoStreamFormat,
                                          UInt32(MemoryLayout.size(ofValue: stereoStreamFormat)))
        if statusCode != noErr {
            DDLogError("Could not set stream format for convert unit output element 0 \(statusCode)")
            exit(1)
        }
        
        statusCode = AudioUnitSetProperty(mixerUnit,
                                          kAudioUnitProperty_StreamFormat,
                                          kAudioUnitScope_Output,
                                          0,
                                          &stereoStreamFormat,
                                          UInt32(MemoryLayout.size(ofValue: stereoStreamFormat)))
        if statusCode != noErr {
            DDLogError("Could not set stream format for mixer unit output element 0 \(statusCode)")
            exit(1)
        }

        var mixerElementCount: UInt32 = 1
        statusCode = AudioUnitSetProperty(mixerUnit,
                                          kAudioUnitProperty_ElementCount,
                                          kAudioUnitScope_Input,
                                          0,
                                          &mixerElementCount,
                                          UInt32(MemoryLayout.size(ofValue: mixerElementCount)))
        if statusCode != noErr {
            DDLogError("Could not set element count for mixer unit input element 0 \(statusCode)")
            exit(1)
        }
        
        statusCode = AudioUnitSetProperty(ioUnit,
                                          kAudioUnitProperty_StreamFormat,
                                          kAudioUnitScope_Input,
                                          outputBus,
                                          &stereoStreamFormat,
                                          UInt32(MemoryLayout.size(ofValue: stereoStreamFormat)))
        if statusCode != noErr {
            DDLogError("Could not set stream format for I/O unit output element 0 \(statusCode)")
            exit(1)
        }
    }
        
    private func makeNodesConnection() {
        var statusCode = AUGraphConnectNodeInput(auGraph, ioNode, inputBus, convertNode, 0)
        if statusCode != noErr {
            DDLogError("I/O node element 1 connect to convert node element 0 \(statusCode)")
            exit(1)
        }
        
        statusCode = AUGraphConnectNodeInput(auGraph, convertNode, 0, mixerNode, 0)
        if statusCode != noErr {
            DDLogError("convert node element 0 connect to mixer node element 0 \(statusCode)")
            exit(1)
        }
        
        var inputCallback = AURenderCallbackStruct()
        inputCallback.inputProc = renderCallback
        inputCallback.inputProcRefCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        statusCode = AUGraphSetNodeInputCallback(auGraph, ioNode, outputBus, &inputCallback)
        if statusCode != noErr {
            DDLogError("Could not set input callback for I/O node \(statusCode)")
            exit(1)
        }
    }
    
    private func prepareAudioFile() {
        let bytesPerSample: UInt32 = 2
        var destinationFormat = AudioStreamBasicDescription()
        memset(&destinationFormat, 0, MemoryLayout.size(ofValue: destinationFormat))
        destinationFormat.mSampleRate = Float64(sampleRate)
        destinationFormat.mFormatID = kAudioFormatLinearPCM
        destinationFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked
        destinationFormat.mBitsPerChannel = 8 * bytesPerSample
        destinationFormat.mChannelsPerFrame = 2
        destinationFormat.mBytesPerFrame = bytesPerSample * 2
        destinationFormat.mFramesPerPacket = 1
        destinationFormat.mBytesPerPacket = bytesPerSample * 2

        var size = UInt32(MemoryLayout.size(ofValue: destinationFormat))
        var statusCode = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                                                0,
                                                nil,
                                                &size,
                                                &destinationFormat)
        if statusCode != noErr {
            DDLogError("AudioFormatGetProperty failed \(statusCode)")
            exit(1)
        }

        statusCode = ExtAudioFileCreateWithURL(fileURL as CFURL,
                                               kAudioFileCAFType,
                                               &destinationFormat,
                                               nil,
                                               AudioFileFlags.eraseFile.rawValue,
                                               &audioFile)
        if statusCode != noErr {
            DDLogError("ExtAudioFileCreateWithURL failed \(statusCode)")
            exit(1)
        }
        
        var codec: UInt32 = kAppleHardwareAudioCodecManufacturer
        statusCode = ExtAudioFileSetProperty(audioFile,
                                             kExtAudioFileProperty_CodecManufacturer,
                                             UInt32(MemoryLayout.size(ofValue: codec)),
                                             &codec)
        if statusCode != noErr {
            DDLogError("ExtAudioFileSetProperty kExtAudioFileProperty_CodecManufacturer failed \(statusCode)")
            exit(1)
        }
        
        statusCode = ExtAudioFileWriteAsync(audioFile, 0, nil)
        if statusCode != noErr {
            DDLogError("ExtAudioFileWriteAsync failed \(statusCode)")
            exit(1)
        }
    }

}

func renderCallback(inRefCon: UnsafeMutableRawPointer,
                    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                    inTimeStamp: UnsafePointer<AudioTimeStamp>,
                    inBusNumber: UInt32,
                    inNumberFrames: UInt32,
                    ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let recorder: AudioRecorder = Unmanaged.fromOpaque(inRefCon).takeUnretainedValue()
    var statusCode = AudioUnitRender(recorder.mixerUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData!)
    DDLogDebug("audio recorder write \(inNumberFrames) frames with \(ioData?.pointee.mBuffers.mDataByteSize ?? 0) btyes")
    statusCode = ExtAudioFileWriteAsync(recorder.audioFile, inNumberFrames, ioData)
    if statusCode != noErr {
        DDLogError("ExtAudioFileWriteAsync failed \(statusCode)")
        exit(1)
    }
    return statusCode
}
