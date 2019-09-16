//
//  PlayerViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/7/17.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AVFoundation
import Action

class PlayerViewController: UIViewController {
    
    private let playerView = PlayerView(style: .fullScreen)
    
    var dismissAction: CocoaAction?
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        playerView.exitAction = CocoaAction { [weak self] in
            self?.presentingViewController?.dismiss(animated: true, completion: {
                if let action = self?.dismissAction {
                    action.execute(())
                }
            })
            return .empty()
        }
        
        view.addSubview(playerView)
        playerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    func setPlayer(_ player: AVPlayer) {
        playerView.setPlayer(player)
    }
    
    func play() {
        playerView.play()
    }
    
}
