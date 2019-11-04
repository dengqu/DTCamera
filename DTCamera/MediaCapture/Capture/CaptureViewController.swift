//
//  CaptureViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/5.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import AVFoundation
import DTMessageBar

class CaptureViewController: UIViewController {
        
    private let mode: MediaMode

    private var isFirstTimeDidMoveToParent = true
    
    private let previewView = CaptureVideoPreviewView()
    
    private let dismissButton = UIButton()
    private let flashButton = UIButton()
    private let positionButton = UIButton()
    private let ratioButton = UIButton()
    
    private var collectionView: UICollectionView!
    private let thumbnailCellIdentifier = "PhotoThumbnailCell"
    private var photos: [UIImage] = []

    private let shutterButton = UIButton()
    private let previewButton = UIButton()
    private let doneButton = UIButton()
    
    private var pipeline: CapturePipeline!

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
    
    init(mode: MediaMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        pipeline = CapturePipeline(mode: mode)
        pipeline.delegate = self

        setupPreview()
        setupCollectionView()
        setupControls()
        toggleControls(isHidden: true)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(enterForeground(_:)),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(enterBackground(_:)),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        
        pipeline.configure()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        pipeline.startSessionRunning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        pipeline.stopSessionRunning()
    }
    
    override func didMove(toParent parent: UIViewController?) {
        if !isFirstTimeDidMoveToParent {
            if parent != nil {
                pipeline.reconfigure()
                pipeline.startSessionRunning()
            } else {
                pipeline.stopSessionRunning()
            }
        } else {
            isFirstTimeDidMoveToParent = false
        }
    }
    
    private func setupPreview() {
        previewView.session = pipeline.session
        view.addSubview(previewView)
        updatePreview()
    }
    
