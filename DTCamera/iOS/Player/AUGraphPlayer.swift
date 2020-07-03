//
//  AUGraphPlayer.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/11/15.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AudioToolbox
import CocoaLumberjack

class AUGraphPlayer {
    
    private let fileURL: URL
    
    private var auGraph: AUGraph!
    private var filePlayerNode = AUNode()
    private var filePlayerUnit: AudioUnit!
    private var mixerNode = AUNode()
    private var mixerUnit: AudioUnit!
    private var ioNode = AUNode()
    private var ioUnit: AudioUnit!
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        createAudioUnitGraph()
    }
    
    func play() {
        let statusCode = AUGraphStart(auGraph)
        if statusCode != noErr {
            DDLogError("Could not start AUGraph \(statusCode)")
            exit(1)
        }
    }
    
    func stop() {
        let statusCode = AUGraphStop(auGraph)
        if statusCode != noErr {
            DDLogError("Could not stop AUGraph \(statusCode)")
            exit(1)
        }
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
        
        setupFilePlayer()
    }
    
    private func addAudioUnitNodes() {
        var filePlayerDescription = AudioComponentDescription()
        bzero(&filePlayerDescription, MemoryLayout.size(ofValue: filePlayerDescription))
        filePlayerDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        filePlayerDescription.componentType = kAudioUnitType_Generator
        filePlayerDescription.componentSubType = kAudioUnitSubType_AudioFilePlayer
        var statusCode = AUGraphAddNode(auGraph, &filePlayerDescription, &filePlayerNode)
        if statusCode != noErr {
            DDLogError("Could not add file player node to AUGraph \(statusCode)")
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
        
        var ioDescription = AudioComponentDescription()
        bzero(&ioDescription, MemoryLayout.size(ofValue: ioDescription))
        ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        ioDescription.componentType = kAudioUnitType_Output
        ioDescription.componentSubType = kAudioUnitSubType_RemoteIO
        statusCode = AUGraphAddNode(auGraph, &ioDescription, &ioNode)
        if statusCode != noErr {
            DDLogError("Could not add I/O node to AUGraph \(statusCode)")
            exit(1)
        }
    }
    
    private func getUnitsFromNodes() {
        var statusCode = AUGraphNodeInfo(auGraph, filePlayerNode, nil, &filePlayerUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for file player node \(statusCode)")
            exit(1)
        }
        
        statusCode = AUGraphNodeInfo(auGraph, mixerNode, nil, &mixerUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for mixer node \(statusCode)")
            exit(1)
        }
        
        statusCode = AUGraphNodeInfo(auGraph, ioNode, nil, &ioUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for I/O node \(statusCode)")
            exit(1)
        }
    }
    
    private func setAudioUnitsProperties() {
        var mixerElementCount: UInt32 = 1
        var statusCode = AudioUnitSetProperty(mixerUnit,
                                              kAudioUnitProperty_ElementCount,
                                              kAudioUnitScope_Input,
                                              0,
                                              &mixerElementCount,
                                              UInt32(MemoryLayout.size(ofValue: mixerElementCount)))
        if statusCode != noErr {
            DDLogError("Could not set element count for mixer unit input element 0 \(statusCode)")
            exit(1)
        }
        
        statusCode = AudioUnitSetParameter(mixerUnit,
                                           kMultiChannelMixerParam_Volume,
                                           kAudioUnitScope_Output,
                                           0,
                                           5.0,
                                           0)
        if statusCode != noErr {
            DDLogError("Could not set volume for mixer unit output element 0 \(statusCode)")
            exit(1)
        }
    }
    
    private func makeNodesConnection() {
        var statusCode = AUGraphConnectNodeInput(auGraph, filePlayerNode, 0, mixerNode, 0)
        if statusCode != noErr {
            DDLogError("file player node element 0 connect to mixer node element 0 \(statusCode)")
            exit(1)
        }
        statusCode = AUGraphConnectNodeInput(auGraph, mixerNode, 0, ioNode, 0)
        if statusCode != noErr {
            DDLogError("mixer node element 0 connect to I/O node element 0 \(statusCode)")
            exit(1)
        }
    }
        
    private func setupFilePlayer() {
        // 打开音频文件
        var fileId: AudioFileID!
        var statusCode = AudioFileOpenURL(fileURL as CFURL, .readPermission, 0, &fileId)
        if statusCode != noErr {
            DDLogError("Could not open audio file \(statusCode)")
            exit(1)
        }
        
        // 给 AudioUnit 设置音频文件 ID
        statusCode = AudioUnitSetProperty(filePlayerUnit,
                                          kAudioUnitProperty_ScheduledFileIDs,
                                          kAudioUnitScope_Global,
                                          0,
                                          &fileId,
                                          UInt32(MemoryLayout.size(ofValue: fileId)))
        if statusCode != noErr {
            DDLogError("Could not tell file player unit load which file \(statusCode)")
            exit(1)
        }
        
        // 获取音频文件的格式信息
        var fileAudioStreamFormat = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: fileAudioStreamFormat))
        statusCode = AudioFileGetProperty(fileId,
                                          kAudioFilePropertyDataFormat,
                                          &size,
                                          &fileAudioStreamFormat)
        if statusCode != noErr {
            DDLogError("Could not get the audio data format from the file \(statusCode)")
            exit(1)
        }
        
        // 获取音频文件的包数量
        var numberOfPackets: UInt64 = 0
        size = UInt32(MemoryLayout.size(ofValue: numberOfPackets))
        statusCode = AudioFileGetProperty(fileId,
                                          kAudioFilePropertyAudioDataPacketCount,
                                          &size,
                                          &numberOfPackets)
        if statusCode != noErr {
            DDLogError("Could not get number of packets from the file \(statusCode)")
            exit(1)
        }
        
        // 设置音频文件播放的范围：是否循环，起始帧，播放多少帧
        var rgn = ScheduledAudioFileRegion(mTimeStamp: .init(),
                                           mCompletionProc: nil,
                                           mCompletionProcUserData: nil,
                                           mAudioFile: fileId,
                                           mLoopCount: 0,
                                           mStartFrame: 0,
                                           mFramesToPlay: UInt32(numberOfPackets) * fileAudioStreamFormat.mFramesPerPacket)
        memset(&rgn.mTimeStamp, 0, MemoryLayout.size(ofValue: rgn.mTimeStamp))
        rgn.mTimeStamp.mFlags = .sampleTimeValid
        rgn.mTimeStamp.mSampleTime = 0
        statusCode = AudioUnitSetProperty(filePlayerUnit,
                                          kAudioUnitProperty_ScheduledFileRegion,
                                          kAudioUnitScope_Global,
                                          0,
                                          &rgn,
                                          UInt32(MemoryLayout.size(ofValue: rgn)))
        if statusCode != noErr {
            DDLogError("Could not set file player unit`s region \(statusCode)")
            exit(1)
        }
        
        // 设置 prime，I don`t know why
        var defaultValue: UInt32 = 0
        statusCode = AudioUnitSetProperty(filePlayerUnit,
                                          kAudioUnitProperty_ScheduledFilePrime,
                                          kAudioUnitScope_Global,
                                          0,
                                          &defaultValue,
                                          UInt32(MemoryLayout.size(ofValue: defaultValue)))
        if statusCode != noErr {
            DDLogError("Could not set file player unit`s prime \(statusCode)")
            exit(1)
        }
        
        // 设置 start time，I don`t know why
        var startTime = AudioTimeStamp()
        memset(&startTime, 0, MemoryLayout.size(ofValue: startTime))
        startTime.mFlags = .sampleTimeValid
        startTime.mSampleTime = -1
        statusCode = AudioUnitSetProperty(filePlayerUnit,
                                          kAudioUnitProperty_ScheduleStartTimeStamp,
                                          kAudioUnitScope_Global,
                                          0,
                                          &startTime,
                                          UInt32(MemoryLayout.size(ofValue: startTime)))
        if statusCode != noErr {
            DDLogError("Could not set file player unit`s start time \(statusCode)")
            exit(1)
        }
    }
    
}
