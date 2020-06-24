//
//  PhotoLibraryViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/8.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import Photos
import DTMessageBar
import DTMessageHUD

class PhotoLibraryViewController: UIViewController {
    
    private let mode: MediaMode

    private struct Album {
        let collection: PHAssetCollection?
        let assets: PHFetchResult<PHAsset>?
        
        var title: String {
            if let collection = collection {
                return collection.localizedTitle ?? ""
            } else {
                return "所有照片"
            }
        }
    }
    
    private let topView = UIView()
    private let albumsButton = UIButton()
    private let arrowButton = UIButton()
    private let line = UIView()
    private var collectionView: UICollectionView!
    private let tableView = UITableView()
    private let countBar = UIView()
    private let previewButton = UIButton()
    private let doneButton = UIButton()
    private let photoCellIdentifier = "LibraryPhotoCell"
    private let videoCellIdentifier = "LibraryVideoCell"
    private let albumCellIdentifier = "LibraryAlbumCell"

    private var albums: [Album] = []
    private var album: Album?
    private var imageManager: PHImageManager?
    private var thumbnailSize: CGSize!
    private let coverSize: CGSize = .init(width: 64, height: 64)
    
    private var isAnimating = false
    private var selectedAssets: [PHAsset] = []
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(mode: MediaMode) {
        self.mode = mode
        
        super.init(nibName: nil, bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        
        setupTopView()
        setupCollectionView()
        setupTableView()
        setupCountBar()

        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            switch status {
            case .authorized:
                self.imageManager = PHCachingImageManager()
                self.fetchAlbums()
                self.album = self.albums.first
                DispatchQueue.main.async { [weak self] in
                    self?.updateAlbum()
                    self?.tableView.reloadData()
                }
            default:
                DispatchQueue.main.async {
                    DTMessageBar.error(message: "相册未授权", position: .bottom)
                }
            }
        }
    }
    