    private func updatePreview() {
        previewView.snp.remakeConstraints { make in
            make.left.right.equalToSuperview()
            let offset: CGFloat = pipeline.ratioMode == .r1to1 ? 58 : 0
            if #available(iOS 11, *) {
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top).offset(offset)
            } else {
                make.top.equalTo(self.topLayoutGuide.snp.bottom).offset(offset)
            }
            make.height.equalTo(previewView.snp.width).multipliedBy(pipeline.ratioMode.ratio)
        }
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.sectionInset = .init(top: 0, left: 9, bottom: 0, right: 9)
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 0
        layout.itemSize = .init(width: 55, height: 55)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = UIColor(white: 0, alpha: 0.2)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(PhotoThumbnailCell.self, forCellWithReuseIdentifier: thumbnailCellIdentifier)
        collectionView.dataSource = self

        view.addSubview(collectionView)
        
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.height.equalTo(73)
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(-167)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top).offset(-167)
            }
        }
    }

    private func setupControls() {
        let dismissButtonTitle = NSAttributedString(string: "关闭",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                 .foregroundColor: UIColor.white])
        dismissButton.setAttributedTitle(dismissButtonTitle, for: .normal)
        dismissButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)

        let positionButtonTitle = NSAttributedString(string: pipeline.positionMode.title,
                                                  attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                               .foregroundColor: UIColor.white])
        positionButton.setAttributedTitle(positionButtonTitle, for: .normal)
        positionButton.addTarget(self, action: #selector(togglePosition), for: .touchUpInside)

        let ratioButtonTitle = NSAttributedString(string: pipeline.ratioMode.title,
                                                  attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                               .foregroundColor: UIColor.white])
        ratioButton.setAttributedTitle(ratioButtonTitle, for: .normal)
        ratioButton.addTarget(self, action: #selector(toggleRatio), for: .touchUpInside)

        let shutterButtonTitle = NSAttributedString(string: "拍照",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 64),
                                                                 .foregroundColor: UIColor.white])
        shutterButton.setAttributedTitle(shutterButtonTitle, for: .normal)
        shutterButton.addTarget(self, action: #selector(capture), for: .touchUpInside)
        
        let previewButtonTitle = NSAttributedString(string: "预览",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                 .foregroundColor: UIColor.white])
        previewButton.setAttributedTitle(previewButtonTitle, for: .normal)
        previewButton.addTarget(self, action: #selector(previewOrEditPhotos), for: .touchUpInside)

        doneButton.backgroundColor = MediaViewController.theme.themeColor
        doneButton.layer.cornerRadius = 2.0
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
        
        updateCountLabel()
        
        view.addSubview(dismissButton)
        view.addSubview(flashButton)
        view.addSubview(positionButton)
        view.addSubview(ratioButton)
        view.addSubview(previewButton)
        view.addSubview(shutterButton)
        view.addSubview(doneButton)

        dismissButton.snp.makeConstraints { make in
            if #available(iOS 11, *) {
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top).offset(12)
            } else {
                make.top.equalTo(self.topLayoutGuide.snp.bottom).offset(12)
            }
            make.left.equalToSuperview().offset(12)
        }
        flashButton.snp.makeConstraints { make in
            make.centerY.equalTo(dismissButton)
            make.right.equalTo(positionButton.snp.left).offset(-24)
        }
        positionButton.snp.makeConstraints { make in
            make.centerY.equalTo(dismissButton)
            make.right.equalTo(ratioButton.snp.left).offset(-24)
        }
        ratioButton.snp.makeConstraints { make in
            make.centerY.equalTo(dismissButton)
            make.right.equalToSuperview().offset(-12)
        }
        shutterButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(-53)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top).offset(-53)
            }
        }
        previewButton.snp.makeConstraints { make in
            make.centerY.equalTo(shutterButton)
            make.left.equalToSuperview().offset(28)
        }
        doneButton.snp.makeConstraints { make in
            make.centerY.equalTo(shutterButton)
            make.right.equalToSuperview().offset(-28)
            make.width.equalTo(60)
            make.height.equalTo(32)
        }
    }

    private func toggleControls(isHidden: Bool) {
        collectionView.isHidden = isHidden
        flashButton.isHidden = isHidden
        ratioButton.isHidden = isHidden
        positionButton.isHidden = isHidden
        shutterButton.isHidden = isHidden
    }
        
    private func updateCountLabel() {
        guard let mediaVC = parent as? MediaViewController else { return }

        mediaVC.toggleButtons(isHidden: !photos.isEmpty)

        previewButton.isHidden = photos.isEmpty
        doneButton.isHidden = photos.isEmpty
        let doneButtonTitle = NSAttributedString(string: "完成(\(photos.count))",
            attributes: [.font: UIFont.systemFont(ofSize: 14),
                         .foregroundColor: UIColor.white])
        doneButton.setAttributedTitle(doneButtonTitle, for: .normal)
    }
        
    @objc private func enterForeground(_ notificaton: Notification) {
        if isViewLoaded && view.window != nil {
            pipeline.startSessionRunning()
        }
    }
    
    @objc private func enterBackground(_ notificaton: Notification) {
        if isViewLoaded && view.window != nil {
            pipeline.stopSessionRunning()
        }
    }

    @objc private func close() {
        guard let mediaVC = parent as? MediaViewController else { return }
        mediaVC.delegate?.mediaDidDismiss(viewController: mediaVC)
    }
    
    @objc private func toggleFlash() {
        pipeline.toggleFlash()
    }

    @objc private func toggleRatio() {
        switch pipeline.ratioMode {
        case .r1to1:
            pipeline.ratioMode = .r3to4
        case .r3to4:
            pipeline.ratioMode = .r9to16
        case .r9to16:
            pipeline.ratioMode = .r1to1
        }

        let ratioButtonTitle = NSAttributedString(string: pipeline.ratioMode.title,
                                                  attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                               .foregroundColor: UIColor.white])
        ratioButton.setAttributedTitle(ratioButtonTitle, for: .normal)
        updatePreview()
    }
    
    @objc private func togglePosition() {
        pipeline.stopSessionRunning()
        
        switch pipeline.positionMode {
        case .front:
            pipeline.positionMode = .back
        case .back:
            pipeline.positionMode = .front
        }

        let positionButtonTitle = NSAttributedString(string: pipeline.positionMode.title,
                                                  attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                               .foregroundColor: UIColor.white])
        positionButton.setAttributedTitle(positionButtonTitle, for: .normal)
        pipeline.reconfigure()
        
        pipeline.startSessionRunning()
    }
        
    @objc private func capture() {
        guard photos.count < mode.config.limitOfPhotos else {
            DTMessageBar.info(message: "单次最多允许拍照\(mode.config.limitOfPhotos)张", position: .bottom)
            return
        }
        pipeline.capture()
    }

    @objc private func previewOrEditPhotos() {
        let previewPhotosVC = PreviewPhotosViewController(mode: mode, photos: photos)
        previewPhotosVC.handler = self
        previewPhotosVC.modalPresentationStyle = .fullScreen
        present(previewPhotosVC, animated: true, completion: nil)
    }
    
    @objc private func done() {
        guard let mediaVC = parent as? MediaViewController else { return }
        mediaVC.delegate?.media(viewController: mediaVC, didFinish: photos)
    }

}

