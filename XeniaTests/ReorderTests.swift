//
//  ReorderTests.swift
//  XeniaTests
//
//  The shared ordering helper behind the up/down chevrons and every "add a
//  rule / rating / group" path.
//

import Testing
import Foundation
import SwiftData
@testable import Xenia

@MainActor
struct ReorderTests {

    private func makeContext() throws -> ModelContext {
        let schema = Persistence.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeRules(_ count: Int, in context: ModelContext) -> [AdjustmentRule] {
        (0..<count).map { index in
            let rule = AdjustmentRule(title: "Rule \(index)", deltaPercent: 1, sortOrder: index)
            context.insert(rule)
            return rule
        }
    }

    // MARK: - Adding

    @Test func nextSortOrderGoesPastTheHighest() throws {
        let context = try makeContext()
        let rules = makeRules(4, in: context)
        #expect(Reorder.nextSortOrder(after: rules) == 4)
    }

    @Test func nextSortOrderIsZeroForAnEmptyList() throws {
        let empty: [AdjustmentRule] = []
        #expect(Reorder.nextSortOrder(after: empty) == 0)
    }

    /// The bug this replaced: a count-based order collides with a surviving row
    /// once a delete has left a gap, so the two sort arbitrarily against each other.
    @Test func nextSortOrderDoesNotCollideAfterADeleteLeavesAGap() throws {
        let context = try makeContext()
        var rules = makeRules(4, in: context)   // sortOrder 0, 1, 2, 3
        let removed = rules.remove(at: 1)       // leaves 0, 2, 3
        context.delete(removed)

        let next = Reorder.nextSortOrder(after: rules)
        #expect(next == 4)
        #expect(!rules.map(\.sortOrder).contains(next), "a new row must not land on an existing one")
    }

    // MARK: - Moving

    @Test func movingDownSwapsAndRenumbersDensely() throws {
        let context = try makeContext()
        let rules = makeRules(4, in: context)

        Reorder.move(rules[0], by: 1, in: rules, saving: context)

        #expect(rules[0].sortOrder == 1)
        #expect(rules[1].sortOrder == 0)
        #expect(rules.sorted { $0.sortOrder < $1.sortOrder }.map(\.title)
                == ["Rule 1", "Rule 0", "Rule 2", "Rule 3"])
    }

    @Test func movingUpSwapsTheOtherWay() throws {
        let context = try makeContext()
        let rules = makeRules(3, in: context)

        Reorder.move(rules[2], by: -1, in: rules, saving: context)

        #expect(rules.sorted { $0.sortOrder < $1.sortOrder }.map(\.title)
                == ["Rule 0", "Rule 2", "Rule 1"])
    }

    @Test func movingOffEitherEndDoesNothing() throws {
        let context = try makeContext()
        let rules = makeRules(3, in: context)

        Reorder.move(rules[0], by: -1, in: rules, saving: context)
        Reorder.move(rules[2], by: 1, in: rules, saving: context)

        #expect(rules.map(\.sortOrder) == [0, 1, 2])
    }

    /// A move renumbers everything, so gaps left by an earlier delete close up.
    @Test func movingRenumbersAGappyListIntoADenseOne() throws {
        let context = try makeContext()
        let rules = makeRules(3, in: context)
        rules[0].sortOrder = 4
        rules[1].sortOrder = 9
        rules[2].sortOrder = 17

        let ordered = rules.sorted { $0.sortOrder < $1.sortOrder }
        Reorder.move(ordered[0], by: 1, in: ordered, saving: context)

        #expect(rules.map(\.sortOrder).sorted() == [0, 1, 2])
    }

    @Test func ratingDimensionsReorderTheSameWay() throws {
        let context = try makeContext()
        let dimensions = (0..<3).map { index -> RatingDimension in
            let dimension = RatingDimension(name: "Dim \(index)", sortOrder: index)
            context.insert(dimension)
            return dimension
        }

        Reorder.move(dimensions[2], by: -1, in: dimensions, saving: context)

        #expect(dimensions.sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
                == ["Dim 0", "Dim 2", "Dim 1"])
    }
}
