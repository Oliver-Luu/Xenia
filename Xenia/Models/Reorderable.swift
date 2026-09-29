//
//  Reorderable.swift
//  Xenia
//
//  Rules and rating dimensions are both user-ordered lists of children, moved a
//  row at a time with the up/down chevrons on `ReorderableRow`. The move was
//  written out four times — once per list, in the category editor and the
//  per-place editor — so it lives here once instead.
//

import SwiftUI
import SwiftData

/// Anything the user keeps in an explicit order.
protocol Ordered: AnyObject {
    var sortOrder: Int { get set }
}

/// An ordered row the user can also move up and down, identified by `uuid`.
protocol Reorderable: Ordered {
    var uuid: UUID { get }
}

extension AdjustmentRule: Reorderable {}
extension RatingDimension: Reorderable {}
extension TipCategory: Ordered {}
extension PlaceGroup: Ordered {}

enum Reorder {
    /// The `sortOrder` to give a newly added row.
    ///
    /// Counting the existing rows is not enough: nothing renumbers after a
    /// delete, so a list that went 0,1,2,3 and lost the second row is left with
    /// 0,2,3 — and a count of 3 would collide with the row already sitting at 3,
    /// leaving the two in arbitrary order. Go past the highest one instead.
    static func nextSortOrder(after existing: [some Ordered]) -> Int {
        (existing.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Moves `item` `offset` places within `ordered`, renumbers every
    /// `sortOrder` so the list stays dense, and saves. A move off either end is
    /// a no-op — the chevron that would do it is disabled anyway.
    @MainActor
    static func move<T: Reorderable>(
        _ item: T,
        by offset: Int,
        in ordered: [T],
        saving context: ModelContext
    ) {
        var ordered = ordered
        guard let index = ordered.firstIndex(where: { $0.uuid == item.uuid }),
              ordered.indices.contains(index + offset)
        else { return }
        withAnimation(.snappy(duration: 0.2)) {
            ordered.swapAt(index, index + offset)
            for (position, element) in ordered.enumerated() { element.sortOrder = position }
        }
        try? context.save()
    }
}