    private func setupTopView() {
        topView.backgroundColor = UIColor.white
        
        let dismissButton = UIButton()
        dismissButton.setImage(#imageLiteral(resourceName: "close_black"), for: .normal)
        dismissButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        let dummyView = UIView()
        
        albumsButton.addTarget(self, action: #selector(toggleAlbums), for: .touchUpInside)
        
        arrowButton.setImage(#imageLiteral(resourceName: "arrow_down"), for: .normal)
        arrowButton.addTarget(self, action: #selector(toggleAlbums), for: .touchUpInside)

        topView.addSubview(dismissButton)
        dummyView.addSubview(albumsButton)
        dummyView.addSubview(arrowButton)
        topView.addSubview(dummyView)

        dismissButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
        }
        dummyView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        albumsButton.snp.makeConstraints { make in
            make.top.bottom.left.equalToSuperview()
        }
        arrowButton.snp.makeConstraints { make in
            make.left.equalTo(albumsButton.snp.right).offset(2)
            make.centerY.equalTo(albumsButton)
            make.right.equalToSuperview()
        }

        line.backgroundColor = UIColor(hex: "#EDEDED")
        
        view.addSubview(topView)
        view.addSubview(line)

        topView.snp.makeConstraints { make in
            make.height.equalTo(44)
            if #available(iOS 11, *) {
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top)
            } else {
                make.top.equalTo(self.topLayoutGuide.snp.bottom)
            }
            make.left.right.equalToSuperview()
        }
        line.snp.makeConstraints { make in
            make.top.equalTo(topView.snp.bottom)
            make.left.right.equalToSuperview()
            make.height.equalTo(0.5)
        }
    }
    
    private func setupCollectionView() {
        let gap: CGFloat = 6
        let itemWidth = (UIScreen.main.bounds.width - gap * 5) / 4.0
        thumbnailSize = .init(width: itemWidth, height: itemWidth)

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.sectionInset = .init(top: gap, left: gap, bottom: gap, right: gap)
        layout.minimumLineSpacing = gap
        layout.minimumInteritemSpacing = gap
        layout.itemSize = thumbnailSize
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = UIColor.white
        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(LibraryPhotoCell.self, forCellWithReuseIdentifier: photoCellIdentifier)
        collectionView.register(LibraryVideoCell.self, forCellWithReuseIdentifier: videoCellIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self

        view.addSubview(collectionView)
        
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(self.line.snp.bottom)
            make.left.right.equalToSuperview()
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(-44)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top).offset(-44)
            }
        }
    }
    
    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 88
        tableView.separatorStyle = .none
        tableView.register(LibraryAlbumCell.self, forCellReuseIdentifier: albumCellIdentifier)
        tableView.isHidden = true
        
        view.addSubview(tableView)
        
        tableView.snp.makeConstraints { make in
            make.top.equalTo(self.line.snp.bottom)
            make.left.right.equalToSuperview()
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top)
            }
        }
    }
    
    private func updateTableView(offset: CGFloat) {
        tableView.snp.updateConstraints { make in
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom).offset(offset)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top).offset(offset)
            }
        }
    }
    
    private func setupCountBar() {
        countBar.backgroundColor = UIColor.white
        countBar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(done)))
        countBar.isHidden = true
        let previewButtonTitle = NSAttributedString(string: "预览勾选图",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                 .foregroundColor: MediaViewController.theme.themeColor])
        previewButton.setAttributedTitle(previewButtonTitle, for: .normal)
        previewButton.addTarget(self, action: #selector(previewOrEditPhotos), for: .touchUpInside)

        updateDoneButton()
        doneButton.backgroundColor = MediaViewController.theme.themeColor
        doneButton.layer.cornerRadius = 2.0
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
        
        countBar.addSubview(previewButton)
        countBar.addSubview(doneButton)
        view.addSubview(countBar)

        countBar.snp.makeConstraints { make in
            make.height.equalTo(44)
            make.left.right.equalToSuperview()
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top)
            }
        }
        previewButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
        }
        doneButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.width.equalTo(62)
            make.height.equalTo(32)
        }
    }
    
    private func updateAlbum() {
        guard let album = album else { return }
        
        let albumsButtonTitle = NSAttributedString(string: album.title,
                                                   attributes: [.font: UIFont.boldSystemFont(ofSize: 18),
                                                                .foregroundColor: UIColor.black])
        albumsButton.setAttributedTitle(albumsButtonTitle, for: .normal)
        collectionView.reloadData()
    }
    
    private func updateCountBar() {
        toggleBottomBar(isHidden: false)
        updateDoneButton()
    }
    
    private func toggleBottomBar(isHidden: Bool) {
        guard let mediaVC = parent as? MediaViewController else { return }

        if selectedAssets.isEmpty {
            countBar.isHidden = true
            mediaVC.toggleButtons(isHidden: isHidden)
        } else {
            mediaVC.toggleButtons(isHidden: true)
            countBar.isHidden = isHidden
        }
    }
    
    private func updateDoneButton() {
        let doneButtonTitle = NSAttributedString(string: "完成(\(selectedAssets.count))",
            attributes: [.font: UIFont.systemFont(ofSize: 14),
                         .foregroundColor: UIColor.white])
        doneButton.setAttributedTitle(doneButtonTitle, for: .normal)
    }

    private func fetchAlbums() {
        var albums: [Album] = []
        
        var assets = fetchAssets()
        var album = Album(collection: nil, assets: assets)
        albums.append(album)
        
        var collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                                  subtype: .albumRegular,
                                                                  options: nil)
        var index = 0
        while index < collections.count {
            let collection = collections.object(at: index)
            var subtypes: [PHAssetCollectionSubtype] = [.smartAlbumRecentlyAdded]
            if #available(iOS 9.0, *) {
                if mode.type != .video {
                    subtypes.append(.smartAlbumScreenshots)
                }
            }
            if mode.type != .photo {
                subtypes.append(.smartAlbumVideos)
            }
            if subtypes.contains(collection.assetCollectionSubtype) {
                assets = fetchAssets(in: collection)
                album = Album(collection: collection, assets: assets)
                albums.append(album)
            }
            index += 1
        }

        collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        index = 0
        while index < collections.count {
            let collection = collections.object(at: index)
            assets = fetchAssets(in: collection)
            album = Album(collection: collection, assets: assets)
            albums.append(album)
            index += 1
        }
        
        self.albums = albums
    }
    
    private func fetchAssets(in collection: PHAssetCollection? = nil) -> PHFetchResult<PHAsset> {
        if let collection = collection {
            let fetchOptions = PHFetchOptions()
            switch mode.type {
            case .photo:
                fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            case .video:
                fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
            case .all:
                break
            }
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            return PHAsset.fetchAssets(in: collection, options: fetchOptions)
        } else {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            switch mode.type {
            case .photo:
                return PHAsset.fetchAssets(with: .image, options: fetchOptions)
            case .video:
                return PHAsset.fetchAssets(with: .video, options: fetchOptions)
            case .all:
                return PHAsset.fetchAssets(with: fetchOptions)
            }
        }
    }

    private func fetchPhotos(completionBlock: @escaping (_ photos: [UIImage]?) -> Void) {
        guard let imageManager = imageManager else { return }
        let total = selectedAssets.count
        var current = 0
        var success = 0
        var photos = [UIImage](repeating: UIImage(), count: selectedAssets.count)
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        for (index, asset) in selectedAssets.enumerated() {
            imageManager.requestImage(for: asset,
                                      targetSize: PHImageManagerMaximumSize,
                                      contentMode: .aspectFit,
                                      options: requestOptions,
                                      resultHandler: { photo, _ in
                                        DispatchQueue.main.async {
                                            current += 1
                                            if let photo = photo {
                                                success += 1
                                                photos[index] = photo
                                            }
                                            if current == total {
                                                completionBlock(success == total ? photos : nil)
                                            }
                                        }
            })
        }
    }
    
    private func previewVideo(_ video: URL) {
        let previewVideoVC = PreviewVideoViewController(mode: mode, video: video)
        previewVideoVC.delegate = self
        present(previewVideoVC, animated: true, completion: nil)
    }
    
    private func exportVideo(_ video: URL, with session: AVAssetExportSession?) {
        guard let session = session else {
            DispatchQueue.main.async {
                DTMessageHUD.dismiss()
                DTMessageBar.error(message: "获取视频导出会话失败", position: .bottom)
            }
            return
        }
        session.outputURL = video
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async { [weak self] in
                switch session.status {
                case .completed:
                    DTMessageHUD.dismiss()
                    self?.previewVideo(video)
                default:
                    DTMessageHUD.dismiss()
                    DTMessageBar.error(message: "视频文件导出失败", position: .bottom)
                }
            }
        }
    }
    
    @objc private func close() {
        guard let mediaVC = parent as? MediaViewController else { return }
        mediaVC.delegate?.mediaDidDismiss(viewController: mediaVC)
    }
    
    @objc private func toggleAlbums() {
        guard !isAnimating else { return }
        
        isAnimating = true
        
        let showOffset: CGFloat = 0
        let hiddenOffset = -tableView.bounds.height
        var isShow = true
        if tableView.isHidden {
            toggleBottomBar(isHidden: true)
            arrowButton.setImage(#imageLiteral(resourceName: "arrow_up"), for: .normal)
            tableView.isHidden = false
        } else {
            toggleBottomBar(isHidden: false)
            arrowButton.setImage(#imageLiteral(resourceName: "arrow_down"), for: .normal)
            isShow = false
        }
        
        if isShow {
            updateTableView(offset: hiddenOffset)
            view.layoutIfNeeded()
        }
        
        updateTableView(offset: isShow ? showOffset : hiddenOffset)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            self.view.layoutIfNeeded()
        }, completion: { _ in
            if !isShow {
                self.tableView.isHidden = true
                self.updateTableView(offset: showOffset)
                self.view.layoutIfNeeded()
            }
            self.isAnimating = false
        })
    }
    
    @objc private func done() {
        DTMessageHUD.hud()
        fetchPhotos { [weak self] photos in
            if let photos = photos, let mediaVC = self?.parent as? MediaViewController {
                DTMessageHUD.dismiss()
                mediaVC.delegate?.media(viewController: mediaVC, didFinish: photos)
            } else {
                DTMessageHUD.dismiss()
                DTMessageBar.error(message: "获取相册照片失败", position: .bottom)
            }
        }
    }
    
    @objc private func previewOrEditPhotos() {
        DTMessageHUD.hud()
        fetchPhotos { [weak self] photos in
            if let photos = photos, let self = self {
                DTMessageHUD.dismiss()
                let previewPhotosVC = PreviewPhotosViewController(mode: self.mode, photos: photos)
                previewPhotosVC.handler = self
                self.present(previewPhotosVC, animated: true, completion: nil)
            } else {
                DTMessageHUD.dismiss()
                DTMessageBar.error(message: "获取相册照片失败", position: .bottom)
            }
        }
    }

}

