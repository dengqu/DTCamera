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
    private var playerNode = AUNode()
    private var playerUnit: AudioUnit!
    private var splitterNode = AUNode()
    private var splitterUnit: AudioUnit!
    private var vocalMixerNode = AUNode()
    private var vocalMixerUnit: AudioUnit!
    private var accMixerNode = AUNode()
    private var accMixerUnit: AudioUnit!
    private var ioNode = AUNode()
    private var ioUnit: AudioUnit!

    init(fileURL: URL) {
        self.fileURL = fileURL
        initializePlayGraph()
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

    private func initializePlayGraph() {
        var statusCode = NewAUGraph(&auGraph)
        if statusCode != noErr {
            DDLogError("Could not create a new AUGraph \(statusCode)")
            exit(1)
        }
        
        var playerDescription = AudioComponentDescription()
        bzero(&playerDescription, MemoryLayout.size(ofValue: playerDescription))
        playerDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        playerDescription.componentType = kAudioUnitType_Generator
        playerDescription.componentSubType = kAudioUnitSubType_AudioFilePlayer
        statusCode = AUGraphAddNode(auGraph, &playerDescription, &playerNode)
        if statusCode != noErr {
            DDLogError("Could not add player node to AUGraph \(statusCode)")
            exit(1)
        }

        var splitterDescription = AudioComponentDescription()
        bzero(&splitterDescription, MemoryLayout.size(ofValue: splitterDescription))
        splitterDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        splitterDescription.componentType = kAudioUnitType_FormatConverter
        splitterDescription.componentSubType = kAudioUnitSubType_Splitter
        statusCode = AUGraphAddNode(auGraph, &splitterDescription, &splitterNode)
        if statusCode != noErr {
            DDLogError("Could not add splitter node to AUGraph \(statusCode)")
            exit(1)
        }
        
        var mixerDescription = AudioComponentDescription()
        bzero(&mixerDescription, MemoryLayout.size(ofValue: mixerDescription))
        mixerDescription.componentManufacturer = kAudioUnitManufacturer_Apple
        mixerDescription.componentType = kAudioUnitType_Mixer
        mixerDescription.componentSubType = kAudioUnitSubType_MultiChannelMixer
        statusCode = AUGraphAddNode(auGraph, &mixerDescription, &vocalMixerNode)
        if statusCode != noErr {
            DDLogError("Could not add vocal mixer node to AUGraph \(statusCode)")
            exit(1)
        }
        statusCode = AUGraphAddNode(auGraph, &mixerDescription, &accMixerNode)
        if statusCode != noErr {
            DDLogError("Could not add acc mixer node to AUGraph \(statusCode)")
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
        
        statusCode = AUGraphOpen(auGraph)
        if statusCode != noErr {
            DDLogError("Could not open AUGraph \(statusCode)")
            exit(1)
        }
                
        statusCode = AUGraphNodeInfo(auGraph, playerNode, nil, &playerUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for player node \(statusCode)")
            exit(1)
        }

        statusCode = AUGraphNodeInfo(auGraph, splitterNode, nil, &splitterUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for splitter node \(statusCode)")
            exit(1)
        }

        statusCode = AUGraphNodeInfo(auGraph, vocalMixerNode, nil, &vocalMixerUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for vocal mixer node \(statusCode)")
            exit(1)
        }
        
        statusCode = AUGraphNodeInfo(auGraph, accMixerNode, nil, &accMixerUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for acc mixer node \(statusCode)")
            exit(1)
        }
        
        statusCode = AUGraphNodeInfo(auGraph, ioNode, nil, &ioUnit)
        if statusCode != noErr {
            DDLogError("Could not retrieve node info for I/O node \(statusCode)")
            exit(1)
        }

        var mixerElementCount: UInt32 = 1
        statusCode = AudioUnitSetProperty(vocalMixerUnit,
                                          kAudioUnitProperty_ElementCount,
                                          kAudioUnitScope_Input,
                                          0,
                                          &mixerElementCount,
                                          UInt32(MemoryLayout.size(ofValue: mixerElementCount)))
        if statusCode != noErr {
            DDLogError("Could not set element count for vocal mixer unit input element 0 \(statusCode)")
            exit(1)
        }

        mixerElementCount = 2
        statusCode = AudioUnitSetProperty(accMixerUnit,
                                          kAudioUnitProperty_ElementCount,
                                          kAudioUnitScope_Input,
                                          0,
                                          &mixerElementCount,
                                          UInt32(MemoryLayout.size(ofValue: mixerElementCount)))
        if statusCode != noErr {
            DDLogError("Could not set element count for acc mixer unit input element 0 \(statusCode)")
            exit(1)
        }
                
        setInputSource()
        
        statusCode = AUGraphConnectNodeInput(auGraph, playerNode, 0, splitterNode, 0)
        if statusCode != noErr {
            DDLogError("player node element 0 connect to splitter node element 0 \(statusCode)")
            exit(1)
        }
        statusCode = AUGraphConnectNodeInput(auGraph, splitterNode, 0, vocalMixerNode, 0)
        if statusCode != noErr {
            DDLogError("splitter node element 0 connect to vocal mixer node element 0 \(statusCode)")
            exit(1)
        }
        statusCode = AUGraphConnectNodeInput(auGraph, splitterNode, 1, accMixerNode, 0)
        if statusCode != noErr {
            DDLogError("splitter node element 1 connect to acc mixer node element 0 \(statusCode)")
            exit(1)
        }
        statusCode = AUGraphConnectNodeInput(auGraph, vocalMixerNode, 0, accMixerNode, 1)
        if statusCode != noErr {
            DDLogError("vocal mixer node element 0 connect to acc mixer node element 1 \(statusCode)")
            exit(1)
        }
        statusCode = AUGraphConnectNodeInput(auGraph, accMixerNode, 0, ioNode, 0)
        if statusCode != noErr {
            DDLogError("acc mixer node element 0 connect to I/O node element 0 \(statusCode)")
            exit(1)
        }
        
        statusCode = AUGraphInitialize(auGraph)
        if statusCode != noErr {
            DDLogError("Could not initialize AUGraph \(statusCode)")
            exit(1)
        }
        
        setupFilePlayer()
    }
    
    private func setInputSource() {
        var value = AudioUnitParameterValue()
        var statusCode = AudioUnitGetParameter(vocalMixerUnit,
                                               kMultiChannelMixerParam_Volume,
                                               kAudioUnitScope_Input,
                                               0,
                                               &value)
        if statusCode != noErr {
            DDLogError("get vocal mixer unit input element 0`s volume failed \(statusCode)")
            exit(1)
        }
        DDLogInfo("Vocal Mixer Unit Input Element 0`s Volume: \(String(describing: value))")
        
        statusCode = AudioUnitGetParameter(accMixerUnit,
                                           kMultiChannelMixerParam_Volume,
                                           kAudioUnitScope_Input,
                                           0,
                                           &value)
        if statusCode != noErr {
            DDLogError("get acc mixer unit input element 0`s volumn failed \(statusCode)")
            exit(1)
        }
        DDLogInfo("Acc Mixer Unit Input Element 0`s Volume: \(String(describing: value))")

        statusCode = AudioUnitGetParameter(accMixerUnit,
                                           kMultiChannelMixerParam_Volume,
                                           kAudioUnitScope_Input,
                                           1,
                                           &value)
        if statusCode != noErr {
            DDLogError("get acc mixer unit input element 1`s volumn failed \(statusCode)")
            exit(1)
        }
        DDLogInfo("Acc Mixer Unit Input Element 1`s Volume: \(String(describing: value))")

        var volume: AudioUnitParameterValue = 1
        statusCode = AudioUnitSetParameter(accMixerUnit,
                                           kMultiChannelMixerParam_Volume,
                                           kAudioUnitScope_Input,
                                           0,
                                           volume,
                                           0)
        if statusCode != noErr {
            DDLogError("set acc mixer unit input element 0`s volumn failed \(statusCode)")
            exit(1)
        }

        volume = 4
        statusCode = AudioUnitSetParameter(accMixerUnit,
                                           kMultiChannelMixerParam_Volume,
                                           kAudioUnitScope_Input,
                                           1,
                                           volume,
                                           0)
        if statusCode != noErr {
            DDLogError("set acc mixer unit input element 1`s volumn failed \(statusCode)")
            exit(1)
        }
    }
    
    private func setupFilePlayer() {
        var musicFile: AudioFileID!
        var statusCode = AudioFileOpenURL(fileURL as CFURL, .readPermission, 0, &musicFile)
        if statusCode != noErr {
            DDLogError("Could not open audio file \(statusCode)")
            exit(1)
        }
        
        statusCode = AudioUnitSetProperty(playerUnit,
                                          kAudioUnitProperty_ScheduledFileIDs,
                                          kAudioUnitScope_Global,
                                          0,
                                          &musicFile,
                                          UInt32(MemoryLayout.size(ofValue: musicFile)))
        if statusCode != noErr {
            DDLogError("Could not tell player unit load which file \(statusCode)")
            exit(1)
        }
        
        var fileASBD = AudioStreamBasicDescription()
        var propSize = UInt32(MemoryLayout.size(ofValue: fileASBD))
        statusCode = AudioFileGetProperty(musicFile,
                                          kAudioFilePropertyDataFormat,
                                          &propSize,
                                          &fileASBD)
        if statusCode != noErr {
            DDLogError("Could not get the audio data format from the file \(statusCode)")
            exit(1)
        }
        
        var nPackets: UInt64 = 0
        var propsSize = UInt32(MemoryLayout.size(ofValue: nPackets))
        statusCode = AudioFileGetProperty(musicFile,
                                          kAudioFilePropertyAudioDataPacketCount,
                                          &propsSize,
                                          &nPackets)
        if statusCode != noErr {
            DDLogError("Could not get packets total number from the file \(statusCode)")
            exit(1)
        }
        
        var rgn = ScheduledAudioFileRegion(mTimeStamp: .init(),
                                           mCompletionProc: nil,
                                           mCompletionProcUserData: nil,
                                           mAudioFile: musicFile,
                                           mLoopCount: 0,
                                           mStartFrame: 0,
                                           mFramesToPlay: UInt32(nPackets) * fileASBD.mFramesPerPacket)
        memset(&rgn.mTimeStamp, 0, MemoryLayout.size(ofValue: rgn.mTimeStamp))
        rgn.mTimeStamp.mFlags = .sampleTimeValid
        rgn.mTimeStamp.mSampleTime = 0
        statusCode = AudioUnitSetProperty(playerUnit,
                                          kAudioUnitProperty_ScheduledFileRegion,
                                          kAudioUnitScope_Global,
                                          0,
                                          &rgn,
                                          UInt32(MemoryLayout.size(ofValue: rgn)))
        if statusCode != noErr {
            DDLogError("Could not set player unit`s region \(statusCode)")
            exit(1)
        }
        
        var defaultValue: UInt32 = 0
        statusCode = AudioUnitSetProperty(playerUnit,
                                          kAudioUnitProperty_ScheduledFilePrime,
                                          kAudioUnitScope_Global,
                                          0,
                                          &defaultValue,
                                          UInt32(MemoryLayout.size(ofValue: defaultValue)))
        if statusCode != noErr {
            DDLogError("Could not set player unit`s prime \(statusCode)")
            exit(1)
        }
        
        var startTime = AudioTimeStamp()
        memset(&startTime, 0, MemoryLayout.size(ofValue: startTime))
        startTime.mFlags = .sampleTimeValid
        startTime.mSampleTime = -1
        statusCode = AudioUnitSetProperty(playerUnit,
                                          kAudioUnitProperty_ScheduleStartTimeStamp,
                                          kAudioUnitScope_Global,
                                          0,
                                          &startTime,
                                          UInt32(MemoryLayout.size(ofValue: startTime)))
        if statusCode != noErr {
            DDLogError("Could not set player unit`s start time \(statusCode)")
            exit(1)
        }
    }

}
