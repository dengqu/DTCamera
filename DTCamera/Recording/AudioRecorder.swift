//
//  AudioRecorder.swift
//  DTCamera
//
//  Created by Dan Jiang on 2020/1/9.
//  Copyright © 2020 Dan Thought Studio. All rights reserved.
//

import Foundation

protocol AudioRecorderDelegate: class {
    func audioRecorder(_ recorder: AudioRecorder, receive buffer: AudioBuffer)
}

class AudioRecorder {

    let sampleRate: Int
    let fileURL: URL?
    let bgmFileURL: URL?

    weak var delegate: AudioRecorderDelegate?

    init(sampleRate: Int, fileURL: URL?, bgmFileURL: URL?) {
        self.sampleRate = sampleRate
        self.fileURL = fileURL
        self.bgmFileURL = bgmFileURL
    }
    
    func startRecording() {}
    
    func stopRecording() {}
    
}