extension PhotoLibraryViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let assets = album?.assets else { return 0 }
        return assets.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let assets = album?.assets else { return UICollectionViewCell() }
        let asset = assets.object(at: indexPath.row)
        if asset.mediaType == .image {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: photoCellIdentifier, for: indexPath) as! LibraryPhotoCell
            cell.photoImageView.image = nil
            cell.representedAssetIdentifier = asset.localIdentifier
            if let imageManager = imageManager {
                let requestOptions = PHImageRequestOptions()
                requestOptions.isNetworkAccessAllowed = true
                imageManager.requestImage(for: asset,
                                          targetSize: thumbnailSize,
                                          contentMode: .aspectFill,
                                          options: requestOptions,
                                          resultHandler: { photo, _ in
                                            DispatchQueue.main.async {
                                                if cell.representedAssetIdentifier == asset.localIdentifier {
                                                    cell.photoImageView.image = photo
                                                }
                                            }
                })
            }
            let index = selectedAssets.firstIndex { $0.localIdentifier == asset.localIdentifier }
            if let index = index {
                cell.setCheckNumber(index + 1)
                cell.toggleMask(isShow: false)
            } else {
                cell.setCheckNumber(nil)
                cell.toggleMask(isShow: selectedAssets.count >= mode.config.limitOfPhotos)
            }
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: videoCellIdentifier, for: indexPath) as! LibraryVideoCell
            cell.photoImageView.image = nil
            cell.representedAssetIdentifier = asset.localIdentifier
            if let imageManager = imageManager {
                let requestOptions = PHImageRequestOptions()
                requestOptions.isNetworkAccessAllowed = true
                imageManager.requestImage(for: asset,
                                          targetSize: thumbnailSize,
                                          contentMode: .aspectFill,
                                          options: requestOptions,
                                          resultHandler: { photo, _ in
                                            DispatchQueue.main.async {
                                                if cell.representedAssetIdentifier == asset.localIdentifier {
                                                    cell.photoImageView.image = photo
                                                }
                                            }
                })
            }
            cell.setDuration(asset.duration)
            if asset.duration >= TimeInterval(mode.config.minDuration),
                asset.duration <= TimeInterval(mode.config.maxDuration) {
                cell.toggleMask(isShow: !selectedAssets.isEmpty)
            } else {
                cell.toggleMask(isShow: true)
            }
            return cell
        }
    }
    
    private func toggleVisibleCellsMask(isShowPhotoMask: Bool?, isShowVideoMask: Bool?,
                                        assets: PHFetchResult<PHAsset>) {
        for visibleCell in collectionView.visibleCells {
            if let visibleIndexPath = collectionView.indexPath(for: visibleCell) {
                if let isShowPhotoMask = isShowPhotoMask,
                    let visibleCell = visibleCell as? LibraryPhotoCell {
                    if isShowPhotoMask {
                        let visible = assets.object(at: visibleIndexPath.row)
                        let exists = selectedAssets.contains { $0.localIdentifier == visible.localIdentifier }
                        if !exists {
                            visibleCell.toggleMask(isShow: isShowPhotoMask)
                        }
                    } else {
                        visibleCell.toggleMask(isShow: isShowPhotoMask)
                    }
                }
                if let isShowVideoMask = isShowVideoMask,
                    let visibleCell = visibleCell as? LibraryVideoCell {
                    if isShowVideoMask {
                        visibleCell.toggleMask(isShow: isShowVideoMask)
                    } else {
                        let visible = assets.object(at: visibleIndexPath.row)
                        if visible.duration >= TimeInterval(mode.config.minDuration),
                            visible.duration <= TimeInterval(mode.config.maxDuration) {
                            visibleCell.toggleMask(isShow: isShowVideoMask)
                        }
                    }
                }
            }
        }
    }
    
}

