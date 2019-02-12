//
//  ProductDetailDirector.swift
//  Marketplace
//
//  Created by Igor Vedeneev on 13.08.17.
//  Copyright © 2017 WeAreLT. All rights reserved.
//

import Foundation
import UIKit
import DeepDiff

/*
 1  потестить обновления
 2  потестить с реалмом и кор датой
 3. удаление/добавления хедеры/футеры
 6. logging
 8. определение уникальности ячейки/секции
 */

//MARK:- CollectionDirector
open class CollectionDirector: NSObject {
    public var sections = [AbstractCollectionSection]()
    ///Register cell classes & xibs automatically
    open var shouldUseAutomaticViewRegistration: Bool = false
    ///Adjust z position for headers/footers to prevent scroll indicator hiding at iOS11
    open var shouldAdjustSupplementaryViewLayerZPosition: Bool = true
    ///Forward scrollView delegae messages to specific object
    open weak var scrollDelegate: UIScrollViewDelegate?
    
    private weak var collectionView: UICollectionView!
    private lazy var updater = CollectionUpdater(collectionView: collectionView)
    private lazy var viewsRegisterer = CollectionReusableViewsRegisterer(collectionView: collectionView)
    private var sectionIds: [String] = []
    
    public init(colletionView: UICollectionView,
                sections: [AbstractCollectionSection] = [],
                shouldUseAutomaticViewRegistration: Bool = true,
                shouldAdjustSupplementaryViewLayerZPosition: Bool = true)
    {
        
        self.collectionView = colletionView
        super.init()
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.shouldUseAutomaticViewRegistration = shouldUseAutomaticViewRegistration
        self.shouldAdjustSupplementaryViewLayerZPosition = shouldAdjustSupplementaryViewLayerZPosition
    }
    
    public func remove(section: AbstractCollectionSection) {
        guard let index = sections.index(where: { $0.identifier == section.identifier }) else {
            log("attempt to remove section not @ director", logLevel: .warning)
            return
        }
        
        sections.remove(at: index)
    }
    
    public func removeSection(at index: Int) {
        sections.remove(at: index)
    }
    
    //todo: add/remove array of sections
    
    public func reload() {
        collectionView.reloadData()
        updateSectionIds()
        sections.forEach { $0.resetLastUpdatesIds() }
    }
    
    public func contains(section: AbstractCollectionSection) -> Bool {
        return sections.contains(where: { $0.identifier == section.identifier })
    }
    
//    public func append(sections: [AbstractCollectionSection]) {
//        
//    }
//    
//    public func remove(sections: [AbstractCollectionSection]) {
//        
//    }

    public func setNeedsUpdate() {
        collectionView.performBatchUpdates({}, completion: nil)
    }
    
    private func updateSectionIds() {
        sectionIds = sections.map { $0.identifier }
    }
    
