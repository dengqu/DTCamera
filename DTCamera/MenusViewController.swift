//
//  MenusViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/11/29.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import Photos
import DTMessageBar
import CocoaLumberjack

class MenusViewController: UITableViewController {
    
    private let sampleRate: Int = 44100
    
    private var audioUnitRecorder: AudioRecorder?
    private var audioEngineRecorder: AudioRecorder?
    private var audioEncoder: AudioEncoder?
    private var auGraphPlayer: AUGraphPlayer?
    
    private let cellIdentifier = "cellIdentifier"
    private let rtmpServerKey = "rtmp_server"
    private let rtmpServerDefaultValue = "rtmp://172.104.92.161/mytv/room"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord)
            try AVAudioSession.sharedInstance().setPreferredSampleRate(Double(sampleRate))
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            DDLogError("Could not config audio session: \(error)")
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 5
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 3
        } else if section == 1 {
            return 4
        } else if section == 2 {
            return 3
        } else if section == 3 {
            return 3
        } else if section == 4 {
            return 4
        }
        return 0
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Camera"
        } else if section == 1 {
            return "Audio Recording with Audio Unit"
        } else if section == 2 {
            return "Audio Recording with AVAudioEngine"
        } else if section == 3 {
            return "Audio Convert"
        } else if section == 4 {
            return "Audio Play"
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "Open Camera for Recording"
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Open Camera for Living"
            } else if indexPath.row == 2 {
                cell.textLabel?.text = "Config RTMP URL"
            }
        } else if indexPath.section == 1 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "Start CAF Recording"
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Start CAF Recording with Drums BGM"
            } else if indexPath.row == 2 {
                cell.textLabel?.text = "Start CAF Recording with Guitar BGM"
            } else if indexPath.row == 3 {
                cell.textLabel?.text = "Stop CAF Recording"
            }
        } else if indexPath.section == 2 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "Start CAF Recording with Drums BGM"
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Start CAF Recording with Guitar BGM"
            } else if indexPath.row == 2 {
                cell.textLabel?.text = "Stop CAF Recording"
            }
        } else if indexPath.section == 3 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "Convert CAF to AAC with AudioToolbox"
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Convert CAF to AAC with FFmpeg"
            } else if indexPath.row == 2 {
                cell.textLabel?.text = "Convert AAC to PCM with FFmpeg"
            }
        } else if indexPath.section == 4 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "Start Play MP3"
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Start Play CAF"
            } else if indexPath.row == 2 {
                cell.textLabel?.text = "Start Play AAC"
            } else if indexPath.row == 3 {
                cell.textLabel?.text = "Stop Play"
            }
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                if let videoFile = MediaViewController.getMediaFileURL(name: "video", ext: "flv", needCreate: true) {
                    let mode = MediaMode(source: .recording, type: .all, config: MediaConfig(videoURL: videoFile.path))
                    let mediaVC = MediaViewController(mode: mode)
                    mediaVC.modalPresentationStyle = .fullScreen
                    mediaVC.delegate = self
                    present(mediaVC, animated: true, completion: nil)
                }
            } else if indexPath.row == 1 {
                let mode = MediaMode(source: .recording,
                                     type: .all,
                                     config: MediaConfig(videoURL: UserDefaults.standard.string(forKey: rtmpServerKey) ?? rtmpServerDefaultValue))
                let mediaVC = MediaViewController(mode: mode)
                mediaVC.modalPresentationStyle = .fullScreen
                mediaVC.delegate = self
                present(mediaVC, animated: true, completion: nil)
            } else if indexPath.row == 2 {
                let alertController = UIAlertController(title: "RTMP URL", message: nil, preferredStyle: .alert)
                alertController.addTextField { textField in
                    textField.text = UserDefaults.standard.string(forKey: self.rtmpServerKey) ?? self.rtmpServerDefaultValue
                }
                let confirmAction = UIAlertAction(title: "Save", style: .default) { _ in
                    let textField = alertController.textFields?.first
                    if let rtmpURL = textField?.text {
                        UserDefaults.standard.set(rtmpURL, forKey: self.rtmpServerKey)
                        UserDefaults.standard.synchronize()
                    }
                }
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
                alertController.addAction(confirmAction)
                alertController.addAction(cancelAction)
                present(alertController, animated: true, completion: nil)
            }
        } else if indexPath.section == 1 {
            if indexPath.row == 0 {
                startPCMRecordingWithAudioUnit(bgmFileURL: nil)
            } else if indexPath.row == 1 {
                if let bgmFileURL = Bundle.main.url(forResource: "DrumsMonoSTP", withExtension: "aif") {
                    startPCMRecordingWithAudioUnit(bgmFileURL: bgmFileURL)
                }
            } else if indexPath.row == 2 {
                if let bgmFileURL = Bundle.main.url(forResource: "GuitarMonoSTP", withExtension: "aif") {
                    startPCMRecordingWithAudioUnit(bgmFileURL: bgmFileURL)
                }
            } else if indexPath.row == 3 {
                audioUnitRecorder?.stopRecording()
                audioUnitRecorder = nil
            }
        } else if indexPath.section == 2 {
            if indexPath.row == 0 {
                if let bgmFileURL = Bundle.main.url(forResource: "DrumsMonoSTP", withExtension: "aif") {
                    startPCMRecordingWithAVAudioEngine(bgmFileURL: bgmFileURL)
                }
            } else if indexPath.row == 1 {
                if let bgmFileURL = Bundle.main.url(forResource: "GuitarMonoSTP", withExtension: "aif") {
                    startPCMRecordingWithAVAudioEngine(bgmFileURL: bgmFileURL)
                }
            } else if indexPath.row == 2 {
                audioEngineRecorder?.stopRecording()
                audioEngineRecorder = nil
            }
        } else if indexPath.section == 3 {
            if indexPath.row == 0 {
                if  let pcmFileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "caf", needRemove: false),
                    let aacFileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "aac", needCreate: true) {
                    audioEncoder = AudioEncoder(sampleRate: sampleRate, inputFileURL: pcmFileURL, outputFileURL: aacFileURL)
                    DispatchQueue.global(qos: .background).async { [weak self] in
                        self?.audioEncoder?.startEncode()
                    }
                }
            } else if indexPath.row == 1 {
                if  let pcmFileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "caf", needRemove: false),
                    let aacFileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "aac", needCreate: true) {
                    let aacEncoder = AACEncoder(inputFilePath: pcmFileURL.path, outputFilePath: aacFileURL.path)
                    aacEncoder.startEncode()
                }
            } else if indexPath.row == 2 {
                if let aacFileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "aac", needRemove: false),
                    let pcmFileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "pcm", needCreate: true) {
                    let aacDecoder = AACDecoder(inputFilePath: aacFileURL.path, outputFilePath: pcmFileURL.path)
                    aacDecoder.startDecode()
                }
            }
        } else if indexPath.section == 4 {
            if indexPath.row == 0 {
                if let fileURL = Bundle.main.url(forResource: "faded", withExtension: "mp3") {
                    playAudio(fileURL: fileURL)
                }
            } else if indexPath.row == 1 {
                if let fileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "caf", needRemove: false) {
                    playAudio(fileURL: fileURL)
                }
            } else if indexPath.row == 2 {
                if let fileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "aac", needRemove: false) {
                    playAudio(fileURL: fileURL)
                }
            } else if indexPath.row == 3 {
                auGraphPlayer?.stop()
                auGraphPlayer = nil
            }
        }
    }
    
    private func startPCMRecordingWithAudioUnit(bgmFileURL: URL?) {
        if let fileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "caf") {
            audioUnitRecorder = AudioUnitRecorder(sampleRate: sampleRate, fileURL: fileURL, bgmFileURL: bgmFileURL)
            audioUnitRecorder?.startRecording()
        }
    }
    
    private func startPCMRecordingWithAVAudioEngine(bgmFileURL: URL?) {
        if let fileURL = MediaViewController.getMediaFileURL(name: "audio", ext: "caf") {
            audioEngineRecorder = AudioEngineRecorder(sampleRate: sampleRate, fileURL: fileURL, bgmFileURL: bgmFileURL)
            audioEngineRecorder?.startRecording()
        }
    }
    
    private func playAudio(fileURL: URL) {
        auGraphPlayer = AUGraphPlayer(fileURL: fileURL)
        auGraphPlayer?.play()
    }
    
}

extension MenusViewController: MediaViewControllerDelegate {
    
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
