//
//  PreviewVideoViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/26.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

protocol PreviewVideoViewControllerDelegate: class {
    func previewVideo(viewController: PreviewVideoViewController, didFinish video: URL)
}

class PreviewVideoViewController: UIViewController {
    
    weak var delegate: PreviewVideoViewControllerDelegate?

    override var prefersStatusBarHidden: Bool { return true }

    private let mode: MediaMode
    private let video: URL
    
    private let playerView = PlayerView(style: .simple)
    private let dismissButton = UIButton()
    private let backButton = UIButton()
    private let doneButton = UIButton()
    
    deinit {
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.willEnterForegroundNotification,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.didEnterBackgroundNotification,
                                                  object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(mode: MediaMode, video: URL) {
        self.mode = mode
        self.video = video
        
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupPlayerView()
        setupControls()
        
        playerView.setURL(video)
        playerView.play()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(enterForeground(_:)),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(enterBackground(_:)),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
    }
    
    private func setupPlayerView() {
        view.addSubview(playerView)
        
        playerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    private func setupControls() {
        let topView = UIView()
        topView.backgroundColor = UIColor(white: 0, alpha: 0.2)
        
        dismissButton.setImage(#imageLiteral(resourceName: "back"), for: .normal)
        dismissButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        let backButtonTitle = NSAttributedString(string: "返回重拍",
                                                 attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                              .foregroundColor: UIColor.white])
        backButton.setAttributedTitle(backButtonTitle, for: .normal)
        backButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        backButton.isHidden = mode.source == .library

        let bottomView = UIView()
        bottomView.backgroundColor = UIColor(white: 0, alpha: 0.2)

        let doneButtonTitle = NSAttributedString(string: "完成",
                                                 attributes: [.font: UIFont.systemFont(ofSize: 14),
                                                              .foregroundColor: UIColor.white])
        doneButton.setAttributedTitle(doneButtonTitle, for: .normal)
        doneButton.backgroundColor = MediaViewController.theme.themeColor
        doneButton.layer.cornerRadius = 2.0
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
        
        topView.addSubview(dismissButton)
        topView.addSubview(backButton)
        view.addSubview(topView)
        bottomView.addSubview(doneButton)
        view.addSubview(bottomView)
        
        topView.snp.makeConstraints { make in
            if #available(iOS 11, *) {
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top)
            } else {
                make.top.equalTo(self.topLayoutGuide.snp.bottom)
            }
            make.left.right.equalToSuperview()
            make.height.equalTo(52)
        }
        dismissButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
        }
        backButton.snp.makeConstraints { make in
            make.left.equalTo(dismissButton.snp.right).offset(6)
            make.centerY.equalToSuperview()
        }
        bottomView.snp.makeConstraints { make in
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top)
            }
            make.left.right.equalToSuperview()
            make.height.equalTo(52)
        }
        doneButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.width.equalTo(60)
            make.height.equalTo(32)
        }
    }
    
    @objc func enterForeground(_ notificaton: Notification) {
        playerView.play()
    }
    
    @objc func enterBackground(_ notificaton: Notification) {
        playerView.pause()
    }

    @objc private func close() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }

    @objc private func done() {
        delegate?.previewVideo(viewController: self, didFinish: video)
    }
    
}