extension CaptureViewController: CapturePipelineDelegate {
    
    func capturePipelineConfigSuccess(_ pipeline: CapturePipeline) {
        DispatchQueue.main.async { [weak self] in
            self?.toggleControls(isHidden: false)
        }
    }
    
    func capturePipelineNotAuthorized(_ pipeline: CapturePipeline) {
        DispatchQueue.main.async {
            DTMessageBar.error(message: "相机未授权", position: .bottom)
        }
    }
    
    func capturePipelineConfigFailed(_ pipeline: CapturePipeline) {
        DispatchQueue.main.async {
            DTMessageBar.error(message: "相机没法用", position: .bottom)
        }
    }
    
    func capturePipeline(_ pipeline: CapturePipeline, capture photo: UIImage) {
        photos.append(photo)
        let photosCount = photos.count
        DispatchQueue.main.async { [weak self] in
            self?.updateCountLabel()
            self?.collectionView.reloadData()
            self?.collectionView.scrollToItem(at: IndexPath(item: photosCount - 1, section: 0),
                                              at: .centeredHorizontally, animated: true)
            self?.pipeline.isCapturing = false
        }
    }
    
    func capturePipeline(_ pipeline: CapturePipeline, flashMode: AVCaptureDevice.FlashMode) {
        var title = "有闪光"
        if flashMode == .off {
            title = "无闪光"
        }
        let flashButtonTitle = NSAttributedString(string: title,
                                                  attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                               .foregroundColor: UIColor.white])
        DispatchQueue.main.async { [weak self] in
            self?.flashButton.setAttributedTitle(flashButtonTitle, for: .normal)
        }
    }
    
}

extension CaptureViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photos.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: thumbnailCellIdentifier, for: indexPath) as! PhotoThumbnailCell
        cell.delegate = self
        cell.photoImageView.image = photos[indexPath.row]
        return cell
    }
    
}

extension CaptureViewController: PhotoThumbnailCellDelegate {
    
    func photoThumbnailCellDidDelete(_ cell: PhotoThumbnailCell) {
        guard !pipeline.isCapturing,
            let indexPath = collectionView.indexPath(for: cell) else { return }
        pipeline.isCapturing = true
        photos.remove(at: indexPath.row)
        updateCountLabel()
        collectionView.deleteItems(at: [indexPath])
        pipeline.isCapturing = false
    }
    
}

extension CaptureViewController: PreviewPhotosViewControllerHandler {
    
    func previewPhotos(viewController: PreviewPhotosViewController, didFinish photos: [UIImage]) {
        dismiss(animated: false) { [weak self] in
            guard let mediaVC = self?.parent as? MediaViewController else { return }
            mediaVC.delegate?.media(viewController: mediaVC, didFinish: photos)
        }
    }
    
}
