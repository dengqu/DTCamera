//
//  EffectRender.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/9/27.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import CoreMedia

protocol EffectRender {
    func prepareForInput(with formatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int)
    func copyRenderedPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer
}
