//
//  PreviewPhotosViewController.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/14.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

protocol PreviewPhotosViewControllerHandler: class {
    func previewPhotos(viewController: PreviewPhotosViewController, didFinish photos: [UIImage])
}

class PreviewPhotosViewController: UIPageViewController {
    
    weak var handler: PreviewPhotosViewControllerHandler?

    override var prefersStatusBarHidden: Bool { return true }

    private let mode: MediaMode
    
    private var photos: [UIImage]
    private var currentPage: Int
    private var isRemoving = false
    private var unselectedIndexs: [Int] = []
    private var isAnimating = false
    private var isTransition = false
    private var isModified = false

    private let topView = UIView()
    private let dismissButton = UIButton()
    private let removeButton = UIButton()
    private var collectionView: UICollectionView!
    private let bottomView = UIView()
    private let editButton = UIButton()
    private let doneButton = UIButton()
    private let thumbnailCellIdentifier = "PhotoThumbnailCell"

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(mode: MediaMode, photos: [UIImage], currentPage: Int = 0) {
        self.mode = mode
        self.photos = photos
        self.currentPage = currentPage
        
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
        modalPresentationStyle = .fullScreen
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        dataSource = self
        delegate = self
        
        setupControls()
        setupCollectionView()

        if let photoVC = photoViewController(with: currentPage) {
            setViewControllers([photoVC], direction: .forward, animated: false, completion: nil)
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
        collectionView.backgroundColor = UIColor(white: 0, alpha: 0.4)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(PhotoThumbnailCell.self, forCellWithReuseIdentifier: thumbnailCellIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        
        view.addSubview(collectionView)
        
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.height.equalTo(73)
            make.bottom.equalTo(bottomView.snp.top).offset(-1)
        }
    }

    private func setupControls() {
        topView.backgroundColor = UIColor(white: 0, alpha: 0.4)

        let topDummyView = UIView()
        
        let dismissButtonTitle = NSAttributedString(string: "取消",
                                                    attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                                 .foregroundColor: UIColor.white])
        dismissButton.setAttributedTitle(dismissButtonTitle, for: .normal)
        dismissButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        
        if mode.source == .capture {
            removeButton.setImage(#imageLiteral(resourceName: "trash"), for: .normal)
        } else {
            updateRemoveButton()
        }
        removeButton.addTarget(self, action: #selector(remove), for: .touchUpInside)
        
        bottomView.backgroundColor = UIColor(white: 0, alpha: 0.4)

        let bottomDummyView = UIView()

        let editButtonTitle = NSAttributedString(string: "编辑",
                                                 attributes: [.font: UIFont.systemFont(ofSize: 16),
                                                              .foregroundColor: UIColor.white])
        editButton.setAttributedTitle(editButtonTitle, for: .normal)
        editButton.addTarget(self, action: #selector(modify), for: .touchUpInside)

        updateDoneButton()
        doneButton.layer.cornerRadius = 2.0
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)

        topView.addSubview(topDummyView)
        topDummyView.addSubview(dismissButton)
        topDummyView.addSubview(removeButton)
        view.addSubview(topView)
        bottomView.addSubview(bottomDummyView)
        bottomDummyView.addSubview(editButton)
        bottomDummyView.addSubview(doneButton)
        view.addSubview(bottomView)
        
        topView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
        }
        topDummyView.snp.makeConstraints { make in
            if #available(iOS 11, *) {
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top)
            } else {
                make.top.equalTo(self.topLayoutGuide.snp.bottom)
            }
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(52)
        }
        dismissButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
        }
        removeButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            if mode.source == .library {
                make.size.equalTo(24)
            }
        }
        bottomView.snp.makeConstraints { make in
            make.bottom.left.right.equalToSuperview()
        }
        bottomDummyView.snp.makeConstraints { make in
            if #available(iOS 11, *) {
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom)
            } else {
                make.bottom.equalTo(self.bottomLayoutGuide.snp.top)
            }
            make.top.left.right.equalToSuperview()
            make.height.equalTo(52)
        }
        editButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
        }
        doneButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.width.equalTo(60)
            make.height.equalTo(32)
        }
    }
    
    private func photoViewController(with page: Int) -> UIViewController? {
        if page >= 0 && page < photos.count {
            let photo = photos[page]
            let photoVC = PreviewPhotoViewController(photo: photo)
            photoVC.page = page
            photoVC.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap)))
            return photoVC
        } else {
            return nil
        }
    }
    
    private func setCurrentPage(_ newValue: Int) {
        currentPage = newValue
        collectionView.reloadData()
        collectionView.scrollToItem(at: IndexPath(item: newValue, section: 0),
                                    at: .centeredHorizontally, animated: true)
        if mode.source == .library {
            updateRemoveButton()
        }
    }
    
    private func updateRemoveButton() {
        if unselectedIndexs.contains(currentPage) {
            removeButton.setAttributedTitle(nil, for: .normal)
            removeButton.backgroundColor = UIColor.clear
            removeButton.layer.cornerRadius = 0
            
            removeButton.setImage(#imageLiteral(resourceName: "check_off"), for: .normal)
        } else {
            removeButton.setImage(nil, for: .normal)
            removeButton.backgroundColor = MediaViewController.theme.themeColor
            removeButton.layer.cornerRadius = 12
            
            var selectedIndex = 0
            for index in 0..<photos.count {
                if index == currentPage {
                    break
                }
                if !unselectedIndexs.contains(index) {
                    selectedIndex += 1
                }
            }
            let removeButtonTitle = NSAttributedString(string: "\(selectedIndex + 1)",
                attributes: [.font: UIFont.systemFont(ofSize: 14),
                             .foregroundColor: UIColor.white])
            removeButton.setAttributedTitle(removeButtonTitle, for: .normal)
        }
    }
    
    private func updateDoneButton() {
        var total = photos.count
        if mode.source == .library {
            total -= unselectedIndexs.count
        }
        let doneButtonTitle = NSAttributedString(string: "完成(\(total))",
            attributes: [.font: UIFont.systemFont(ofSize: 14),
                         .foregroundColor: UIColor.white])
        doneButton.setAttributedTitle(doneButtonTitle, for: .normal)
        doneButton.backgroundColor = total == 0 ? UIColor(hex: "#D8DCE0") : MediaViewController.theme.themeColor
    }
    
    @objc private func close() {
        if isModified {
            let alert = UIAlertController(title: "注意", message: "返回会丢失当前编辑的内容，是否要返回", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "确认", style: .default, handler: { [weak self] _ in
                self?.presentingViewController?.dismiss(animated: true, completion: nil)
            }))
            self.present(alert, animated: true, completion: nil)
        } else {
            presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc private func remove() {
        guard !isRemoving && !isTransition else { return }
        isRemoving = true
        if mode.source == .capture {
            if photos.count > 1 {
                photos.remove(at: currentPage)
                var newCurrentPage = currentPage
                let oldIndexPath = IndexPath(item: currentPage, section: 0)
                var newIndexPath = IndexPath(item: currentPage + 1, section: 0)
                if currentPage > 0 {
                    newCurrentPage = currentPage - 1
                    newIndexPath = IndexPath(item: currentPage - 1, section: 0)
                }
                if let photoVC = photoViewController(with: newCurrentPage) {
                    currentPage = newCurrentPage
                    setViewControllers([photoVC], direction: .forward, animated: false, completion: nil)
                    collectionView.performBatchUpdates({ [weak self] in
                        self?.collectionView.reloadItems(at: [newIndexPath])
                        self?.collectionView.deleteItems(at: [oldIndexPath])
                    }, completion: { [weak self] _ in
                        self?.isRemoving = false
                    })
                }
            } else {
                close()
            }
        } else {
            let index = unselectedIndexs.firstIndex { $0 == currentPage }
            if let index = index {
                unselectedIndexs.remove(at: index)
            } else {
                unselectedIndexs.append(currentPage)
            }
            updateRemoveButton()
            collectionView.performBatchUpdates({ [weak self] in
                self?.collectionView.reloadItems(at: [IndexPath(item: currentPage, section: 0)])
            }, completion: { [weak self] _ in
                self?.isRemoving = false
            })
        }
        updateDoneButton()
    }

    @objc private func modify() {
        guard !isRemoving && !isTransition else { return }
        let photo = photos[currentPage]
        let editorVC = PhotoEditorViewController(photo: photo)
        editorVC.delegate = self
        present(editorVC, animated: true, completion: nil)
    }
    
    @objc private func done() {
        guard !isRemoving && !isTransition else { return }
        if mode.source == .capture {
            handler?.previewPhotos(viewController: self, didFinish: photos)
        } else if unselectedIndexs.count != photos.count {
            var selectedPhotos: [UIImage] = []
            for (index, photo) in photos.enumerated() {
                if !unselectedIndexs.contains(index) {
                    selectedPhotos.append(photo)
                }
            }
            handler?.previewPhotos(viewController: self, didFinish: selectedPhotos)
        }
    }
    
    @objc private func onTap() {
        guard !isAnimating else { return }
        isAnimating = true
        let isShow = topView.isHidden
        if isShow {
            topView.transform = .init(translationX: 0, y: -topView.frame.maxY)
            collectionView.transform = .init(translationX: 0,
                                             y: view.bounds.height - collectionView.frame.minX)
            bottomView.transform = .init(translationX: 0,
                                         y: view.bounds.height - bottomView.frame.minX)
            topView.isHidden = false
            collectionView.isHidden = false
            bottomView.isHidden = false
        }
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: {
            if isShow {
                self.topView.transform = .identity
                self.collectionView.transform = .identity
                self.bottomView.transform = .identity
            } else {
                self.topView.transform = .init(translationX: 0, y: -self.topView.frame.maxY)
                self.collectionView.transform = .init(translationX: 0,
                                                      y: self.view.bounds.height - self.collectionView.frame.minX)
                self.bottomView.transform = .init(translationX: 0,
                                                  y: self.view.bounds.height - self.bottomView.frame.minX)
            }
        }, completion: { _ in
            if !isShow {
                self.topView.isHidden = true
                self.collectionView.isHidden = true
                self.bottomView.isHidden = true
                self.topView.transform = .identity
                self.collectionView.transform = .identity
                self.bottomView.transform = .identity
            }
            self.isAnimating = false
        })
    }
    
}

