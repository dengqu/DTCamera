//
//  LibraryPhotoCell.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/9.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

class LibraryPhotoCell: UICollectionViewCell {
    
    var representedAssetIdentifier: String!
    
    let overlayView = UIView()
    let photoImageView = UIImageView()
    let checkNumberLabel = UILabel()
    var checkNumber: Int?
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        photoImageView.contentMode = .scaleAspectFill
        photoImageView.clipsToBounds = true
        
        checkNumberLabel.backgroundColor = MediaViewController.theme.themeColor
        checkNumberLabel.layer.cornerRadius = 12
        checkNumberLabel.clipsToBounds = true
        checkNumberLabel.font = UIFont.systemFont(ofSize: 14)
        checkNumberLabel.textColor = UIColor.white
        checkNumberLabel.textAlignment = .center
                
        overlayView.backgroundColor = UIColor(white: 1.0, alpha: 0.6)
        overlayView.isHidden = true

        contentView.addSubview(photoImageView)
        contentView.addSubview(checkNumberLabel)
        contentView.addSubview(overlayView)

        photoImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        checkNumberLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.right.equalToSuperview().offset(-4)
            make.size.equalTo(24)
        }
        overlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        setCheckNumber(checkNumber)
    }
    
    func toggleMask(isShow: Bool) {
        overlayView.isHidden = !isShow
    }
    
    func setCheckNumber(_ number: Int?) {
        if let number = number {
            checkNumberLabel.isHidden = false
            checkNumberLabel.text = "\(number)"
        } else {
            checkNumberLabel.isHidden = true
        }
        checkNumber = number
    }

}