extension PhotoLibraryViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let assets = album?.assets else { return }
        let asset = assets.object(at: indexPath.row)
        if asset.mediaType == .image {
            if let cell = collectionView.cellForItem(at: indexPath) as? LibraryPhotoCell {
                var isShowPhotoMask: Bool?
                var isShowVideoMask: Bool?
                if let number = cell.checkNumber {
                    if selectedAssets.count == mode.config.limitOfPhotos {
                        isShowPhotoMask = false
                    }
                    if mode.type == .all && selectedAssets.count == 1 {
                        isShowVideoMask = false
                    }
                    toggleVisibleCellsMask(isShowPhotoMask: isShowPhotoMask,
                                           isShowVideoMask: isShowVideoMask,
                                           assets: assets)
                    let selectedIndex = number - 1
                    if selectedAssets.count - 1 == selectedIndex {
                        selectedAssets.remove(at: selectedIndex)
                        collectionView.reloadItems(at: [indexPath])
                    } else {
                        var selectedIndexPaths: [IndexPath] = []
                        for visibleIndexPath in collectionView.indexPathsForVisibleItems {
                            let visible = assets.object(at: visibleIndexPath.row)
                            let exists = selectedAssets.contains { $0.localIdentifier == visible.localIdentifier }
                            if exists {
                                selectedIndexPaths.append(visibleIndexPath)
                            }
                        }
                        selectedAssets.remove(at: selectedIndex)
                        collectionView.reloadItems(at: selectedIndexPaths)
                    }
                    updateCountBar()
                } else if selectedAssets.count < mode.config.limitOfPhotos {
                    selectedAssets.append(asset)
                    if selectedAssets.count == mode.config.limitOfPhotos {
                        isShowPhotoMask = true
                    }
                    if mode.type == .all && selectedAssets.count == 1 {
                        isShowVideoMask = true
                    }
                    toggleVisibleCellsMask(isShowPhotoMask: isShowPhotoMask,
                                           isShowVideoMask: isShowVideoMask,
                                           assets: assets)
                    collectionView.reloadItems(at: [indexPath])
                    updateCountBar()
                }                
            }
        } else if selectedAssets.isEmpty,
            asset.duration >= TimeInterval(mode.config.minDuration),
            asset.duration <= TimeInterval(mode.config.maxDuration) {
            DTMessageHUD.hud()
            guard let videoFile = MediaViewController.getMediaFileURL(name: "video", ext: "mp4"),
                let imageManager = imageManager else {
                    DTMessageHUD.dismiss()
                    DTMessageBar.error(message: "创建视频文件失败", position: .bottom)
                    return
            }
            let requestOptions = PHVideoRequestOptions()
            requestOptions.isNetworkAccessAllowed = true
            let presets = AVAssetExportSession.allExportPresets()
            var preset = presets.first ?? ""
            if presets.contains(AVAssetExportPreset1280x720) {
                preset = AVAssetExportPreset1280x720
            } else if presets.contains(AVAssetExportPresetMediumQuality) {
                preset = AVAssetExportPresetMediumQuality
            }
            imageManager.requestExportSession(forVideo: asset, options: requestOptions,
                                              exportPreset: preset) { [weak self] sess, _ in
                                                self?.exportVideo(videoFile, with: sess)
            }
        }
    }
    
}