extension PreviewPhotosViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photos.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: thumbnailCellIdentifier, for: indexPath) as! PhotoThumbnailCell
        cell.deleteButton.isHidden = true
        cell.photoImageView.image = photos[indexPath.row]
        cell.overlayView.layer.borderColor = UIColor.clear.cgColor
        cell.overlayView.backgroundColor = UIColor.clear
        if indexPath.row == currentPage {
            cell.overlayView.layer.borderColor = MediaViewController.theme.previewThumbnailSelectedColor.cgColor
            cell.overlayView.backgroundColor = UIColor(white: 0, alpha: 0.2)
        }
        if mode.source == .library && unselectedIndexs.contains(indexPath.row) {
            cell.overlayView.backgroundColor = UIColor(white: 1, alpha: 0.6)
        }
        return cell
    }
    
}

extension PreviewPhotosViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isRemoving && !isTransition else { return }
        let newCurrentPage = indexPath.row
        if currentPage != newCurrentPage {
            if let photoVC = photoViewController(with: newCurrentPage) {
                setViewControllers([photoVC], direction: .forward, animated: false, completion: nil)
                setCurrentPage(newCurrentPage)
            }
        }
    }
    
}

extension PreviewPhotosViewController: UIPageViewControllerDataSource {
    
    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        if let photoVC = viewController as? PreviewPhotoViewController {
            return photoViewController(with: photoVC.page + 1)
        } else {
            return nil
        }
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        if let photoVC = viewController as? PreviewPhotoViewController {
            return photoViewController(with: photoVC.page - 1)
        } else {
            return nil
        }
    }
    
}

extension PreviewPhotosViewController: UIPageViewControllerDelegate {
    
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        isTransition = true
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        isTransition = false
        if completed {
            if let photoVC = viewControllers?.last as? PreviewPhotoViewController {
                setCurrentPage(photoVC.page)
            }
        }
    }
    
}

extension PreviewPhotosViewController: PhotoEditorViewControllerDelegate {
    
    func photoEditor(viewController: PhotoEditorViewController, didEdit photo: UIImage) {
        isModified = true
        photos[currentPage] = photo
        if let photoVC = photoViewController(with: currentPage) {
            setViewControllers([photoVC], direction: .forward, animated: false, completion: nil)
        }
        collectionView.reloadItems(at: [IndexPath(item: currentPage, section: 0)])
        dismiss(animated: true, completion: nil)
    }
    
    func photoEditor(viewController: PhotoEditorViewController, didRotate photo: UIImage) {}
    
}