    public func testUpdate(completion: (() -> Void)? = nil) {
        //todo: section updates
        let newIds = sections.map { $0.identifier }
        let oldIds = sectionIds
        let sectionDiff = diff(old: oldIds, new: newIds)
        
        /////////
        var deletes: [(Delete<String>, IndexPath)] = []
        var inserts: [(Insert<String>, IndexPath)] = []
        var reloads: [(Replace<String>, IndexPath)] = []
        var moves: [(IndexPath, IndexPath)] = []
        
        sections.enumerated().forEach { (idx, section) in
            let diff_ = diff(old: section.idsBeforeUpdate, new: section.currentItemIds())
            let d = diff_.compactMap { $0.delete }.map { ($0, IndexPath(row: $0.index, section: idx)) }
            let i = diff_.compactMap { $0.insert }.map { ($0, IndexPath(row: $0.index, section: idx)) }
            let r = diff_.compactMap { $0.replace }.map { ($0, IndexPath(row: $0.index, section: idx)) }
            let m = diff_.compactMap { $0.move }.map { (IndexPath(row: $0.fromIndex, section: idx), IndexPath(row: $0.toIndex, section: idx)) }
            
            deletes.append(contentsOf: d)
            inserts.append(contentsOf: i)
            reloads.append(contentsOf: r)
            moves.append(contentsOf: m)
        }
        
        deletes.forEach { del in
            guard let idx = deletes.firstIndex(where: { $0.0.item == del.0.item }),
            let ins = inserts.firstIndex(where: { $0.0.item == del.0.item }) else { return }
            
            let toIp = inserts[ins].1
            let fromIp = del.1
            deletes.remove(at: idx)
            inserts.remove(at: ins)
            moves.append((fromIp, toIp))
        }
        
        let hasSectionChanges = sectionDiff.isEmpty
        
        collectionView.performBatchUpdates({ [unowned self] in
            print("performBatchUpdates")
            deletes.map { $0.0 }.executeIfPresent { _ in
//                print(self.collectionView.numberOfSections, self.collectionView.numberOfItems(inSection: 1))
                self.collectionView.deleteItems(at: deletes.map { $1 })
            }
            
            inserts.map { $0.0 }.executeIfPresent { _ in
                self.collectionView.insertItems(at: inserts.map { $1 })
            }
            
            moves.executeIfPresent {
                $0.forEach { move in
                    let from = move.0
                    let to = move.1
                    self.collectionView.moveItem(at: from, to: to)
                }
            }
            
            let v = self.collectionView.dataSource!.numberOfSections!(in: self.collectionView)
            let sectionDeletes = sectionDiff.compactMap { $0.delete?.index }
            sectionDeletes.executeIfPresent({ (deletes) in
                self.collectionView.deleteSections(IndexSet(deletes))
            })
            
            let sectionInserts = sectionDiff.compactMap { $0.insert?.index }
            sectionInserts.executeIfPresent({ (inserts) in
                self.collectionView.insertSections(IndexSet(inserts))
            })
            
            let sectionReloads = sectionDiff.compactMap { $0.replace?.index }
            sectionReloads.executeIfPresent({ (reloads) in
                self.collectionView.reloadSections(IndexSet(reloads))
            })
            
        }) { [unowned self] _ in
            self.updateSectionIds()
            self.sections.forEach { $0.resetLastUpdatesIds() }
            completion?()
        }
        
        reloads.executeIfPresent { [unowned self] _ in
            self.collectionView.reloadItems(at: reloads.map { $1 })
        }
    }
    
    open override func responds(to selector: Selector) -> Bool {
        return super.responds(to: selector) || scrollDelegate?.responds(to: selector) == true
    }
    
    open override func forwardingTarget(for selector: Selector) -> Any? {
        return scrollDelegate?.responds(to: selector) == true ? scrollDelegate : super.forwardingTarget(for: selector)
    }
}

//MARK:- Public
extension CollectionDirector {
    public func removeAll(clearSections: Bool = false) {
        if clearSections {
            sections.forEach { $0.removeAll() }
        }
        
        sections.removeAll()
    }
}

//MARK:- UICollectionViewDataSource
extension CollectionDirector: UICollectionViewDataSource {
    open func numberOfSections(in collectionView: UICollectionView) -> Int {
        print("numberOfSections(in")
        return sections.count
    }
    
    open func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        print("numberOfItemsInSection")
        return sections[section].numberOfItems()
    }
    
    open func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let item = sections[indexPath.section].item(for: indexPath.row)
        if shouldUseAutomaticViewRegistration {
            viewsRegisterer.registerCellIfNeeded(reuseIdentifier: item.reuseIdentifier, cellClass: item.cellType)
        }
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: item.reuseIdentifier, for: indexPath)
        item.configure(cell)
        return cell
    }
    
    open func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let section = sections[indexPath.section]

        switch kind {
        case UICollectionElementKindSectionHeader:
            guard let header = section.headerItem else { return UICollectionReusableView() }
            if shouldUseAutomaticViewRegistration {
                viewsRegisterer.registerHeaderFooterViewIfNeeded(reuseIdentifier: header.reuseIdentifier, viewClass: header.viewType, kind: kind)
            }
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: header.reuseIdentifier, for: indexPath)
            header.configure(headerView)
            return headerView
        case UICollectionElementKindSectionFooter:
            guard let footer = section.footerItem else { return UICollectionReusableView() }
            if shouldUseAutomaticViewRegistration {
                viewsRegisterer.registerHeaderFooterViewIfNeeded(reuseIdentifier: footer.reuseIdentifier, viewClass: footer.viewType, kind: kind)
            }
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: footer.reuseIdentifier, for: indexPath)
            footer.configure(footerView)
            return footerView
            
        default:
            return UICollectionReusableView()
        }
    }
}

