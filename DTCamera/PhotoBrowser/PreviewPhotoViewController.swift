//
//  PreviewPhotoViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/20.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

class PreviewPhotoViewController: UIViewController {
    
    var page = 0
    
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let photo: UIImage
    private var fitScale: CGFloat = 1

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(photo: UIImage) {
        self.photo = photo
        
        super.init(nibName: nil, bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        setupScrollView()
        
        imageView.image = photo
        imageView.frame = CGRect(x: 0, y: 0, width: photo.size.width, height: photo.size.height)
        scrollView.contentSize = photo.size
        
        caculateZoomScale()
        centerContents()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        scrollView.zoomScale = fitScale
    }
    
    private func setupScrollView() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self
        if #available(iOS 11, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        
        scrollView.addSubview(imageView)
        view.addSubview(scrollView)
        
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    private func centerContents() {
        let maxFrame = view.bounds
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
        
        imageView.frame = contentsFrame
    }
    
    private func caculateZoomScale() {
        let scaleWidth = view.bounds.size.width / photo.size.width
        let scaleHeight = view.bounds.size.height / photo.size.height
        fitScale = min(scaleWidth, scaleHeight)
        
        if fitScale < 1 {
            scrollView.minimumZoomScale = fitScale
            scrollView.maximumZoomScale = 1
        } else {
            scrollView.minimumZoomScale = fitScale
            scrollView.maximumZoomScale = fitScale * 1.5
        }
        if scrollView.zoomScale != fitScale {
            scrollView.zoomScale = fitScale
        }
    }
    
}

extension PreviewPhotoViewController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContents()
    }
    
}
