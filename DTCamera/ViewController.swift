//
//  ViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/9/16.
//  Copyright © 2019 Dan Jiang. All rights reserved.
//

import UIKit
import Photos
import DTMessageBar
import CocoaLumberjack

class ViewController: UIViewController {
    
    private let sampleRate: Int = 44100

    private var auGraphPlayer: AUGraphPlayer?
    
    private var audioRecorder: AudioRecorder?
    
    private var audioEncoder: AudioEncoder?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord)
            try AVAudioSession.sharedInstance().setPreferredSampleRate(Double(sampleRate))
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            DDLogError("Could not config audio session: \(error)")
        }
    }

    @IBAction func openCamera(_ sender: Any) {
        let mode = MediaMode(source: .recording, type: .all, config: MediaConfig())
        let mediaVC = MediaViewController(mode: mode)
        mediaVC.modalPresentationStyle = .fullScreen
        mediaVC.delegate = self
        present(mediaVC, animated: true, completion: nil)
    }
        
    @IBAction func startPCMRecording(_ sender: Any) {
        if let fileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "caf") {
            audioRecorder = AudioRecorder(fileURL: fileURL, sampleRate: sampleRate)
            audioRecorder?.startRecording()
        }
    }
    
    @IBAction func stopPCMRecording(_ sender: Any) {
        audioRecorder?.stopRecording()
        audioRecorder = nil
    }
    
    @IBAction func convertPCMtoAAC(_ sender: Any) {
        guard let pcmFileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "caf", needRemove: false),
            let aacFileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "aac", needCreate: true) else {
                return
        }
        audioEncoder = AudioEncoder(sampleRate: sampleRate, inputFileURL: pcmFileURL, outputFileURL: aacFileURL)
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.audioEncoder?.startEncode()
        }
    }
    
    @IBAction func playAAC(_ sender: Any) {
        if let fileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "aac", needRemove: false) {
            auGraphPlayer = AUGraphPlayer(fileURL: fileURL)
            auGraphPlayer?.play()
        }
    }
    
    @IBAction func stopAAC(_ sender: Any) {
        auGraphPlayer?.stop()
        auGraphPlayer = nil
    }
    
}

extension ViewController: MediaViewControllerDelegate {
    
    func media(viewController: MediaViewController, didFinish photos: [UIImage]) {
        dismiss(animated: true, completion: nil)
        PHPhotoLibrary.shared().performChanges({
            for photo in photos {
                PHAssetChangeRequest.creationRequestForAsset(from: photo)
            }
        }, completionHandler: { (success, error) in
            DispatchQueue.main.async {
                if success {
                    DTMessageBar.success(message: "照片保存到相册成功", position: .bottom)
                } else {
                    if let error = error {
                        DDLogError("Could not save photos to album: \(error)")
                    }
                    DTMessageBar.error(message: "照片保存到相册失败", position: .bottom)
                }
            }
        })
    }
    
    func media(viewController: MediaViewController, didFinish video: URL) {
        dismiss(animated: true, completion: nil)
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video)
        }, completionHandler: { (success, error) in
            DispatchQueue.main.async {
                if success {
                    DTMessageBar.success(message: "视频保存到相册成功", position: .bottom)
                } else {
                    if let error = error {
                        DDLogError("Could not save video to album: \(error)")
                    }
                    DTMessageBar.error(message: "视频保存到相册失败", position: .bottom)
                }
            }
        })
    }
    
    func mediaDidDismiss(viewController: MediaViewController) {
        dismiss(animated: true, completion: nil)
    }
    
}