//MARK:- UICollectionViewDataSource
extension CollectionDirector : UICollectionViewDelegateFlowLayout {
    open func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = sections[indexPath.section].item(for: indexPath.row)
        item.onSelect?(indexPath)
    }
    
    open func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        let item = sections[indexPath.section].item(for: indexPath.row)
        item.onDeselect?(indexPath)
    }
    
    open func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        let item = sections[indexPath.section].item(for: indexPath.row)
        item.onDisplay?(indexPath, cell)
    }
    
    open func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard sections.count > indexPath.section,
            sections[indexPath.section].numberOfItems() > indexPath.row else { return }
        let item = sections[indexPath.section].item(for: indexPath.row)
        item.onEndDisplay?(indexPath, cell)
    }
    
    open func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        let item = sections[indexPath.section].item(for: indexPath.row)
        //TODO: consider false as default value or set default value in colection item
        return item.shouldHighlight ?? true
    }
    
    open func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        let item = sections[indexPath.section].item(for: indexPath.row)
        item.onHighlight?(indexPath)
    }
    
    open func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        let item = sections[indexPath.section].item(for: indexPath.row)
        item.onUnighlight?(indexPath)
    }
    
    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let section = sections[indexPath.section]
        let item = section.item(for: indexPath.row)
        var size = item.estimatedSize(boundingSize: collectionView.bounds.size)
        size.width -= (collectionView.contentInset.left + collectionView.contentInset.right)
        size.height -= (collectionView.contentInset.top + collectionView.contentInset.bottom)
        let inset = section.insetForSection
        if item.adjustsWidth {
            let paddings = inset.left + inset.right
            size.width -= paddings
        }
        
        if item.adjustsHeight {
            let paddings = inset.top + inset.bottom
            size.width -= paddings
        }
        
        return size
    }
    
    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return sections[section].insetForSection
    }
    
    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        let section_ = sections[section]
        
        let value = section_.headerItem?.estimatedSize(boundingSize: collectionView.bounds.size) ?? .zero
        return value
    }
    
    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        let section_ = sections[section]        
        let value = section_.footerItem?.estimatedSize(boundingSize: collectionView.bounds.size) ?? .zero
        return value
    }
    
    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return sections[section].minimumInterItemSpacing
    }
    
    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return sections[section].lineSpacing
    }
    
    public func collectionView(_ collectionView: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView, forElementKind elementKind: String, at indexPath: IndexPath) {
        guard sections.indices.contains(indexPath.section) else { return }
        switch elementKind {
        case UICollectionElementKindSectionHeader:
            sections[indexPath.section].headerItem?.onDisplay?()
            break
        case UICollectionElementKindSectionFooter:
            sections[indexPath.section].footerItem?.onDisplay?()
            break
        default:
            break
        }
        
        guard shouldAdjustSupplementaryViewLayerZPosition, #available(iOS 11.0, *) else { return }
        view.layer.zPosition = 0
    }
    
    public func collectionView(_ collectionView: UICollectionView, didEndDisplayingSupplementaryView view: UICollectionReusableView, forElementOfKind elementKind: String, at indexPath: IndexPath) {
        guard indexPath.count > 0 else { return }
        guard sections.indices.contains(indexPath.section) else { return }
        switch elementKind {
        case UICollectionElementKindSectionHeader:
            sections[indexPath.section].headerItem?.onEndDisplay?()
            break
        case UICollectionElementKindSectionFooter:
            sections[indexPath.section].footerItem?.onEndDisplay?()
            break
        default:
            break
        }
    }
}

//MARK:- Insertions
extension CollectionDirector {
    public func append(section: AbstractCollectionSection) {
        sections.append(section)
    }
    
    public func insert(section: AbstractCollectionSection, after afterSection: AbstractCollectionSection) {
        guard let afterIndex = sections.index(where: { section == $0 }) else { return }
        sections.insert(section, at: afterIndex + 1)
    }
    
    public func insert(section: AbstractCollectionSection, at index: Int) {
        sections.insert(section, at: index)
    }
    
    public func append(sections: [AbstractCollectionSection]) {
        self.sections.append(contentsOf: sections)
    }
}

//MARK:- UIScrollViewDelegate
extension CollectionDirector : UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.scrollDelegate?.scrollViewDidScroll?(scrollView)
    }
}

extension UICollectionView {
    
    func isValidIndexPath(_ indexPath: IndexPath) -> Bool {
        if indexPath.section >= numberOfSections {
            return false
        }
        
        if indexPath.row >= numberOfItems(inSection: indexPath.section) {
            return false
        }
        
        return true
    }
    
}
