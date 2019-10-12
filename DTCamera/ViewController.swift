//
//  ViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/9/16.
//  Copyright © 2019 Dan Jiang. All rights reserved.
//

import UIKit

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
    }
    
    func media(viewController: MediaViewController, didFinish video: URL) {
        dismiss(animated: true, completion: nil)
    }
    
    func mediaDidDismiss(viewController: MediaViewController) {
        dismiss(animated: true, completion: nil)
    }
    
}
