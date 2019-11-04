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

    @IBAction func go(_ sender: Any) {
        let mode = MediaMode(source: .recording, type: .all, config: MediaConfig())
        let mediaVC = MediaViewController(mode: mode)
        mediaVC.modalPresentationStyle = .fullScreen
        mediaVC.delegate = self
        present(mediaVC, animated: true, completion: nil)
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
