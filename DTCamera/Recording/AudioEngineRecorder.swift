//
//  AudioEngineRecorder.swift
//  DTCamera
//
//  Created by Dan Jiang on 2020/1/9.
//  Copyright © 2020 Dan Thought Studio. All rights reserved.
//

import UIKit
import AVFoundation
import CocoaLumberjack

class AudioEngineRecorder: AudioRecorder {
    
    var outputFile: AVAudioFile?
    var outputFormat: AVAudioFormat!
    var converterFormat: AVAudioFormat!
    var converter: AVAudioConverter!

    var bgmFile: AVAudioFile?

    private let engine = AVAudioEngine()
    private let filePlayer = AVAudioPlayerNode()
    
    override init(sampleRate: Int, fileURL: URL?, bgmFileURL: URL?) {
        super.init(sampleRate: sampleRate, fileURL: fileURL, bgmFileURL: bgmFileURL)
        outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        setupFilePlayer()
        setupOutputFile()
        setupConverter()
        setupAudioEngine()
    }
    
    override func startRecording() {
        do {
          try engine.start()
        } catch let error {
            DDLogError("Could not start AVAudioEngine \(error.localizedDescription)")
            exit(1)
        }
        scheduleAudioFile()
        filePlayer.play()
        installTap()
        DDLogDebug("start audio recording")
    }
    
    override func stopRecording() {
        removeTap()
        filePlayer.stop()
        engine.stop()
        DDLogDebug("stops audio recording")
    }

    private func setupAudioEngine() {
        engine.attach(filePlayer)
        
        let format = engine.inputNode.inputFormat(forBus: 0)

        engine.connect(engine.inputNode, to: engine.mainMixerNode, fromBus: 0,
                       toBus: 0, format: format)
        if let bgmFile = bgmFile {
            engine.connect(filePlayer, to: engine.mainMixerNode, fromBus: 0,
                           toBus: 1, format: bgmFile.processingFormat)
        }
                
        engine.prepare()
    }
    
    private func setupOutputFile() {
        guard let fileURL = fileURL else { return }

        outputFile = try? AVAudioFile(forWriting: fileURL, settings: outputFormat.settings)
    }
    
    private func setupFilePlayer() {
        guard let bgmFileURL = bgmFileURL else { return }
        
        bgmFile = try? AVAudioFile(forReading: bgmFileURL)
    }
    
    private func scheduleAudioFile() {
        guard let bgmFile = bgmFile else { return }

        filePlayer.scheduleFile(bgmFile, at: nil, completionHandler: nil)
    }
    
    private func setupConverter() {
        guard fileURL == nil else { return }
        guard let converterFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: 2, interleaved: true) else {
            DDLogError("Could not create audio format for converter")
            exit(1)
        }
        self.converterFormat = converterFormat
        self.converter = AVAudioConverter(from: outputFormat, to: converterFormat)!
    }
    
    private func installTap() {
        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: outputFormat) { [weak self] buffer, when in
            guard let self = self else { return }
            if let outputFile = self.outputFile {
                do {
                  try outputFile.write(from: buffer)
                } catch let error {
                    DDLogError("Could not write buffer data to file \(error.localizedDescription)")
                }
            } else if let delegate = self.delegate, let converter = self.converter {
                let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = AVAudioConverterInputStatus.haveData
                    return buffer
                }
                let convertedBuffer = AVAudioPCMBuffer(pcmFormat: self.converterFormat,
                                                       frameCapacity: AVAudioFrameCount(self.converterFormat.sampleRate) * buffer.frameLength / AVAudioFrameCount(buffer.format.sampleRate))!
                var error: NSError? = nil
                let statusCode = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputCallback)
                if statusCode == .error {
                    DDLogError("AVAudioConverter failed \(error?.localizedDescription ?? "")")
                    exit(1)
                }
                delegate.audioRecorder(self, receive: convertedBuffer.audioBufferList.pointee.mBuffers)
            }
        }
    }
    
    private func removeTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
    }
    
}
