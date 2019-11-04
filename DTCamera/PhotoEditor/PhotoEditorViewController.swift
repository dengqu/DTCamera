//
//  PhotoEditorViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/13.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import DeviceKit

protocol PhotoEditorViewControllerDelegate: class {
    func photoEditor(viewController: PhotoEditorViewController, didEdit photo: UIImage)
    func photoEditor(viewController: PhotoEditorViewController, didRotate photo: UIImage)
}

class PhotoEditorViewController: UIViewController {
    
    override var prefersStatusBarHidden: Bool { return true }

    weak var delegate: PhotoEditorViewControllerDelegate?

    private let scrollView = UIScrollView()
    private var imageView = UIImageView()
    private var fitBounds: CGRect = .zero

    private var resizeView: PhotoEditorResizeView!
    private let maskView = PhotoEditorMaskView()
    private var timer: DispatchSourceTimer?

    private let dismissButton = UIButton()
    private let rotateButton = UIButton()
    private let doneButton = UIButton()
    
    private let originalPhoto: UIImage
    private var photo: UIImage
    private var photoOrientation: UIImage.Orientation = .up
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(photo: UIImage) { // photo should already corrected orientation
        self.photo = photo
        self.originalPhoto = photo
        
        super.init(nibName: nil, bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        setupScrollView()
        setupControls()
        
        centerContents()
    }
    
    private func setupScrollView() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self
        if #available(iOS 11, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        
        let boundsSize = view.bounds.size
        let top: CGFloat = Device.current.isFaceIDCapable ? 22 : 0
        let bottom: CGFloat = Device.current.isFaceIDCapable ? 34 : 0
        let maxFrame = CGRect(x: 0,
                              y: top,
                              width: boundsSize.width,
                              height: boundsSize.height - 52 - bottom)

        resizeView = PhotoEditorResizeView(maxFrame: maxFrame)
        resizeView.delegate = self
        
        scrollView.addSubview(imageView)
        view.addSubview(scrollView)
        view.addSubview(maskView)
        view.addSubview(resizeView)

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        maskView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    private func setupControls() {
        let dismissButtonTitle = NSAttributedString(string: "关闭",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                 .foregroundColor: UIColor.white])
        dismissButton.setAttributedTitle(dismissButtonTitle, for: .normal)
        dismissButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        let rotateButtonTitle = NSAttributedString(string: "旋转90°",
                                                   attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                .foregroundColor: UIColor.white])
        rotateButton.setAttributedTitle(rotateButtonTitle, for: .normal)
        rotateButton.addTarget(self, action: #selector(rotate), for: .touchUpInside)

        let doneButtonTitle = NSAttributedString(string: "完成",
                                                   attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                .foregroundColor: UIColor.white])
        doneButton.setAttributedTitle(doneButtonTitle, for: .normal)
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
        
        view.addSubview(dismissButton)
        view.addSubview(rotateButton)
        view.addSubview(doneButton)

        rotateButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(-12)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top).offset(-12)
            }
        }
        dismissButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalTo(rotateButton)
        }
        doneButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-12)
            make.centerY.equalTo(rotateButton)
        }
    }

    private func centerContents() {
        imageView.image = photo
        imageView.frame = CGRect(x: 0, y: 0, width: photo.size.width, height: photo.size.height)
        scrollView.contentSize = photo.size
        
        caculateZoomScale(cropRect: resizeView.cropRectMaxFrame)

        let maxFrame = resizeView.cropRectMaxFrame
        var contentsFrame = imageView.frame
        
        if contentsFrame.size.width < maxFrame.size.width {
            contentsFrame.origin.x = maxFrame.minX +
                (maxFrame.size.width - contentsFrame.size.width) / 2
        } else {
            contentsFrame.origin.x = maxFrame.minX
        }
        if contentsFrame.size.height < maxFrame.size.height {
            contentsFrame.origin.y = maxFrame.minY +
                (maxFrame.size.height - contentsFrame.size.height) / 2
        } else {
            contentsFrame.origin.y = maxFrame.minY
        }
        
        fitBounds = view.bounds.applying(.init(translationX: contentsFrame.origin.x,
                                               y: contentsFrame.origin.y))
        
        imageView.frame = contentsFrame
        resizeView.updateFrame(wtih: contentsFrame)
        caculateContentInset(cropRect: contentsFrame)
        hideMask()
    }
    
    private func caculateZoomScale(cropRect: CGRect, isFit: Bool = true, isEdit: Bool = true) {
        let scaleWidth = cropRect.size.width / photo.size.width
        let scaleHeight = cropRect.size.height / photo.size.height
        let scale = isFit ? min(scaleWidth, scaleHeight) : max(scaleWidth, scaleHeight)
        
        if scale < 1 {
            scrollView.minimumZoomScale = scale
            scrollView.maximumZoomScale = 1
        } else {
            scrollView.minimumZoomScale = scale
            scrollView.maximumZoomScale = scale * 1.5
        }
        if scrollView.zoomScale != scale && isEdit {
            scrollView.zoomScale = scale
        }
    }
    
    private func caculateContentInset(cropRect: CGRect) {
        scrollView.contentInset = .init(top: cropRect.minY - fitBounds.minY,
                                        left: cropRect.minX - fitBounds.minX,
                                        bottom: fitBounds.maxY - cropRect.maxY,
                                        right: fitBounds.maxX - cropRect.maxX)
    }
    
    private func cancelShowMask() {
        timer?.cancel()
        timer = nil
    }
    
    private func showMaskLater() {
        cancelShowMask()
        if timer == nil {
            let queue = DispatchQueue.global()
            timer = DispatchSource.makeTimerSource(queue: queue)
            timer?.schedule(deadline: .now() + .milliseconds(800))
        }
        timer?.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.maskView.toggleMask(rect: self.resizeView.maskClipRect)
            }            
        })
        timer?.resume()
    }
    
    private func hideMask() {
        cancelShowMask()
        maskView.toggleMask(rect: nil)
    }
    
    @objc private func close() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    @objc private func rotate() {
        if let cgImage = photo.cgImage {
            switch photoOrientation {
            case .up:
                photoOrientation = .right
            case .right:
                photoOrientation = .down
            case .down:
                photoOrientation = .left
            case .left:
                photoOrientation = .up
            default:
                break
            }
            
            photo = UIImage(cgImage: cgImage, scale: 1.0, orientation: photoOrientation)
            
            // some kinds of cache can cause frame is not right, so recreate
            imageView.removeFromSuperview()
            imageView = UIImageView()
            scrollView.addSubview(imageView)
            
            centerContents()
            
            delegate?.photoEditor(viewController: self, didRotate: photo)
        }
    }
    
    @objc private func done() {
        let cropRect = resizeView.convert(resizeView.cropRectInResizeView, to: imageView)
        guard let correctImage = photo.cgImageCorrectedOrientation(),
            let croppedImage = correctImage.cropping(to: cropRect) else {
                return
        }
        let croppedPhoto = UIImage(cgImage: croppedImage)
        delegate?.photoEditor(viewController: self, didEdit: croppedPhoto)
    }
    
}

extension PhotoEditorViewController: UIScrollViewDelegate {
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        hideMask()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            showMaskLater()
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        showMaskLater()
    }
    
}

extension PhotoEditorViewController: PhotoEditorResizeViewDelegate {
    
    func resizeView(_ resizeView: PhotoEditorResizeView, didResize cropRect: CGRect) {
        var isEdit = false
        if cropRect.height > scrollView.contentSize.height ||
            cropRect.width > scrollView.contentSize.width {
            isEdit = true
        }
        caculateZoomScale(cropRect: cropRect, isFit: false, isEdit: isEdit)
        caculateContentInset(cropRect: cropRect)
    }
    
    func resizeViewThumbOn(_ resizeView: PhotoEditorResizeView) {
        hideMask()
    }
    
    func resizeViewThumbOff(_ resizeView: PhotoEditorResizeView) {
        showMaskLater()
    }
    
}
