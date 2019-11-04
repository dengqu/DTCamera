//
//  PhotoThumbnailCell.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/6.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

protocol PhotoThumbnailCellDelegate: class {
    func photoThumbnailCellDidDelete(_ cell: PhotoThumbnailCell)
}

class PhotoThumbnailCell: UICollectionViewCell {
    
    weak var delegate: PhotoThumbnailCellDelegate?

    let overlayView = UIView()
    let photoImageView = UIImageView()
    let deleteButton = UIButton()
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        photoImageView.layer.cornerRadius = 2
        photoImageView.contentMode = .scaleAspectFill
        photoImageView.clipsToBounds = true
        
        let deleteButtonTitle = NSAttributedString(string: "x",
                                                   attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                .foregroundColor: MediaViewController.theme.themeColor])
        deleteButton.setAttributedTitle(deleteButtonTitle, for: .normal)
        
        overlayView.layer.cornerRadius = 2
        overlayView.layer.borderWidth = 2
        overlayView.layer.borderColor = UIColor.clear.cgColor
        overlayView.backgroundColor = UIColor.clear

        contentView.addSubview(photoImageView)
        contentView.addSubview(overlayView)
        contentView.addSubview(deleteButton)

        photoImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        deleteButton.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.right.equalToSuperview()
            make.size.equalTo(16)
        }
        overlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        deleteButton.addTarget(self, action: #selector(onDelete), for: .touchUpInside)
    }
    
    @objc private func onDelete() {
        delegate?.photoThumbnailCellDidDelete(self)
    }
}
