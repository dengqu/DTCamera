//
//  LibraryVideoCell.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/26.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

class LibraryVideoCell: UICollectionViewCell {
    
    var representedAssetIdentifier: String!
    
    let overlayView = UIView()
    let photoImageView = UIImageView()
    let durationLabel = UILabel()
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        photoImageView.contentMode = .scaleAspectFill
        photoImageView.clipsToBounds = true
        
        let durationView = UIView()
        durationView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        
        durationLabel.font = UIFont.systemFont(ofSize: 11)
        durationLabel.textColor = UIColor.white
        
        overlayView.backgroundColor = UIColor(white: 1.0, alpha: 0.6)
        overlayView.isHidden = true
        
        contentView.addSubview(photoImageView)
        contentView.addSubview(durationView)
        durationView.addSubview(durationLabel)
        contentView.addSubview(overlayView)
        
        photoImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        durationView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(16)
        }
        durationLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(6)
            make.centerY.equalToSuperview()
        }
        overlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    func toggleMask(isShow: Bool) {
        overlayView.isHidden = !isShow
    }
    
    func setDuration(_ duration: TimeInterval) {
        var seconds = Int64(duration)
        let minutes = seconds / 60
        seconds = seconds % 60
        durationLabel.text = String(format: "%02d:%02d", minutes, seconds)
    }
    
}
