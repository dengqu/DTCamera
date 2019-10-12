//
//  CameraPreviewView.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/5.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AVFoundation

class CameraPreviewView: UIView {
    
    var session: AVCaptureSession? {
        set {
            videoPreviewLayer?.session = newValue
            videoPreviewLayer?.videoGravity = .resizeAspectFill
        }
        get {
            return videoPreviewLayer?.session
        }
    }
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer? {
        return layer as? AVCaptureVideoPreviewLayer
    }
    
}
