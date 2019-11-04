//
//  RecordingControl.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/29.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

class RecordingControl: UIView {
    
    private let circleView = CircleView(frame: CGRect(x: 0, y: 0, width: 82, height: 82))
    let controlButton = UIButton()

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        circleView.lineWidth = 6
        circleView.progressStrokeColor = MediaViewController.theme.themeColor
        circleView.emptyStrokeColor = UIColor(white: 1.0, alpha: 0.46)
        
        controlButton.layer.cornerRadius = 22
        controlButton.layer.masksToBounds = true
        let controlButtonTitle = NSAttributedString(string: "完成",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                 .foregroundColor: UIColor.white])
        controlButton.setAttributedTitle(controlButtonTitle, for: .normal)
        
        addSubview(circleView)
        addSubview(controlButton)
        
        circleView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        controlButton.snp.makeConstraints { make in
            make.size.equalTo(44)
            make.center.equalToSuperview()
        }
        
        toggleEnable(isEnable: false)
    }
    
    func toggleEnable(isEnable: Bool) {
        if controlButton.isEnabled != isEnable {
            controlButton.isEnabled = isEnable
            let color = isEnable ? MediaViewController.theme.themeColor : UIColor(hex: "#D9D9D9")!
            let controlButtonTitle = NSAttributedString(string: "完成",
                                                        attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                     .foregroundColor: color])
            controlButton.setAttributedTitle(controlButtonTitle, for: .normal)
            if !isEnable {
                circleView.setProgress(0)
                circleView.setNeedsDisplay()
            }
        }
    }
    
    func setProgress(_ progress: CGFloat) {
        circleView.setProgress(progress, isAnimating: true,
                               duration: Double(RecordingViewController.repeatingInterval) * 0.001)
    }
    
}