extension PhotoLibraryViewController: UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return albums.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: albumCellIdentifier, for: indexPath) as! LibraryAlbumCell
        cell.coverImageView.image = nil
        let album = albums[indexPath.row]
        if let asset = album.assets?.firstObject {
            cell.representedAssetIdentifier = asset.localIdentifier
            if let imageManager = imageManager {
                let requestOptions = PHImageRequestOptions()
                requestOptions.isNetworkAccessAllowed = true
                imageManager.requestImage(for: asset,
                                          targetSize: coverSize,
                                          contentMode: .aspectFill,
                                          options: requestOptions,
                                          resultHandler: { photo, _ in
                                            DispatchQueue.main.async {
                                                if cell.representedAssetIdentifier == asset.localIdentifier {
                                                    cell.coverImageView.image = photo
                                                }
                                            }
                })
            }
        }
        cell.titleLabel.text = album.title
        cell.countLabel.text = "\(album.assets?.count ?? 0)"
        return cell
    }
    
}

extension PhotoLibraryViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        album = albums[indexPath.row]
        toggleAlbums()
        updateAlbum()
    }
    
}

extension PhotoLibraryViewController: PreviewPhotosViewControllerHandler {
    
    func previewPhotos(viewController: PreviewPhotosViewController, didFinish photos: [UIImage]) {
        dismiss(animated: false) { [weak self] in
            guard let mediaVC = self?.parent as? MediaViewController else { return }
            mediaVC.delegate?.media(viewController: mediaVC, didFinish: photos)
        }
    }
    
}

extension PhotoLibraryViewController: PreviewVideoViewControllerDelegate {
    
    func previewVideo(viewController: PreviewVideoViewController, didFinish video: URL) {
        dismiss(animated: false) { [weak self] in
            guard let mediaVC = self?.parent as? MediaViewController else { return }
            mediaVC.delegate?.media(viewController: mediaVC, didFinish: video)
        }
    }
    
}
