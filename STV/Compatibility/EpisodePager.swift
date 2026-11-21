import SwiftUI
import UIKit

/// Reusable vertical pages on iOS 16. UICollectionView keeps only nearby episode views alive.
struct EpisodePager<Content: View>: UIViewControllerRepresentable {
    let count: Int
    let selection: Int
    let enabled: Bool
    let revision: String
    let onSelect: (Int) -> Void
    let onOffset: (CGFloat) -> Void
    let onSettled: (Bool) -> Void
    @ViewBuilder let content: (Int) -> Content

    func makeUIViewController(context: Context) -> Controller { Controller(configuration: self) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.update(self) }

    final class Controller: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        var configuration: EpisodePager
        private let layout = UICollectionViewFlowLayout()
        private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        private var pageSize = CGSize.zero
        private var lastSelection: Int?

        init(configuration: EpisodePager) { self.configuration = configuration; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            layout.minimumLineSpacing = 0; layout.minimumInteritemSpacing = 0
            layout.scrollDirection = .vertical
            collection.backgroundColor = .clear
            collection.isPagingEnabled = true
            collection.showsVerticalScrollIndicator = false
            collection.contentInsetAdjustmentBehavior = .never
            collection.dataSource = self; collection.delegate = self
            collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "episode")
            view.addSubview(collection)
            collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            collection.frame = view.bounds
            collection.isScrollEnabled = configuration.enabled
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard view.bounds.width > 0, view.bounds.height > 0 else { return }
            if pageSize != view.bounds.size {
                pageSize = view.bounds.size
                layout.itemSize = pageSize
                layout.invalidateLayout()
                collection.layoutIfNeeded()
                position(configuration.selection)
            }
        }

        func update(_ new: EpisodePager) {
            let countChanged = configuration.count != new.count
            let contentChanged = countChanged || configuration.revision != new.revision
            configuration = new
            guard isViewLoaded else { return }
            collection.isScrollEnabled = new.enabled
            if countChanged { collection.reloadData() }
            if contentChanged {
                for index in collection.indexPathsForVisibleItems where index.item < new.count {
                    if let cell = collection.cellForItem(at: index) { configure(cell, index.item) }
                }
            }
            if !collection.isDragging && !collection.isDecelerating && lastSelection != new.selection {
                position(new.selection)
            }
        }

        private func position(_ index: Int) {
            guard configuration.count > 0, pageSize.height > 0 else { return }
            let index = min(max(0, index), configuration.count - 1)
            lastSelection = index
            collection.setContentOffset(CGPoint(x: 0, y: CGFloat(index) * pageSize.height), animated: false)
            publishOffset()
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { configuration.count }
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "episode", for: indexPath)
            configure(cell, indexPath.item)
            return cell
        }
        private func configure(_ cell: UICollectionViewCell, _ index: Int) {
            cell.backgroundColor = .clear
            let content = configuration.content
            cell.contentConfiguration = UIHostingConfiguration { content(index) }.margins(.all, 0)
        }
        private func publishOffset() {
            let offset = collection.contentOffset.y
            let notify = configuration.onOffset
            DispatchQueue.main.async { notify(offset) }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) { publishOffset() }
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            configuration.onSettled(false)
        }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { finishScroll() }
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishScroll() }
        private func finishScroll() {
            guard pageSize.height > 0, configuration.count > 0 else { return }
            let index = min(configuration.count - 1, max(0, Int((collection.contentOffset.y / pageSize.height).rounded())))
            lastSelection = index
            if index != configuration.selection { configuration.onSelect(index) }
            configuration.onSettled(true)
        }
    }
}
