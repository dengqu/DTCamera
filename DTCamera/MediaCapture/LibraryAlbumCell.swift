//
//  LibraryAlbumCell.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/9.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

class LibraryAlbumCell: UITableViewCell {
    
    var representedAssetIdentifier: String!

    let coverImageView = UIImageView()
    let titleLabel = UILabel()
    let countLabel = UILabel()
    let arrowImageView = UIImageView()
    let line = UIView()

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
                
        contentView.backgroundColor = .white
        
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        
        titleLabel.font = UIFont.systemFont(ofSize: 16)
        titleLabel.textColor = UIColor(hex: "#303032")

        countLabel.font = UIFont.systemFont(ofSize: 12)
        countLabel.textColor = UIColor(hex: "#949A9F")

        arrowImageView.image = #imageLiteral(resourceName: "right_arrow")
        
        line.backgroundColor = UIColor(hex: "#EDEDED")
        
        contentView.addSubview(coverImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(countLabel)
        contentView.addSubview(arrowImageView)
        contentView.addSubview(line)

        coverImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(64)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(23)
            make.left.equalTo(coverImageView.snp.right).offset(12)
        }
        countLabel.snp.makeConstraints { make in
            make.bottom.equalToSuperview().offset(-23)
            make.left.equalTo(coverImageView.snp.right).offset(12)
        }
        arrowImageView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalToSuperview().offset(-20)
        }
        line.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.right.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }
    
}
